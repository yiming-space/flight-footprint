import 'package:flight_footprint/domain/flight.dart';
import 'package:flight_footprint/domain/flight_query.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final flight = Flight(
    id: 'f1',
    departureIata: 'PVG',
    arrivalIata: 'NRT',
    departedAt: DateTime.utc(2026, 5, 1),
    createdAt: DateTime.utc(2026, 4, 1),
    updatedAt: DateTime.utc(2026, 4, 1),
    airline: '东航',
    flightNumber: 'MU523',
    aircraftType: 'A350',
  );

  test('search matches localized city, IATA, airline, aircraft and number', () {
    String airportText(String iata) =>
        {'PVG': '上海 Shanghai 浦东 Pudong', 'NRT': '东京 Tokyo 成田 Narita'}[iata] ??
        iata;

    expect(
      const FlightQuery(text: '东京').matches(flight, airportText: airportText),
      isTrue,
    );
    expect(
      const FlightQuery(text: 'mu523')
          .matches(flight, airportText: airportText),
      isTrue,
    );
    expect(
      const FlightQuery(text: '浦东 a350')
          .matches(flight, airportText: airportText),
      isTrue,
    );
  });

  test('airline and aircraft filters combine with text query', () {
    expect(
      const FlightQuery(airline: '东航', aircraftType: 'A350').matches(flight),
      isTrue,
    );
    expect(
      const FlightQuery(airline: '国航', aircraftType: 'A350').matches(flight),
      isFalse,
    );
    expect(const FlightQuery(text: 'osaka').matches(flight), isFalse);
  });
}
