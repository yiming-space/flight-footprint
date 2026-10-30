import 'package:flight_footprint/data/flight_data_controller.dart';
import 'package:flight_footprint/data/flight_repository.dart';
import 'package:flight_footprint/domain/flight.dart';
import 'package:flight_footprint/domain/transfer_decision.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test(
    'confirmed transfer survives controller recreation and database reload',
    () async {
      sqfliteFfiInit();
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await db.execute(
        'CREATE TABLE app_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
      );
      await db.execute(
        '''CREATE TABLE flights (id TEXT PRIMARY KEY, departure_iata TEXT, arrival_iata TEXT, departed_at INTEGER, arrived_at INTEGER, status TEXT, is_transit_arrival INTEGER, airline TEXT, flight_number TEXT, cabin_class TEXT, aircraft_type TEXT, duration_minutes INTEGER, seat TEXT, note TEXT, distance_km REAL, track_json TEXT, created_at INTEGER, updated_at INTEGER)''',
      );
      await db.execute(
        '''CREATE TABLE visited_places (id TEXT PRIMARY KEY, name TEXT, latitude REAL, longitude REAL, visited_at INTEGER, country_code TEXT, note TEXT, source TEXT, created_at INTEGER, updated_at INTEGER)''',
      );
      final repo = FlightRepository(databaseProvider: () async => db);
      final t = DateTime.utc(2026, 1, 1);
      Flight f(String id, String from, String to, int dep, int arr) => Flight(
        id: id,
        departureIata: from,
        arrivalIata: to,
        departedAt: t.add(Duration(hours: dep)),
        arrivedAt: t.add(Duration(hours: arr)),
        createdAt: t,
        updatedAt: t,
      );
      final inbound = f('in', 'SZX', 'PEK', 0, 2);
      final outbound = f('out', 'PEK', 'SHA', 4, 6);
      await repo.upsertFlight(inbound);
      await repo.upsertFlight(outbound);
      final first = FlightDataController(repo);
      await first.refresh(now: t.add(const Duration(days: 1)));
      await first.decideTransfer(
        inbound,
        outbound,
        TransferDecisionStatus.confirmed,
      );
      first.dispose();
      final reopened = FlightDataController(repo);
      addTearDown(reopened.dispose);
      await reopened.refresh(now: t.add(const Duration(days: 1)));
      expect(
        reopened.transferDecisionFor(inbound, outbound)?.status,
        TransferDecisionStatus.confirmed,
      );
    },
  );
}
