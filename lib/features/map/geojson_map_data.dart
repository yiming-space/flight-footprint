import 'dart:convert';

import 'package:flutter/services.dart';

class MapPolygon {
  const MapPolygon(this.rings);
  final List<List<List<double>>> rings;
}

class MapLine {
  const MapLine(this.points);
  final List<List<double>> points;
}

class GeoJsonMapData {
  const GeoJsonMapData({required this.polygons, this.lines = const []});
  final List<MapPolygon> polygons;
  final List<MapLine> lines;

  factory GeoJsonMapData.fromJson(Map<String, dynamic> json) {
    final polygons = <MapPolygon>[];
    final lines = <MapLine>[];
    for (final feature in (json['features'] as List? ?? const [])) {
      final geometry = feature is Map ? feature['geometry'] : null;
      if (geometry is! Map) continue;
      final type = geometry['type'];
      final coordinates = geometry['coordinates'];
      if (type == 'Polygon') {
        final rings = _rings(coordinates);
        if (rings.isNotEmpty) polygons.add(MapPolygon(rings));
      } else if (type == 'MultiPolygon') {
        for (final polygon in (coordinates as List? ?? const [])) {
          final rings = _rings(polygon);
          if (rings.isNotEmpty) polygons.add(MapPolygon(rings));
        }
      } else if (type == 'LineString') {
        final line = _line(coordinates);
        if (line.length >= 2) lines.add(MapLine(line));
      } else if (type == 'MultiLineString') {
        for (final value in (coordinates as List? ?? const [])) {
          final line = _line(value);
          if (line.length >= 2) lines.add(MapLine(line));
        }
      }
    }
    return GeoJsonMapData(
      polygons: List.unmodifiable(polygons),
      lines: List.unmodifiable(lines),
    );
  }

  static List<List<List<double>>> _rings(dynamic value) => [
    for (final ring in (value as List? ?? const []))
      [
        for (final point in (ring as List? ?? const []))
          if (point is List && point.length >= 2)
            [
              double.tryParse('${point[0]}') ?? 0,
              double.tryParse('${point[1]}') ?? 0,
            ],
      ],
  ].where((ring) => ring.length >= 3).toList();

  static List<List<double>> _line(dynamic value) => [
    for (final point in (value as List? ?? const []))
      if (point is List && point.length >= 2)
        [
          double.tryParse('${point[0]}') ?? 0,
          double.tryParse('${point[1]}') ?? 0,
        ],
  ];
}

class GeoJsonMapBundle {
  const GeoJsonMapBundle({
    required this.land,
    required this.countries,
    required this.provinces,
    required this.nationalBoundary,
    required this.internalBoundaries,
    required this.maritimeMarks,
  });

  final GeoJsonMapData land;
  final GeoJsonMapData countries;
  final GeoJsonMapData provinces;
  final GeoJsonMapData nationalBoundary;
  final GeoJsonMapData internalBoundaries;
  final GeoJsonMapData maritimeMarks;
}

class GeoJsonMapLoader {
  const GeoJsonMapLoader();

  // The home map and the fullscreen map use the same bundled world data.
  // Reusing the in-flight/completed future prevents a second JSON decode from
  // landing on the exact frames in which the fullscreen transition starts.
  static Future<GeoJsonMapBundle>? _bundleCache;

  Future<GeoJsonMapData> load(String assetPath) async {
    final source = await rootBundle.loadString(assetPath);
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic> ||
        decoded['type'] != 'FeatureCollection') {
      throw const FormatException('GeoJSON must be a FeatureCollection');
    }
    return GeoJsonMapData.fromJson(decoded);
  }

  Future<GeoJsonMapBundle> loadBundle() {
    return _bundleCache ??= _loadBundle();
  }

  Future<GeoJsonMapBundle> _loadBundle() async {
    final entries = await Future.wait([
      load('assets/data/world-land-50m.geo.json'),
      load('assets/data/world-countries-50m.geo.json'),
      load('assets/data/china-provinces.geo.json'),
      load('assets/data/china-national-boundary.geo.json'),
      load('assets/data/china-internal-boundaries.geo.json'),
      load('assets/data/china-maritime-marks.geo.json'),
    ]);
    return GeoJsonMapBundle(
      land: entries[0],
      countries: entries[1],
      provinces: entries[2],
      nationalBoundary: entries[3],
      internalBoundaries: entries[4],
      maritimeMarks: entries[5],
    );
  }
}
