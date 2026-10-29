import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

GeoJsonMapData _decodeGeoJson(String source) {
  final decoded = jsonDecode(source);
  if (decoded is! Map<String, dynamic> ||
      decoded['type'] != 'FeatureCollection') {
    throw const FormatException('GeoJSON must be a FeatureCollection');
  }
  return GeoJsonMapData.fromJson(decoded);
}

class MapPolygon {
  const MapPolygon(this.rings, {this.properties = const {}});
  final List<List<List<double>>> rings;
  final Map<String, dynamic> properties;

  String? get countryCode => properties['ISO_A2_EH']?.toString().toUpperCase();

  bool matchesChinaAdministrativeRegion(String? countryCode) {
    final code = countryCode?.trim().toUpperCase();
    if (code == null || code.isEmpty) return true;
    return switch (properties['adcode']?.toString()) {
      '710000' => code == 'TW',
      '810000' => code == 'HK',
      '820000' => code == 'MO',
      _ => code == 'CN',
    };
  }

  /// Tests a WGS84 point against this polygon, including polygons crossing
  /// the antimeridian. GeoJSON rings after the first are treated as holes.
  bool containsPoint(double longitude, double latitude) =>
      longitude.isFinite &&
      latitude.isFinite &&
      longitude >= -180 &&
      longitude <= 180 &&
      latitude >= -90 &&
      latitude <= 90 &&
      rings.isNotEmpty &&
      _containsRing(rings.first, longitude, latitude) &&
      !rings.skip(1).any((ring) => _containsRing(ring, longitude, latitude));

  static bool _containsRing(
    List<List<double>> ring,
    double longitude,
    double latitude,
  ) {
    if (ring.length < 3) return false;
    final points = <(double, double)>[];
    var minX = double.infinity;
    var maxX = double.negativeInfinity;
    var minY = double.infinity;
    var maxY = double.negativeInfinity;
    for (final point in ring) {
      if (point.length < 2 || !point[0].isFinite || !point[1].isFinite) {
        continue;
      }
      var x = point[0];
      if (points.isNotEmpty) {
        final previous = points.last.$1;
        x = previous + (x - previous + 180) % 360 - 180;
      }
      final y = point[1];
      points.add((x, y));
      minX = x < minX ? x : minX;
      maxX = x > maxX ? x : maxX;
      minY = y < minY ? y : minY;
      maxY = y > maxY ? y : maxY;
    }
    if (points.length < 3 || latitude < minY || latitude > maxY) return false;
    final x = longitude + (((minX + maxX) / 2 - longitude) / 360).round() * 360;
    if (x < minX || x > maxX) return false;
    var inside = false;
    for (var i = 0, j = points.length - 1; i < points.length; j = i++) {
      final a = points[i], b = points[j];
      if ((a.$2 > latitude) != (b.$2 > latitude) &&
          x < (b.$1 - a.$1) * (latitude - a.$2) / (b.$2 - a.$2) + a.$1) {
        inside = !inside;
      }
    }
    return inside;
  }
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
      final properties = feature is Map && feature['properties'] is Map
          ? Map<String, dynamic>.from(feature['properties'] as Map)
          : const <String, dynamic>{};
      final type = geometry['type'];
      final coordinates = geometry['coordinates'];
      if (type == 'Polygon') {
        final rings = _rings(coordinates);
        if (rings.isNotEmpty) {
          polygons.add(MapPolygon(rings, properties: properties));
        }
      } else if (type == 'MultiPolygon') {
        for (final polygon in (coordinates as List? ?? const [])) {
          final rings = _rings(polygon);
          if (rings.isNotEmpty) {
            polygons.add(MapPolygon(rings, properties: properties));
          }
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
    // The complete bundle is several megabytes. Parse and materialize its
    // coordinate graph away from the UI isolate so opening the map cannot
    // steal frames from the page transition or the first gesture.
    return compute(_decodeGeoJson, source, debugLabel: 'decode $assetPath');
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
