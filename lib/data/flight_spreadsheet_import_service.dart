import 'dart:convert';

import 'package:archive/archive.dart';
// The package does not expose its OLE stream reader publicly. We need the raw
// Workbook stream so BIFF CONTINUE boundaries can be decoded correctly.
import 'package:excel2003/src/ole2/ole2_reader.dart'; // ignore: implementation_imports
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:xml/xml.dart';

import '../domain/airport.dart';
import '../domain/flight.dart';
import 'airport_catalog.dart';
import 'airport_localization.dart';

/// A row that can be reviewed before it is written to the local database.
class SpreadsheetFlightRow {
  const SpreadsheetFlightRow({
    required this.rowNumber,
    required this.flight,
    required this.departureText,
    required this.arrivalText,
    required this.departureAirportName,
    required this.arrivalAirportName,
    this.departureAmbiguous = false,
    this.arrivalAmbiguous = false,
  });

  final int rowNumber;
  final Flight flight;
  final String departureText;
  final String arrivalText;
  final String departureAirportName;
  final String arrivalAirportName;
  final bool departureAmbiguous;
  final bool arrivalAmbiguous;

  bool get hasAmbiguousAirport => departureAmbiguous || arrivalAmbiguous;
}

class SpreadsheetImportIssue {
  const SpreadsheetImportIssue({
    required this.rowNumber,
    required this.message,
  });

  final int rowNumber;
  final String message;
}

class SpreadsheetImportResult {
  const SpreadsheetImportResult({
    required this.sheetName,
    required this.rows,
    required this.issues,
  });

  final String sheetName;
  final List<SpreadsheetFlightRow> rows;
  final List<SpreadsheetImportIssue> issues;

  bool get hasRows => rows.isNotEmpty;
}

/// Converts the spreadsheet exported by 航旅纵横 into local [Flight] records.
///
/// The exporter currently uses these columns: 日期、航空公司、航班号、出发城市、
/// 出发时间、到达城市、到达时间、里程数、客票号、客票状态. The parser also accepts
/// common English and legacy aliases so a user can import a lightly edited file.
class FlightSpreadsheetImportService {
  FlightSpreadsheetImportService({required this.airports});

  final AirportCatalog airports;
  final Map<String, _AirportMatch?> _airportResolutionCache = {};

  SpreadsheetImportResult parse({
    required List<int> bytes,
    required String fileName,
    DateTime? now,
  }) {
    final sheets = _readSpreadsheetSheets(bytes: bytes, fileName: fileName);
    return _parseSheets(sheets, now: now ?? DateTime.now());
  }

  /// Parses a workbook away from Flutter's UI isolate.
  ///
  /// Reading legacy `.xls` files can involve walking a very large BIFF
  /// dimension even when only a few rows contain data. Keep that work out of
  /// the frame that owns the file picker and progress notice. The airport
  /// lookup and row normalization still use this service's in-memory catalog
  /// after the raw sheet grid has been safely read.
  Future<SpreadsheetImportResult> parseInBackground({
    required List<int> bytes,
    required String fileName,
    DateTime? now,
  }) async {
    final sheets =
        await compute<_SpreadsheetReadRequest, List<_SpreadsheetSheet>>(
          _readSpreadsheetSheetsInBackground,
          _SpreadsheetReadRequest(
            bytes: Uint8List.fromList(bytes),
            fileName: fileName,
          ),
        );
    return _parseSheetsInChunks(sheets, now: now ?? DateTime.now());
  }

  SpreadsheetImportResult _parseSheets(
    List<_SpreadsheetSheet> sheets, {
    required DateTime now,
  }) {
    final selected = _selectSheetHeaders(sheets);
    final parsed = [
      for (final candidate in selected)
        _parseSheet(candidate.sheet, candidate.header, now),
    ];
    return _combineParsedSheets(selected, parsed);
  }

  Future<SpreadsheetImportResult> _parseSheetsInChunks(
    List<_SpreadsheetSheet> sheets, {
    required DateTime now,
  }) async {
    final selected = _selectSheetHeaders(sheets);
    final parsed = <SpreadsheetImportResult>[];
    for (final candidate in selected) {
      parsed.add(
        await _parseSheetInChunks(candidate.sheet, candidate.header, now),
      );
    }
    return _combineParsedSheets(selected, parsed);
  }

  List<_SheetHeader> _selectSheetHeaders(List<_SpreadsheetSheet> sheets) {
    if (sheets.isEmpty) {
      throw const FormatException('表格中没有可读取的工作表。');
    }
    final candidates = <_SheetHeader>[
      for (final sheet in sheets)
        if (_HeaderMap.find(sheet.rows) case final header?)
          _SheetHeader(sheet, header),
    ];
    if (candidates.isEmpty) {
      throw const FormatException('未找到航旅纵横表头。需要包含：日期、航空公司、航班号、出发城市和到达城市。');
    }
    final named = candidates
        .where((candidate) => _isImportableSheet(candidate.sheet.name))
        .toList(growable: false);
    return named.isEmpty ? candidates : named;
  }

  SpreadsheetImportResult _combineParsedSheets(
    List<_SheetHeader> selected,
    List<SpreadsheetImportResult> parsed,
  ) {
    final rows = <SpreadsheetFlightRow>[
      for (final result in parsed) ...result.rows,
    ];
    final issues = <SpreadsheetImportIssue>[
      for (final result in parsed) ...result.issues,
    ];
    return SpreadsheetImportResult(
      sheetName: selected.map((candidate) => candidate.sheet.name).join('、'),
      rows: List.unmodifiable(rows),
      issues: List.unmodifiable(issues),
    );
  }

  static bool _isImportableSheet(String name) {
    final normalized = name.trim().toLowerCase();
    if (normalized.contains('无效') || normalized.contains('invalid')) {
      return false;
    }
    return normalized.contains('待出行') ||
        normalized.contains('upcoming') ||
        normalized.contains('已结束') ||
        normalized.contains('completed') ||
        normalized.contains('finished');
  }

  SpreadsheetImportResult _parseSheet(
    _SpreadsheetSheet sheet,
    _HeaderMap header,
    DateTime now,
  ) {
    final rows = <SpreadsheetFlightRow>[];
    final issues = <SpreadsheetImportIssue>[];
    for (var index = header.rowIndex + 1; index < sheet.rows.length; index++) {
      final values = sheet.rows[index];
      if (_isBlankRow(values) || _HeaderMap.looksLikeHeader(values)) continue;
      final rowNumber = index + 1;
      final parsed = _parseRow(values, rowNumber, header, now);
      if (parsed.row != null) {
        rows.add(parsed.row!);
      }
      if (parsed.issue != null) {
        issues.add(parsed.issue!);
      }
    }
    if (rows.isEmpty && issues.isEmpty) {
      issues.add(
        SpreadsheetImportIssue(
          rowNumber: header.rowIndex + 1,
          message: '表头下没有可导入的行。',
        ),
      );
    }
    return SpreadsheetImportResult(
      sheetName: sheet.name,
      rows: List.unmodifiable(rows),
      issues: List.unmodifiable(issues),
    );
  }

  Future<SpreadsheetImportResult> _parseSheetInChunks(
    _SpreadsheetSheet sheet,
    _HeaderMap header,
    DateTime now,
  ) async {
    final rows = <SpreadsheetFlightRow>[];
    final issues = <SpreadsheetImportIssue>[];
    var processed = 0;
    for (var index = header.rowIndex + 1; index < sheet.rows.length; index++) {
      final values = sheet.rows[index];
      if (!_isBlankRow(values) && !_HeaderMap.looksLikeHeader(values)) {
        final rowNumber = index + 1;
        final parsed = _parseRow(values, rowNumber, header, now);
        if (parsed.row != null) rows.add(parsed.row!);
        if (parsed.issue != null) issues.add(parsed.issue!);
      }
      processed++;
      if (processed % 200 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }
    if (rows.isEmpty && issues.isEmpty) {
      issues.add(
        SpreadsheetImportIssue(
          rowNumber: header.rowIndex + 1,
          message: '表头下没有可导入的行。',
        ),
      );
    }
    return SpreadsheetImportResult(
      sheetName: sheet.name,
      rows: List.unmodifiable(rows),
      issues: List.unmodifiable(issues),
    );
  }

  _ParsedSpreadsheetRow _parseRow(
    List<String> values,
    int rowNumber,
    _HeaderMap header,
    DateTime now,
  ) {
    final airline = _cell(values, header.airline);
    final flightNumber = _normalizeFlightNumber(
      _cell(values, header.flightNumber),
    );
    final dateText = _cell(values, header.date);
    final departureText = _cell(values, header.departureCity);
    final arrivalText = _cell(values, header.arrivalCity);
    final errors = <String>[];
    if (airline.isEmpty) errors.add('航空公司为空');
    if (flightNumber.isEmpty) errors.add('航班号为空');
    if (dateText.isEmpty) errors.add('日期为空');
    if (departureText.isEmpty) errors.add('出发城市为空');
    if (arrivalText.isEmpty) errors.add('到达城市为空');

    final departureMatch = departureText.isEmpty
        ? null
        : _resolveAirport(departureText);
    final arrivalMatch = arrivalText.isEmpty
        ? null
        : _resolveAirport(arrivalText);
    if (departureText.isNotEmpty && departureMatch == null) {
      errors.add('找不到出发城市对应的机场：$departureText');
    }
    if (arrivalText.isNotEmpty && arrivalMatch == null) {
      errors.add('找不到到达城市对应的机场：$arrivalText');
    }

    final departureTimeText = _cell(values, header.departureTime);
    final arrivalTimeText = _cell(values, header.arrivalTime);
    final departedAt = _parseDateTime(
      dateText: dateText,
      timeText: departureTimeText,
    );
    if (departedAt == null && dateText.isNotEmpty) {
      errors.add(
        '无法识别起飞日期时间：$dateText${departureTimeText.isEmpty ? '' : ' $departureTimeText'}',
      );
    }

    // The Umetrip export normally contains departure/arrival clock times but
    // no dedicated duration column. Keep the optional duration column as a
    // fallback, then prefer the duration calculated from the parsed times so
    // preview cards and imported records always agree with the itinerary.
    final declaredDurationMinutes = _parseDuration(
      _cell(values, header.duration),
    );
    DateTime? arrivedAt;
    if (departedAt != null) {
      arrivedAt = _parseDateTime(
        dateText: dateText,
        timeText: arrivalTimeText,
        relativeTo: departedAt,
        arrival: true,
      );
      arrivedAt ??= declaredDurationMinutes == null
          ? null
          : departedAt.add(Duration(minutes: declaredDurationMinutes));
    }

    final calculatedDurationMinutes = arrivedAt == null || departedAt == null
        ? null
        : arrivedAt.difference(departedAt).inMinutes;
    final durationMinutes =
        calculatedDurationMinutes != null && calculatedDurationMinutes > 0
        ? calculatedDurationMinutes
        : declaredDurationMinutes;

    if (errors.isNotEmpty ||
        departureMatch == null ||
        arrivalMatch == null ||
        departedAt == null) {
      return _ParsedSpreadsheetRow(
        issue: SpreadsheetImportIssue(
          rowNumber: rowNumber,
          message: errors.join('；'),
        ),
      );
    }

    final distance =
        _parseDistance(_cell(values, header.distance)) ??
        AirportCatalog.greatCircleDistanceKm(
          departureMatch.airport,
          arrivalMatch.airport,
        );
    final normalizedDate = departedAt.toUtc().toIso8601String();
    final fingerprint = [
      airline.toLowerCase(),
      flightNumber,
      departureMatch.airport.iataCode,
      arrivalMatch.airport.iataCode,
      normalizedDate,
    ].join('|');
    final createdAt = now.toUtc();
    final flight = Flight(
      id: const Uuid().v5(Namespace.url.value, 'excel-v1|$fingerprint'),
      departureIata: departureMatch.airport.iataCode,
      arrivalIata: arrivalMatch.airport.iataCode,
      departedAt: departedAt,
      arrivedAt: arrivedAt,
      createdAt: createdAt,
      updatedAt: createdAt,
      status: _statusForDate(departedAt, now),
      airline: airline,
      flightNumber: flightNumber,
      aircraftType: _cell(values, header.aircraft).nullIfEmpty,
      durationMinutes: durationMinutes,
      // Ticket number/status are intentionally not imported. They are not
      // useful for the footprint and can contain personal information.
      note: null,
      distanceKm: distance,
    );
    return _ParsedSpreadsheetRow(
      row: SpreadsheetFlightRow(
        rowNumber: rowNumber,
        flight: flight,
        departureText: departureText,
        arrivalText: arrivalText,
        departureAirportName: localizedAirportCardName(departureMatch.airport),
        arrivalAirportName: localizedAirportCardName(arrivalMatch.airport),
        departureAmbiguous: departureMatch.ambiguous,
        arrivalAmbiguous: arrivalMatch.ambiguous,
      ),
    );
  }

  _AirportMatch? _resolveAirport(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    final cacheKey = value.toLowerCase();
    if (_airportResolutionCache.containsKey(cacheKey)) {
      return _airportResolutionCache[cacheKey];
    }
    final codes = RegExp(r'(?<![A-Za-z])([A-Za-z]{3})(?![A-Za-z])')
        .allMatches(value)
        .map((match) => match.group(1)!.toUpperCase());
    for (final code in codes) {
      final airport = airports.findByIata(code);
      if (airport != null) {
        final match = _AirportMatch(airport, false);
        _cacheAirportMatch(cacheKey, match);
        return match;
      }
    }

    final queries = (<String>{
      value,
      value.replaceAll(RegExp(r'[市區区县縣]$'), ''),
      value.replaceAll(RegExp(r'机场|機場'), ''),
    })..removeWhere((item) => item.trim().isEmpty);
    final candidates = <Airport>[];
    final seen = <String>{};
    for (final query in queries) {
      for (final airport in airports.search(query, limit: 12)) {
        if (seen.add(airport.iataCode)) candidates.add(airport);
      }
      if (candidates.isNotEmpty) break;
    }
    if (candidates.isEmpty) {
      _cacheAirportMatch(cacheKey, null);
      return null;
    }
    final match = _AirportMatch(candidates.first, candidates.length > 1);
    _cacheAirportMatch(cacheKey, match);
    return match;
  }

  void _cacheAirportMatch(String key, _AirportMatch? match) {
    if (_airportResolutionCache.length >= 2048 &&
        !_airportResolutionCache.containsKey(key)) {
      _airportResolutionCache.clear();
    }
    _airportResolutionCache[key] = match;
  }

  static FlightStatus _statusForDate(DateTime date, DateTime now) {
    final flightDay = DateTime(date.year, date.month, date.day);
    final today = DateTime(now.year, now.month, now.day);
    return flightDay.isAfter(today)
        ? FlightStatus.upcoming
        : FlightStatus.completed;
  }
}

class _SpreadsheetReadRequest {
  const _SpreadsheetReadRequest({required this.bytes, required this.fileName});

  final Uint8List bytes;
  final String fileName;
}

List<_SpreadsheetSheet> _readSpreadsheetSheetsInBackground(
  _SpreadsheetReadRequest request,
) => _readSpreadsheetSheets(bytes: request.bytes, fileName: request.fileName);

List<_SpreadsheetSheet> _readSpreadsheetSheets({
  required List<int> bytes,
  required String fileName,
}) {
  final extension = _extension(fileName);
  return switch (extension) {
    'csv' => [_SpreadsheetSheet('CSV', _parseDelimited(_decodeText(bytes)))],
    'xlsx' => _XlsxReader().read(bytes),
    'xls' => _XlsReader().read(bytes),
    _ => throw const FormatException('目前支持 .xlsx、.xls 或 .csv 文件。'),
  };
}

class _ParsedSpreadsheetRow {
  const _ParsedSpreadsheetRow({this.row, this.issue});

  final SpreadsheetFlightRow? row;
  final SpreadsheetImportIssue? issue;
}

class _AirportMatch {
  const _AirportMatch(this.airport, this.ambiguous);

  final Airport airport;
  final bool ambiguous;
}

class _SpreadsheetSheet {
  const _SpreadsheetSheet(this.name, this.rows);

  final String name;
  final List<List<String>> rows;
}

class _SheetHeader {
  const _SheetHeader(this.sheet, this.header);

  final _SpreadsheetSheet sheet;
  final _HeaderMap header;
}

class _HeaderMap {
  const _HeaderMap({
    required this.rowIndex,
    required this.date,
    required this.airline,
    required this.flightNumber,
    required this.departureCity,
    required this.departureTime,
    required this.arrivalCity,
    required this.arrivalTime,
    required this.distance,
    required this.ticketNumber,
    required this.ticketStatus,
    required this.aircraft,
    required this.duration,
  });

  final int rowIndex;
  final int? date;
  final int? airline;
  final int? flightNumber;
  final int? departureCity;
  final int? departureTime;
  final int? arrivalCity;
  final int? arrivalTime;
  final int? distance;
  final int? ticketNumber;
  final int? ticketStatus;
  final int? aircraft;
  final int? duration;

  static _HeaderMap? find(List<List<String>> rows) {
    final limit = rows.length < 30 ? rows.length : 30;
    _HeaderMap? best;
    var bestScore = 0;
    for (var rowIndex = 0; rowIndex < limit; rowIndex++) {
      final row = rows[rowIndex];
      final candidate = _fromRow(row, rowIndex);
      if (candidate == null) continue;
      final score = [
        candidate.date,
        candidate.airline,
        candidate.flightNumber,
        candidate.departureCity,
        candidate.departureTime,
        candidate.arrivalCity,
        candidate.arrivalTime,
        candidate.distance,
        candidate.ticketNumber,
        candidate.ticketStatus,
      ].whereType<int>().length;
      if (score > bestScore) {
        best = candidate;
        bestScore = score;
      }
    }
    return best;
  }

  static _HeaderMap? _fromRow(List<String> row, int rowIndex) {
    final date = _findColumn(row, const [
      '日期',
      '飞行日期',
      '航班日期',
      '行程日期',
      'date',
      'flightdate',
    ]);
    final airline = _findColumn(row, const [
      '航空公司',
      '航司',
      '承运航空公司',
      '航空公司名称',
      'airline',
      'carrier',
    ]);
    final flightNumber = _findColumn(row, const [
      '航班号',
      '航班编号',
      '航班',
      'flightnumber',
      'flightno',
      'flight',
    ]);
    final departureCity = _findColumn(row, const [
      '出发城市',
      '出发地',
      '起飞城市',
      '始发城市',
      '起飞机场',
      '出发机场',
      'origin',
      'departurecity',
      'from',
    ]);
    final departureTime = _findColumn(row, const [
      '出发时间',
      '起飞时间',
      '计划起飞',
      '起飞日期时间',
      'departuredatetime',
      'departuretime',
      'depart',
    ]);
    final arrivalCity = _findColumn(row, const [
      '到达城市',
      '目的地',
      '到达地',
      '降落城市',
      '到达机场',
      '降落机场',
      'destination',
      'arrivalcity',
      'to',
    ]);
    final arrivalTime = _findColumn(row, const [
      '到达时间',
      '降落时间',
      '计划到达',
      '到达日期时间',
      'arrivaldatetime',
      'arrivaltime',
      'arrive',
    ]);
    final distance = _findColumn(row, const [
      '里程数',
      '里程',
      '航程',
      '距离',
      '公里数',
      'distance',
      'mileage',
    ]);
    final ticketNumber = _findColumn(row, const [
      '客票号',
      '票号',
      '客票编号',
      'ticketnumber',
      'ticketno',
    ]);
    final ticketStatus = _findColumn(row, const [
      '客票状态',
      '票状态',
      'ticketstatus',
    ]);
    final aircraft = _findColumn(row, const [
      '飞机机型',
      '机型',
      '机型名称',
      'aircrafttype',
      'aircraft',
    ]);
    final duration = _findColumn(row, const ['飞行时长', '时长', '飞行时间', 'duration']);

    final required = [date, airline, flightNumber, departureCity, arrivalCity];
    if (required.whereType<int>().length < 4 ||
        departureCity == null && arrivalCity == null) {
      return null;
    }
    return _HeaderMap(
      rowIndex: rowIndex,
      date: date,
      airline: airline,
      flightNumber: flightNumber,
      departureCity: departureCity,
      departureTime: departureTime,
      arrivalCity: arrivalCity,
      arrivalTime: arrivalTime,
      distance: distance,
      ticketNumber: ticketNumber,
      ticketStatus: ticketStatus,
      aircraft: aircraft,
      duration: duration,
    );
  }

  static bool looksLikeHeader(List<String> row) => _fromRow(row, 0) != null;

  static int? _findColumn(List<String> row, List<String> aliases) {
    final normalizedAliases = aliases.map(_normalizeHeader).toList();
    for (var index = 0; index < row.length; index++) {
      final value = _normalizeHeader(row[index]);
      if (value.isEmpty) continue;
      for (final alias in normalizedAliases) {
        if (value == alias || value.contains(alias)) {
          return index;
        }
      }
    }
    return null;
  }
}

class _XlsxReader {
  List<_SpreadsheetSheet> read(List<int> bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final files = <String, ArchiveFile>{
      for (final file in archive.files)
        if (file.isFile) file.name: file,
    };
    final workbook = _document(files['xl/workbook.xml']);
    if (workbook == null) return const [];
    final relationships = _relationships(files['xl/_rels/workbook.xml.rels']);
    final sharedStrings = _sharedStrings(files['xl/sharedStrings.xml']);
    final dateStyles = _DateStyles.fromDocument(files['xl/styles.xml']);
    final result = <_SpreadsheetSheet>[];
    for (final sheet in workbook.findAllElements('sheet')) {
      final name = _attribute(sheet, 'name') ?? 'Sheet';
      final relationshipId = _attribute(sheet, 'id');
      final target = relationshipId == null
          ? null
          : relationships[relationshipId];
      if (target == null) continue;
      final path = _workbookTargetPath(target);
      final document = _document(files[path]);
      if (document == null) continue;
      result.add(
        _SpreadsheetSheet(
          name,
          _sheetRows(document, sharedStrings, dateStyles),
        ),
      );
    }
    return result;
  }

  List<List<String>> _sheetRows(
    XmlDocument document,
    List<String> sharedStrings,
    _DateStyles dateStyles,
  ) {
    final rows = <List<String>>[];
    for (final row in document.findAllElements('row')) {
      final values = <String>[];
      for (final cell in row.childElements.where(
        (element) => element.localName == 'c',
      )) {
        final reference = _attribute(cell, 'r');
        final index = _columnIndex(reference);
        if (index == null) continue;
        while (values.length <= index) {
          values.add('');
        }
        values[index] = _cellValue(cell, sharedStrings, dateStyles);
      }
      rows.add(values);
    }
    return rows;
  }

  String _cellValue(
    XmlElement cell,
    List<String> sharedStrings,
    _DateStyles dateStyles,
  ) {
    final type = _attribute(cell, 't');
    final raw = cell.childElements
        .where((element) => element.localName == 'v')
        .map((element) => element.innerText)
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    if (type == 'inlineStr') {
      return cell
          .findAllElements('t')
          .map((element) => element.innerText)
          .join();
    }
    if (type == 's') {
      final index = int.tryParse(raw);
      return index == null || index < 0 || index >= sharedStrings.length
          ? raw
          : sharedStrings[index];
    }
    if (type == 'b') return raw == '1' ? 'TRUE' : 'FALSE';
    final style = int.tryParse(_attribute(cell, 's') ?? '');
    if (style != null && dateStyles.contains(style)) {
      return _formatExcelDate(raw, dateStyles.isTimeOnly(style));
    }
    return raw;
  }

  static String _formatExcelDate(String raw, bool timeOnly) {
    final value = double.tryParse(raw);
    if (value == null || !value.isFinite) return raw;
    final day = value.floor();
    final milliseconds = ((value - day) * Duration.millisecondsPerDay).round();
    final date = DateTime.utc(
      1899,
      12,
      30,
    ).add(Duration(days: day, milliseconds: milliseconds));
    String two(int value) => value.toString().padLeft(2, '0');
    final time = '${two(date.hour)}:${two(date.minute)}';
    if (timeOnly) return time;
    final dateText = '${date.year}-${two(date.month)}-${two(date.day)}';
    return milliseconds == 0 ? dateText : '$dateText $time';
  }

  static XmlDocument? _document(ArchiveFile? file) {
    if (file == null) return null;
    try {
      return XmlDocument.parse(utf8.decode(file.content as List<int>));
    } catch (_) {
      return null;
    }
  }

  static List<String> _sharedStrings(ArchiveFile? file) {
    final document = _document(file);
    if (document == null) return const [];
    return [
      for (final item in document.findAllElements('si'))
        item.findAllElements('t').map((element) => element.innerText).join(),
    ];
  }

  static Map<String, String> _relationships(ArchiveFile? file) {
    final document = _document(file);
    if (document == null) return const {};
    return {
      for (final relationship in document.findAllElements('Relationship'))
        if (_attribute(relationship, 'id') != null &&
            _attribute(relationship, 'target') != null)
          _attribute(relationship, 'id')!: _attribute(relationship, 'target')!,
    };
  }

  static String _workbookTargetPath(String target) {
    final normalized = target.replaceAll('\\', '/');
    if (normalized.startsWith('/')) return normalized.substring(1);
    if (normalized.startsWith('xl/')) return normalized;
    return 'xl/$normalized';
  }

  static int? _columnIndex(String? reference) {
    if (reference == null || reference.isEmpty) return null;
    final letters = RegExp(r'^[A-Za-z]+').stringMatch(reference);
    if (letters == null) return null;
    var result = 0;
    for (final codeUnit in letters.codeUnits) {
      final upper = codeUnit >= 97 && codeUnit <= 122
          ? codeUnit - 32
          : codeUnit;
      result = result * 26 + upper - 64;
    }
    return result - 1;
  }
}

/// Reads the legacy BIFF8 `.xls` format without native code. The public
/// importer intentionally converts every worksheet to the same string grid
/// used by the CSV/XLSX readers, so header matching and date inference stay
/// identical across all three formats.
///
/// This is deliberately kept in the app instead of relying on the small
/// `excel2003` reader's high-level API. BIFF8 may split the Shared String
/// Table over several `CONTINUE` records. Concatenating those records (which
/// the package does) loses the one-byte encoding marker at each boundary and
/// turns every later cell into garbled text. `_BiffSharedStringTable` keeps
/// record boundaries and consumes those markers while reading characters.
class _XlsReader {
  // BIFF8 stores a worksheet dimension separately from its sparse cell data.
  // A stale formatting range can therefore claim millions of cells even when
  // the visible export only contains a few hundred flights. Keep a hard upper
  // bound as a last-resort guard before creating any dense Dart lists.
  static const _maxDeclaredRows = 100000;
  static const _maxDeclaredColumns = 256;
  static const _maxDeclaredCells = 2000000;
  static const _maxLeadingEmptyRows = 512;
  static const _maxTrailingEmptyRows = 128;

  List<_SpreadsheetSheet> read(List<int> bytes) {
    final ole = Ole2Reader()..openBytes(Uint8List.fromList(bytes));
    final workbookEntry = ole.findEntry('Workbook') ?? ole.findEntry('Book');
    if (workbookEntry == null) {
      throw const FormatException('XLS 文件中没有 Workbook 工作簿流。');
    }

    final workbook = ole.readEntry(workbookEntry);
    final parser = _BiffRecordCursor(workbook);
    final rawSheets = <_BiffSheetInfo>[];
    var codePage = 1200;
    var sharedStrings = const <String>[];

    globals:
    while (parser.hasMore) {
      final record = parser.next();
      if (record == null) break;
      switch (record.type) {
        case _BiffRecordType.codePage:
          if (record.data.length >= 2) {
            codePage = record.uint16(0);
          }
          break;
        case _BiffRecordType.boundSheet:
          final sheet = _BiffSheetInfo.fromRecord(record);
          if (sheet != null && sheet.type == 0) rawSheets.add(sheet);
          break;
        case _BiffRecordType.sst:
          final segments = <Uint8List>[record.data];
          while (parser.peekType == _BiffRecordType.continueRec) {
            final continuation = parser.next();
            if (continuation == null) break;
            segments.add(continuation.data);
          }
          sharedStrings = _BiffSharedStringTable(
            segments: segments,
            codePage: codePage,
          ).read();
          break;
        case _BiffRecordType.eof:
          break globals;
      }
    }

    final sheets = [
      for (final sheet in rawSheets) sheet.withDecodedName(codePage),
    ];
    return [
      for (final sheet in sheets)
        _readSheet(
          workbook: workbook,
          sheet: sheet,
          sharedStrings: sharedStrings,
          codePage: codePage,
        ),
    ];
  }

  _SpreadsheetSheet _readSheet({
    required Uint8List workbook,
    required _BiffSheetInfo sheet,
    required List<String> sharedStrings,
    required int codePage,
  }) {
    final parser = _BiffRecordCursor(workbook, position: sheet.bofPosition);
    final cells = <int, Map<int, String>>{};
    var firstRow = 0;
    var lastRow = 0;
    var firstColumn = 0;
    var lastColumn = 0;
    var hasDimension = false;
    _BiffFormulaCell? pendingFormula;

    while (parser.hasMore) {
      final record = parser.next();
      if (record == null) break;
      switch (record.type) {
        case _BiffRecordType.dimension:
          if (record.data.length >= 12) {
            firstRow = record.uint32(0);
            lastRow = record.uint32(4);
            firstColumn = record.uint16(8);
            lastColumn = record.uint16(10);
            hasDimension = true;
          }
          break;
        case _BiffRecordType.labelSst:
          if (record.data.length >= 10) {
            final row = record.uint16(0);
            final column = record.uint16(2);
            final index = record.uint32(6);
            _setCell(
              cells,
              row,
              column,
              index < sharedStrings.length ? sharedStrings[index] : '',
            );
          }
          break;
        case _BiffRecordType.label:
          if (record.data.length >= 8) {
            _setCell(
              cells,
              record.uint16(0),
              record.uint16(2),
              _BiffInlineString.read(record.data, 6, codePage),
            );
          }
          break;
        case _BiffRecordType.number:
          if (record.data.length >= 14) {
            _setCell(
              cells,
              record.uint16(0),
              record.uint16(2),
              _formatNumber(record.float64(6)),
            );
          }
          break;
        case _BiffRecordType.rk:
          if (record.data.length >= 10) {
            _setCell(
              cells,
              record.uint16(0),
              record.uint16(2),
              _formatNumber(_decodeRk(record.uint32(6))),
            );
          }
          break;
        case _BiffRecordType.mulRk:
          _readMultipleRk(record, cells);
          break;
        case _BiffRecordType.boolErr:
          if (record.data.length >= 8) {
            final value = record.data[6];
            final isError = record.data[7] == 1;
            _setCell(
              cells,
              record.uint16(0),
              record.uint16(2),
              isError
                  ? _errorText(value)
                  : value == 0
                  ? 'FALSE'
                  : 'TRUE',
            );
          }
          break;
        case _BiffRecordType.formula:
          if (record.data.length >= 20) {
            final row = record.uint16(0);
            final column = record.uint16(2);
            final resultType = record.uint16(6);
            if (resultType == 0xffff) {
              final specialType = record.data[8];
              if (specialType == 0) {
                pendingFormula = _BiffFormulaCell(row, column);
              } else if (specialType == 1) {
                _setCell(
                  cells,
                  row,
                  column,
                  record.data[10] == 0 ? 'FALSE' : 'TRUE',
                );
                pendingFormula = null;
              } else if (specialType == 2) {
                _setCell(cells, row, column, _errorText(record.data[10]));
                pendingFormula = null;
              } else {
                pendingFormula = null;
              }
            } else {
              _setCell(cells, row, column, _formatNumber(record.float64(6)));
              pendingFormula = null;
            }
          }
          break;
        case _BiffRecordType.string:
          if (pendingFormula != null) {
            _setCell(
              cells,
              pendingFormula.row,
              pendingFormula.column,
              _BiffInlineString.read(record.data, 0, codePage),
            );
            pendingFormula = null;
          }
          break;
        case _BiffRecordType.eof:
          return _buildSheet(
            sheet.name,
            cells,
            firstRow: firstRow,
            lastRow: lastRow,
            firstColumn: firstColumn,
            lastColumn: lastColumn,
            hasDimension: hasDimension,
          );
      }
    }

    return _buildSheet(
      sheet.name,
      cells,
      firstRow: firstRow,
      lastRow: lastRow,
      firstColumn: firstColumn,
      lastColumn: lastColumn,
      hasDimension: hasDimension,
    );
  }

  _SpreadsheetSheet _buildSheet(
    String name,
    Map<int, Map<int, String>> cells, {
    required int firstRow,
    required int lastRow,
    required int firstColumn,
    required int lastColumn,
    required bool hasDimension,
  }) {
    if (cells.isNotEmpty) {
      final rows = cells.keys;
      final columns = cells.values.expand((row) => row.keys);
      final actualFirstRow = rows.reduce((a, b) => a < b ? a : b);
      final actualLastRow = rows.reduce((a, b) => a > b ? a : b) + 1;
      final actualFirstColumn = columns.reduce((a, b) => a < b ? a : b);
      final actualLastColumn = columns.reduce((a, b) => a > b ? a : b) + 1;
      if (!hasDimension || actualFirstRow < firstRow) firstRow = actualFirstRow;
      if (!hasDimension || actualLastRow > lastRow) lastRow = actualLastRow;
      if (!hasDimension || actualFirstColumn < firstColumn) {
        firstColumn = actualFirstColumn;
      }
      if (!hasDimension || actualLastColumn > lastColumn) {
        lastColumn = actualLastColumn;
      }
    }

    final rowCount = lastRow - firstRow;
    final columnCount = lastColumn - firstColumn;
    if (rowCount < 0 ||
        columnCount < 0 ||
        rowCount > _maxDeclaredRows ||
        columnCount > _maxDeclaredColumns ||
        rowCount > 0 && columnCount > _maxDeclaredCells ~/ rowCount) {
      throw FormatException(
        '工作表“$name”声明的范围过大（$rowCount 行 × '
        '$columnCount 列），文件可能包含异常格式。请另存为 .xlsx 或 .csv 后重试。',
      );
    }

    final result = <List<String>>[];
    var foundValue = false;
    var leadingEmptyRows = 0;
    var trailingEmptyRows = 0;
    for (var row = firstRow; row < lastRow; row++) {
      final values = List<String>.filled(columnCount, '');
      var rowHasValue = false;
      final source = cells[row];
      if (source != null) {
        for (final entry in source.entries) {
          if (entry.key < firstColumn || entry.key >= lastColumn) continue;
          values[entry.key - firstColumn] = entry.value;
          if (entry.value.trim().isNotEmpty) rowHasValue = true;
        }
      }

      if (rowHasValue) {
        foundValue = true;
        leadingEmptyRows = 0;
        trailingEmptyRows = 0;
      } else if (!foundValue) {
        leadingEmptyRows++;
        if (leadingEmptyRows > _maxLeadingEmptyRows) break;
      } else {
        trailingEmptyRows++;
        // The exporter writes a contiguous table. Stop after a reasonable
        // blank tail instead of walking a stale BIFF lastRow to the limit.
        if (trailingEmptyRows >= _maxTrailingEmptyRows) break;
      }
      result.add(values);
    }
    return _SpreadsheetSheet(name, result);
  }

  static void _setCell(
    Map<int, Map<int, String>> cells,
    int row,
    int column,
    String value,
  ) {
    cells.putIfAbsent(row, () => {})[column] = value;
  }

  static void _readMultipleRk(
    _BiffRecord record,
    Map<int, Map<int, String>> cells,
  ) {
    if (record.data.length < 10) return;
    final row = record.uint16(0);
    final firstColumn = record.uint16(2);
    final lastColumn = record.uint16(record.data.length - 2);
    var offset = 4;
    for (
      var column = firstColumn;
      column <= lastColumn && offset + 6 <= record.data.length - 2;
      column++
    ) {
      _setCell(
        cells,
        row,
        column,
        _formatNumber(_decodeRk(record.uint32(offset + 2))),
      );
      offset += 6;
    }
  }

  static double _decodeRk(int value) {
    final isInteger = (value & 0x02) != 0;
    final divideBy100 = (value & 0x01) != 0;
    double result;
    if (isInteger) {
      var integer = (value >> 2) & 0x3fffffff;
      if ((integer & 0x20000000) != 0) integer -= 0x40000000;
      result = integer.toDouble();
    } else {
      final bytes = ByteData(8);
      bytes.setUint32(4, value & 0xfffffffc, Endian.little);
      result = bytes.getFloat64(0, Endian.little);
    }
    return divideBy100 ? result / 100 : result;
  }

  static String _formatNumber(double value) {
    if (!value.isFinite) return '';
    if (value == value.truncateToDouble()) return value.toInt().toString();
    return value.toString();
  }

  static String _errorText(int code) => switch (code) {
    0x00 => '#NULL!',
    0x07 => '#DIV/0!',
    0x0f => '#VALUE!',
    0x17 => '#REF!',
    0x1d => '#NAME?',
    0x24 => '#NUM!',
    0x2a => '#N/A',
    _ => '#ERROR',
  };
}

class _BiffRecordType {
  static const eof = 0x000a;
  static const boundSheet = 0x0085;
  static const sst = 0x00fc;
  static const continueRec = 0x003c;
  static const codePage = 0x0042;
  static const dimension = 0x0200;
  static const number = 0x0203;
  static const label = 0x0204;
  static const boolErr = 0x0205;
  static const formula = 0x0006;
  static const string = 0x0207;
  static const rk = 0x027e;
  static const mulRk = 0x00bd;
  static const labelSst = 0x00fd;
}

class _BiffRecord {
  _BiffRecord({required this.type, required this.data, required this.offset});

  final int type;
  final Uint8List data;
  final int offset;

  int uint16(int offset) {
    if (offset < 0 || offset + 2 > data.length) return 0;
    return data[offset] | data[offset + 1] << 8;
  }

  int uint32(int offset) {
    if (offset < 0 || offset + 4 > data.length) return 0;
    return data[offset] |
        data[offset + 1] << 8 |
        data[offset + 2] << 16 |
        data[offset + 3] << 24;
  }

  double float64(int offset) {
    if (offset < 0 || offset + 8 > data.length) return 0;
    return ByteData.sublistView(
      data,
      offset,
      offset + 8,
    ).getFloat64(0, Endian.little);
  }
}

class _BiffRecordCursor {
  _BiffRecordCursor(this.data, {this.position = 0});

  final Uint8List data;
  int position;

  bool get hasMore => position + 4 <= data.length;
  int? get peekType =>
      hasMore ? data[position] | data[position + 1] << 8 : null;

  _BiffRecord? next() {
    if (!hasMore) return null;
    final offset = position;
    final type = data[position] | data[position + 1] << 8;
    final length = data[position + 2] | data[position + 3] << 8;
    position += 4;
    if (position + length > data.length) {
      throw const FormatException('XLS 工作簿记录不完整。');
    }
    final record = _BiffRecord(
      type: type,
      data: Uint8List.sublistView(data, position, position + length),
      offset: offset,
    );
    position += length;
    return record;
  }
}

class _BiffSheetInfo {
  _BiffSheetInfo({
    required this.bofPosition,
    required this.visibility,
    required this.type,
    required this.nameLength,
    required this.nameFlags,
    required this.nameBytes,
  });

  final int bofPosition;
  final int visibility;
  final int type;
  final int nameLength;
  final int nameFlags;
  final Uint8List nameBytes;
  late final String name;

  static _BiffSheetInfo? fromRecord(_BiffRecord record) {
    if (record.data.length < 8) return null;
    final nameLength = record.data[6];
    final unicode = (record.data[7] & 0x01) != 0;
    final byteLength = unicode ? nameLength * 2 : nameLength;
    final available = record.data.length - 8;
    final bytes = Uint8List.fromList(
      record.data.sublist(
        8,
        8 + (byteLength < available ? byteLength : available),
      ),
    );
    return _BiffSheetInfo(
      bofPosition: record.uint32(0),
      visibility: record.data[4],
      type: record.data[5],
      nameLength: nameLength,
      nameFlags: record.data[7],
      nameBytes: bytes,
    );
  }

  _BiffSheetInfo withDecodedName(int codePage) {
    final unicode = (nameFlags & 0x01) != 0;
    name = unicode
        ? _decodeUtf16Le(nameBytes)
        : _decodeCompressed(nameBytes, codePage);
    if (name.isEmpty) name = 'Sheet';
    return this;
  }
}

class _BiffFormulaCell {
  const _BiffFormulaCell(this.row, this.column);

  final int row;
  final int column;
}

class _BiffInlineString {
  static String read(Uint8List data, int offset, int codePage) {
    if (offset < 0 || offset + 3 > data.length) return '';
    final charCount = data[offset] | data[offset + 1] << 8;
    final flags = data[offset + 2];
    var position = offset + 3;
    final unicode = (flags & 0x01) != 0;
    if (unicode) {
      final units = <int>[];
      for (
        var index = 0;
        index < charCount && position + 2 <= data.length;
        index++
      ) {
        units.add(data[position] | data[position + 1] << 8);
        position += 2;
      }
      position += (flags & 0x08) != 0 && position + 2 <= data.length
          ? (data[position] | data[position + 1] << 8) * 4 + 2
          : 0;
      return String.fromCharCodes(units);
    }
    final end = (position + charCount).clamp(position, data.length);
    final value = _decodeCompressed(data.sublist(position, end), codePage);
    return value;
  }
}

class _BiffSharedStringTable {
  _BiffSharedStringTable({required this.segments, required this.codePage});

  final List<Uint8List> segments;
  final int codePage;
  var _segmentIndex = 0;
  var _offset = 0;
  var _unicode = false;

  List<String> read() {
    if (segments.isEmpty) return const [];
    final total = _readUint32Raw();
    final unique = _readUint32Raw();
    if (total == null || unique == null) return const [];
    if (unique > 1000000) {
      throw const FormatException('XLS 共享字符串数量异常，文件可能已损坏。');
    }

    final result = <String>[];
    for (var index = 0; index < unique; index++) {
      final value = _readString();
      if (value == null) break;
      result.add(value);
    }
    return result;
  }

  String? _readString() {
    final charCount = _readUint16Raw();
    final flags = _readByteRaw();
    if (charCount == null || flags == null) return null;
    final hasRichText = (flags & 0x08) != 0;
    final hasExtendedText = (flags & 0x04) != 0;
    final richTextRuns = hasRichText ? _readUint16Raw() : 0;
    final extendedBytes = hasExtendedText ? _readUint32Raw() : 0;
    if (hasRichText && richTextRuns == null ||
        hasExtendedText && extendedBytes == null) {
      return null;
    }

    _unicode = (flags & 0x01) != 0;
    final text = StringBuffer();
    final compressedBytes = <int>[];
    void flushCompressed() {
      if (compressedBytes.isEmpty) return;
      text.write(_decodeCompressed(compressedBytes, codePage));
      compressedBytes.clear();
    }

    for (var index = 0; index < charCount; index++) {
      if (_unicode) {
        flushCompressed();
        final low = _readStringByte();
        final high = _readStringByte();
        if (low == null || high == null) return text.toString();
        text.writeCharCode(low | high << 8);
      } else {
        final byte = _readStringByte();
        if (byte == null) return text.toString();
        compressedBytes.add(byte);
      }
    }
    flushCompressed();

    final richBytes = (richTextRuns ?? 0) * 4;
    final extensionBytes = extendedBytes ?? 0;
    if (richBytes > 0) _skipRaw(richBytes);
    if (extensionBytes > 0) _skipRaw(extensionBytes);
    return text.toString();
  }

  int? _readUint16Raw() {
    final low = _readRawByte();
    final high = _readRawByte();
    if (low == null || high == null) return null;
    return low | high << 8;
  }

  int? _readByteRaw() => _readRawByte();

  int? _readUint32Raw() {
    final b0 = _readRawByte();
    final b1 = _readRawByte();
    final b2 = _readRawByte();
    final b3 = _readRawByte();
    if (b0 == null || b1 == null || b2 == null || b3 == null) return null;
    return b0 | b1 << 8 | b2 << 16 | b3 << 24;
  }

  int? _readRawByte() {
    while (_segmentIndex < segments.length) {
      final segment = segments[_segmentIndex];
      if (_offset < segment.length) return segment[_offset++];
      _segmentIndex++;
      _offset = 0;
    }
    return null;
  }

  int? _readStringByte() {
    while (_segmentIndex < segments.length) {
      final segment = segments[_segmentIndex];
      if (_offset >= segment.length) {
        _segmentIndex++;
        _offset = 0;
        continue;
      }
      // A CONTINUE record starts with the compression flag for the part of
      // the string that follows it. The SST record itself is segment 0.
      if (_segmentIndex > 0 && _offset == 0) {
        _unicode = (segment[_offset++] & 0x01) != 0;
        if (_offset >= segment.length) continue;
      }
      return segment[_offset++];
    }
    return null;
  }

  void _skipRaw(int count) {
    for (var index = 0; index < count; index++) {
      if (_readRawByte() == null) break;
    }
  }
}

String _decodeUtf16Le(List<int> bytes) {
  final units = <int>[];
  for (var index = 0; index + 1 < bytes.length; index += 2) {
    units.add(bytes[index] | bytes[index + 1] << 8);
  }
  return String.fromCharCodes(units);
}

String _decodeCompressed(List<int> bytes, int codePage) {
  if (bytes.isEmpty) return '';
  if (codePage == 65001) {
    return utf8.decode(bytes, allowMalformed: true);
  }
  // BIFF8 normally writes East-Asian text as UTF-16LE even when CODEPAGE is
  // 1200. For byte strings, preserve ASCII/Latin text and avoid replacing
  // unknown bytes with U+FFFD; this is also what older Excel readers expect.
  return String.fromCharCodes(bytes);
}

String? _attribute(XmlElement element, String localName) {
  for (final attribute in element.attributes) {
    if (attribute.localName.toLowerCase() == localName.toLowerCase()) {
      return attribute.value;
    }
  }
  return null;
}

class _DateStyles {
  _DateStyles(this._dateStyles, this._timeOnlyStyles);

  final Set<int> _dateStyles;
  final Set<int> _timeOnlyStyles;

  bool contains(int style) => _dateStyles.contains(style);
  bool isTimeOnly(int style) => _timeOnlyStyles.contains(style);

  factory _DateStyles.fromDocument(ArchiveFile? file) {
    final document = _XlsxReader._document(file);
    if (document == null) return _DateStyles(<int>{}, <int>{});
    final customFormats = <int, String>{
      for (final format in document.findAllElements('numFmt'))
        if (int.tryParse(_attribute(format, 'numFmtId') ?? '') != null)
          int.parse(_attribute(format, 'numFmtId')!):
              (_attribute(format, 'formatCode') ?? ''),
    };
    final dates = <int>{};
    final times = <int>{};
    final xfs = document
        .findAllElements('cellXfs')
        .expand(
          (element) =>
              element.childElements.where((item) => item.localName == 'xf'),
        );
    var style = 0;
    for (final xf in xfs) {
      final id = int.tryParse(_attribute(xf, 'numFmtId') ?? '') ?? 0;
      final code = customFormats[id] ?? _builtInFormat(id);
      if (_looksLikeDateFormat(code)) {
        dates.add(style);
        if (!_containsDateToken(code)) times.add(style);
      }
      style++;
    }
    return _DateStyles(dates, times);
  }

  static String _builtInFormat(int id) => switch (id) {
    14 => 'm/d/yy',
    15 => 'd-mmm-yy',
    16 => 'd-mmm',
    17 => 'mmm-yy',
    18 => 'h:mm AM/PM',
    19 => 'h:mm:ss AM/PM',
    20 => 'h:mm',
    21 => 'h:mm:ss',
    22 => 'm/d/yy h:mm',
    27 || 28 || 29 || 30 || 31 || 32 || 33 || 34 || 35 || 36 => 'date',
    45 => 'mm:ss',
    46 => '[h]:mm:ss',
    47 => 'mm:ss.0',
    _ => '',
  };

  static bool _looksLikeDateFormat(String format) {
    final clean = format
        .replaceAll(RegExp(r'"[^"]*"'), '')
        .replaceAll(RegExp(r'\[[^\]]*\]'), '')
        .toLowerCase();
    return RegExp(r'[dmy]').hasMatch(clean) ||
        RegExp(r'(^|[^a-z])h{1,2}([^a-z]|$)').hasMatch(clean);
  }

  static bool _containsDateToken(String format) {
    final clean = format.toLowerCase();
    return RegExp(r'[dmy]').hasMatch(clean);
  }
}

String _decodeText(List<int> bytes) {
  if (bytes.length >= 2 && bytes[0] == 0xff && bytes[1] == 0xfe) {
    final units = <int>[];
    for (var index = 2; index + 1 < bytes.length; index += 2) {
      units.add(bytes[index] | bytes[index + 1] << 8);
    }
    return String.fromCharCodes(units);
  }
  if (bytes.length >= 2 && bytes[0] == 0xfe && bytes[1] == 0xff) {
    final units = <int>[];
    for (var index = 2; index + 1 < bytes.length; index += 2) {
      units.add(bytes[index] << 8 | bytes[index + 1]);
    }
    return String.fromCharCodes(units);
  }
  return utf8.decode(bytes, allowMalformed: true).replaceFirst('\uFEFF', '');
}

List<List<String>> _parseDelimited(String source, {String delimiter = ','}) {
  final rows = <List<String>>[];
  final row = <String>[];
  final value = StringBuffer();
  var quoted = false;
  for (var index = 0; index < source.length; index++) {
    final char = source[index];
    if (char == '"') {
      if (quoted && index + 1 < source.length && source[index + 1] == '"') {
        value.write('"');
        index++;
      } else {
        quoted = !quoted;
      }
    } else if (char == delimiter && !quoted) {
      row.add(value.toString());
      value.clear();
    } else if ((char == '\n' || char == '\r') && !quoted) {
      if (char == '\r' &&
          index + 1 < source.length &&
          source[index + 1] == '\n') {
        index++;
      }
      row.add(value.toString());
      value.clear();
      rows.add(List<String>.from(row));
      row.clear();
    } else {
      value.write(char);
    }
  }
  if (value.length > 0 || row.isNotEmpty) {
    row.add(value.toString());
    rows.add(List<String>.from(row));
  }
  return rows;
}

String _extension(String fileName) {
  final dot = fileName.lastIndexOf('.');
  return dot == -1 ? '' : fileName.substring(dot + 1).trim().toLowerCase();
}

String _normalizeHeader(String value) => value.trim().toLowerCase().replaceAll(
  RegExp(r'[\s\u3000:：_\-—–()（）【】\[\]]'),
  '',
);

String _cell(List<String> values, int? index) =>
    index == null || index < 0 || index >= values.length
    ? ''
    : values[index].trim();

bool _isBlankRow(List<String> values) =>
    values.every((value) => value.trim().isEmpty);

String _normalizeFlightNumber(String value) => value
    .trim()
    .toUpperCase()
    .replaceAll(RegExp(r'\s+'), '')
    .replaceFirst(RegExp(r'^航班号'), '');

DateTime? _parseDateTime({
  required String dateText,
  required String timeText,
  DateTime? relativeTo,
  bool arrival = false,
}) {
  final directDateTime = _tryDateTime(dateText);
  final directTimeDateTime = _tryDateTime(timeText);
  if (directTimeDateTime != null && _hasDate(timeText)) {
    return _adjustArrivalDate(
      directTimeDateTime,
      relativeTo,
      arrival,
      explicitDate: true,
    );
  }
  if (directDateTime != null && _hasTime(dateText) && timeText.isEmpty) {
    return _adjustArrivalDate(
      directDateTime,
      relativeTo,
      arrival,
      explicitDate: true,
    );
  }
  final base =
      _parseDateOnly(dateText) ??
      (directDateTime != null ? _dateOnly(directDateTime) : null);
  final clock = _parseClock(timeText) ?? _parseClock(dateText);
  if (base == null) {
    if (directTimeDateTime != null) {
      return _adjustArrivalDate(
        directTimeDateTime,
        relativeTo,
        arrival,
        explicitDate: _hasDate(timeText),
      );
    }
    return null;
  }
  final result = DateTime(
    base.year,
    base.month,
    base.day,
    clock?.$1 ?? 0,
    clock?.$2 ?? 0,
    clock?.$3 ?? 0,
  );
  return _adjustArrivalDate(
    result,
    relativeTo,
    arrival,
    explicitDate: _hasDate(timeText),
  );
}

DateTime _adjustArrivalDate(
  DateTime value,
  DateTime? relativeTo,
  bool arrival, {
  required bool explicitDate,
}) {
  if (arrival &&
      relativeTo != null &&
      !explicitDate &&
      value.isBefore(relativeTo)) {
    return value.add(const Duration(days: 1));
  }
  return value;
}

DateTime? _tryDateTime(String value) {
  final raw = value.trim();
  if (raw.isEmpty) return null;
  final excelSerial = double.tryParse(raw);
  if (excelSerial != null && excelSerial >= 1 && excelSerial < 100000) {
    return DateTime.utc(1899, 12, 30).add(
      Duration(
        milliseconds: (excelSerial * Duration.millisecondsPerDay).round(),
      ),
    );
  }
  final normalized = raw
      .trim()
      .replaceAll('年', '-')
      .replaceAll('月', '-')
      .replaceAll('日', ' ')
      .replaceAll('／', '/')
      .replaceAll('：', ':');
  final parsed = DateTime.tryParse(normalized);
  if (parsed != null) return parsed;
  final dateParts = RegExp(
    r'^(\d{4})\s*(?:年|[-/.])\s*(\d{1,2})\s*(?:月|[-/.])\s*(\d{1,2})\s*(?:日)?(?:\s+(.*))?$',
  ).firstMatch(raw);
  if (dateParts != null) {
    try {
      final year = int.parse(dateParts.group(1)!);
      final month = int.parse(dateParts.group(2)!);
      final day = int.parse(dateParts.group(3)!);
      final clock = _parseClock(dateParts.group(4) ?? '');
      return DateTime(
        year,
        month,
        day,
        clock?.$1 ?? 0,
        clock?.$2 ?? 0,
        clock?.$3 ?? 0,
      );
    } on FormatException {
      return null;
    }
  }
  final serial = double.tryParse(normalized.replaceAll(',', ''));
  if (serial == null || serial < 0) return null;
  final day = serial.floor();
  final milliseconds = ((serial - day) * Duration.millisecondsPerDay).round();
  return DateTime(
    1899,
    12,
    30,
  ).add(Duration(days: day, milliseconds: milliseconds));
}

DateTime? _parseDateOnly(String value) {
  final direct = _tryDateTime(value);
  if (direct == null) return null;
  return _dateOnly(direct);
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

bool _hasDate(String value) =>
    RegExp(r'(\d{4}[^\d]?\d{1,2}[^\d]?\d{1,2})').hasMatch(value) ||
    value.contains('年');

bool _hasTime(String value) =>
    RegExp(r'\d{1,2}[:：]\d{2}').hasMatch(value) ||
    RegExp(r'\d{1,2}点').hasMatch(value);

(int, int, int)? _parseClock(String value) {
  final match = RegExp(r'(\d{1,2})\s*[:：]\s*(\d{2})(?:\s*[:：]\s*(\d{2}))?')
      .firstMatch(value);
  if (match != null) {
    final hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    final second = int.tryParse(match.group(3) ?? '0') ?? 0;
    if (hour < 24 && minute < 60 && second < 60) return (hour, minute, second);
  }
  final serial = double.tryParse(value.trim().replaceAll(',', ''));
  if (serial != null && serial >= 0 && serial < 1) {
    final milliseconds = (serial * Duration.millisecondsPerDay).round();
    final duration = Duration(milliseconds: milliseconds);
    final hours = duration.inHours % 24;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;
    return (hours, minutes, seconds);
  }
  final chinese = RegExp(r'(\d{1,2})\s*点(?:\s*(\d{1,2})\s*分?)?')
      .firstMatch(value);
  if (chinese == null) return null;
  final hour = int.parse(chinese.group(1)!);
  final minute = int.tryParse(chinese.group(2) ?? '0') ?? 0;
  return hour < 24 && minute < 60 ? (hour, minute, 0) : null;
}

int? _parseDuration(String value) {
  final text = value.trim().toLowerCase();
  if (text.isEmpty) return null;
  final hour = RegExp(r'(\d+(?:\.\d+)?)\s*(?:小时|小時|h)').firstMatch(text);
  final minute = RegExp(r'(\d+)\s*(?:分钟|分鐘|min|m)').firstMatch(text);
  if (hour != null || minute != null) {
    final hours = hour == null
        ? 0
        : (double.parse(hour.group(1)!) * 60).round();
    final minutes = minute == null ? 0 : int.parse(minute.group(1)!);
    return hours + minutes;
  }
  final numeric = double.tryParse(text.replaceAll(',', ''));
  return numeric == null || numeric <= 0 ? null : numeric.round();
}

double? _parseDistance(String value) {
  final text = value.trim().replaceAll(',', '');
  if (text.isEmpty) return null;
  final match = RegExp(r'-?\d+(?:\.\d+)?').firstMatch(text);
  final number = match == null ? null : double.tryParse(match.group(0)!);
  return number == null || number <= 0 ? null : number;
}

extension on String {
  String? get nullIfEmpty => trim().isEmpty ? null : trim();
}
