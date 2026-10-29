import 'dart:io';

import 'package:flight_footprint/data/local_database.dart';
import 'package:flight_footprint/data/flight_repository.dart';
import 'package:flight_footprint/domain/flight.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('real SQLite upgrades v4 records and preserves unrelated settings', () async {
    sqfliteFfiInit();
    final directory = await Directory.systemTemp.createTemp('ff-upgrade-');
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/legacy.db';
    var db = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 4,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE app_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE flights (id TEXT PRIMARY KEY, departure_iata TEXT NOT NULL, arrival_iata TEXT NOT NULL, departed_at INTEGER NOT NULL, arrived_at INTEGER, status TEXT NOT NULL, airline TEXT, flight_number TEXT, cabin_class TEXT, aircraft_type TEXT, duration_minutes INTEGER, seat TEXT, note TEXT, distance_km REAL, track_json TEXT NOT NULL, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE visited_places (id TEXT PRIMARY KEY, name TEXT NOT NULL, latitude REAL NOT NULL, longitude REAL NOT NULL, visited_at INTEGER NOT NULL, country_code TEXT, note TEXT, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)',
          );
          await db.insert('app_meta', {'key': 'schema_version', 'value': '4'});
          await db.insert('app_meta', {'key': 'language', 'value': 'zh'});
          await db.insert('app_meta', {'key': 'theme_mode', 'value': 'dark'});
          await db.insert('app_meta', {
            'key': 'transfer_decisions_v1',
            'value': '[{"saved":true}]',
          });
          await db.insert('flights', {
            'id': 'flight-1',
            'departure_iata': 'PVG',
            'arrival_iata': 'LHR',
            'departed_at': 100,
            'arrived_at': 200,
            'status': 'completed',
            'flight_number': 'CA123',
            'track_json': '[]',
            'created_at': 100,
            'updated_at': 100,
          });
          await db.insert('visited_places', {
            'id': 'place-1',
            'name': 'London',
            'latitude': 51.5,
            'longitude': -0.1,
            'visited_at': 200,
            'note': 'legacy note',
            'created_at': 100,
            'updated_at': 100,
          });
        },
      ),
    );
    await db.close();
    db = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: LocalDatabase.schemaVersion,
        onUpgrade: LocalDatabase.upgradeSchema,
      ),
    );
    addTearDown(db.close);
    final meta = {
      for (final row in await db.query('app_meta')) row['key']: row['value'],
    };
    expect(meta['schema_version'], '6');
    expect(meta['language'], 'zh');
    expect(meta['theme_mode'], 'dark');
    expect(meta['transfer_decisions_v1'], '[{"saved":true}]');
    final flight = (await db.query('flights')).single;
    expect(flight['id'], 'flight-1');
    expect(flight['arrival_iata'], 'LHR');
    expect(flight['is_transit_arrival'], 0);
    final place = (await db.query('visited_places')).single;
    expect(place['name'], 'London');
    expect(place['note'], 'legacy note');
    expect(place['source'], 'unknown');

    final repo = FlightRepository(databaseProvider: () async => db);
    final changed = Flight(
      id: 'flight-1',
      departureIata: 'PVG',
      arrivalIata: 'LHR',
      departedAt: DateTime.utc(2026, 5, 2),
      arrivedAt: DateTime.utc(2026, 5, 2, 8),
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      flightNumber: 'CA123',
    );
    final result = await repo.importFlights([
      changed,
    ], overwriteExisting: false);
    expect(result.added, 0);
    expect(result.skipped, 1);
    expect((await db.query('flights')).single['departed_at'], 100);
  });
}
