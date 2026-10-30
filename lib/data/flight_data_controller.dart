import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/flight.dart';
import '../domain/visited_place.dart';
import '../domain/transfer_decision.dart';
import 'flight_repository.dart';
import '../domain/footprint_sources.dart';

/// Thin UI-facing state holder; screens can listen to it with Listenable APIs.
class FlightDataController extends ChangeNotifier {
  FlightDataController(this.repository);

  final FlightRepository repository;
  List<Flight> flights = const [];
  List<VisitedPlace> visitedPlaces = const [];
  List<TransferDecision> transferDecisions = const [];
  bool countTransitArrivals = true;
  bool isLoading = false;
  Object? error;
  Timer? _statusRefreshTimer;
  Future<void> _transferDecisionQueue = Future<void>.value();
  int _transferDecisionRevision = 0;

  Future<void> refresh({DateTime? now}) async {
    final reference = (now ?? DateTime.now()).toLocal();
    _statusRefreshTimer?.cancel();
    _statusRefreshTimer = null;
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      final storedFlights = await repository.listFlights();
      final matured = <Flight>[];
      final reconciled = <Flight>[];
      for (final flight in storedFlights) {
        if (flight.status == FlightStatus.upcoming &&
            flight.effectiveStatusAt(reference) == FlightStatus.completed) {
          final updated = flight.copyWith(
            status: FlightStatus.completed,
            updatedAt: reference.toUtc(),
          );
          matured.add(updated);
          reconciled.add(updated);
        } else {
          reconciled.add(flight);
        }
      }
      flights = List.unmodifiable(reconciled);
      if (matured.isNotEmpty) await repository.upsertFlights(matured);
      visitedPlaces = await repository.listVisitedPlaces();
      final decisionRevision = _transferDecisionRevision;
      final loadedDecisions = await repository.listTransferDecisions();
      if (decisionRevision == _transferDecisionRevision) {
        transferDecisions = loadedDecisions;
      }
      countTransitArrivals =
          await repository.getMeta('count_transit_arrivals') != 'false';
      _scheduleStatusRefresh(reference);
    } catch (exception) {
      error = exception;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  void _scheduleStatusRefresh(DateTime now) {
    _statusRefreshTimer?.cancel();
    DateTime? nextTransition;
    for (final flight in flights) {
      if (flight.effectiveStatusAt(now) != FlightStatus.upcoming) continue;
      final transition = flightStatusTransitionAt(
        flight.departedAt,
        arrivedAt: flight.arrivedAt,
        durationMinutes: flight.durationMinutes,
      );
      if (transition == null || !transition.isAfter(now)) continue;
      if (nextTransition == null || transition.isBefore(nextTransition)) {
        nextTransition = transition;
      }
    }
    if (nextTransition == null) return;
    final delay = nextTransition.difference(now);
    _statusRefreshTimer = Timer(delay + const Duration(milliseconds: 100), () {
      _statusRefreshTimer = null;
      unawaited(refresh());
    });
  }

  Future<void> saveFlight(Flight flight) async {
    await repository.upsertFlight(flight);
    await refresh();
  }

  TransferDecision? transferDecisionFor(Flight inbound, Flight outbound) {
    for (final decision in transferDecisions) {
      if (decision.matchesFlights(inbound, outbound)) return decision;
    }
    return null;
  }

  Future<void> decideTransfer(
    Flight inbound,
    Flight outbound,
    TransferDecisionStatus status, {
    DateTime? decidedAt,
  }) {
    final decision = TransferDecision.fromFlights(
      inbound: inbound,
      outbound: outbound,
      status: status,
      decidedAt: decidedAt,
    );
    final write = _transferDecisionQueue.then(
      (_) => _persistTransferDecision(decision),
    );
    // Keep the queue usable after one failed write while returning that
    // failure to the caller that requested it.
    _transferDecisionQueue = write.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return write;
  }

  Future<void> _persistTransferDecision(TransferDecision decision) async {
    final currentFlights = await repository.listFlights();
    final byId = <String, Flight>{};
    final counts = <String, int>{};
    for (final flight in currentFlights) {
      byId[flight.id] = flight;
      counts.update(flight.id, (count) => count + 1, ifAbsent: () => 1);
    }
    final inbound = byId[decision.inboundFlightId];
    final outbound = byId[decision.outboundFlightId];
    if (inbound == null ||
        outbound == null ||
        counts[inbound.id] != 1 ||
        counts[outbound.id] != 1 ||
        !decision.matchesFlights(inbound, outbound)) {
      throw const StaleTransferDecisionException();
    }

    final latestDecisions = await repository.listTransferDecisions();
    if (hasConfirmedTransferEndpointConflict(
      decision,
      flights: currentFlights,
      decisions: latestDecisions,
    )) {
      throw const TransferDecisionConflictException();
    }

    await repository.saveTransferDecision(decision);
    transferDecisions = await repository.listTransferDecisions();
    _transferDecisionRevision++;
    notifyListeners();
  }

  Future<FlightImportSummary> previewImportFlights(Iterable<Flight> flights) =>
      repository.previewImportFlights(flights);

  Future<FlightImportPreview> previewImportDetails(Iterable<Flight> flights) =>
      repository.previewImportDetails(flights);

  Future<FlightImportSummary> importFlights(
    Iterable<Flight> flights, {
    bool overwriteExisting = false,
    void Function(int completed, int total)? onProgress,
  }) async {
    final imported = await repository.importFlights(
      flights,
      overwriteExisting: overwriteExisting,
      onProgress: onProgress,
    );
    await refresh();
    return imported;
  }

  Future<void> saveVisitedPlace(VisitedPlace place) async {
    await repository.upsertVisitedPlace(place);
    await refresh();
  }

  Future<void> setCountTransitArrivals(bool value) async {
    await repository.setMeta('count_transit_arrivals', value.toString());
    countTransitArrivals = value;
    notifyListeners();
  }

  Future<void> removeFlight(String id) async {
    await repository.deleteFlight(id);
    await refresh();
  }

  Future<void> removeVisitedPlace(String id) async {
    await repository.deleteVisitedPlace(id);
    await refresh();
  }

  Future<ImportResult> importBackup(String source) async {
    final result = await repository.importBackup(source);
    await refresh();
    return result;
  }

  @override
  void dispose() {
    _statusRefreshTimer?.cancel();
    super.dispose();
  }
}
