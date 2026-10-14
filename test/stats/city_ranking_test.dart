import 'package:flutter_test/flutter_test.dart';
import 'package:flight_footprint/domain/airport.dart';
import 'package:flight_footprint/domain/flight.dart';
import 'package:flight_footprint/features/stats/city_ranking.dart';

void main() {
  const airports = <String, Airport>{
    'PVG': Airport(
      iataCode: 'PVG',
      longitude: 0,
      latitude: 0,
      name: 'Pudong',
      city: 'Shanghai',
      countryCode: 'CN',
    ),
    'SHA': Airport(
      iataCode: 'SHA',
      longitude: 0,
      latitude: 0,
      name: 'Hongqiao',
      city: 'Shanghai',
      countryCode: 'CN',
    ),
    'AAA': Airport(
      iataCode: 'AAA',
      longitude: 0,
      latitude: 0,
      name: 'Airport A',
      city: 'Springfield',
      countryCode: 'US',
    ),
    'BBB': Airport(
      iataCode: 'BBB',
      longitude: 0,
      latitude: 0,
      name: 'Airport B',
      city: 'Springfield',
      countryCode: 'CA',
    ),
    'CCC': Airport(
      iataCode: 'CCC',
      longitude: 0,
      latitude: 0,
      name: 'Airport C',
      city: '  ',
      countryCode: 'CA',
    ),
  };

  Airport? airportFor(String code) => airports[code];
  String cityNameFor(Airport airport) => airport.city;
  String countryNameFor(Airport airport) => switch (airport.countryCode) {
    'CN' => 'China',
    'US' => 'United States',
    'CA' => 'Canada',
    _ => '',
  };

  Flight flight(
    String id,
    String from,
    String to,
    DateTime date, {
    FlightStatus status = FlightStatus.completed,
  }) => Flight(
    id: id,
    departureIata: from,
    arrivalIata: to,
    departedAt: date,
    createdAt: date,
    updatedAt: date,
    status: status,
  );

  test('merges airports in one city and counts both flight endpoints', () {
    final one = flight('1', 'PVG', 'AAA', DateTime(2024));
    final two = flight('2', 'SHA', 'PVG', DateTime(2025));
    final result = buildCityRanking(
      [one, two],
      airportFor: airportFor,
      cityNameFor: cityNameFor,
      countryNameFor: countryNameFor,
    );

    final shanghai = result.singleWhere((entry) => entry.key == 'CN:shanghai');
    expect(shanghai.count, 3);
    expect(shanghai.flights, [two, one]);
    expect(shanghai.flights, hasLength(2));
    expect(shanghai.flights, isA<List<Flight>>());
    expect(() => shanghai.flights.add(one), throwsUnsupportedError);
  });

  test('keeps same-named cities in different countries distinct', () {
    final result = buildCityRanking(
      [flight('1', 'AAA', 'BBB', DateTime(2024))],
      airportFor: airportFor,
      cityNameFor: cityNameFor,
      countryNameFor: countryNameFor,
    );

    final springfields = result.where((entry) => entry.name == 'Springfield');
    expect(springfields.map((entry) => entry.key).toSet(), {
      'US:springfield',
      'CA:springfield',
    });
    expect(springfields.every((entry) => entry.count == 1), isTrue);
  });

  test('counts both same-city endpoints but associates a flight once', () {
    final sameCity = flight('1', 'PVG', 'SHA', DateTime(2024));
    final result = buildCityRanking(
      [sameCity],
      airportFor: airportFor,
      cityNameFor: cityNameFor,
      countryNameFor: countryNameFor,
    );

    expect(result.single.count, 2);
    expect(result.single.flights, [sameCity]);
  });

  test('skips upcoming flights and endpoints without usable city data', () {
    final result = buildCityRanking(
      [
        flight(
          'future',
          'AAA',
          'BBB',
          DateTime(2027),
          status: FlightStatus.upcoming,
        ),
        flight('missing', 'UNKNOWN', 'CCC', DateTime(2024)),
      ],
      airportFor: airportFor,
      cityNameFor: cityNameFor,
      countryNameFor: countryNameFor,
    );

    expect(result, isEmpty);
  });

  test('orders ties consistently by city and then country', () {
    final result = buildCityRanking(
      [flight('1', 'BBB', 'AAA', DateTime(2024))],
      airportFor: airportFor,
      cityNameFor: cityNameFor,
      countryNameFor: countryNameFor,
    );

    expect(result.map((entry) => entry.key).toList(), [
      'CA:springfield',
      'US:springfield',
    ]);
  });
}
