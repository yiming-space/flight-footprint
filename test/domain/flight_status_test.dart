import 'package:flight_footprint/domain/flight.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('upcoming flight stays pending until its exact arrival instant', () {
    final departure = DateTime(2026, 9, 14, 18, 30);
    final arrival = DateTime(2026, 9, 14, 21);
    final flight = _flight(
      status: FlightStatus.upcoming,
      departedAt: departure,
      arrivedAt: arrival,
      durationMinutes: 60,
    );

    for (final now in [
      DateTime(2026, 9, 13, 23, 59),
      DateTime(2026, 9, 14),
      departure,
      arrival.subtract(const Duration(milliseconds: 1)).toUtc(),
    ]) {
      expect(flight.effectiveStatusAt(now), FlightStatus.upcoming);
    }
    expect(flight.effectiveStatusAt(arrival.toUtc()), FlightStatus.completed);
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

  test('transition uses the recorded arrival across midnight', () {
    final departure = DateTime(2026, 9, 14, 23, 30);
    final arrival = DateTime(2026, 9, 15, 2);
    final boundary = flightStatusTransitionAt(
      departure.toUtc(),
      arrivedAt: arrival,
      durationMinutes: 60,
    );

    expect(boundary, arrival);
  });

  test('missing arrival uses duration with mixed UTC and local clocks', () {
    final departure = DateTime.utc(2026, 9, 14, 23, 30);
    final arrival = DateTime.utc(2026, 9, 15, 2);
    final flight = _flight(
      status: FlightStatus.upcoming,
      departedAt: departure,
      durationMinutes: 150,
    );

    expect(
      flight.effectiveStatusAt(
        arrival.subtract(const Duration(milliseconds: 1)).toLocal(),
      ),
      FlightStatus.upcoming,
    );
    expect(flight.effectiveStatusAt(arrival.toLocal()), FlightStatus.completed);
    expect(flightStatusTransitionAt(departure, durationMinutes: 150), arrival);
  });

  test('unknown or invalid durations never complete from departure alone', () {
    final departure = DateTime(2026, 9, 14, 8);
    for (final duration in [null, 0, -1, 48 * 60 + 1]) {
      final flight = _flight(
        status: FlightStatus.upcoming,
        departedAt: departure,
        durationMinutes: duration,
      );
      expect(
        flight.effectiveStatusAt(DateTime(2026, 10, 14)),
        FlightStatus.upcoming,
      );
      expect(
        flightStatusTransitionAt(departure, durationMinutes: duration),
        isNull,
      );
    }
  });

  test('invalid explicit arrival is not silently corrected by duration', () {
    final departure = DateTime(2026, 9, 14, 8);
    for (final arrival in [
      departure,
      departure.subtract(const Duration(hours: 1)),
    ]) {
      final flight = _flight(
        status: FlightStatus.upcoming,
        departedAt: departure,
        arrivedAt: arrival,
        durationMinutes: 120,
      );
      expect(
        flight.effectiveStatusAt(DateTime(2026, 10, 14)),
        FlightStatus.upcoming,
      );
      expect(
        flightStatusTransitionAt(
          departure,
          arrivedAt: arrival,
          durationMinutes: 120,
        ),
        isNull,
      );
    }
  });
}

Flight _flight({
  required FlightStatus status,
  required DateTime departedAt,
  DateTime? arrivedAt,
  int? durationMinutes,
}) => Flight(
  id: 'flight-1',
  departureIata: 'SZX',
  arrivalIata: 'PEK',
  departedAt: departedAt,
  arrivedAt: arrivedAt,
  durationMinutes: durationMinutes,
  createdAt: DateTime.utc(2026, 9, 1),
  updatedAt: DateTime.utc(2026, 9, 1),
  status: status,
);
