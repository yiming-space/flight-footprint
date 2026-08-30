import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../data/airport_catalog.dart';
import '../data/calendar_import_service.dart';
import '../data/cloud_sync_service.dart';
import '../data/flight_data_controller.dart';
import '../data/flight_enrichment_service.dart';
import '../data/flight_repository.dart';
import '../data/flight_spreadsheet_import_service.dart';
import '../domain/airport.dart';
import '../domain/flight.dart';
import '../domain/visited_place.dart';

class AppController extends ChangeNotifier {
  AppController._(
    this.repository,
    this.airports,
    this.data,
    this.cloudSync,
    this.flightEnrichment,
    this.flightSpreadsheetImport,
    this.calendarImport,
  );

  final FlightRepository repository;
  final AirportCatalog airports;
  final FlightDataController data;
  final CloudSyncService cloudSync;
  final FlightEnrichmentService flightEnrichment;
  final FlightSpreadsheetImportService flightSpreadsheetImport;
  final CalendarImportService calendarImport;
  Locale _locale = const Locale('zh');
  String _travellerName = 'TRAVELER';

  Locale get locale => _locale;
  String get travellerName => _travellerName;
  List<Flight> get flights => data.flights;
  List<VisitedPlace> get visitedPlaces => data.visitedPlaces;
  bool get isLoading => data.isLoading;

  static Future<AppController> create() async {
    final repository = FlightRepository();
    final airports = await AirportCatalog.load();
    final data = FlightDataController(repository);
    final cloudSync = CloudSyncService(
      repository: repository,
      onLocalDataChanged: data.refresh,
    );
    final flightEnrichment = FlightEnrichmentService();
    final flightSpreadsheetImport = FlightSpreadsheetImportService(
      airports: airports,
    );
    final calendarImport = CalendarImportService(airports: airports);
    final controller = AppController._(
      repository,
      airports,
      data,
      cloudSync,
      flightEnrichment,
      flightSpreadsheetImport,
      calendarImport,
    );
    data.addListener(controller.notifyListeners);
    cloudSync.addListener(controller.notifyListeners);
    final language = await repository.getMeta('language');
    controller._locale = Locale(language == 'en' ? 'en' : 'zh');
    final travellerName = await repository.getMeta('traveller_name');
    if (travellerName != null && travellerName.trim().isNotEmpty) {
      controller._travellerName = travellerName.trim();
    }
    await data.refresh();
    await cloudSync.initialize();
    return controller;
  }

  Future<void> setLocale(Locale value) async {
    if (_locale.languageCode == value.languageCode) return;
    _locale = value;
    notifyListeners();
    await repository.setMeta('language', value.languageCode);
  }

  Future<void> setTravellerName(String value) async {
    final normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    final nextName = normalized.isEmpty ? 'TRAVELER' : normalized;
    await repository.setMeta('traveller_name', normalized);
    if (_travellerName == nextName) return;
    _travellerName = nextName;
    notifyListeners();
  }

  Future<FlightEnrichment?> lookupFlight({
    required String airline,
    required String flightNumber,
    DateTime? flightDate,
  }) => flightEnrichment.lookup(
    airline: airline,
    flightNumber: flightNumber,
    flightDate: flightDate,
  );

  SpreadsheetImportResult parseFlightSpreadsheet({
    required List<int> bytes,
    required String fileName,
  }) => flightSpreadsheetImport.parse(bytes: bytes, fileName: fileName);

  Future<FlightImportSummary> previewSpreadsheetFlights(
    Iterable<Flight> flights,
  ) => data.previewImportFlights(flights);

  Future<FlightImportPreview> previewSpreadsheetDetails(
    Iterable<Flight> flights,
  ) => data.previewImportDetails(flights);

  Future<FlightImportSummary> importSpreadsheetFlights(
    Iterable<Flight> flights, {
    bool overwriteExisting = false,
    void Function(int completed, int total)? onProgress,
  }) => data.importFlights(
    flights,
    overwriteExisting: overwriteExisting,
    onProgress: onProgress,
  );

  Future<CalendarImportResult> scanCalendarFlights({
    DateTime? start,
    DateTime? end,
  }) => calendarImport.scan(start: start, end: end);

  Future<FlightImportPreview> previewCalendarFlights(
    Iterable<CalendarFlightDraft> drafts,
  ) => data.previewImportDetails(drafts.map((draft) => draft.toFlight()));

  Future<FlightImportSummary> importCalendarFlights(
    Iterable<CalendarFlightDraft> drafts, {
    bool overwriteExisting = false,
    void Function(int completed, int total)? onProgress,
  }) => data.importFlights(
    drafts.map((draft) => draft.toFlight()),
    overwriteExisting: overwriteExisting,
    onProgress: onProgress,
  );

  Future<void> addFlight({
    required Airport departure,
    required Airport arrival,
    required DateTime date,
    DateTime? arrivedAt,
    double? distanceKm,
    String? airline,
    String? flightNumber,
    String? aircraftType,
    int? durationMinutes,
    String? seat,
    String? cabinClass,
    String? note,
    FlightStatus status = FlightStatus.completed,
  }) async {
    await repository.createFlight(
      departureIata: departure.iataCode,
      arrivalIata: arrival.iataCode,
      departedAt: date,
      arrivedAt: arrivedAt,
      distanceKm:
          distanceKm ??
          AirportCatalog.greatCircleDistanceKm(departure, arrival),
      airline: _emptyToNull(airline),
      flightNumber: _emptyToNull(flightNumber),
      aircraftType: _emptyToNull(aircraftType),
      durationMinutes: durationMinutes,
      seat: _emptyToNull(seat),
      cabinClass: _emptyToNull(cabinClass),
      note: _emptyToNull(note),
      status: status,
    );
    await data.refresh();
  }

  Future<void> updateFlight({
    required Flight existing,
    required Airport departure,
    required Airport arrival,
    required DateTime date,
    DateTime? arrivedAt,
    double? distanceKm,
    String? airline,
    String? flightNumber,
    String? aircraftType,
    int? durationMinutes,
    String? seat,
    String? cabinClass,
    String? note,
    FlightStatus? status,
  }) async {
    final updated = Flight(
      id: existing.id,
      departureIata: departure.iataCode,
      arrivalIata: arrival.iataCode,
      departedAt: date.toUtc(),
      arrivedAt: arrivedAt?.toUtc(),
      createdAt: existing.createdAt,
      updatedAt: DateTime.now().toUtc(),
      status: status ?? existing.status,
      airline: _emptyToNull(airline),
      flightNumber: _emptyToNull(flightNumber),
      aircraftType: _emptyToNull(aircraftType),
      durationMinutes: durationMinutes,
      seat: _emptyToNull(seat),
      cabinClass: _emptyToNull(cabinClass),
      note: _emptyToNull(note),
      distanceKm:
          distanceKm ??
          AirportCatalog.greatCircleDistanceKm(departure, arrival),
      track: existing.track,
    );
    await data.saveFlight(updated);
  }

  Future<void> addVisitedPlace({
    required String name,
    required double latitude,
    required double longitude,
    required DateTime visitedAt,
    String? countryCode,
    String? note,
  }) async {
    await repository.createVisitedPlace(
      name: name,
      latitude: latitude,
      longitude: longitude,
      visitedAt: visitedAt,
      countryCode: _emptyToNull(countryCode),
      note: _emptyToNull(note),
    );
    await data.refresh();
  }

  Future<void> deleteVisitedPlace(String id) async {
    await data.removeVisitedPlace(id);
  }

  /// Restores a previously removed footprint with its original identity so
  /// an Undo action cannot create a duplicate city record.
  Future<void> restoreVisitedPlace(VisitedPlace place) async {
    await data.saveVisitedPlace(place);
  }

  Future<void> deleteFlight(String id) => data.removeFlight(id);
  Airport? airportFor(String iata) => airports.findByIata(iata);

  String? _emptyToNull(String? value) =>
      value == null || value.trim().isEmpty ? null : value.trim();

  @override
  void dispose() {
    data.dispose();
    cloudSync.dispose();
    flightEnrichment.dispose();
    super.dispose();
  }
}
