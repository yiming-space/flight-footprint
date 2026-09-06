import 'dart:convert';

import '../domain/journey.dart';
import 'flight_repository.dart';

/// Persists explicit user-created groupings in app_meta, independently from
/// the flight table. Missing flight references remain recoverable metadata.
class JourneyStore {
  JourneyStore(this.repository);

  static const metaKey = 'journeys_v1';
  static const schemaVersion = 1;

  final FlightRepository repository;

  Future<List<Journey>> load() async {
    final raw = await repository.getMeta(metaKey);
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['version'] != schemaVersion) {
        return const [];
      }
      final values = decoded['journeys'];
      if (values is! List) return const [];
      final journeys = <Journey>[];
      for (final value in values) {
        if (value is! Map) continue;
        try {
          journeys.add(Journey.fromJson(Map<String, Object?>.from(value)));
        } on Object {
          // Map.from can throw TypeError for malformed JSON values. Ignore one
          // malformed group while keeping the other groups usable.
        }
      }
      return journeys;
    } on FormatException {
      return const [];
    } on JsonUnsupportedObjectError {
      return const [];
    }
  }

  Future<void> save(Iterable<Journey> journeys) async {
    await repository.setMeta(
      metaKey,
      jsonEncode({
        'version': schemaVersion,
        'journeys': journeys.map((journey) => journey.toJson()).toList(),
      }),
    );
  }

  /// Returns a display-safe view without writing it back.
  ///
  /// Missing IDs remain in metadata so a later backup restore can bring the
  /// referenced flight back into the journey. Only explicit UI membership
  /// actions should call [save].
  Future<List<Journey>> removeMissingFlights(
    Iterable<Journey> journeys,
    Set<String> existingFlightIds,
  ) async => [
    for (final journey in journeys)
      journey.copyWith(
        flightIds: journey.flightIds
            .where(existingFlightIds.contains)
            .toList(growable: false),
      ),
  ];
}
