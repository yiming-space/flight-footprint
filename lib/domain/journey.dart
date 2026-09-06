class Journey {
  const Journey({
    required this.id,
    required this.name,
    required this.flightIds,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final List<String> flightIds;
  final DateTime createdAt;
  final DateTime updatedAt;

  Journey copyWith({
    String? name,
    List<String>? flightIds,
    DateTime? updatedAt,
  }) => Journey(
    id: id,
    name: name ?? this.name,
    flightIds: List.unmodifiable(flightIds ?? this.flightIds),
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'flightIds': flightIds,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  factory Journey.fromJson(Map<String, Object?> json) => Journey(
    id: _requiredString(json['id']),
    name: _requiredString(json['name']),
    flightIds: [
      for (final value in (json['flightIds'] as List? ?? const []))
        if (value is String && value.trim().isNotEmpty) value,
    ],
    createdAt: DateTime.parse(_requiredString(json['createdAt'])).toUtc(),
    updatedAt: DateTime.parse(_requiredString(json['updatedAt'])).toUtc(),
  );

  static String _requiredString(Object? value) {
    final result = value?.toString().trim() ?? '';
    if (result.isEmpty) throw const FormatException('Missing journey field');
    return result;
  }
}
