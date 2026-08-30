import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class LocalDatabase {
  LocalDatabase._();

  static const schemaVersion = 4;
  static const _databaseName = 'flight_footprint.db';
  static Database? _instance;

  static Future<Database> open() async {
    if (_instance != null) return _instance!;
    final directory = await getApplicationDocumentsDirectory();
    _instance = await openDatabase(
      path.join(directory.path, _databaseName),
      version: schemaVersion,
      onCreate: (database, version) async {
        await database.execute('''
          CREATE TABLE app_meta (
            key TEXT PRIMARY KEY NOT NULL,
            value TEXT NOT NULL
          )
        ''');
        await database.execute('''
          CREATE TABLE flights (
            id TEXT PRIMARY KEY NOT NULL,
            departure_iata TEXT NOT NULL,
            arrival_iata TEXT NOT NULL,
            departed_at INTEGER NOT NULL,
            arrived_at INTEGER,
            status TEXT NOT NULL DEFAULT 'completed',
            airline TEXT,
            flight_number TEXT,
            cabin_class TEXT,
            aircraft_type TEXT,
            duration_minutes INTEGER,
            seat TEXT,
            note TEXT,
            distance_km REAL,
            track_json TEXT NOT NULL DEFAULT '[]',
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
        await database.execute('''
          CREATE TABLE visited_places (
            id TEXT PRIMARY KEY NOT NULL,
            name TEXT NOT NULL,
            latitude REAL NOT NULL,
            longitude REAL NOT NULL,
            visited_at INTEGER NOT NULL,
            country_code TEXT,
            note TEXT,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
        await database.execute(
          'CREATE INDEX flights_departed_at_idx ON flights(departed_at DESC)',
        );
        await database.execute(
          'CREATE INDEX flights_route_idx ON flights(departure_iata, arrival_iata)',
        );
        await database.execute(
          'CREATE INDEX visited_places_visited_at_idx '
          'ON visited_places(visited_at DESC)',
        );
        await database.insert('app_meta', {
          'key': 'schema_version',
          'value': '$schemaVersion',
        });
      },
      onUpgrade: (database, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await database.execute(
            "ALTER TABLE flights ADD COLUMN track_json TEXT NOT NULL DEFAULT '[]'",
          );
        }
        if (oldVersion < 3) {
          await database.execute(
            "ALTER TABLE flights ADD COLUMN status TEXT NOT NULL DEFAULT 'completed'",
          );
        }
        if (oldVersion < 4) {
          await database.execute(
            'ALTER TABLE flights ADD COLUMN arrived_at INTEGER',
          );
        }
        if (oldVersion < newVersion) {
          await database.update('app_meta', {'value': '$newVersion'});
        }
      },
    );
    return _instance!;
  }

  static Future<void> closeForTesting() async {
    await _instance?.close();
    _instance = null;
  }
}
