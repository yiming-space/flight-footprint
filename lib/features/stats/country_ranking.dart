import '../../domain/airport.dart';
import '../../domain/flight.dart';
import '../../domain/footprint_sources.dart';
import '../../domain/transfer_decision.dart';
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
/// Both endpoints establish country presence; only arrivals contribute to the
/// flight-arrival count. Saved footprints stay visible as separate records.
/// Hong Kong and Macau retain their own HK/MO codes.
List<CountryRankingEntry> buildCountryRanking(
  Iterable<Flight> flights, {
  required Airport? Function(String) airportFor,
  required String Function(String) countryNameForCode,
  Iterable<VisitedPlace> visitedPlaces = const [],
  bool includeTransitArrivals = true,
  Iterable<TransferDecision> confirmedTransfers = const [],
}) {
  final aggregates = <String, _CountryAggregate>{};
  _CountryAggregate? aggregateFor(String? source) {
    final code = source?.trim().toUpperCase() ?? '';
    if (!RegExp(r'^[A-Z]{2}$').hasMatch(code)) return null;
    return aggregates.putIfAbsent(code, () => _CountryAggregate(code));
  }

  final seenPlaceIds = <String>{};
  for (final source in buildFootprintSources(
    flights: flights,
    visitedPlaces: visitedPlaces,
    airportFor: airportFor,
    includeTransitArrivals: includeTransitArrivals,
    confirmedTransfers: confirmedTransfers,
  )) {
    if (source.airport case final airport?) {
      final flight = source.flight!;
      final country = aggregateFor(airport.countryCode);
      if (country == null) continue;
      country.flights[flight.id] = flight;
      if (source.isArrival) country.arrivalFlightIds.add(flight.id);
    } else if (source.visitedPlace case final place?) {
      if (!seenPlaceIds.add(place.id)) continue;
      final country = aggregateFor(place.countryCode);
      if (country == null) continue;
      country.visitedPlaces.add(place);
    }
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
          count: aggregate.arrivalFlightIds.length,
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
  final Set<String> arrivalFlightIds = {};
  final Map<String, Flight> flights = {};
  final List<VisitedPlace> visitedPlaces = [];
}
