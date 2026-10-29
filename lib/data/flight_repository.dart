import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../domain/flight.dart';
import '../domain/journey.dart';
import '../domain/transfer_decision.dart';
import '../domain/visited_place.dart';
import 'backup_codec.dart';
import 'local_database.dart';
import 'transfer_decision_store.dart';
import 'flight_time_resolver.dart';

class ImportResult {
  const ImportResult({required this.flightsMerged, required this.placesMerged});

  final int flightsMerged;
  final int placesMerged;
}

/// The outcome of importing an itinerary spreadsheet.
///
/// [conflicts] counts existing flights whose spreadsheet-controlled fields
/// differ from the incoming row. They are only written when the caller opts
/// into overwriting. Fields not present in the spreadsheet (seat, cabin and
/// recorded track) are always preserved.
class FlightImportSummary {
  const FlightImportSummary({
    this.added = 0,
    this.updated = 0,
    this.unchanged = 0,
    this.conflicts = 0,
    this.skipped = 0,
    this.addedRecords = const [],
  });

  final int added;
  final int updated;
  final int unchanged;
  final int conflicts;
  final int skipped;
  final List<Flight> addedRecords;

  int get written => added + updated;
}

/// Detailed preview used by the import review UI.
///
/// The summary is kept for the final write result, while these lists let the
/// user inspect additions, unchanged rows and rows that need overwrite
/// confirmation without reimplementing repository matching rules in a page.
class FlightImportPreview {
  const FlightImportPreview({
    required this.summary,
    required this.addedFlights,
    required this.conflictingFlights,
    required this.unchangedFlights,
    this.existingByIncomingId = const {},
  });

  final FlightImportSummary summary;
  final List<Flight> addedFlights;
  final List<Flight> conflictingFlights;
  final List<Flight> unchangedFlights;
  final Map<String, Flight> existingByIncomingId;
}

class _FlightImportPlan {
  const _FlightImportPlan({
    required this.operations,
    required this.summary,
    required this.conflicts,
  });

  final List<_FlightImportOperation> operations;
  final FlightImportSummary summary;
  final int conflicts;
}

class _FlightImportOperation {
  _FlightImportOperation({
    required this.incoming,
    this.existing,
    Flight? merged,
    this.changed = false,
  }) : merged = merged ?? incoming;

  final Flight incoming;
  final Flight? existing;
  final Flight merged;
  final bool changed;
}

class FlightRepository {
  static const _importBatchSize = 100;
  static const _journeyMetaKey = 'journeys_v1';
  static const _journeySchemaVersion = 1;
  static const _transferDecisionsMetaKey = 'transfer_decisions_v1';

  FlightRepository({
    Future<Database> Function()? databaseProvider,
    Uuid? uuid,
    String? Function(String)? timeZoneForIata,
  }) : _databaseProvider = databaseProvider ?? LocalDatabase.open,
       _uuid = uuid ?? const Uuid(),
       _timeZoneForIata = timeZoneForIata;

  final Future<Database> Function() _databaseProvider;
  final Uuid _uuid;
  final String? Function(String)? _timeZoneForIata;

  Future<List<Flight>> listFlights() async {
    final database = await _databaseProvider();
    final rows = await database.query('flights', orderBy: 'departed_at DESC');
    return rows.map(_flightFromRow).toList(growable: false);
  }

  Future<List<VisitedPlace>> listVisitedPlaces() async {
    final database = await _databaseProvider();
    final rows = await database.query(
      'visited_places',
      orderBy: 'visited_at DESC',
    );
    return rows.map(_placeFromRow).toList(growable: false);
  }

  Future<String?> getMeta(String key) async {
    final database = await _databaseProvider();
    final rows = await database.query(
      'app_meta',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single['value']! as String;
  }

  Future<void> setMeta(String key, String value) async {
    final database = await _databaseProvider();
    await database.transaction((transaction) async {
      await transaction.insert('app_meta', {
        'key': key,
        'value': value,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<List<TransferDecision>> listTransferDecisions() async =>
      TransferDecisionStore.decode(await getMeta(_transferDecisionsMetaKey));

  Future<void> saveTransferDecision(TransferDecision decision) async {
    final database = await _databaseProvider();
    await database.transaction((transaction) async {
      final current = TransferDecisionStore.decode(
        await _getMetaInTransaction(transaction, _transferDecisionsMetaKey),
      );
      final updated = TransferDecisionStore.upsert(current, decision);
      await _setMetaInTransaction(
        transaction,
        _transferDecisionsMetaKey,
        TransferDecisionStore.encode(updated),
      );
    });
  }

  Future<TransferDecision?> activeTransferDecision(
    Flight inbound,
    Flight outbound,
  ) async => TransferDecisionStore.findActive(
    await listTransferDecisions(),
    inbound,
    outbound,
  );

  Future<Flight> createFlight({
    required String departureIata,
    required String arrivalIata,
    required DateTime departedAt,
    DateTime? arrivedAt,
    String? airline,
    String? flightNumber,
    String? cabinClass,
    String? aircraftType,
    int? durationMinutes,
    String? seat,
    String? note,
    double? distanceKm,
    FlightStatus status = FlightStatus.completed,
    bool isTransitArrival = false,
  }) async {
    final now = DateTime.now().toUtc();
    final flight = Flight(
      id: _uuid.v4(),
      departureIata: departureIata.trim().toUpperCase(),
      arrivalIata: arrivalIata.trim().toUpperCase(),
      departedAt: departedAt.toUtc(),
      arrivedAt: arrivedAt?.toUtc(),
      createdAt: now,
      updatedAt: now,
      status: status,
      isTransitArrival: isTransitArrival,
      airline: airline,
      flightNumber: flightNumber,
      cabinClass: cabinClass,
      aircraftType: aircraftType,
      durationMinutes: durationMinutes,
      seat: seat,
      note: note,
      distanceKm: distanceKm,
    );
    await upsertFlight(flight);
    return flight;
  }

  Future<VisitedPlace> createVisitedPlace({
    required String name,
    required double latitude,
    required double longitude,
    required DateTime visitedAt,
    String? countryCode,
    String? note,
    FootprintRecordSource source = FootprintRecordSource.unknown,
  }) async {
    final now = DateTime.now().toUtc();
    final place = VisitedPlace(
      id: _uuid.v4(),
      name: name.trim(),
      latitude: latitude,
      longitude: longitude,
      visitedAt: visitedAt.toUtc(),
      createdAt: now,
      updatedAt: now,
      countryCode: countryCode,
      note: note,
      source: source,
    );
    await upsertVisitedPlace(place);
    return place;
  }

  Future<void> upsertFlight(Flight flight) async {
    final database = await _databaseProvider();
    await database.transaction((transaction) async {
      await transaction.insert(
        'flights',
        _flightToRow(flight),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  Future<void> upsertFlights(Iterable<Flight> flights) async {
    final values = flights.toList(growable: false);
    if (values.isEmpty) return;
    final database = await _databaseProvider();
    await database.transaction((transaction) async {
      final batch = transaction.batch();
      for (final flight in values) {
        batch.insert(
          'flights',
          _flightToRow(flight),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  /// Returns how many rows would be added, updated or left unchanged.
  ///
  /// A flight is matched by local calendar day + flight number. This lets an
  /// accurate spreadsheet correct a manually entered time or airport without
  /// creating a second row for the same flight.
  Future<FlightImportSummary> previewImportFlights(
    Iterable<Flight> flights,
  ) async => (await previewImportDetails(flights)).summary;

  /// Returns the same identity-aware classification used during import.
  Future<FlightImportPreview> previewImportDetails(
    Iterable<Flight> flights,
  ) async {
    final incoming = flights.toList(growable: false);
    if (incoming.isEmpty) {
      return const FlightImportPreview(
        summary: FlightImportSummary(),
        addedFlights: [],
        conflictingFlights: [],
        unchangedFlights: [],
      );
    }
    final database = await _databaseProvider();
    final rows = await database.query('flights');
    final plan = _planImport(rows.map(_flightFromRow), incoming);
    final added = <Flight>[];
    final conflicts = <Flight>[];
    final unchanged = <Flight>[];
    final existingByIncomingId = <String, Flight>{};
    for (final operation in plan.operations) {
      if (operation.existing == null) {
        added.add(operation.incoming);
      } else if (operation.changed) {
        conflicts.add(operation.incoming);
        existingByIncomingId[operation.incoming.id] = operation.existing!;
      } else {
        unchanged.add(operation.incoming);
      }
    }
    return FlightImportPreview(
      summary: plan.summary,
      addedFlights: List.unmodifiable(added),
      conflictingFlights: List.unmodifiable(conflicts),
      unchangedFlights: List.unmodifiable(unchanged),
      existingByIncomingId: Map.unmodifiable(existingByIncomingId),
    );
  }

  /// Imports spreadsheet rows. New rows are always added. Existing rows that
  /// differ are updated only when [overwriteExisting] is true; unchanged rows
  /// are never rewritten.
  Future<FlightImportSummary> importFlights(
    Iterable<Flight> flights, {
    bool overwriteExisting = false,
    void Function(int completed, int total)? onProgress,
  }) async {
    final incoming = flights.toList(growable: false);
    if (incoming.isEmpty) return const FlightImportSummary();
    final database = await _databaseProvider();
    return database.transaction((transaction) async {
      final existingRows = await transaction.query('flights');
      final plan = _planImport(existingRows.map(_flightFromRow), incoming);
      var added = 0;
      final addedRecords = <Flight>[];
      var updated = 0;
      var unchanged = 0;
      var skipped = 0;
      var completed = 0;
      var lastProgress = 0;
      var pendingWrites = 0;
      var batch = transaction.batch();

      Future<void> flushBatch() async {
        if (pendingWrites == 0) return;
        await batch.commit(noResult: true);
        batch = transaction.batch();
        pendingWrites = 0;
      }

      for (final operation in plan.operations) {
        final existing = operation.existing;
        if (existing == null) {
          batch.insert(
            'flights',
            _flightToRow(operation.incoming),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          added++;
          addedRecords.add(operation.incoming);
        } else if (!operation.changed) {
          unchanged++;
        } else if (overwriteExisting) {
          batch.insert(
            'flights',
            _flightToRow(operation.merged),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          updated++;
        } else {
          skipped++;
        }
        completed++;
        if (existing == null || overwriteExisting && operation.changed) {
          pendingWrites++;
        }
        if (completed - lastProgress >= _importBatchSize) {
          if (pendingWrites > 0) await flushBatch();
          onProgress?.call(completed, plan.operations.length);
          lastProgress = completed;
        }
      }
      await flushBatch();
      onProgress?.call(completed, plan.operations.length);
      return FlightImportSummary(
        added: added,
        updated: updated,
        unchanged: unchanged,
        conflicts: plan.conflicts,
        skipped: skipped,
        addedRecords: List.unmodifiable(addedRecords),
      );
    });
  }

  Future<void> upsertVisitedPlace(VisitedPlace place) async {
    final database = await _databaseProvider();
    await database.transaction((transaction) async {
      await transaction.insert(
        'visited_places',
        _placeToRow(place),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  Future<void> deleteFlight(String id) async {
    final database = await _databaseProvider();
    await database.transaction(
      (transaction) =>
          transaction.delete('flights', where: 'id = ?', whereArgs: [id]),
    );
  }

  /// Only delete records that still have the exact import revision.
  Future<int> undoAddedFlights(Iterable<Flight> flights) async {
    final database = await _databaseProvider();
    return database.transaction((txn) async {
      var deleted = 0;
      for (final flight in flights) {
        deleted += await txn.delete(
          'flights',
          where: 'id = ? AND updated_at = ?',
          whereArgs: [flight.id, flight.updatedAt.millisecondsSinceEpoch],
        );
      }
      return deleted;
    });
  }

  Future<void> deleteVisitedPlace(String id) async {
    final database = await _databaseProvider();
    await database.transaction(
      (transaction) => transaction.delete(
        'visited_places',
        where: 'id = ?',
        whereArgs: [id],
      ),
    );
  }

  Future<String> exportBackup() async => BackupCodec.encode(
    BackupData(
      flights: await listFlights(),
      visitedPlaces: await listVisitedPlaces(),
      journeys: _journeysFromMeta(await getMeta(_journeyMetaKey)),
      transferDecisions: await listTransferDecisions(),
      containsTransferDecisions: true,
      containsJourneys: true,
      countTransitArrivals:
          (await getMeta('count_transit_arrivals')) != 'false',
    ),
  );

  /// Validates fully before opening a write transaction. A UUID collision is
  /// resolved by keeping the record with the most recent [updatedAt].
  Future<ImportResult> importBackup(String source) async {
    final backup = BackupCodec.decode(source);
    final database = await _databaseProvider();
    return database.transaction((transaction) async {
      var flightCount = 0;
      var placeCount = 0;
      for (final flight in backup.flights) {
        if (await _shouldWrite(
          transaction,
          'flights',
          flight.id,
          flight.updatedAt,
        )) {
          final existingTransit = await _transitFlagInTransaction(
            transaction,
            flight.id,
          );
          await transaction.insert(
            'flights',
            _flightToRow(
              flight.withImportedTransitAnnotation(
                existingValue: existingTransit,
              ),
            ),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          flightCount++;
        }
      }
      for (final place in backup.visitedPlaces) {
        if (await _shouldWrite(
          transaction,
          'visited_places',
          place.id,
          place.updatedAt,
        )) {
          final existingSource = await _placeSourceInTransaction(
            transaction,
            place.id,
          );
          await transaction.insert(
            'visited_places',
            _placeToRow(
              place.withImportedSource(existingSource: existingSource),
            ),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          placeCount++;
        }
      }
      if (backup.containsJourneys) {
        final localJourneys = _journeysFromMeta(
          await _getMetaInTransaction(transaction, _journeyMetaKey),
        );
        await _setJourneysInTransaction(
          transaction,
          _mergeJourneys(localJourneys, backup.journeys),
        );
      }
      if (backup.containsTransferDecisions) {
        final localDecisions = TransferDecisionStore.decode(
          await _getMetaInTransaction(transaction, _transferDecisionsMetaKey),
        );
        await _setMetaInTransaction(
          transaction,
          _transferDecisionsMetaKey,
          TransferDecisionStore.encode(
            _mergeTransferDecisions(localDecisions, backup.transferDecisions),
          ),
        );
      }
      if (backup.countTransitArrivals != null) {
        await transaction.insert('app_meta', {
          'key': 'count_transit_arrivals',
          'value': backup.countTransitArrivals.toString(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      return ImportResult(flightsMerged: flightCount, placesMerged: placeCount);
    });
  }

  /// Replaces the local snapshot with a fully validated backup.
  ///
  /// Cloud restore is an explicit destructive operation, so it must not use
  /// [importBackup]'s ID-based merge semantics. Clearing both tables in the
  /// same transaction makes the local result deterministic and prevents old
  /// records from being duplicated or left behind after a device restore.
  Future<ImportResult> replaceBackup(String source) async {
    final backup = BackupCodec.decode(source);
    final database = await _databaseProvider();
    return database.transaction((transaction) async {
      await transaction.delete('flights');
      await transaction.delete('visited_places');
      for (final flight in backup.flights) {
        await transaction.insert(
          'flights',
          _flightToRow(flight),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      for (final place in backup.visitedPlaces) {
        await transaction.insert(
          'visited_places',
          _placeToRow(place),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      if (backup.containsJourneys) {
        await _setJourneysInTransaction(transaction, backup.journeys);
      }
      if (backup.containsTransferDecisions) {
        await _setTransferDecisionsInTransaction(
          transaction,
          backup.transferDecisions,
        );
      }
      if (backup.countTransitArrivals != null) {
        await transaction.insert('app_meta', {
          'key': 'count_transit_arrivals',
          'value': backup.countTransitArrivals.toString(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      return ImportResult(
        flightsMerged: backup.flights.length,
        placesMerged: backup.visitedPlaces.length,
      );
    });
  }

  Future<String?> _getMetaInTransaction(
    Transaction transaction,
    String key,
  ) async {
    final rows = await transaction.query(
      'app_meta',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single['value']! as String;
  }

  Future<void> _setTransferDecisionsInTransaction(
    Transaction transaction,
    List<TransferDecision> decisions,
  ) => _setMetaInTransaction(
    transaction,
    _transferDecisionsMetaKey,
    TransferDecisionStore.encode(decisions),
  );

  Future<void> _setMetaInTransaction(
    Transaction transaction,
    String key,
    String value,
  ) async {
    await transaction.insert('app_meta', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  List<TransferDecision> _mergeTransferDecisions(
    Iterable<TransferDecision> local,
    Iterable<TransferDecision> imported,
  ) {
    final result = <String, TransferDecision>{
      for (final decision in local) decision.id: decision,
    };
    for (final decision in imported) {
      final existing = result[decision.id];
      if (existing == null || !existing.decidedAt.isAfter(decision.decidedAt)) {
        result[decision.id] = decision;
      }
    }
    return List.unmodifiable(result.values);
  }

  Future<bool> _transitFlagInTransaction(
    Transaction transaction,
    String flightId,
  ) async {
    final rows = await transaction.query(
      'flights',
      columns: ['is_transit_arrival'],
      where: 'id = ?',
      whereArgs: [flightId],
      limit: 1,
    );
    return rows.isNotEmpty &&
        (rows.single['is_transit_arrival'] as int? ?? 0) != 0;
  }

  Future<FootprintRecordSource?> _placeSourceInTransaction(
    Transaction transaction,
    String placeId,
  ) async {
    final rows = await transaction.query(
      'visited_places',
      columns: ['source'],
      where: 'id = ?',
      whereArgs: [placeId],
      limit: 1,
    );
    return rows.isEmpty
        ? null
        : footprintRecordSourceFromStorage(rows.single['source']);
  }

  Future<void> _setJourneysInTransaction(
    Transaction transaction,
    Iterable<Journey> journeys,
  ) async {
    await transaction.insert('app_meta', {
      'key': _journeyMetaKey,
      'value': jsonEncode({
        'version': _journeySchemaVersion,
        'journeys': journeys.map((journey) => journey.toJson()).toList(),
      }),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  List<Journey> _journeysFromMeta(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['version'] != _journeySchemaVersion) {
        return const [];
      }
      final values = decoded['journeys'];
      if (values is! List) return const [];
      final result = <String, Journey>{};
      for (final value in values) {
        if (value is! Map) continue;
        try {
          final journey = Journey.fromJson(Map<String, Object?>.from(value));
          final current = result[journey.id];
          if (current == null || journey.updatedAt.isAfter(current.updatedAt)) {
            result[journey.id] = journey;
          }
        } on FormatException {
          // A corrupt local journey entry should not block flight restore.
        }
      }
      return result.values.toList(growable: false);
    } on FormatException {
      return const [];
    } on JsonUnsupportedObjectError {
      return const [];
    }
  }

  List<Journey> _mergeJourneys(
    Iterable<Journey> local,
    Iterable<Journey> incoming,
  ) {
    final merged = <String, Journey>{
      for (final journey in local) journey.id: journey,
    };
    for (final journey in incoming) {
      final current = merged[journey.id];
      if (current == null ||
          journey.updatedAt.isAfter(current.updatedAt) ||
          journey.updatedAt.isAtSameMomentAs(current.updatedAt)) {
        merged[journey.id] = journey;
      }
    }
    return merged.values.toList(growable: false);
  }

  Future<bool> _shouldWrite(
    Transaction transaction,
    String table,
    String id,
    DateTime incomingUpdatedAt,
  ) async {
    final rows = await transaction.query(
      table,
      columns: ['updated_at'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ||
        incomingUpdatedAt.millisecondsSinceEpoch >=
            (rows.single['updated_at'] as int);
  }

  Map<String, Object?> _flightToRow(Flight flight) => {
    'id': flight.id,
    'departure_iata': flight.departureIata,
    'arrival_iata': flight.arrivalIata,
    'departed_at': flight.departedAt.millisecondsSinceEpoch,
    'arrived_at': flight.arrivedAt?.millisecondsSinceEpoch,
    'status': flightStatusToStorage(flight.status),
    'is_transit_arrival': flight.isTransitArrival ? 1 : 0,
    'airline': flight.airline,
    'flight_number': flight.flightNumber,
    'cabin_class': flight.cabinClass,
    'aircraft_type': flight.aircraftType,
    'duration_minutes': flight.durationMinutes,
    'seat': flight.seat,
    'note': flight.note,
    'distance_km': flight.distanceKm,
    'track_json': jsonEncode([
      for (final point in flight.track)
        {
          'recordedAt': point.recordedAt,
          'latitude': point.latitude,
          'longitude': point.longitude,
          'altitudeFt': point.altitudeFt,
          'groundSpeedKt': point.groundSpeedKt,
          'heading': point.heading,
          'onGround': point.onGround,
          'source': point.source,
        },
    ]),
    'created_at': flight.createdAt.millisecondsSinceEpoch,
    'updated_at': flight.updatedAt.millisecondsSinceEpoch,
  };

  Flight _flightFromRow(Map<String, Object?> row) => Flight(
    id: row['id']! as String,
    departureIata: row['departure_iata']! as String,
    arrivalIata: row['arrival_iata']! as String,
    departedAt: _date(row['departed_at']),
    arrivedAt: _nullableDate(row['arrived_at']),
    status: flightStatusFromStorage(row['status']),
    isTransitArrival: (row['is_transit_arrival'] as int? ?? 0) != 0,
    airline: row['airline'] as String?,
    flightNumber: row['flight_number'] as String?,
    cabinClass: row['cabin_class'] as String?,
    aircraftType: row['aircraft_type'] as String?,
    durationMinutes: row['duration_minutes'] as int?,
    seat: row['seat'] as String?,
    note: row['note'] as String?,
    distanceKm: (row['distance_km'] as num?)?.toDouble(),
    track: _trackFromJson(row['track_json']),
    createdAt: _date(row['created_at']),
    updatedAt: _date(row['updated_at']),
  );

  Map<String, Object?> _placeToRow(VisitedPlace place) => {
    'id': place.id,
    'name': place.name,
    'latitude': place.latitude,
    'longitude': place.longitude,
    'visited_at': place.visitedAt.millisecondsSinceEpoch,
    'country_code': place.countryCode,
    'note': place.note,
    'source': place.source.name,
    'created_at': place.createdAt.millisecondsSinceEpoch,
    'updated_at': place.updatedAt.millisecondsSinceEpoch,
  };

  VisitedPlace _placeFromRow(Map<String, Object?> row) => VisitedPlace(
    id: row['id']! as String,
    name: row['name']! as String,
    latitude: (row['latitude']! as num).toDouble(),
    longitude: (row['longitude']! as num).toDouble(),
    visitedAt: _date(row['visited_at']),
    countryCode: row['country_code'] as String?,
    note: row['note'] as String?,
    source: footprintRecordSourceFromStorage(row['source']),
    createdAt: _date(row['created_at']),
    updatedAt: _date(row['updated_at']),
  );

  DateTime _date(Object? value) =>
      DateTime.fromMillisecondsSinceEpoch(value! as int, isUtc: true);

  DateTime? _nullableDate(Object? value) => value == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(value as int, isUtc: true);

  _FlightImportPlan _planImport(
    Iterable<Flight> existing,
    Iterable<Flight> incoming,
  ) {
    final existingByKey = <String, Flight>{};
    final existingById = <String, Flight>{};
    for (final flight in existing) {
      if (flight.id.isNotEmpty) existingById[flight.id] = flight;
      final key = _flightImportIdentityKey(flight);
      if (key.isEmpty) continue;
      final previous = existingByKey[key];
      if (previous == null || flight.updatedAt.isAfter(previous.updatedAt)) {
        existingByKey[key] = flight;
      }
    }

    // A malformed export can contain the same flight more than once. Keep the
    // last row while retaining the first row's position for a stable preview.
    final uniqueIncoming = <String, Flight>{};
    for (final flight in incoming) {
      final key = _flightImportIdentityKey(flight);
      if (key.isEmpty) continue;
      uniqueIncoming[key] = flight;
    }

    final operations = <_FlightImportOperation>[];
    var conflicts = 0;
    for (final flight in uniqueIncoming.values) {
      final existingFlight =
          existingById[flight.id] ??
          existingByKey[_flightImportIdentityKey(flight)];
      if (existingFlight == null) {
        operations.add(_FlightImportOperation(incoming: flight));
        continue;
      }
      final merged = _mergeSpreadsheetFlight(existingFlight, flight);
      final changed = !_spreadsheetFieldsEqual(existingFlight, merged);
      if (changed) conflicts++;
      operations.add(
        _FlightImportOperation(
          incoming: flight,
          existing: existingFlight,
          merged: merged,
          changed: changed,
        ),
      );
    }

    var added = 0;
    var unchanged = 0;
    for (final operation in operations) {
      if (operation.existing == null) {
        added++;
      } else if (!operation.changed) {
        unchanged++;
      }
    }
    return _FlightImportPlan(
      operations: operations,
      summary: FlightImportSummary(
        added: added,
        unchanged: unchanged,
        conflicts: conflicts,
      ),
      conflicts: conflicts,
    );
  }

  Flight _mergeSpreadsheetFlight(Flight existing, Flight incoming) => Flight(
    id: existing.id,
    departureIata: incoming.departureIata,
    arrivalIata: incoming.arrivalIata,
    departedAt: incoming.departedAt,
    arrivedAt: incoming.arrivedAt ?? existing.arrivedAt,
    createdAt: existing.createdAt,
    updatedAt: incoming.updatedAt,
    status: incoming.status,
    // Explicit annotation is local/user-authored and must survive imports.
    isTransitArrival: existing.isTransitArrival,
    airline: incoming.airline ?? existing.airline,
    flightNumber: incoming.flightNumber ?? existing.flightNumber,
    // These fields are not included in the Umetrip export, so keep the local
    // value instead of erasing information the user entered separately.
    cabinClass: existing.cabinClass,
    aircraftType: incoming.aircraftType ?? existing.aircraftType,
    durationMinutes: incoming.durationMinutes ?? existing.durationMinutes,
    seat: existing.seat,
    note: _mergeSpreadsheetNote(existing.note, incoming.note),
    distanceKm: incoming.distanceKm ?? existing.distanceKm,
    track: existing.track,
  );

  bool _spreadsheetFieldsEqual(Flight left, Flight right) =>
      left.departureIata.trim().toUpperCase() ==
          right.departureIata.trim().toUpperCase() &&
      left.arrivalIata.trim().toUpperCase() ==
          right.arrivalIata.trim().toUpperCase() &&
      left.departedAt.millisecondsSinceEpoch ==
          right.departedAt.millisecondsSinceEpoch &&
      left.arrivedAt?.millisecondsSinceEpoch ==
          right.arrivedAt?.millisecondsSinceEpoch &&
      left.status == right.status &&
      _normalized(left.airline) == _normalized(right.airline) &&
      _normalized(left.flightNumber) == _normalized(right.flightNumber) &&
      _normalized(left.aircraftType) == _normalized(right.aircraftType) &&
      left.durationMinutes == right.durationMinutes &&
      _normalized(left.note) == _normalized(right.note) &&
      left.distanceKm == right.distanceKm;

  String? _mergeSpreadsheetNote(String? existing, String? incoming) {
    final incomingText = incoming?.trim();
    if (incomingText == null || incomingText.isEmpty) return existing;
    final customParts = (existing ?? '')
        .split(' · ')
        .map((part) => part.trim())
        .where(
          (part) =>
              part.isNotEmpty &&
              !part.startsWith('客票号：') &&
              !part.startsWith('客票状态：') &&
              !part.startsWith('Ticket number:') &&
              !part.startsWith('Ticket status:'),
        )
        .toList();
    return [...customParts, incomingText].join(' · ');
  }

  String _flightImportIdentityKey(Flight flight) {
    final number = _normalized(flight.flightNumber);
    if (number.isEmpty) return '';
    final airport = flight.departureIata.trim().toUpperCase();
    if (airport.isEmpty) return '';
    final zone = _timeZoneForIata?.call(airport);
    final date = FlightTimeResolver.toWallTime(flight.departedAt, zone);
    // Without an airport timezone, different imports cannot be safely matched
    // by calendar day; stable IDs still match in _planImport.
    if (date == null) return 'unknown-zone|${flight.id}';
    final day = [
      date.year,
      date.month,
      date.day,
    ].map((value) => value.toString().padLeft(2, '0')).join('-');
    return '$day|$number|$airport';
  }

  String _normalized(String? value) =>
      value?.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '') ?? '';

  List<FlightTrackPoint> _trackFromJson(Object? value) {
    if (value is! String || value.isEmpty) return const [];
    try {
      final decoded = jsonDecode(value);
      if (decoded is! List) return const [];
      return [
        for (final item in decoded)
          if (item is Map)
            FlightTrackPoint(
              recordedAt: (item['recordedAt'] as num?)?.round() ?? 0,
              latitude: (item['latitude'] as num?)?.toDouble() ?? 0,
              longitude: (item['longitude'] as num?)?.toDouble() ?? 0,
              altitudeFt: (item['altitudeFt'] as num?)?.round(),
              groundSpeedKt: (item['groundSpeedKt'] as num?)?.round(),
              heading: (item['heading'] as num?)?.round(),
              onGround: item['onGround'] == true,
              source: item['source'] is String ? item['source'] as String : '',
            ),
      ];
    } catch (_) {
      return const [];
    }
  }
}
