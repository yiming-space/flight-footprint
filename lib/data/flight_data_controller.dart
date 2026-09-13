import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/flight.dart';
import '../domain/visited_place.dart';
import 'flight_repository.dart';

/// Thin UI-facing state holder; screens can listen to it with Listenable APIs.
class FlightDataController extends ChangeNotifier {
  FlightDataController(this.repository);

  final FlightRepository repository;
  List<Flight> flights = const [];
  List<VisitedPlace> visitedPlaces = const [];
  bool isLoading = false;
  Object? error;
  Timer? _statusRefreshTimer;

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
      final transition = flightStatusTransitionAt(flight.departedAt);
      if (!transition.isAfter(now)) continue;
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
