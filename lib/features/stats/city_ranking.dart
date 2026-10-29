import '../../data/city_catalog.dart';
import '../../domain/airport.dart';
import '../../domain/flight.dart';
import '../../domain/visited_place.dart';
import '../../domain/transfer_decision.dart';
import '../../domain/footprint_sources.dart';

class CityRankingEntry {
  CityRankingEntry({
    required this.key,
    required this.name,
    required this.countryName,
    required this.countryCode,
    required this.count,
    required List<Flight> flights,
    List<VisitedPlace> visitedPlaces = const [],
  }) : flights = List.unmodifiable(flights),
       visitedPlaces = List.unmodifiable(visitedPlaces);

  final String key;
  final String name;
  final String countryName;
  final String countryCode;
  final int count;
  final List<Flight> flights;
  final List<VisitedPlace> visitedPlaces;
}

/// Ranks recorded visits: completed-flight endpoints plus saved footprints.
/// City identity uses a country and an exact city name/known alias. A nearby
/// coordinate alone never assigns a footprint to a different named city.
List<CityRankingEntry> buildCityRanking(
  Iterable<Flight> flights, {
  required Airport? Function(String) airportFor,
  required String Function(Airport) cityNameFor,
  required String Function(Airport) countryNameFor,
  Iterable<VisitedPlace> visitedPlaces = const [],
  CityCatalog? cityCatalog,
  String Function(String)? countryNameForCode,
  bool includeTransitArrivals = true,
  Iterable<TransferDecision> confirmedTransfers = const [],
}) {
  final aggregates = <String, _CityAggregate>{};
  final identityResolver = CityIdentityResolver(cityCatalog);
  final flightList = flights.toList(growable: false);
  final excludedTransferEndpoints = includeTransitArrivals
      ? const <({String flightId, bool isArrival})>{}
      : confirmedTransitFootprintEndpoints(flightList, confirmedTransfers);

  _CityAggregate? aggregateFor({
    required String name,
    required String countryCode,
    required String countryName,
    required double latitude,
    required double longitude,
  }) {
    if (!latitude.isFinite ||
        !longitude.isFinite ||
        latitude.abs() > 90 ||
        longitude.abs() > 180) {
      return null;
    }
    var normalizedName = normalizeMapCityName(
      name,
      countryCode: countryCode,
    ).trim().replaceAll(RegExp(r'\s+'), ' ');
    var normalizedCountry = countryCode.trim().toUpperCase();
    // HK/MO are both cities and regions. Legacy explicit region labels are
    // still valid city visits, unlike province-only mainland footprints.
    if (normalizedCountry == 'HK' && normalizedName == '香港特别行政区') {
      normalizedName = '香港';
    } else if (normalizedCountry == 'MO' && normalizedName == '澳门特别行政区') {
      normalizedName = '澳门';
    }
    if (normalizedName.isEmpty || isProvinceMapName(normalizedName)) {
      return null;
    }
    var canonicalName = normalizedName;
    // Index exact aliases once per immutable catalogue. Repeated stats
    // rebuilds must not scan the worldwide catalogue for every endpoint.
    final known = cityCatalog?.resolveCity(
      normalizedName,
      countryCode: normalizedCountry,
      latitude: latitude,
      longitude: longitude,
      allowCoordinateFallback: false,
    );
    if (known != null) {
      canonicalName = known.name;
      normalizedCountry = known.countryCode.trim().toUpperCase();
    }
    final key = identityResolver.keyFor(
      name: canonicalName,
      countryCode: normalizedCountry,
      latitude: latitude,
      longitude: longitude,
    );
    final existing = aggregates[key];
    if (existing != null) return existing;
    final aggregate = _CityAggregate(
      key: key,
      name: normalizedName,
      countryCode: normalizedCountry,
      countryName:
          countryNameForCode?.call(normalizedCountry).trim() ??
          countryName.trim(),
      latitude: latitude,
      longitude: longitude,
    );
    aggregates[key] = aggregate;
    return aggregate;
  }

  for (final flight in flightList) {
    if (flight.status != FlightStatus.completed) continue;
    final flightCities = <String>{};
    final flightEndpoints = <({String iata, bool isArrival})>[
      (iata: flight.departureIata, isArrival: false),
      if (includeTransitArrivals || !flight.isTransitArrival)
        (iata: flight.arrivalIata, isArrival: true),
    ];
    for (final endpoint in flightEndpoints) {
      if (excludedTransferEndpoints.contains((
        flightId: flight.id,
        isArrival: endpoint.isArrival,
      ))) {
        continue;
      }
      final airport = airportFor(endpoint.iata);
      if (airport == null) continue;
      final countryCode = airport.countryCode.trim().toUpperCase();
      if (countryCode.isEmpty) continue;
      final aggregate = aggregateFor(
        name: cityNameFor(airport),
        countryCode: countryCode,
        countryName: countryNameFor(airport),
        latitude: airport.latitude,
        longitude: airport.longitude,
      );
      if (aggregate == null) continue;
      aggregate.count++;
      flightCities.add(aggregate.key);
    }
    for (final key in flightCities) {
      aggregates[key]!.flights[flight.id] = flight;
    }
  }

  final seenPlaceIds = <String>{};
  for (final place in visitedPlaces) {
    if (!seenPlaceIds.add(place.id)) continue;
    final aggregate = aggregateFor(
      name: place.name,
      countryCode: place.countryCode ?? '',
      countryName: place.countryCode ?? '',
      latitude: place.latitude,
      longitude: place.longitude,
    );
    if (aggregate == null) continue;
    aggregate.count++;
    aggregate.visitedPlaces.add(place);
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
      visitedPlaces: aggregate.visitedPlaces
        ..sort((a, b) {
          final byDate = b.visitedAt.compareTo(a.visitedAt);
          return byDate != 0 ? byDate : a.id.compareTo(b.id);
        }),
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
    required this.latitude,
    required this.longitude,
  });

  final String key;
  final String name;
  final String countryName;
  final String countryCode;
  final double latitude;
  final double longitude;
  int count = 0;
  final Map<String, Flight> flights = <String, Flight>{};
  final List<VisitedPlace> visitedPlaces = [];
}

String cityVisitSummary(int count, {required bool isZh}) =>
    isZh ? '到访 $count 座城市' : '$count ${count == 1 ? 'city' : 'cities'} visited';
