import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel2003/excel2003.dart';
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

  SpreadsheetImportResult parse({
    required List<int> bytes,
    required String fileName,
    DateTime? now,
  }) {
    final extension = _extension(fileName);
    final sheets = switch (extension) {
      'csv' => [_SpreadsheetSheet('CSV', _parseDelimited(_decodeText(bytes)))],
      'xlsx' => _XlsxReader().read(bytes),
      'xls' => _XlsReader().read(bytes),
      _ => throw const FormatException('目前支持 .xlsx、.xls 或 .csv 文件。'),
    };
    if (sheets.isEmpty) {
      throw const FormatException('表格中没有可读取的工作表。');
    }

    final candidates = <_SheetHeader>[
      for (final sheet in sheets)
        if (_HeaderMap.find(sheet.rows) case final header?)
          _SheetHeader(sheet, header),
    ];
    if (candidates.isNotEmpty) {
      final named = candidates
          .where((candidate) => _isImportableSheet(candidate.sheet.name))
          .toList(growable: false);
      final selected = named.isEmpty ? candidates : named;
      final parsed = [
        for (final candidate in selected)
          _parseSheet(candidate.sheet, candidate.header, now ?? DateTime.now()),
      ];
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
    throw const FormatException('未找到航旅纵横表头。需要包含：日期、航空公司、航班号、出发城市和到达城市。');
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
    final codes = RegExp(r'(?<![A-Za-z])([A-Za-z]{3})(?![A-Za-z])')
        .allMatches(value)
        .map((match) => match.group(1)!.toUpperCase());
    for (final code in codes) {
      final airport = airports.findByIata(code);
      if (airport != null) return _AirportMatch(airport, false);
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
    if (candidates.isEmpty) return null;
    return _AirportMatch(candidates.first, candidates.length > 1);
  }

  static FlightStatus _statusForDate(DateTime date, DateTime now) {
    final flightDay = DateTime(date.year, date.month, date.day);
    final today = DateTime(now.year, now.month, now.day);
    return flightDay.isAfter(today)
        ? FlightStatus.upcoming
        : FlightStatus.completed;
  }
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
class _XlsReader {
  List<_SpreadsheetSheet> read(List<int> bytes) {
    final reader = XlsReader.fromBytes(Uint8List.fromList(bytes));
    final result = <_SpreadsheetSheet>[];
    for (var index = 0; index < reader.sheetCount; index++) {
      final sheet = reader.sheet(index);
      final rows = <List<String>>[];
      for (var row = sheet.firstRow; row < sheet.lastRow; row++) {
        final values = <String>[];
        for (var column = sheet.firstCol; column < sheet.lastCol; column++) {
          values.add(_stringify(sheet.cell(row, column)));
        }
        rows.add(values);
      }
      result.add(_SpreadsheetSheet(sheet.name, rows));
    }
    return result;
  }

  static String _stringify(Object? value) {
    if (value == null) return '';
    if (value is DateTime) {
      final local = value.toLocal();
      String two(int part) => part.toString().padLeft(2, '0');
      return '${local.year}-${two(local.month)}-${two(local.day)} '
          '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
    }
    return value.toString();
  }
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
