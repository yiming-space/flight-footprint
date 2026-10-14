import '../../domain/airport.dart';
import '../../domain/flight.dart';

class CityRankingEntry {
  CityRankingEntry({
    required this.key,
    required this.name,
    required this.countryName,
    required this.countryCode,
    required this.count,
    required List<Flight> flights,
  }) : flights = List.unmodifiable(flights);

  final String key;
  final String name;
  final String countryName;
  final String countryCode;
  final int count;
  final List<Flight> flights;
}

/// Ranks cities by completed-flight airport endpoints (each takeoff/landing).
List<CityRankingEntry> buildCityRanking(
  Iterable<Flight> flights, {
  required Airport? Function(String) airportFor,
  required String Function(Airport) cityNameFor,
  required String Function(Airport) countryNameFor,
}) {
  final aggregates = <String, _CityAggregate>{};

  for (final flight in flights) {
    if (flight.status != FlightStatus.completed) continue;
    final flightCities = <String>{};
    for (final iata in [flight.departureIata, flight.arrivalIata]) {
      final airport = airportFor(iata);
      if (airport == null) continue;
      final name = cityNameFor(airport).trim().replaceAll(RegExp(r'\s+'), ' ');
      final countryCode = airport.countryCode.trim().toUpperCase();
      if (name.isEmpty || countryCode.isEmpty) continue;
      final normalizedName = name.toLowerCase();
      final key = '$countryCode:$normalizedName';
      final aggregate = aggregates.putIfAbsent(
        key,
        () => _CityAggregate(
          key: key,
          name: name,
          countryCode: countryCode,
          countryName: countryNameFor(airport).trim(),
        ),
      );
      aggregate.count++;
      flightCities.add(key);
    }
    for (final key in flightCities) {
      aggregates[key]!.flights[flight.id] = flight;
    }
  }

  final result = aggregates.values.map((aggregate) {
    final associatedFlights = aggregate.flights.values.toList()
      ..sort((a, b) {
        final byDate = b.departedAt.compareTo(a.departedAt);
        return byDate != 0 ? byDate : a.id.compareTo(b.id);
      });
    return CityRankingEntry(
      key: aggregate.key,
      name: aggregate.name,
      countryName: aggregate.countryName,
      countryCode: aggregate.countryCode,
      count: aggregate.count,
      flights: associatedFlights,
    );
  }).toList();

  result.sort((a, b) {
    final byCount = b.count.compareTo(a.count);
    if (byCount != 0) return byCount;
    final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    if (byName != 0) return byName;
    final byCountry = a.countryName.toLowerCase().compareTo(
      b.countryName.toLowerCase(),
    );
    if (byCountry != 0) return byCountry;
    return a.key.compareTo(b.key);
  });
  return List<CityRankingEntry>.unmodifiable(result);
}

class _CityAggregate {
  _CityAggregate({
    required this.key,
    required this.name,
    required this.countryName,
    required this.countryCode,
  });

  final String key;
  final String name;
  final String countryName;
  final String countryCode;
  int count = 0;
  final Map<String, Flight> flights = <String, Flight>{};
}
