import 'package:flight_footprint/data/flight_repository.dart';
import 'package:flight_footprint/domain/flight.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('undo removes only unchanged records added by this batch', () async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await db.execute('''CREATE TABLE flights (
      id TEXT PRIMARY KEY, departure_iata TEXT, arrival_iata TEXT,
      departed_at INTEGER, arrived_at INTEGER, status TEXT,
      is_transit_arrival INTEGER, airline TEXT, flight_number TEXT,
      cabin_class TEXT, aircraft_type TEXT, duration_minutes INTEGER,
      seat TEXT, note TEXT, distance_km REAL, track_json TEXT,
      created_at INTEGER, updated_at INTEGER)''');
    final repo = FlightRepository(databaseProvider: () async => db);
    final now = DateTime.utc(2026, 1, 1);
    Flight f(String id, String number) => Flight(
      id: id,
      departureIata: 'SZX',
      arrivalIata: 'PEK',
      departedAt: now,
      createdAt: now,
      updatedAt: now,
      flightNumber: number,
    );
    final previous = f('existing', 'CA100');
    await repo.upsertFlight(previous);
    final a = f('new-a', 'CA101');
    final b = f('new-b', 'CA102');
    final result = await repo.importFlights([previous, a, b]);
    expect(result.addedRecords.map((x) => x.id), ['new-a', 'new-b']);
    await repo.upsertFlight(
      b.copyWith(
        note: 'edited',
        updatedAt: now.add(const Duration(seconds: 1)),
      ),
    );
    expect(await repo.undoAddedFlights(result.addedRecords), 1);
    final rows = await db.query('flights', columns: ['id'], orderBy: 'id');
    expect(rows.map((r) => r['id']), ['existing', 'new-b']);
  });
}
