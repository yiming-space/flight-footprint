import 'dart:convert';

import 'package:flutter/material.dart';

import '../data/airport_catalog.dart';
import '../data/calendar_import_service.dart';
import '../data/cloud_sync_service.dart';
import '../data/flight_data_controller.dart';
import '../data/flight_enrichment_service.dart';
import '../data/flight_repository.dart';
import '../data/flight_spreadsheet_import_service.dart';
import '../domain/airport.dart';
import '../domain/flight.dart';
import '../domain/transfer_decision.dart';
import '../domain/visited_place.dart';

enum CalendarAutoImportState {
  completed,
  permissionRequired,
  unsupported,
  failed,
}

class CalendarAutoImportOutcome {
  const CalendarAutoImportOutcome({
    required this.summary,
    required this.pendingConfirmationCount,
    this.state = CalendarAutoImportState.completed,
    this.candidates,
  });

  final FlightImportSummary summary;
  final int pendingConfirmationCount;
  final CalendarAutoImportState state;
  final CalendarImportResult? candidates;
}

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
  ThemeMode _themeMode = ThemeMode.system;
  bool _calendarAutoImportEnabled = false;
  bool _hasCheckedCalendarOnStartup = false;
  bool get countTransitArrivals => data.countTransitArrivals;

  Locale get locale => _locale;
  String get travellerName => _travellerName;
  ThemeMode get themeMode => _themeMode;
  bool get calendarAutoImportEnabled => _calendarAutoImportEnabled;
  List<Flight> get flights => data.flights;
  List<TransferDecision> get transferDecisions => data.transferDecisions;
  List<VisitedPlace> get visitedPlaces => data.visitedPlaces;
  bool get isLoading => data.isLoading;

  static Future<AppController> create() async {
    final airports = await AirportCatalog.load();
    final repository = FlightRepository(
      timeZoneForIata: airports.timeZoneIdForIata,
    );
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
    controller._themeMode = _themeModeFromStorage(
      await repository.getMeta('theme_mode'),
    );
    controller._calendarAutoImportEnabled =
        await repository.getMeta('calendar_auto_import_enabled') == 'true';
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

  Future<void> setThemeMode(ThemeMode value) async {
    if (_themeMode == value) return;
    _themeMode = value;
    notifyListeners();
    await repository.setMeta('theme_mode', _themeModeToStorage(value));
  }

  Future<void> setTravellerName(String value) async {
    final normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    final nextName = normalized.isEmpty ? 'TRAVELER' : normalized;
    await repository.setMeta('traveller_name', normalized);
    if (_travellerName == nextName) return;
    _travellerName = nextName;
    notifyListeners();
  }

  Future<void> setCountTransitArrivals(bool value) async {
    await data.setCountTransitArrivals(value);
  }

  Future<void> setCalendarAutoImportEnabled(bool value) async {
    if (_calendarAutoImportEnabled == value) return;
    _calendarAutoImportEnabled = value;
    notifyListeners();
    await repository.setMeta('calendar_auto_import_enabled', value.toString());
  }

  /// Checks the calendar once per controller lifetime, and only when the
  /// feature is enabled and READ_CALENDAR was already granted. This path
  /// never requests permission.
  Future<CalendarAutoImportOutcome?> checkCalendarAutoImportOnStartup() async {
    if (_hasCheckedCalendarOnStartup || !_calendarAutoImportEnabled) {
      return null;
    }
    _hasCheckedCalendarOnStartup = true;
    final permission = await calendarImport.checkReadPermission();
    if (!_calendarAutoImportEnabled) return null;
    switch (permission) {
      case CalendarPermissionState.granted:
        break;
      case CalendarPermissionState.denied:
        return const CalendarAutoImportOutcome(
          summary: FlightImportSummary(),
          pendingConfirmationCount: 0,
          state: CalendarAutoImportState.permissionRequired,
        );
      case CalendarPermissionState.unsupported:
        return const CalendarAutoImportOutcome(
          summary: FlightImportSummary(),
          pendingConfirmationCount: 0,
          state: CalendarAutoImportState.unsupported,
        );
      case CalendarPermissionState.failed:
        return const CalendarAutoImportOutcome(
          summary: FlightImportSummary(),
          pendingConfirmationCount: 0,
          state: CalendarAutoImportState.failed,
        );
    }
    final now = DateTime.now();
    final scanned = await scanCalendarFlights(
      start: now.subtract(const Duration(days: 30)),
      end: now.add(const Duration(days: 365 * 3)),
      allowPermissionRequest: false,
    );
    // Scanning can take long enough for the user to turn this setting off.
    // Do not write events or advance the seen set after that explicit change.
    if (!_calendarAutoImportEnabled) return null;
    if (!scanned.isAvailable ||
        (scanned.flights.isEmpty && scanned.reviewKeys.isEmpty)) {
      if (!scanned.isAvailable) {
        return CalendarAutoImportOutcome(
          summary: const FlightImportSummary(),
          pendingConfirmationCount: 0,
          state: switch (scanned.status) {
            CalendarScanStatus.permissionDenied =>
              CalendarAutoImportState.permissionRequired,
            CalendarScanStatus.unsupported =>
              CalendarAutoImportState.unsupported,
            CalendarScanStatus.failed => CalendarAutoImportState.failed,
            CalendarScanStatus.available => CalendarAutoImportState.completed,
          },
        );
      }
      return null;
    }

    final seen = _decodeCalendarSeenIds(
      await repository.getMeta('calendar_auto_import_seen_ids'),
    );
    seen.addAll(
      _decodeCalendarSeenIds(
        await repository.getMeta('calendar_ignored_revision_keys'),
      ),
    );
    if (!_calendarAutoImportEnabled) return null;
    final newDrafts = scanned.flights
        .where((draft) {
          return !seen.contains(draft.autoImportRevisionKey);
        })
        .toList(growable: false);
    final newReviewCount = scanned.reviewKeys
        .where((key) => !seen.contains(key))
        .length;
    if (newDrafts.isEmpty && newReviewCount == 0) return null;
    final preview = await previewCalendarFlights(newDrafts);
    if (!_calendarAutoImportEnabled) return null;
    final unchanged = preview.unchangedFlights
        .map((flight) => flight.id)
        .toSet();
    final pending = newDrafts
        .where((draft) => !unchanged.contains(draft.toFlight().id))
        .toList(growable: false);
    if (pending.isEmpty && newReviewCount == 0) return null;
    return CalendarAutoImportOutcome(
      summary: const FlightImportSummary(),
      pendingConfirmationCount: pending.length + newReviewCount,
      candidates: CalendarImportResult(
        status: scanned.status,
        eventsRead: scanned.eventsRead,
        flights: pending,
        reviewCandidates: newReviewCount,
        reviewKeys: scanned.reviewKeys
            .where((key) => !seen.contains(key))
            .toList(),
        reviewTitles: [
          for (var i = 0; i < scanned.reviewKeys.length; i++)
            if (!seen.contains(scanned.reviewKeys[i]) &&
                i < scanned.reviewTitles.length)
              scanned.reviewTitles[i],
        ],
      ),
    );
  }

  static Set<String> _decodeCalendarSeenIds(String? value) {
    if (value == null || value.isEmpty) return <String>{};
    try {
      final decoded = jsonDecode(value);
      if (decoded is List) {
        return decoded.whereType<String>().toSet();
      }
    } on FormatException {
      // A malformed preference should not prevent calendar imports.
    }
    return <String>{};
  }

  Future<void> ignoreCalendarRevisions(Iterable<String> keys) async {
    final current = _decodeCalendarSeenIds(
      await repository.getMeta('calendar_ignored_revision_keys'),
    );
    current.addAll(keys.where((key) => key.isNotEmpty));
    final values = current.toList();
    await repository.setMeta(
      'calendar_ignored_revision_keys',
      jsonEncode(
        values.length > 2000 ? values.sublist(values.length - 2000) : values,
      ),
    );
  }

  TransferDecision? transferDecisionFor(Flight inbound, Flight outbound) =>
      data.transferDecisionFor(inbound, outbound);

  Future<void> decideTransfer(
    Flight inbound,
    Flight outbound,
    TransferDecisionStatus status,
  ) => data.decideTransfer(inbound, outbound, status);

  Future<FlightEnrichment?> lookupFlight({
    required String airline,
    required String flightNumber,
    DateTime? flightDate,
    String? departureIata,
    String? arrivalIata,
  }) => flightEnrichment.lookup(
    airline: airline,
    flightNumber: flightNumber,
    flightDate: flightDate,
    departureIata: departureIata,
    arrivalIata: arrivalIata,
  );

  Future<SpreadsheetImportResult> parseFlightSpreadsheet({
    required List<int> bytes,
    required String fileName,
  }) => flightSpreadsheetImport.parseInBackground(
    bytes: bytes,
    fileName: fileName,
  );

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
    bool allowPermissionRequest = true,
  }) => calendarImport.scan(
    start: start,
    end: end,
    allowPermissionRequest: allowPermissionRequest,
  );

  Future<void> refreshFlights() => data.refresh();

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

  Future<Flight> addFlight({
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
    bool isTransitArrival = false,
  }) async {
    final created = await repository.createFlight(
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
      isTransitArrival: isTransitArrival,
    );
    await data.refresh();
    return created;
  }

  Future<int> undoAddedFlights(Iterable<Flight> flights) async {
    final count = await repository.undoAddedFlights(flights);
    await data.refresh();
    return count;
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
    bool? isTransitArrival,
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
      isTransitArrival: isTransitArrival ?? existing.isTransitArrival,
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
    FootprintRecordSource source = FootprintRecordSource.manual,
  }) async {
    await repository.createVisitedPlace(
      name: name,
      latitude: latitude,
      longitude: longitude,
      visitedAt: visitedAt,
      countryCode: _emptyToNull(countryCode),
      note: _emptyToNull(note),
      source: source,
    );
    await data.refresh();
  }

  Future<void> updateVisitedPlace({
    required VisitedPlace existing,
    required String name,
    required double latitude,
    required double longitude,
    required DateTime visitedAt,
    String? countryCode,
  }) async {
    await data.saveVisitedPlace(
      existing.copyWith(
        name: name,
        latitude: latitude,
        longitude: longitude,
        visitedAt: visitedAt,
        countryCode: _emptyToNull(countryCode),
        updatedAt: DateTime.now().toUtc(),
      ),
    );
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

  static ThemeMode _themeModeFromStorage(String? value) => switch (value) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  static String _themeModeToStorage(ThemeMode value) => switch (value) {
    ThemeMode.light => 'light',
    ThemeMode.dark => 'dark',
    ThemeMode.system => 'system',
  };
}
