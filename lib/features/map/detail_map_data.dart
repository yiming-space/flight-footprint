import 'dart:math' as math;

import 'map_models.dart';

/// GeoJSON coordinates with adjacent longitudes unwrapped across the dateline.
List<List<double>> detailRouteCoordinates(MapRoute route) {
  if (route.track.length >= 2) {
    return _unwrap([
      for (final point in route.track) [point.longitude, point.latitude],
    ]);
  }
  final a = _unit(route.from.latitude, route.from.longitude);
  final b = _unit(route.to.latitude, route.to.longitude);
  final dot = _dot(a, b).clamp(-1.0, 1.0).toDouble();
  var tangent = [for (var i = 0; i < 3; i++) b[i] - dot * a[i]];
  final length = math.sqrt(_dot(tangent, tangent));
  final angle = math.atan2(length, dot);
  if (angle < 1e-10) {
    return _unwrap([
      [route.from.longitude, route.from.latitude],
      [route.to.longitude, route.to.latitude],
    ]);
  }
  if (length > 1e-10) {
    tangent = [for (final value in tangent) value / length];
  } else {
    // An antipodal route has no unique great circle. Choose a stable normal.
    final axis = a[2].abs() < .9 ? [0.0, 0.0, 1.0] : [0.0, 1.0, 0.0];
    final projection = _dot(axis, a);
    tangent = [for (var i = 0; i < 3; i++) axis[i] - projection * a[i]];
    final norm = math.sqrt(_dot(tangent, tangent));
    tangent = [for (final value in tangent) value / norm];
  }
  final steps = (angle / (math.pi / 128)).ceil().clamp(16, 64);
  final coordinates = <List<double>>[];
  for (var step = 0; step <= steps; step++) {
    if (step == 0 || step == steps) {
      coordinates.add(
        step == 0
            ? [route.from.longitude, route.from.latitude]
            : [route.to.longitude, route.to.latitude],
      );
      continue;
    }
    final theta = angle * step / steps;
    final vector = [
      for (var i = 0; i < 3; i++)
        a[i] * math.cos(theta) + tangent[i] * math.sin(theta),
    ];
    coordinates.add([
      math.atan2(vector[1], vector[0]) * 180 / math.pi,
      math.atan2(
            vector[2],
            math.sqrt(vector[0] * vector[0] + vector[1] * vector[1]),
          ) *
          180 /
          math.pi,
    ]);
  }
  return _unwrap(coordinates);
}

/// Center of the shortest longitude interval containing all points.
MapCoordinate detailMapCenter(Iterable<MapCoordinate> coordinates) {
  final points = coordinates.toList(growable: false);
  if (points.isEmpty) return const MapCoordinate(20, 0);
  final longitudes = [for (final point in points) point.longitude % 360]
    ..sort();
  var largestGap = -1.0;
  var start = longitudes.first;
  for (var i = 0; i < longitudes.length; i++) {
    final next = i + 1 < longitudes.length
        ? longitudes[i + 1]
        : longitudes.first + 360;
    final gap = next - longitudes[i];
    if (gap > largestGap) {
      largestGap = gap;
      start = next;
    }
  }
  final latitudes = [for (final point in points) point.latitude]..sort();
  return MapCoordinate(
    ((latitudes.first + latitudes.last) / 2).clamp(-80.0, 80.0).toDouble(),
    _longitude(start + (360 - largestGap) / 2),
  );
}

Map<String, dynamic> detailPointFeature(
  MapCoordinate coordinate, {
  required String kind,
  required int index,
  required String label,
}) => {
  'type': 'Feature',
  'properties': {'kind': kind, 'index': index, 'label': label},
  'geometry': {
    'type': 'Point',
    'coordinates': [coordinate.longitude, coordinate.latitude],
  },
};

Map<String, dynamic> detailFeatureCollection(
  List<Map<String, dynamic>> features,
) => {'type': 'FeatureCollection', 'features': features};

double _longitude(double longitude) => (longitude + 180) % 360 - 180;

List<List<double>> _unwrap(List<List<double>> coordinates) {
  double? previous;
  return [
    for (final coordinate in coordinates)
      [
        previous = previous == null
            ? _longitude(coordinate[0])
            : previous + _longitude(coordinate[0] - previous),
        coordinate[1],
      ],
  ];
}

List<double> _unit(double latitude, double longitude) {
  final lat = latitude * math.pi / 180;
  final lng = longitude * math.pi / 180;
  return [
    math.cos(lat) * math.cos(lng),
    math.cos(lat) * math.sin(lng),
    math.sin(lat),
  ];
}

double _dot(List<double> a, List<double> b) =>
    a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
