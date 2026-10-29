import 'package:flutter_test/flutter_test.dart';
import 'package:flight_footprint/domain/airport.dart';
import 'package:flight_footprint/domain/flight.dart';
import 'package:flight_footprint/domain/visited_place.dart';
import 'package:flight_footprint/features/stats/country_ranking.dart';

void main() {
  const airports = {
    'SHA': Airport(
      iataCode: 'SHA',
      latitude: 31.2,
      longitude: 121.3,
      name: 'Hongqiao',
      city: 'Shanghai',
      countryCode: 'CN',
    ),
    'HKG': Airport(
      iataCode: 'HKG',
      latitude: 22.3,
      longitude: 113.9,
      name: 'Hong Kong',
      city: 'Hong Kong',
      countryCode: 'HK',
    ),
  };
  Flight flight(String id, {FlightStatus status = FlightStatus.completed}) =>
      Flight(
        id: id,
        departureIata: 'SHA',
        arrivalIata: 'HKG',
        departedAt: DateTime(2025),
        createdAt: DateTime(2025),
        updatedAt: DateTime(2025),
        status: status,
      );
  VisitedPlace place(String id, String? code) => VisitedPlace(
    id: id,
    name: 'City $id',
    latitude: 0,
    longitude: 0,
    countryCode: code,
    visitedAt: DateTime(2025),
    createdAt: DateTime(2025),
    updatedAt: DateTime(2025),
  );
  String countryName(String code) => switch (code) {
    'CN' => 'China',
    'HK' => 'Hong Kong',
    'MO' => 'Macau',
    'JP' => 'Japan',
    _ => code,
  };

  test('merges visits by country code and retains HK / MO classification', () {
    final completed = flight('completed');
    final manual = place('cn', ' cn ');
    final result = buildCountryRanking(
      [completed, flight('future', status: FlightStatus.upcoming)],
      airportFor: (iata) => airports[iata],
      countryNameForCode: countryName,
      visitedPlaces: [
        manual,
        manual,
        place('hk', 'HK'),
        place('mo', 'MO'),
        place('jp', 'JP'),
      ],
    );
    expect(result.map((entry) => entry.countryCode).toSet(), {
      'CN',
      'HK',
      'MO',
      'JP',
    });
    final china = result.singleWhere((entry) => entry.countryCode == 'CN');
    expect(china.count, 0);
    expect(china.flights, [completed]);
    expect(china.visitedPlaces, [manual]);
    expect(() => china.visitedPlaces.clear(), throwsUnsupportedError);
    expect(result.singleWhere((entry) => entry.countryCode == 'HK').count, 1);
    expect(result.singleWhere((entry) => entry.countryCode == 'MO').count, 0);
  });

  test('country totals are available for footprints without any flight', () {
    final saved = place('only', 'JP');
    final result = buildCountryRanking(
      const [],
      airportFor: (iata) => airports[iata],
      countryNameForCode: countryName,
      visitedPlaces: [saved, place('unknown', null), place('bad', 'Japan')],
    );
    expect(result, hasLength(1));
    expect(result.single.name, 'Japan');
    expect(result.single.count, 0);
    expect(result.single.flights, isEmpty);
    expect(result.single.visitedPlaces, [saved]);
  });

  test('domestic flight counts one arrival and associates one flight', () {
    final domestic = flight('domestic').copyWith(arrivalIata: 'SHA');
    final result = buildCountryRanking(
      [domestic],
      airportFor: (iata) => airports[iata],
      countryNameForCode: countryName,
    );
    expect(result.single.count, 1);
    expect(result.single.flights, [domestic]);
  });

  test('known arrival counts even when departure airport is missing', () {
    final inbound = flight('inbound').copyWith(departureIata: '???');
    final outbound = flight('outbound').copyWith(arrivalIata: '???');
    final result = buildCountryRanking(
      [inbound, inbound, outbound],
      airportFor: (iata) => airports[iata],
      countryNameForCode: countryName,
    );
    expect(result.singleWhere((e) => e.countryCode == 'HK').count, 1);
    expect(result.singleWhere((e) => e.countryCode == 'CN').count, 0);
    expect(result.singleWhere((e) => e.countryCode == 'CN').flights, [
      outbound,
    ]);
  });
}
