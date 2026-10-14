import 'package:flight_footprint/domain/flight.dart';
import 'package:flight_footprint/features/stats/airline_ranking.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Flight flight(
    String id, {
    String? airline,
    String? number,
    String date = '2026-01-01T10:00:00Z',
    FlightStatus status = FlightStatus.completed,
  }) => Flight(
    id: id,
    departureIata: 'PVG',
    arrivalIata: 'PEK',
    departedAt: DateTime.parse(date),
    createdAt: DateTime.parse(date),
    updatedAt: DateTime.parse(date),
    airline: airline,
    flightNumber: number,
    status: status,
  );

  test('groups canonical Chinese, English, aliases, IATA and ICAO names', () {
    final ranking = buildAirlineRanking([
      flight('1', airline: '中国国际航空'),
      flight('2', airline: 'Air China'),
      flight('3', airline: '国航'),
      flight('4', airline: ' ca '),
      flight('5', airline: 'CCA'),
    ]);

    expect(ranking, hasLength(1));
    expect(ranking.single.name, '中国国际航空');
    expect(ranking.single.iataCode, 'CA');
    expect(ranking.single.count, 5);
  });

  test(
    'recovers known IATA, ICAO and alphanumeric prefixes for blank names',
    () {
      final ranking = buildAirlineRanking([
        flight('1', number: 'SA789'),
        flight('2', airline: ' ', number: 'KAL123'),
        flight('3', number: '6e 123'),
      ]);

      expect(
        ranking.map((item) => item.iataCode),
        containsAll(['SA', 'KE', '6E']),
      );
      expect(ranking.fold<int>(0, (sum, item) => sum + item.count), 3);
    },
  );

  test('does not infer an airline from unknown or invalid bare prefixes', () {
    final ranking = buildAirlineRanking([
      flight('1', number: 'ZZ123'),
      flight('2', number: '1234'),
      flight('3', number: 'SA'),
      flight('4', number: 'unknown'),
      flight('5'),
    ]);

    expect(ranking, isEmpty);
  });

  test(
    'preserves unknown labels and groups case and whitespace variations',
    () {
      final ranking = buildAirlineRanking([
        flight('1', airline: '  Acme   Air  '),
        flight('2', airline: 'acme air'),
      ]);

      expect(ranking.single.name, 'Acme Air');
      expect(ranking.single.iataCode, isNull);
      expect(ranking.single.count, 2);
    },
  );

  test('explicit airlines win over codeshare flight number prefixes', () {
    final ranking = buildAirlineRanking([
      flight('1', airline: 'Hainan Airlines', number: 'CA123'),
      flight('2', airline: 'Acme Air', number: 'CA456'),
    ]);

    final known = ranking.singleWhere((item) => item.iataCode != null);
    final unknown = ranking.singleWhere((item) => item.iataCode == null);
    expect(known.iataCode, 'HU');
    expect(unknown.name, 'Acme Air');
    expect(ranking.every((item) => item.iataCode != 'CA'), isTrue);
  });

  test('counts each completed flight once and excludes upcoming records', () {
    final ranking = buildAirlineRanking([
      flight('1', airline: 'CA'),
      flight('2', airline: 'CA', status: FlightStatus.upcoming),
      flight('3', airline: 'CA'),
    ]);

    expect(ranking.single.count, 2);
    expect(ranking.single.flights.map((item) => item.id), ['1', '3']);
  });

  test('sorts count descending with alphabetical ties deterministically', () {
    final ranking = buildAirlineRanking([
      flight('1', airline: 'Zulu Air'),
      flight('2', airline: 'Alpha Air'),
      flight('3', airline: 'Busy Air'),
      flight('4', airline: 'Busy Air'),
    ]);

    expect(ranking.map((item) => item.name), [
      'Busy Air',
      'Alpha Air',
      'Zulu Air',
    ]);
  });

  test(
    'sorts drilldown newest first without mutating input records or order',
    () {
      final oldest = flight('old', airline: 'CA', date: '2025-01-01T10:00:00Z');
      final newest = flight('new', airline: 'CA', date: '2026-01-01T10:00:00Z');
      final input = [oldest, newest];
      final ranking = buildAirlineRanking(input);

      expect(input, [oldest, newest]);
      expect(ranking.single.flights, [newest, oldest]);
      expect(identical(ranking.single.flights.last, oldest), isTrue);
      expect(() => ranking.single.flights.add(oldest), throwsUnsupportedError);
      expect(() => ranking.clear(), throwsUnsupportedError);
    },
  );
}
