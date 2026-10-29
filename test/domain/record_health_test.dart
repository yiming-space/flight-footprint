import 'package:flutter_test/flutter_test.dart';
import 'package:flight_footprint/domain/airport.dart';
import 'package:flight_footprint/domain/flight.dart';
import 'package:flight_footprint/domain/record_health.dart';
import 'package:flight_footprint/domain/visited_place.dart';

Flight _flight({
  required String id,
  String departure = 'AAA',
  String arrival = 'BBB',
  String? number = 'FF100',
  DateTime? departedAt,
  FlightStatus status = FlightStatus.completed,
}) => Flight(
  id: id,
  departureIata: departure,
  arrivalIata: arrival,
  departedAt: departedAt ?? DateTime.utc(2025),
  createdAt: DateTime.utc(2025),
  updatedAt: DateTime.utc(2025),
  status: status,
  flightNumber: number,
);

Airport _airport(String code, double latitude, double longitude) => Airport(
  iataCode: code,
  latitude: latitude,
  longitude: longitude,
  name: code,
  city: code,
  countryCode: 'ZZ',
);

VisitedPlace _place({
  required String id,
  String name = 'Somewhere',
  double latitude = 10,
  double longitude = 20,
}) => VisitedPlace(
  id: id,
  name: name,
  latitude: latitude,
  longitude: longitude,
  visitedAt: DateTime.utc(2025),
  createdAt: DateTime.utc(2025),
  updatedAt: DateTime.utc(2025),
);

void main() {
  test('reports only completed flights with unknown or invalid airports', () {
    final airports = {
      'AAA': _airport('AAA', 10, 20),
      'BAD': _airport('BAD', 91, 20),
    };
    final report = inspectRecordHealth(
      flights: [
        _flight(id: 'ok', departure: 'AAA', arrival: 'AAA'),
        _flight(id: 'unknown', departure: 'MISSING'),
        _flight(id: 'invalid', departure: 'BAD'),
        _flight(
          id: 'upcoming',
          departure: 'MISSING',
          status: FlightStatus.upcoming,
        ),
      ],
      places: const [],
      airportFor: (iata) => airports[iata],
    );

    expect(report.flights.map((issue) => issue.flight!.id), [
      'unknown',
      'invalid',
    ]);
    expect(
      report.flights.first.problems,
      contains(RecordHealthProblem.unknownDepartureAirport),
    );
    expect(
      report.flights.last.problems,
      contains(RecordHealthProblem.invalidDepartureCoordinates),
    );
  });

  test('reports invalid saved footprints without collapsing distinct ids', () {
    final report = inspectRecordHealth(
      flights: const [],
      places: [
        _place(id: 'one', latitude: double.nan),
        _place(id: 'two', name: '', longitude: 181),
      ],
      airportFor: (_) => null,
    );

    expect(report.places.map((issue) => issue.place!.id), ['one', 'two']);
    expect(report.count, 2);
    expect(
      report.places[1].problems,
      contains(RecordHealthProblem.emptyPlaceName),
    );
    expect(
      report.places[1].problems,
      contains(RecordHealthProblem.invalidPlaceCoordinates),
    );
  });

  test('flags only exact completed-flight matches with distinct ids', () {
    final instant = DateTime.utc(2025, 4, 5, 6, 7);
    final flights = [
      _flight(
        id: 'first',
        departure: 'aaa',
        arrival: 'bbb',
        departedAt: instant,
      ),
      _flight(
        id: 'second',
        departure: 'AAA',
        arrival: 'BBB',
        departedAt: instant,
      ),
      _flight(
        id: 'first',
        departure: 'AAA',
        arrival: 'BBB',
        departedAt: instant,
      ),
      _flight(
        id: 'first',
        departure: 'AAA',
        arrival: 'BBB',
        departedAt: instant,
      ),
      _flight(
        id: 'different-time',
        departure: 'AAA',
        arrival: 'BBB',
        departedAt: instant.add(const Duration(microseconds: 1)),
      ),
      _flight(
        id: 'different-route',
        departure: 'AAA',
        arrival: 'CCC',
        departedAt: instant,
      ),
      _flight(
        id: 'missing-number',
        departure: 'AAA',
        arrival: 'BBB',
        departedAt: instant,
        number: null,
      ),
      _flight(
        id: 'upcoming-match',
        departure: 'AAA',
        arrival: 'BBB',
        departedAt: instant,
        status: FlightStatus.upcoming,
      ),
    ];

    final groups = findSuspectedDuplicateFlights(flights);
    expect(groups, hasLength(1));
    expect(groups.single.map((flight) => flight.id), ['first', 'second']);
  });
}
