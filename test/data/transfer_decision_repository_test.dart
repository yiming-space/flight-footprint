import 'package:flight_footprint/data/flight_repository.dart';
import 'package:flight_footprint/domain/flight.dart';
import 'package:flight_footprint/domain/transfer_decision.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database database;
  late FlightRepository repository;

  setUp(() async {
    sqfliteFfiInit();
    database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE app_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
          );
        },
      ),
    );
    repository = FlightRepository(databaseProvider: () async => database);
  });

  tearDown(() async => database.close());

  test(
    'decision survives repository reload and becomes stale after edits',
    () async {
      final inbound = _flight(
        id: 'in',
        departureIata: 'PVG',
        arrivalIata: 'PEK',
        departedAt: DateTime.utc(2026, 10, 1, 2),
        arrivedAt: DateTime.utc(2026, 10, 1, 5),
      );
      final outbound = _flight(
        id: 'out',
        departureIata: 'PEK',
        arrivalIata: 'HND',
        departedAt: DateTime.utc(2026, 10, 1, 8),
      );
      await repository.saveTransferDecision(
        TransferDecision.fromFlights(
          inbound: inbound,
          outbound: outbound,
          status: TransferDecisionStatus.confirmed,
        ),
      );

      expect(
        (await repository.activeTransferDecision(inbound, outbound))?.status,
        TransferDecisionStatus.confirmed,
      );
      expect(
        await repository.activeTransferDecision(
          inbound,
          outbound.copyWith(departureIata: 'SHA'),
        ),
        isNull,
      );
    },
  );

  test(
    'legacy backups without decision data preserve local decisions',
    () async {
      final inbound = _flight(
        id: 'in',
        departureIata: 'PVG',
        arrivalIata: 'PEK',
        departedAt: DateTime.utc(2026, 10, 1, 2),
      );
      final outbound = _flight(
        id: 'out',
        departureIata: 'PEK',
        arrivalIata: 'HND',
        departedAt: DateTime.utc(2026, 10, 1, 8),
      );
      final decision = TransferDecision.fromFlights(
        inbound: inbound,
        outbound: outbound,
        status: TransferDecisionStatus.rejected,
      );
      await repository.saveTransferDecision(decision);

      await repository.importBackup(
        '{"format":"flight-footprint-backup","version":1,'
        '"flights":[],"visitedPlaces":[]}',
      );

      expect(
        (await repository.listTransferDecisions()).single.status,
        TransferDecisionStatus.rejected,
      );
    },
  );
}

Flight _flight({
  required String id,
  required String departureIata,
  required String arrivalIata,
  required DateTime departedAt,
  DateTime? arrivedAt,
}) => Flight(
  id: id,
  departureIata: departureIata,
  arrivalIata: arrivalIata,
  departedAt: departedAt,
  arrivedAt: arrivedAt,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
);
