import 'package:flight_footprint/data/flight_repository.dart';
import 'package:flight_footprint/domain/flight.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test(
    'uses departure airport local day and does not merge different airports',
    () async {
      sqfliteFfiInit();
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await db.execute(
        '''CREATE TABLE flights (id TEXT PRIMARY KEY, departure_iata TEXT, arrival_iata TEXT, departed_at INTEGER, arrived_at INTEGER, status TEXT, is_transit_arrival INTEGER, airline TEXT, flight_number TEXT, cabin_class TEXT, aircraft_type TEXT, duration_minutes INTEGER, seat TEXT, note TEXT, distance_km REAL, track_json TEXT, created_at INTEGER, updated_at INTEGER)''',
      );
      final repo = FlightRepository(
        databaseProvider: () async => db,
        timeZoneForIata: (iata) =>
            {'SZX': 'Asia/Shanghai', 'PEK': 'Asia/Shanghai'}[iata],
      );
      final now = DateTime.utc(2026, 1, 1);
      Flight f(String id, String origin, DateTime departure) => Flight(
        id: id,
        departureIata: origin,
        arrivalIata: 'SHA',
        departedAt: departure,
        createdAt: now,
        updatedAt: now,
        flightNumber: 'CA123',
      );
      await repo.upsertFlight(
        f('existing', 'SZX', DateTime.utc(2026, 1, 1, 16, 30)),
      );
      final sameLocalDay = await repo.previewImportDetails([
        f('same-day', 'SZX', DateTime.utc(2026, 1, 2, 1)),
      ]);
      expect(
        sameLocalDay.summary.conflicts + sameLocalDay.summary.unchanged,
        1,
      );
      final differentAirport = await repo.previewImportDetails([
        f('different-airport', 'PEK', DateTime.utc(2026, 1, 2, 1)),
      ]);
      expect(differentAirport.summary.added, 1);
      final differentLocalDay = await repo.previewImportDetails([
        f('different-day', 'SZX', DateTime.utc(2026, 1, 2, 17)),
      ]);
      expect(differentLocalDay.summary.added, 1);
      final unknown = await repo.previewImportDetails([
        f('unknown-a', 'XXX', DateTime.utc(2026, 1, 2, 1)),
        f('unknown-b', 'XXX', DateTime.utc(2026, 1, 2, 2)),
      ]);
      expect(unknown.summary.added, 2);
    },
  );
}
