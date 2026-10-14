import 'package:flight_footprint/domain/flight.dart';
import 'package:flight_footprint/features/stats/aircraft_collection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Flight flight(
    String id, {
    String? type,
    double? distance,
    String date = '2026-01-01T10:00:00Z',
    FlightStatus status = FlightStatus.completed,
  }) => Flight(
    id: id,
    departureIata: 'PVG',
    arrivalIata: 'PEK',
    departedAt: DateTime.parse(date),
    createdAt: DateTime.parse(date),
    updatedAt: DateTime.parse(date),
    aircraftType: type,
    distanceKm: distance,
    status: status,
  );

  test('groups case and whitespace with explicit matching brand prefixes', () {
    final entries = buildAircraftCollection([
      flight('1', type: '  Airbus   a320  '),
      flight('2', type: '空客 A320'),
      flight('3', type: '空中客车A320'),
      flight('4', type: 'a320'),
      flight('5', type: ' Boeing 737   MAX 8 '),
      flight('6', type: '波音737 max 8'),
    ]);

    expect(entries.map((entry) => entry.type), ['A320', '737 MAX 8']);
    expect(entries.map((entry) => entry.key), ['A320', '737 MAX 8']);
    expect(entries.map((entry) => entry.count), [4, 2]);
    expect(entries.first.manufacturer, AircraftManufacturer.airbus);
    expect(entries.last.manufacturer, AircraftManufacturer.boeing);
  });

  test('only includes completed records with a usable recorded type', () {
    final entries = buildAircraftCollection([
      flight('null'),
      flight('blank', type: ' \t\n '),
      flight('unknown', type: ' Unknown '),
      flight('unknown-cn', type: '未知机型'),
      flight('na', type: 'N/A'),
      flight('future', type: 'A350', status: FlightStatus.upcoming),
      flight('known', type: 'C919'),
    ]);

    expect(entries, hasLength(1));
    expect(entries.single.type, 'C919');
    expect(entries.single.count, 1);
    expect(entries.single.manufacturer, AircraftManufacturer.other);
  });

  test('keeps specific models and MAX or NEO variants separate', () {
    final types = [
      'A320',
      'A320NEO',
      'A320-200',
      'A321NEO',
      '737',
      'B737',
      '737-800',
      '737 MAX 8',
      '737 MAX 9',
    ];
    final entries = buildAircraftCollection([
      for (var index = 0; index < types.length; index++)
        flight('$index', type: types[index]),
    ]);

    expect(entries, hasLength(types.length));
    expect(entries.map((entry) => entry.type), containsAll(types));
    expect(entries.every((entry) => entry.count == 1), isTrue);
  });

  test('identifies bounded Airbus and known Boeing codes conservatively', () {
    final expected = {
      'A220-300': AircraftManufacturer.airbus,
      'A350': AircraftManufacturer.airbus,
      'A321XLR': AircraftManufacturer.airbus,
      'B777-300ER': AircraftManufacturer.boeing,
      '787-9': AircraftManufacturer.boeing,
      'B737MAX 8': AircraftManufacturer.boeing,
      'C919': AircraftManufacturer.other,
      'ARJ21': AircraftManufacturer.other,
      'EMBRAER E190': AircraftManufacturer.other,
      'A320ISH': AircraftManufacturer.other,
      'A299': AircraftManufacturer.other,
      'A399': AircraftManufacturer.other,
      'B737XYZ': AircraftManufacturer.other,
      'B799': AircraftManufacturer.other,
      'UNKNOWN A320': AircraftManufacturer.other,
      'AIRBUS MYSTERY': AircraftManufacturer.other,
      'BOEING A320': AircraftManufacturer.other,
      'AIRBUSINESS A320': AircraftManufacturer.other,
      '国产 客机': AircraftManufacturer.other,
    };
    final entries = buildAircraftCollection([
      for (final type in expected.keys) flight(type, type: type),
    ]);

    for (final entry in entries) {
      expect(entry.manufacturer, expected[entry.type], reason: entry.type);
    }
    expect(entries, hasLength(expected.length));
  });

  test('deduplicates IDs globally using the first eligible record', () {
    final first = flight('duplicate', type: 'A320', distance: 100);
    final entries = buildAircraftCollection([
      flight('later-valid', type: 'A350', status: FlightStatus.upcoming),
      flight('later-valid'),
      first,
      first,
      flight('duplicate', type: 'B787', distance: 200),
      flight('later-valid', type: 'A350', distance: 300),
    ]);

    expect(entries.map((entry) => entry.type), ['A320', 'A350']);
    expect(entries.fold<int>(0, (total, entry) => total + entry.count), 2);
    expect(entries.first.flights.single, same(first));
  });

  test(
    'sums finite nonnegative distances and ignores missing or invalid data',
    () {
      final distances = <double?>[
        null,
        0,
        123.5,
        456.25,
        -10,
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ];
      final entries = buildAircraftCollection([
        for (var index = 0; index < distances.length; index++)
          flight('$index', type: 'A320', distance: distances[index]),
      ]);

      expect(entries.single.count, 8);
      expect(entries.single.distanceKm, 579.75);
    },
  );

  test(
    'orders count descending, then type ascending and flights newest first',
    () {
      final oldest = flight('old', type: 'A320', date: '2025-01-01T10:00:00Z');
      final newestB = flight('b', type: 'A320');
      final newestA = flight('a', type: 'A320');
      final entries = buildAircraftCollection([
        flight('c919', type: 'C919'),
        oldest,
        newestB,
        flight('a350', type: 'A350'),
        newestA,
      ]);

      expect(entries.map((entry) => entry.type), ['A320', 'A350', 'C919']);
      expect(entries.first.flights, [newestA, newestB, oldest]);
    },
  );

  test('does not mutate inputs and exposes immutable snapshot lists', () {
    final oldest = flight('old', type: 'A320', date: '2025-01-01T10:00:00Z');
    final newest = flight('new', type: 'A320');
    final input = [oldest, newest];
    final entries = buildAircraftCollection(input);

    expect(input, [oldest, newest]);
    expect(() => entries.clear(), throwsUnsupportedError);
    expect(() => entries.single.flights.add(oldest), throwsUnsupportedError);
    expect(() => entries.single.flights[0] = oldest, throwsUnsupportedError);
    input.clear();
    expect(entries.single.count, 2);

    final source = [oldest];
    final entry = AircraftCollectionEntry(
      key: 'A320',
      type: 'A320',
      manufacturer: AircraftManufacturer.airbus,
      flights: source,
    );
    source.add(newest);
    expect(entry.count, 1);
    expect(entry.distanceKm, 0);
    expect(() => entry.flights.clear(), throwsUnsupportedError);
  });

  test('empty input returns an empty immutable collection', () {
    final entries = buildAircraftCollection(const []);
    expect(entries, isEmpty);
    expect(() => entries.clear(), throwsUnsupportedError);
  });
}
