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

  Future<void> refresh() async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      flights = await repository.listFlights();
      visitedPlaces = await repository.listVisitedPlaces();
    } catch (exception) {
      error = exception;
    } finally {
      isLoading = false;
      notifyListeners();
    }
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
}
