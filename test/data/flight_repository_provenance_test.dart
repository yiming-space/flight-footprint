import 'package:flight_footprint/data/backup_codec.dart';
import 'package:flight_footprint/data/flight_data_controller.dart';
import 'package:flight_footprint/data/flight_repository.dart';
import 'package:flight_footprint/domain/flight.dart';
import 'package:flight_footprint/domain/visited_place.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

void main() {
  late _MemoryDatabase database;
  late FlightRepository repository;
  final created = DateTime.utc(2025, 1, 1);

  setUp(() {
    database = _MemoryDatabase();
    repository = FlightRepository(databaseProvider: () async => database);
  });

  test(
    'merge import keeps local mark when old backup omits the field',
    () async {
      await repository.upsertFlight(_flight(created, transit: true));
      final incoming = _flight(created.add(const Duration(days: 1)));
      final oldBackup = BackupCodec.encode(
        BackupData(
          flights: [incoming.copyWith(hasTransitArrivalAnnotation: false)],
          visitedPlaces: const [],
        ),
      );

      await repository.importBackup(oldBackup);

      expect((await repository.listFlights()).single.isTransitArrival, isTrue);
    },
  );

  test('merge import honors explicit false from an updated backup', () async {
    await repository.upsertFlight(_flight(created, transit: true));
    final incoming = _flight(created.add(const Duration(days: 1)));
    final updatedBackup = BackupCodec.encode(
      BackupData(flights: [incoming], visitedPlaces: const []),
    );

    await repository.importBackup(updatedBackup);

    expect((await repository.listFlights()).single.isTransitArrival, isFalse);
  });

  test(
    'merge import preserves known source when old backup omits source',
    () async {
      await repository.upsertVisitedPlace(_place(created));
      final incoming = _place(created.add(const Duration(days: 1))).copyWith(
        source: FootprintRecordSource.unknown,
        hasSourceAnnotation: false,
      );
      final oldBackup = BackupCodec.encode(
        BackupData(flights: const [], visitedPlaces: [incoming]),
      );

      await repository.importBackup(oldBackup);

      expect(
        (await repository.listVisitedPlaces()).single.source,
        FootprintRecordSource.manual,
      );
    },
  );

  test('merge import honors explicitly unknown source', () async {
    await repository.upsertVisitedPlace(_place(created));
    final incoming = _place(created.add(const Duration(days: 1)))
        .copyWith(source: FootprintRecordSource.unknown);
    final updatedBackup = BackupCodec.encode(
      BackupData(flights: const [], visitedPlaces: [incoming]),
    );

    await repository.importBackup(updatedBackup);

    expect(
      (await repository.listVisitedPlaces()).single.source,
      FootprintRecordSource.unknown,
    );
  });

  test('transit preference persists through repository metadata', () async {
    final controller = FlightDataController(repository);
    addTearDown(controller.dispose);
    await controller.setCountTransitArrivals(false);

    final restored = FlightDataController(repository);
    addTearDown(restored.dispose);
    await restored.refresh(now: created);

    expect(restored.countTransitArrivals, isFalse);
  });
}

Flight _flight(DateTime time, {bool transit = false}) => Flight(
  id: 'flight-1',
  departureIata: 'PVG',
  arrivalIata: 'SZX',
  departedAt: time,
  createdAt: time,
  updatedAt: time,
  isTransitArrival: transit,
);

VisitedPlace _place(DateTime time) => VisitedPlace(
  id: 'place-1',
  name: 'Shanghai',
  latitude: 31.2,
  longitude: 121.5,
  visitedAt: time,
  createdAt: time,
  updatedAt: time,
  source: FootprintRecordSource.manual,
);

class _MemoryDatabase implements Database {
  _MemoryDatabase([Map<String, Map<String, Object?>>? tables])
    : tables = tables ?? {'flights': {}, 'visited_places': {}, 'app_meta': {}};

  final Map<String, Map<String, Object?>> tables;

  @override
  Future<T> transaction<T>(
    Future<T> Function(Transaction txn) action, {
    bool? exclusive,
  }) => action(_MemoryTransaction(tables));

  @override
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    final row = Map<String, Object?>.from(values);
    final key = (row['id'] ?? row['key'])! as String;
    tables[table]![key] = row;
    return 1;
  }

  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) async =>
      _queryRows(tables, table, columns, where, whereArgs, limit, offset);

  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MemoryTransaction extends _MemoryDatabase implements Transaction {
  _MemoryTransaction(super.tables);
}

List<Map<String, Object?>> _queryRows(
  Map<String, Map<String, Object?>> tables,
  String table,
  List<String>? columns,
  String? where,
  List<Object?>? whereArgs,
  int? limit,
  int? offset,
) {
  List<Map<String, Object?>> result = tables[table]!.values
      .map((row) => Map<String, Object?>.from(row as Map))
      .toList();
  if (where != null && whereArgs != null && whereArgs.isNotEmpty) {
    final keyColumn = where.startsWith('key') ? 'key' : 'id';
    result = result.where((row) => row[keyColumn] == whereArgs.first).toList();
  }
  if (offset != null && offset > 0) result = result.skip(offset).toList();
  if (limit != null) result = result.take(limit).toList();
  return [
    for (final row in result)
      columns == null
          ? Map<String, Object?>.from(row)
          : {for (final column in columns) column: row[column]},
  ];
}
