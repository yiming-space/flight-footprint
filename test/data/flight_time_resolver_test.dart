import 'package:flight_footprint/data/flight_time_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'converts departure and arrival airport clocks across the date line',
    () {
      final departure = FlightTimeResolver.resolveWallTime(
        DateTime.utc(2026, 1, 1, 23, 30),
        'America/Los_Angeles',
      );
      final arrival = FlightTimeResolver.resolveWallTime(
        DateTime.utc(2026, 1, 3, 1, 30),
        'Pacific/Auckland',
      );

      expect(departure.instant, DateTime.utc(2026, 1, 2, 7, 30));
      expect(arrival.instant, DateTime.utc(2026, 1, 2, 12, 30));
      expect(arrival.instant!.difference(departure.instant!).inMinutes, 5 * 60);
    },
  );

  test('uses the historical DST offset for the selected travel date', () {
    final before = FlightTimeResolver.resolveWallTime(
      DateTime.utc(2026, 3, 8, 1, 30),
      'Europe/London',
    );
    final after = FlightTimeResolver.resolveWallTime(
      DateTime.utc(2026, 3, 8, 3, 30),
      'America/New_York',
    );

    expect(before.instant, DateTime.utc(2026, 3, 8, 1, 30));
    expect(after.instant, DateTime.utc(2026, 3, 8, 7, 30));
    expect(after.instant!.difference(before.instant!).inHours, 6);
  });

  test('reports DST gaps and repeated clocks instead of guessing', () {
    final gap = FlightTimeResolver.resolveWallTime(
      DateTime.utc(2026, 3, 8, 2, 30),
      'America/New_York',
    );
    final fold = FlightTimeResolver.resolveWallTime(
      DateTime.utc(2026, 11, 1, 1, 30),
      'America/New_York',
    );

    expect(gap.status, AirportWallTimeStatus.nonexistent);
    expect(fold.status, AirportWallTimeStatus.ambiguous);
  });

  test(
    'unknown airport zones stay explicit and do not use device timezone',
    () {
      final result = FlightTimeResolver.resolveWallTime(
        DateTime.utc(2026, 6, 1, 12),
        null,
      );

      expect(result.status, AirportWallTimeStatus.unknownTimeZone);
      expect(result.instant, isNull);
    },
  );

  test(
    'projects stored instants to airport wall time without device offset',
    () {
      final wallTime = FlightTimeResolver.toWallTime(
        DateTime.utc(2026, 1, 2, 7, 30),
        'America/Los_Angeles',
      );

      expect(wallTime, DateTime.utc(2026, 1, 1, 23, 30));
    },
  );

  test('preserves sub-millisecond wall clock precision', () {
    final result = FlightTimeResolver.resolveWallTime(
      DateTime.utc(2026, 1, 1, 12, 0, 0, 123, 456),
      'Etc/UTC',
    );

    expect(result.instant, DateTime.utc(2026, 1, 1, 12, 0, 0, 123, 456));
  });

  test('uses the departure airport calendar year near UTC New Year', () {
    final instant = DateTime.utc(2025, 12, 31, 18, 30);

    expect(
      FlightTimeResolver.calendarYearAtAirport(instant, 'Asia/Singapore'),
      2026,
    );
    expect(
      FlightTimeResolver.calendarYearAtAirport(instant, 'America/Los_Angeles'),
      2025,
    );
    expect(FlightTimeResolver.calendarYearAtAirport(instant, null),
      instant.toLocal().year);
  });
}
