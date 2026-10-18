import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flight_footprint/data/airport_catalog.dart';
import 'package:flight_footprint/data/airport_localization.dart';
import 'package:flight_footprint/data/city_catalog.dart';
import 'package:flight_footprint/domain/airport.dart';
import 'package:flight_footprint/domain/flight.dart';
import 'package:flight_footprint/domain/visited_place.dart';
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

  VisitedPlace place(
    String id,
    String name, {
    String? countryCode = 'CN',
    double latitude = 0,
    double longitude = 0,
  }) => VisitedPlace(
    id: id,
    name: name,
    latitude: latitude,
    longitude: longitude,
    countryCode: countryCode,
    visitedAt: DateTime(2025),
    createdAt: DateTime(2025),
    updatedAt: DateTime(2025),
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

  test('combines flight cities and footprints without duplicating cities', () {
    final one = flight('flight', 'PVG', 'AAA', DateTime(2024));
    final manual = place('manual', 'Shanghai');
    final footprintOnly = place('new-city', 'Beijing');
    final result = buildCityRanking(
      [one],
      airportFor: airportFor,
      cityNameFor: cityNameFor,
      countryNameFor: countryNameFor,
      visitedPlaces: [manual, footprintOnly, manual],
    );
    expect(result, hasLength(3));
    final shanghai = result.singleWhere((entry) => entry.name == 'Shanghai');
    expect(shanghai.count, 2);
    expect(shanghai.flights, [one]);
    expect(shanghai.visitedPlaces, [manual]);
    expect(() => shanghai.visitedPlaces.clear(), throwsUnsupportedError);
    final beijing = result.singleWhere((entry) => entry.name == 'Beijing');
    expect(beijing.flights, isEmpty);
    expect(beijing.visitedPlaces, [footprintOnly]);
  });

  test('uses exact catalogue aliases without a nearest-city fallback', () {
    final catalog = CityCatalog([
      const CityCenter(
        name: '上海',
        aliases: ['Shanghai'],
        longitude: 0,
        latitude: 0,
        province: '上海市',
      ),
    ]);
    final result = buildCityRanking(
      [flight('1', 'PVG', 'AAA', DateTime(2024))],
      airportFor: airportFor,
      cityNameFor: cityNameFor,
      countryNameFor: countryNameFor,
      cityCatalog: catalog,
      visitedPlaces: [
        place('same-city', '上海市'),
        place('nearby-other-city', '苏州', latitude: .2),
        place('province', '浙江省', latitude: .2),
      ],
    );
    expect(result, hasLength(3));
    final shanghai = result.singleWhere((entry) => entry.key == 'CN:上海');
    expect(shanghai.count, 2);
    // Canonical keys unify aliases; the display callback retains its language.
    expect(shanghai.name, 'Shanghai');
    expect(result.singleWhere((entry) => entry.name == '苏州').count, 1);
    expect(result.any((entry) => entry.name == '浙江省'), isFalse);
  });

  test('keeps far same-country homonyms and foreign names distinct', () {
    final result = buildCityRanking(
      const [],
      airportFor: airportFor,
      cityNameFor: cityNameFor,
      countryNameFor: countryNameFor,
      visitedPlaces: [
        place('a', 'Springfield', countryCode: 'US', latitude: 40),
        place('b', 'Springfield', countryCode: 'US', latitude: 35),
        place('c', 'Springfield', countryCode: 'CA', latitude: 40),
      ],
    );
    expect(result, hasLength(3));
    expect(result.map((entry) => entry.key).toSet(), hasLength(3));
    expect(result.every((entry) => entry.count == 1), isTrue);
  });

  test('a footprint-only city remains available with no flights', () {
    final result = buildCityRanking(
      const [],
      airportFor: airportFor,
      cityNameFor: cityNameFor,
      countryNameFor: countryNameFor,
      countryNameForCode: (code) => code == 'CN' ? 'China' : code,
      visitedPlaces: [place('only', 'Beijing')],
    );
    expect(result.single.name, 'Beijing');
    expect(result.single.countryName, 'China');
    expect(result.single.count, 1);
    expect(result.single.flights, isEmpty);
    expect(cityVisitSummary(result.length, isZh: true), '到访 1 座城市');
    expect(cityVisitSummary(result.length, isZh: false), '1 city visited');
    expect(cityVisitSummary(2, isZh: false), '2 cities visited');
  });

  test('Hong Kong and Macau cities survive province-label filtering', () {
    final bundledAirports = AirportCatalog.fromJsonString(
      File(AirportCatalog.assetPath).readAsStringSync(),
    );
    final cityCatalog = CityCatalog.fromJsonString(
      File(CityCatalog.assetPath).readAsStringSync(),
    ).withAirports(bundledAirports);
    final result = buildCityRanking(
      [flight('regions', 'HKG', 'MFM', DateTime(2025))],
      airportFor: bundledAirports.findByIata,
      cityNameFor: localizedAirportCity,
      countryNameFor: (airport) => localizedCountryName(airport.countryCode),
      cityCatalog: cityCatalog,
      visitedPlaces: [
        place(
          'hong-kong',
          '香港特别行政区',
          countryCode: 'HK',
          latitude: 22.32,
          longitude: 114.17,
        ),
        place(
          'macau',
          '澳门特别行政区',
          countryCode: 'MO',
          latitude: 22.2,
          longitude: 113.55,
        ),
      ],
    );
    expect(result, hasLength(2));
    expect(result.map((entry) => entry.countryCode).toSet(), {'HK', 'MO'});
    expect(result.map((entry) => entry.name).toSet(), {'香港', '澳门'});
    expect(result.every((entry) => entry.count == 2), isTrue);
  });
}
