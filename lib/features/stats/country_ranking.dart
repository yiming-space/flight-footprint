import '../../domain/airport.dart';
import '../../domain/flight.dart';
import '../../domain/visited_place.dart';

class CountryRankingEntry {
  CountryRankingEntry({
    required this.countryCode,
    required this.name,
    required this.count,
    required List<Flight> flights,
    required List<VisitedPlace> visitedPlaces,
  }) : flights = List.unmodifiable(flights),
       visitedPlaces = List.unmodifiable(visitedPlaces);

  final String countryCode;
  final String name;
  final int count;
  final List<Flight> flights;
  final List<VisitedPlace> visitedPlaces;
}

/// ISO country/region codes keep names and translations out of identity.
/// Each completed-flight endpoint and each saved footprint is one record.
/// Hong Kong and Macau retain their own HK/MO codes.
List<CountryRankingEntry> buildCountryRanking(
  Iterable<Flight> flights, {
  required Airport? Function(String) airportFor,
  required String Function(String) countryNameForCode,
  Iterable<VisitedPlace> visitedPlaces = const [],
}) {
  final aggregates = <String, _CountryAggregate>{};
  _CountryAggregate? aggregateFor(String? source) {
    final code = source?.trim().toUpperCase() ?? '';
    if (!RegExp(r'^[A-Z]{2}$').hasMatch(code)) return null;
    return aggregates.putIfAbsent(code, () => _CountryAggregate(code));
  }

  for (final flight in flights) {
    if (!flight.isCompleted) continue;
    for (final code in [flight.departureIata, flight.arrivalIata]) {
      final country = aggregateFor(airportFor(code)?.countryCode);
      if (country == null) continue;
      country.count++;
      country.flights[flight.id] = flight;
    }
  }
  final seenPlaceIds = <String>{};
  for (final place in visitedPlaces) {
    if (!seenPlaceIds.add(place.id)) continue;
    final country = aggregateFor(place.countryCode);
    if (country == null) continue;
    country.count++;
    country.visitedPlaces.add(place);
  }
  final result =
      aggregates.values.map((aggregate) {
        final associatedFlights = aggregate.flights.values.toList()
          ..sort((a, b) {
            final byDate = b.departedAt.compareTo(a.departedAt);
            return byDate != 0 ? byDate : a.id.compareTo(b.id);
          });
        final places = aggregate.visitedPlaces
          ..sort((a, b) {
            final byDate = b.visitedAt.compareTo(a.visitedAt);
            return byDate != 0 ? byDate : a.id.compareTo(b.id);
          });
        final name = countryNameForCode(aggregate.code).trim();
        return CountryRankingEntry(
          countryCode: aggregate.code,
          name: name.isEmpty ? aggregate.code : name,
          count: aggregate.count,
          flights: associatedFlights,
          visitedPlaces: places,
        );
      }).toList()..sort((a, b) {
        final byCount = b.count.compareTo(a.count);
        if (byCount != 0) return byCount;
        final byName = a.name.compareTo(b.name);
        return byName != 0 ? byName : a.countryCode.compareTo(b.countryCode);
      });
  return List.unmodifiable(result);
}

class _CountryAggregate {
  _CountryAggregate(this.code);
  final String code;
  int count = 0;
  final Map<String, Flight> flights = {};
  final List<VisitedPlace> visitedPlaces = [];
}
