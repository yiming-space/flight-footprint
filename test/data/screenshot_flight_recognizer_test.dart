import 'package:flight_footprint/data/airport_catalog.dart';
import 'package:flight_footprint/data/screenshot_flight_recognizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final airports = AirportCatalog.fromJsonString('''{
    "SZX": [113.8, 22.6, "Shenzhen", "Shenzhen", "CN"],
    "PEK": [116.6, 40.1, "Beijing", "Beijing", "CN"],
    "PKX": [116.4, 39.5, "Daxing", "Beijing", "CN"],
    "SHA": [121.3, 31.2, "Shanghai", "Shanghai", "CN"]
  }''');

  test('extracts unambiguous flight details into a draft', () {
    final draft = parseScreenshotFlight([
      'CA1234',
      'SZX → PEK',
      '2026年11月18日',
      '08:35',
    ], airports);
    expect(draft.identity, 'CA1234');
    expect(draft.departureIata, 'SZX');
    expect(draft.arrivalIata, 'PEK');
    expect(draft.date, DateTime(2026, 11, 18, 8, 35));
    expect(draft.dateTouched, isTrue);
  });

  test('resolves explicit Chinese airport names', () {
    final draft = parseScreenshotFlight([
      'CA1234',
      '深圳宝安 → 北京首都',
      '2026-11-18',
      '08:35',
    ], airports);
    expect(draft.departureIata, 'SZX');
    expect(draft.arrivalIata, 'PEK');
  });

  test('leaves an ambiguous city unset for the user to choose', () {
    final draft = parseScreenshotFlight([
      'CA1234',
      '深圳宝安 → 北京',
      '2026-11-18',
      '08:35',
    ], airports);
    expect(draft.departureIata, 'SZX');
    expect(draft.arrivalIata, isNull);
  });

  test('does not guess multiple flight numbers, airports or times', () {
    final draft = parseScreenshotFlight([
      'CA1234 MU5678',
      'SZX PEK SHA',
      '2026-11-18',
      '08:35 11:15',
    ], airports);
    expect(draft.identity, isEmpty);
    expect(draft.departureIata, isNull);
    expect(draft.arrivalIata, isNull);
    expect(draft.date, isNull);
    expect(draft.dateTouched, isFalse);
  });

  test('recognizes explicitly labelled departure and next-day arrival', () {
    final draft = parseScreenshotFlight([
      'CA1234',
      'SZX PEK',
      '2026-11-18',
      '起飞 23:30',
      '次日到达 02:15',
    ], airports);
    expect(draft.date, DateTime(2026, 11, 18, 23, 30));
    expect(draft.arrivalAt, DateTime(2026, 11, 19, 2, 15));
  });

  test('does not infer an unmarked next-day arrival', () {
    final draft = parseScreenshotFlight([
      'CA1234',
      'SZX PEK',
      '2026-11-18',
      '起飞 23:30',
      '到达 02:15',
    ], airports);
    expect(draft.date, DateTime(2026, 11, 18, 23, 30));
    expect(draft.arrivalAt, isNull);
  });

  test('separates clear consecutive flight sections', () {
    final drafts = parseScreenshotFlights([
      'CA1234',
      'SZX PEK',
      '2026-11-18',
      '起飞 08:30',
      '到达 11:30',
      'MU5678',
      'PEK SHA',
      '2026-11-19',
      '起飞 12:00',
      '到达 14:00',
    ], airports);
    expect(drafts.length, 2);
    expect(drafts.map((d) => d.identity), ['CA1234', 'MU5678']);
    expect(drafts[1].arrivalIata, 'SHA');
  });

  test(
    'rejects invalid dates and does not infer a date from the current year',
    () {
      final draft = parseScreenshotFlight([
        'CA1234',
        '2026-02-30',
        '09:00',
      ], airports);
      expect(draft.date, isNull);
      expect(draft.dateTouched, isFalse);
    },
  );
}
