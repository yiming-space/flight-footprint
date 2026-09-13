import 'package:flight_footprint/domain/flight.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('upcoming flight matures at the start of its local departure day', () {
    final departure = DateTime(2026, 9, 14, 18, 30);

    expect(
      flightStatusForDeparture(departure, DateTime(2026, 9, 13, 23, 59)),
      FlightStatus.upcoming,
    );
    expect(
      flightStatusForDeparture(departure, DateTime(2026, 9, 14)),
      FlightStatus.completed,
    );
  });

  test('a completed stored flight never moves backwards to upcoming', () {
    final flight = _flight(
      status: FlightStatus.completed,
      departedAt: DateTime(2026, 9, 20, 8),
    );

    expect(
      flight.effectiveStatusAt(DateTime(2026, 9, 13)),
      FlightStatus.completed,
    );
  });

  test('transition matches the start of the departure local day', () {
    final departure = DateTime(2026, 9, 14, 0, 30);
    final boundary = flightStatusTransitionAt(departure);

    expect(boundary, DateTime(2026, 9, 14));
  });
}

Flight _flight({required FlightStatus status, required DateTime departedAt}) =>
    Flight(
      id: 'flight-1',
      departureIata: 'SZX',
      arrivalIata: 'PEK',
      departedAt: departedAt,
      createdAt: DateTime.utc(2026, 9, 1),
      updatedAt: DateTime.utc(2026, 9, 1),
      status: status,
    );
