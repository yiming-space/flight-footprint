enum FootprintRecordSource { unknown, manual, photo }

FootprintRecordSource footprintRecordSourceFromStorage(Object? value) =>
    FootprintRecordSource.values.firstWhere(
      (source) => source.name == value?.toString(),
      orElse: () => FootprintRecordSource.unknown,
    );

class VisitedPlace {
  const VisitedPlace({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.visitedAt,
    required this.createdAt,
    required this.updatedAt,
    this.countryCode,
    this.note,
    this.source = FootprintRecordSource.unknown,
    this.hasSourceAnnotation = true,
  });

  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final DateTime visitedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? countryCode;
  final String? note;

  /// Unknown is intentional for legacy/imported records without provenance.
  final FootprintRecordSource source;

  /// False only when a legacy interchange format omitted provenance.
  final bool hasSourceAnnotation;

  VisitedPlace copyWith({
    String? name,
    double? latitude,
    double? longitude,
    DateTime? visitedAt,
    String? countryCode,
    String? note,
    FootprintRecordSource? source,
    bool? hasSourceAnnotation,
    DateTime? updatedAt,
  }) => VisitedPlace(
    id: id,
    name: name ?? this.name,
    latitude: latitude ?? this.latitude,
    longitude: longitude ?? this.longitude,
    visitedAt: visitedAt ?? this.visitedAt,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    countryCode: countryCode ?? this.countryCode,
    note: note ?? this.note,
    source: source ?? this.source,
    hasSourceAnnotation: hasSourceAnnotation ?? this.hasSourceAnnotation,
  );

  /// Preserve locally known provenance when an older backup omitted it.
  VisitedPlace withImportedSource({FootprintRecordSource? existingSource}) =>
      copyWith(
        source: hasSourceAnnotation ? source : existingSource ?? source,
      );
}
