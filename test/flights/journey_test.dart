import 'package:flight_footprint/domain/journey.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('journey round-trips stable JSON fields and UTC dates', () {
    final journey = Journey(
      id: 'j1',
      name: '东京周末',
      flightIds: const ['f1', 'f2'],
      createdAt: DateTime.parse('2026-05-01T01:02:03+08:00'),
      updatedAt: DateTime.parse('2026-05-02T01:02:03+08:00'),
    );

    final restored = Journey.fromJson(journey.toJson());

    expect(restored.id, journey.id);
    expect(restored.name, journey.name);
    expect(restored.flightIds, journey.flightIds);
    expect(restored.createdAt, journey.createdAt.toUtc());
    expect(restored.updatedAt, journey.updatedAt.toUtc());
  });

  test('journey ignores malformed flight ids but rejects missing identity', () {
    final journey = Journey.fromJson({
      'id': 'j1',
      'name': 'Trip',
      'flightIds': ['f1', '', 42, 'f2'],
      'createdAt': '2026-05-01T00:00:00Z',
      'updatedAt': '2026-05-01T00:00:00Z',
    });
    expect(journey.flightIds, ['f1', 'f2']);

    expect(
      () => Journey.fromJson({
        'id': '',
        'name': 'Trip',
        'flightIds': const [],
        'createdAt': '2026-05-01T00:00:00Z',
        'updatedAt': '2026-05-01T00:00:00Z',
      }),
      throwsFormatException,
    );
  });
}
