import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class LocalDatabase {
  LocalDatabase._();

  static const schemaVersion = 6;
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
            is_transit_arrival INTEGER NOT NULL DEFAULT 0,
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
            source TEXT NOT NULL DEFAULT 'unknown',
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
      onUpgrade: upgradeSchema,
    );
    return _instance!;
  }

  /// Upgrades an existing database using the same path as app startup.
  static Future<void> upgradeSchema(
    Database database,
    int oldVersion,
    int newVersion,
  ) async {
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
    if (oldVersion < 5) {
      await database.execute(
        "ALTER TABLE visited_places ADD COLUMN source TEXT NOT NULL DEFAULT 'unknown'",
      );
    }
    if (oldVersion < 6) {
      await database.execute(
        'ALTER TABLE flights ADD COLUMN is_transit_arrival INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (oldVersion < newVersion) {
      await database.update(
        'app_meta',
        {'value': '$newVersion'},
        where: 'key = ?',
        whereArgs: ['schema_version'],
      );
    }
  }

  static Future<void> closeForTesting() async {
    await _instance?.close();
    _instance = null;
  }
}
