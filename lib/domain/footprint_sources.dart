import 'airport.dart';
import 'flight.dart';
import 'transfer_decision.dart';
import 'visited_place.dart';

/// Resolves persisted confirmed transfer decisions against the current flight
/// records. Any endpoint claimed by more than one active decision makes every
/// decision in that conflict group unresolved; no winner is selected.
class ConfirmedTransferResolution {
  const ConfirmedTransferResolution({
    required this.activeDecisions,
    required this.conflictedDecisionIds,
    required this.excludedEndpoints,
  });

  final List<TransferDecision> activeDecisions;
  final Set<String> conflictedDecisionIds;
  final Set<({String flightId, bool isArrival})> excludedEndpoints;
}

ConfirmedTransferResolution resolveConfirmedTransfers(
  Iterable<Flight> flights,
  Iterable<TransferDecision> decisions,
) {
  final byId = <String, Flight>{};
  final idCounts = <String, int>{};
  for (final flight in flights) {
    byId[flight.id] = flight;
    idCounts.update(flight.id, (count) => count + 1, ifAbsent: () => 1);
  }
  final uniqueById = {
    for (final entry in byId.entries)
      if (idCounts[entry.key] == 1) entry.key: entry.value,
  };
  final active = <TransferDecision>[];
  for (final decision in decisions) {
    if (decision.status != TransferDecisionStatus.confirmed) continue;
    final inbound = uniqueById[decision.inboundFlightId];
    final outbound = uniqueById[decision.outboundFlightId];
    if (inbound == null ||
        outbound == null ||
        !decision.matchesFlights(inbound, outbound)) {
      continue;
    }
    active.add(decision);
  }
  final endpointOwners = <({String flightId, bool isArrival}), Set<String>>{};
  for (final decision in active) {
    endpointOwners
        .putIfAbsent((
          flightId: decision.inboundFlightId,
          isArrival: true,
        ), () => <String>{})
        .add(decision.id);
    endpointOwners
        .putIfAbsent((
          flightId: decision.outboundFlightId,
          isArrival: false,
        ), () => <String>{})
        .add(decision.id);
  }
  final conflictedIds = <String>{
    for (final owners in endpointOwners.values)
      if (owners.length > 1) ...owners,
  };
  final excludedEndpoints = <({String flightId, bool isArrival})>{};
  for (final decision in active) {
    if (conflictedIds.contains(decision.id)) continue;
    excludedEndpoints
      ..add((flightId: decision.inboundFlightId, isArrival: true))
      ..add((flightId: decision.outboundFlightId, isArrival: false));
  }
  return ConfirmedTransferResolution(
    activeDecisions: List.unmodifiable(active),
    conflictedDecisionIds: Set.unmodifiable(conflictedIds),
    excludedEndpoints: Set.unmodifiable(excludedEndpoints),
  );
}

/// Endpoint keys excluded by explicitly confirmed, signature-matching
/// transfer decisions. Conflicted active decisions conservatively exclude
/// neither endpoint until a user resolves the conflict.
Set<({String flightId, bool isArrival})> confirmedTransitFootprintEndpoints(
  Iterable<Flight> flights,
  Iterable<TransferDecision> decisions,
) => resolveConfirmedTransfers(flights, decisions).excludedEndpoints;

/// Whether [candidate] claims an arrival/departure endpoint already used by a
/// different active confirmed decision.
bool hasConfirmedTransferEndpointConflict(
  TransferDecision candidate, {
  required Iterable<Flight> flights,
  required Iterable<TransferDecision> decisions,
}) {
  if (candidate.status != TransferDecisionStatus.confirmed) return false;
  final resolution = resolveConfirmedTransfers(flights, decisions);
  final candidateEndpoints = {
    (flightId: candidate.inboundFlightId, isArrival: true),
    (flightId: candidate.outboundFlightId, isArrival: false),
  };
  return resolution.activeDecisions.any((existing) {
    if (existing.id == candidate.id) return false;
    return candidateEndpoints.contains((
          flightId: existing.inboundFlightId,
          isArrival: true,
        )) ||
        candidateEndpoints.contains((
          flightId: existing.outboundFlightId,
          isArrival: false,
        ));
  });
}

/// A source record for a map footprint. A completed flight contributes each
/// known endpoint independently; saved places remain separate source records.
class FootprintSource {
  const FootprintSource.flight({
    required this.flight,
    required this.airport,
    required this.isArrival,
    required DateTime? visitedAt,
  }) : _flightVisitedAt = visitedAt,
       visitedPlace = null;

  const FootprintSource.saved(this.visitedPlace)
    : flight = null,
      airport = null,
      isArrival = false,
      _flightVisitedAt = null;

  final Flight? flight;
  final Airport? airport;
  final VisitedPlace? visitedPlace;
  final bool isArrival;
  final DateTime? _flightVisitedAt;
  DateTime? get visitedAt => visitedPlace?.visitedAt ?? _flightVisitedAt;
}

bool validFootprintCoordinates(double latitude, double longitude) =>
    latitude.isFinite &&
    longitude.isFinite &&
    latitude.abs() <= 90 &&
    longitude.abs() <= 180;

List<FootprintSource> buildFootprintSources({
  required Iterable<Flight> flights,
  required Iterable<VisitedPlace> visitedPlaces,
  required Airport? Function(String) airportFor,
  bool includeTransitArrivals = true,
  Iterable<TransferDecision> confirmedTransfers = const [],
}) {
  final result = <FootprintSource>[];
  final flightList = flights.toList(growable: false);
  final excludedTransferEndpoints = includeTransitArrivals
      ? const <({String flightId, bool isArrival})>{}
      : confirmedTransitFootprintEndpoints(flightList, confirmedTransfers);
  for (final flight in flightList) {
    if (!flight.isCompleted) continue;
    for (final isArrival in [false, true]) {
      if (isArrival && flight.isTransitArrival && !includeTransitArrivals) {
        continue;
      }
      if (excludedTransferEndpoints.contains((
        flightId: flight.id,
        isArrival: isArrival,
      ))) {
        continue;
      }
      final airport = airportFor(
        isArrival ? flight.arrivalIata : flight.departureIata,
      );
      if (airport == null ||
          !validFootprintCoordinates(airport.latitude, airport.longitude)) {
        continue;
      }
      final arrival =
          flight.arrivedAt ??
          (flight.durationMinutes == null
              ? flight.departedAt
              : flight.departedAt.add(
                  Duration(minutes: flight.durationMinutes!),
                ));
      result.add(
        FootprintSource.flight(
          flight: flight,
          airport: airport,
          isArrival: isArrival,
          visitedAt: isArrival ? arrival : flight.departedAt,
        ),
      );
    }
  }
  for (final place in visitedPlaces) {
    if (place.name.trim().isEmpty ||
        !validFootprintCoordinates(place.latitude, place.longitude)) {
      continue;
    }
    result.add(FootprintSource.saved(place));
  }
  return List.unmodifiable(result);
}
