import 'package:flight_footprint/domain/flight.dart';
import 'package:flight_footprint/features/stats/travel_milestones.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const cities = {'HKG': 'Hong Kong', 'NRT': 'Tokyo', 'ICN': 'Seoul'};

  Flight flight(String id, String from, String to, String date) => Flight(
    id: id,
    departureIata: from,
    arrivalIata: to,
    departedAt: DateTime.parse(date),
    createdAt: DateTime.parse(date),
    updatedAt: DateTime.parse(date),
  );

  test(
    'derives first arrival, latest new cities and undirected route counts',
    () {
      final result = TravelMilestones.fromFlights([
        flight('3', 'NRT', 'HKG', '2025-04-01T08:00:00Z'),
        flight('1', 'HKG', 'NRT', '2023-01-01T08:00:00Z'),
        flight('2', 'NRT', 'ICN', '2025-03-01T08:00:00Z'),
      ], cityNameFor: (code) => cities[code]);

      expect(result.firstArrival?.city, 'Tokyo');
      expect(result.latestNewCities?.year, 2025);
      expect(result.latestNewCities?.cities, ['Hong Kong', 'Seoul']);
      expect(result.frequentRoute?.label, 'Hong Kong — Tokyo');
      expect(result.frequentRoute?.flights.length, 2);
    },
  );

  test('ignores upcoming flights and unknown arrival cities for visits', () {
    final upcoming = flight(
      '1',
      'HKG',
      'NRT',
      '2026-01-01T08:00:00Z',
    ).copyWith(status: FlightStatus.upcoming);
    final result = TravelMilestones.fromFlights([
      upcoming,
      flight('2', 'HKG', 'XXX', '2025-01-01T08:00:00Z'),
    ], cityNameFor: (code) => cities[code]);

    expect(result.firstArrival, isNull);
    expect(result.latestNewCities, isNull);
    expect(result.routes.single.label, 'Hong Kong — XXX');
  });
}
