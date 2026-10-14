import '../../domain/flight.dart';

enum AircraftManufacturer { airbus, boeing, other }

class AircraftCollectionEntry {
  AircraftCollectionEntry({
    required this.key,
    required this.type,
    required this.manufacturer,
    required List<Flight> flights,
  }) : flights = List<Flight>.unmodifiable(flights);

  final String key;
  final String type;
  final AircraftManufacturer manufacturer;
  final List<Flight> flights;

  int get count => flights.length;

  double get distanceKm => flights.fold<double>(0, (total, flight) {
    final distance = flight.distanceKm;
    return distance != null && distance.isFinite && distance >= 0
        ? total + distance
        : total;
  });
}

/// Collects recorded aircraft types without guessing missing types or variants.
///
/// IDs are unique across the collection: the first completed record with a
/// usable type wins. Normalization only changes case, whitespace and an explicit
/// matching manufacturer prefix; suffixes such as MAX and NEO stay distinct.
List<AircraftCollectionEntry> buildAircraftCollection(
  Iterable<Flight> flights,
) {
  final groups = <String, List<Flight>>{};
  final seenIds = <String>{};
  for (final flight in flights) {
    if (!flight.isCompleted) continue;
    final type = _normalizeType(flight.aircraftType);
    if (type == null || !seenIds.add(flight.id)) continue;
    groups.putIfAbsent(type, () => <Flight>[]).add(flight);
  }

  final entries = groups.entries.map((group) {
    group.value.sort((left, right) {
      final dateOrder = right.departedAt.compareTo(left.departedAt);
      return dateOrder != 0 ? dateOrder : left.id.compareTo(right.id);
    });
    return AircraftCollectionEntry(
      key: group.key,
      type: group.key,
      manufacturer: _manufacturerForType(group.key),
      flights: group.value,
    );
  }).toList();
  entries.sort((left, right) {
    final countOrder = right.count.compareTo(left.count);
    return countOrder != 0 ? countOrder : left.type.compareTo(right.type);
  });
  return List<AircraftCollectionEntry>.unmodifiable(entries);
}

String? _normalizeType(String? value) {
  var type = (value ?? '').trim().replaceAll(RegExp(r'\s+'), ' ').toUpperCase();
  if (type.isEmpty || _missingTypes.contains(type)) return null;

  for (final prefix in _manufacturerPrefixes.entries) {
    final match = prefix.value.firstMatch(type);
    if (match == null) continue;
    final remainder = type.substring(match.end).trim();
    if (_manufacturerForType(remainder) == prefix.key) type = remainder;
    break;
  }
  return type;
}

const _missingTypes = {
  'UNKNOWN',
  'UNKNOWN AIRCRAFT',
  'UNKNOWN TYPE',
  '未知',
  '未知机型',
  '不详',
  'N/A',
  'NA',
  '-',
  '--',
};

final _manufacturerPrefixes = {
  AircraftManufacturer.airbus: RegExp(r'^(?:AIRBUS\s+|空中客车\s*|空客\s*)'),
  AircraftManufacturer.boeing: RegExp(r'^(?:BOEING\s+|波音\s*)'),
};

// Require a model boundary so unrelated labels such as A320ISH or B737XYZ
// cannot be classified merely because they begin with a familiar model code.
final _airbusType = RegExp(
  r'^A(?:220|300|310|318|319|320|321|330|340|350|380)(?:$|[\s-]|(?:NEO|CEO|XLR|LR)(?:$|[\s-]))',
);
final _boeingType = RegExp(
  r'^B?(?:707|717|727|737|747|757|767|777|787)(?:$|[\s-]|MAX(?:$|[\s-]))',
);

AircraftManufacturer _manufacturerForType(String type) {
  if (_airbusType.hasMatch(type)) return AircraftManufacturer.airbus;
  if (_boeingType.hasMatch(type)) return AircraftManufacturer.boeing;
  return AircraftManufacturer.other;
}
