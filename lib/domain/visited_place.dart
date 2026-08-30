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

  VisitedPlace copyWith({
    String? name,
    double? latitude,
    double? longitude,
    DateTime? visitedAt,
    String? countryCode,
    String? note,
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
  );
}
