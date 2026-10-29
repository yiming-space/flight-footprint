import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'airport_catalog.dart';
import 'airport_localization.dart';
import 'flight_draft_store.dart';

/// OCR stays on the device. Recognition is only a draft, never an import.
class ScreenshotFlightRecognizer {
  const ScreenshotFlightRecognizer({
    this.channel = const MethodChannel('flight_footprint/screenshot_ocr'),
  });
  final MethodChannel channel;

  Future<List<String>> recognize(Uint8List image) async {
    final lines = await channel.invokeListMethod<String>('recognize', {
      'image': image,
    });
    return List.unmodifiable(lines ?? const []);
  }
}

final _flightNumberPattern = RegExp(
  r'(?<![A-Z0-9])(?:[A-Z]{2,3}|[A-Z][0-9]|[0-9][A-Z])[ \t]*\d{1,4}[A-Z]?(?![A-Z0-9])',
);

final _chineseAirportAliases = Expando<Map<String, Set<String>>>();

List<Set<String>> _chineseAirportMentions(
  String text,
  AirportCatalog airports,
) {
  final index = _chineseAirportAliases[airports] ??= () {
    final result = <String, Set<String>>{};
    for (final airport in airports.values) {
      final aliases = {
        localizedAirportCity(airport),
        localizedAirportName(airport),
        ...localizedAirportSearchAliases(airport),
      };
      for (final alias in aliases) {
        final trimmed = alias.trim();
        if (trimmed.length >= 2 &&
            RegExp(r'^[\u4e00-\u9fff]+$').hasMatch(trimmed)) {
          result.putIfAbsent(trimmed, () => <String>{}).add(airport.iataCode);
        }
      }
    }
    return result;
  }();
  final matches = <({int start, int end, Set<String> codes})>[];
  for (final entry in index.entries) {
    var offset = 0;
    while (offset < text.length) {
      final position = text.indexOf(entry.key, offset);
      if (position < 0) break;
      matches.add((
        start: position,
        end: position + entry.key.length,
        codes: entry.value,
      ));
      offset = position + entry.key.length;
    }
  }
  // Longest mention wins over overlapping city and shorter airport aliases.
  matches.sort((a, b) {
    final length = (b.end - b.start).compareTo(a.end - a.start);
    return length != 0 ? length : a.start.compareTo(b.start);
  });
  final selected = <({int start, int end, Set<String> codes})>[];
  for (final match in matches) {
    if (selected.any(
      (item) => match.start < item.end && item.start < match.end,
    ))
      continue;
    selected.add(match);
  }
  selected.sort((a, b) => a.start.compareTo(b.start));
  final distinct = <Set<String>>[];
  for (final mention in selected) {
    if (!distinct.any(
      (value) =>
          value.length == mention.codes.length &&
          value.containsAll(mention.codes),
    ))
      distinct.add(mention.codes);
  }
  return distinct;
}

/// Split only when separate flight numbers each start a clear route section.
/// Ambiguous screenshots remain a single editable draft.
List<FlightDraft> parseScreenshotFlights(
  List<String> lines,
  AirportCatalog airports,
) {
  final starts = <int>[];
  for (var i = 0; i < lines.length; i++) {
    if (_flightNumberPattern.hasMatch(lines[i].toUpperCase())) starts.add(i);
  }
  if (starts.length < 2) return [parseScreenshotFlight(lines, airports)];
  final result = <FlightDraft>[];
  for (var i = 0; i < starts.length; i++) {
    final draft = parseScreenshotFlight(
      lines.sublist(
        starts[i],
        i + 1 < starts.length ? starts[i + 1] : lines.length,
      ),
      airports,
    );
    if (draft.identity.isEmpty ||
        draft.departureIata == null ||
        draft.arrivalIata == null) {
      return [parseScreenshotFlight(lines, airports)];
    }
    result.add(draft);
  }
  return result;
}

/// Only fill fields that can be identified unambiguously. All results remain
/// editable; airport-local dates and times are never inferred across timezones.
FlightDraft parseScreenshotFlight(List<String> lines, AirportCatalog airports) {
  final text = lines.join('\n').toUpperCase();
  final codes = <String>[];
  for (final match in RegExp(
    r'(?<![A-Z0-9])[A-Z]{3}(?![A-Z0-9])',
  ).allMatches(text)) {
    final code = match.group(0)!;
    if (airports.findByIata(code) != null && !codes.contains(code))
      codes.add(code);
  }
  String? departureIata = codes.length == 2 ? codes[0] : null;
  String? arrivalIata = codes.length == 2 ? codes[1] : null;
  if (codes.isEmpty) {
    final mentions = _chineseAirportMentions(text, airports);
    if (mentions.length == 2) {
      if (mentions[0].length == 1) departureIata = mentions[0].single;
      if (mentions[1].length == 1) arrivalIata = mentions[1].single;
    }
  }
  final numbers = _flightNumberPattern
      .allMatches(text)
      .map((m) => m.group(0)!.replaceAll(RegExp(r'\s+'), ''))
      .toSet();
  final dates = <DateTime>[];
  for (final match in RegExp(
    r'(?<!\d)(20\d{2})\s*[-/.年]\s*(\d{1,2})\s*[-/.月]\s*(\d{1,2})\s*日?',
  ).allMatches(text)) {
    final year = int.parse(match[1]!);
    final month = int.parse(match[2]!);
    final day = int.parse(match[3]!);
    final date = DateTime(year, month, day);
    if (date.year == year &&
        date.month == month &&
        date.day == day &&
        !dates.any((d) => d == date))
      dates.add(date);
  }
  final times = RegExp(r'(?<!\d)([01]?\d|2[0-3])[:：]([0-5]\d)(?!\d)')
      .allMatches(text)
      .toList();
  DateTime? departure;
  DateTime? arrival;
  if (dates.length == 1 && times.length == 1) {
    final day = dates.single;
    final clock = times.single;
    departure = DateTime(
      day.year,
      day.month,
      day.day,
      int.parse(clock[1]!),
      int.parse(clock[2]!),
    );
  }
  // Explicit labels permit distinguishing two clocks. Never infer a date
  // across midnight unless the screenshot explicitly says next day.
  DateTime? labelledTime(RegExp label) {
    final matches = lines.where((line) => label.hasMatch(line)).toList();
    if (matches.length != 1 || dates.isEmpty) return null;
    final clocks = RegExp(r'(?<!\d)([01]?\d|2[0-3])[:：]([0-5]\d)(?!\d)')
        .allMatches(matches.single)
        .toList();
    if (clocks.length != 1) return null;
    final dateMatch = RegExp(
      r'(?<!\d)(20\d{2})\s*[-/.年]\s*(\d{1,2})\s*[-/.月]\s*(\d{1,2})',
    ).firstMatch(matches.single);
    DateTime day;
    if (dateMatch != null) {
      day = DateTime(
        int.parse(dateMatch[1]!),
        int.parse(dateMatch[2]!),
        int.parse(dateMatch[3]!),
      );
      if (day.month != int.parse(dateMatch[2]!) ||
          day.day != int.parse(dateMatch[3]!))
        return null;
    } else if (dates.length == 1) {
      day = dates.single;
      if (RegExp(
        r'次日|翌日|NEXT\s*DAY|\+1',
        caseSensitive: false,
      ).hasMatch(matches.single))
        day = day.add(const Duration(days: 1));
    } else {
      return null;
    }
    return DateTime(
      day.year,
      day.month,
      day.day,
      int.parse(clocks.single[1]!),
      int.parse(clocks.single[2]!),
    );
  }

  departure ??= labelledTime(
    RegExp(r'起飞|出发|起飛|出發|DEPART', caseSensitive: false),
  );
  arrival = labelledTime(RegExp(r'到达|抵达|降落|到達|抵達|ARRIV', caseSensitive: false));
  if (arrival != null &&
      departure != null &&
      dates.length == 1 &&
      arrival.isBefore(departure) &&
      !lines.any(
        (line) => RegExp(
          r'次日|翌日|NEXT\s*DAY|\+1',
          caseSensitive: false,
        ).hasMatch(line),
      ))
    arrival = null;
  return FlightDraft(
    departureIata: departureIata,
    arrivalIata: arrivalIata,
    identity: numbers.length == 1 ? numbers.single : '',
    date: departure,
    dateTouched: departure != null,
    arrivalAt: arrival,
    arrivalTouched: arrival != null,
  );
}
