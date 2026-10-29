import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'map_models.dart';

const emptyDetailFootprint = <String, dynamic>{
  'type': 'FeatureCollection',
  'features': <Map<String, dynamic>>[],
};

/// Retains entire GeoJSON features (including islands and holes), unlike the
/// canvas renderer's flattened polygon list. Nothing is sent to the tile host.
class DetailFootprintBoundaries {
  DetailFootprintBoundaries({
    required Map<String, dynamic> countries,
    required Map<String, dynamic> provinces,
  }) : _countries = _index(countries),
       _provinces = _index(provinces);

  final List<_Region> _countries;
  final List<_Region> _provinces;

  Map<String, dynamic> select(List<MapPlace> places) {
    final visited = places
        .where(
          (p) =>
              p.isVisited &&
              p.latitude.isFinite &&
              p.longitude.isFinite &&
              p.latitude.abs() <= 90 &&
              p.longitude.abs() <= 180,
        )
        .toList();
    final domestic = visited
        .where((p) => p.countryCode?.trim().toUpperCase() == 'CN')
        .toList();
    final overseas = visited
        .where(
          (p) =>
              p.countryCode?.trim().toUpperCase() != 'CN' &&
              // Hong Kong uses the local administrative feature, not a second
              // overlapping world feature with a different coastline.
              !_provinces.any(
                (r) => r.adcode == 810000 && r.matchesProvince(p),
              ),
        )
        .toList();
    return {
      'type': 'FeatureCollection',
      'features': [
        for (final region in _countries)
          // Mainland China uses its province features instead of filling the
          // whole country. The witness also handles unlabelled legacy data.
          if (!region.contains(_chinaWitness) &&
              !domestic.any(region.matchesCountry) &&
              overseas.any(region.matchesCountry))
            region.feature,
        for (final region in _provinces)
          if (visited.any(region.matchesProvince)) region.feature,
      ],
    };
  }

  // Identify the unlabeled mainland country feature even when imported
  // domestic records have no country code. Province selection remains local.
  static const _chinaWitness = MapPlace(
    name: '',
    latitude: 39.9,
    longitude: 116.4,
    countryCode: 'CN',
  );

  static List<_Region> _index(Map<String, dynamic> collection) => [
    for (final raw in collection['features'] as List? ?? const [])
      if (raw is Map && raw['geometry'] is Map)
        _Region(Map<String, dynamic>.from(raw)),
  ];
}

class DetailFootprintResult {
  DetailFootprintResult(this.collection) : encoded = jsonEncode(collection);
  final Map<String, dynamic> collection;
  final String encoded;
}

/// Decode/index once; select and serialize off the UI isolate only when the
/// records change. Panning/zooming never executes point-in-polygon work.
class DetailFootprintLoader {
  static Future<DetailFootprintBoundaries>? _boundaries;

  Future<DetailFootprintResult> load(List<MapPlace> places) async {
    final boundaries = await (_boundaries ??= _loadBoundaries());
    return compute(_select, (
      boundaries,
      places,
    ), debugLabel: 'select detail footprint');
  }

  static Future<DetailFootprintBoundaries> _loadBoundaries() async {
    try {
      final sources = await Future.wait([
        rootBundle.loadString('assets/data/world-countries-50m.geo.json'),
        rootBundle.loadString('assets/data/china-provinces.geo.json'),
      ]);
      return await compute(
        _decode,
        sources,
        debugLabel: 'index detail footprint boundaries',
      );
    } catch (_) {
      _boundaries = null;
      rethrow;
    }
  }

  static DetailFootprintBoundaries _decode(List<String> sources) =>
      DetailFootprintBoundaries(
        countries: jsonDecode(sources[0]) as Map<String, dynamic>,
        provinces: jsonDecode(sources[1]) as Map<String, dynamic>,
      );

  static DetailFootprintResult _select(
    (DetailFootprintBoundaries, List<MapPlace>) query,
  ) => DetailFootprintResult(query.$1.select(query.$2));
}

class _Region {
  _Region(this.feature) {
    final geometry = feature['geometry'] as Map;
    final coordinates = geometry['coordinates'] as List? ?? const [];
    polygons = [
      if (geometry['type'] == 'Polygon') _Polygon(coordinates),
      if (geometry['type'] == 'MultiPolygon')
        for (final polygon in coordinates)
          if (polygon is List) _Polygon(polygon),
    ];
  }

  final Map<String, dynamic> feature;
  late final List<_Polygon> polygons;
  int? get adcode => (feature['properties'] as Map?)?['adcode'] as int?;
  bool contains(MapPlace place) =>
      polygons.any((p) => p.contains(place.longitude, place.latitude));

  bool matchesCountry(MapPlace place) {
    final recordedCode = place.countryCode?.trim().toUpperCase();
    final geometryCode = (feature['properties'] as Map?)?['ISO_A2_EH']
        ?.toString()
        .toUpperCase();
    if (geometryCode == '-99') return false;
    if (recordedCode != null && recordedCode.isNotEmpty) {
      // An explicit but disputed/missing ISO assignment (-99) cannot safely
      // be used to select a country. Older/custom geometry without an ISO
      // attribute retains its previous coordinate-only behavior.
      if (geometryCode != null && geometryCode != recordedCode) return false;
    }
    return contains(place);
  }

  bool matchesProvince(MapPlace place) {
    final code = place.countryCode?.trim().toUpperCase();
    final regionCode = adcode;

    // A coordinate in another country must not light a China administrative
    // feature just because of a bad import or a border overlap. Older records
    // without a country code still use geometry as their only evidence.
    if (regionCode == 810000) {
      if (code != 'HK') return false;
      if (contains(place)) return true;
      // HKG's current airport coordinate is just outside the simplified coast.
      // A trusted HK code may select its own feature near its geographic bounds.
      return polygons.any(
        (p) =>
            p.rings.isNotEmpty &&
            p.rings.first.nearBounds(place.longitude, place.latitude, .02),
      );
    }
    if (regionCode == 820000 && code != null && code != 'MO') return false;
    if (regionCode == 710000 && code != null && code != 'TW') return false;
    if (regionCode != 710000 &&
        regionCode != 810000 &&
        regionCode != 820000 &&
        code != null &&
        code != 'CN') {
      return false;
    }
    return contains(place);
  }
}

class _Polygon {
  _Polygon(List coordinates)
    : rings = [
        for (final ring in coordinates)
          if (ring is List) _Ring(ring),
      ];
  final List<_Ring> rings;
  bool contains(double x, double y) =>
      rings.isNotEmpty &&
      rings.first.contains(x, y) &&
      !rings.skip(1).any((hole) => hole.contains(x, y));
}

class _Ring {
  _Ring(List coordinates) {
    points = [];
    for (final point in coordinates) {
      if (point is! List ||
          point.length < 2 ||
          point[0] is! num ||
          point[1] is! num) {
        continue;
      }
      var x = (point[0] as num).toDouble();
      final y = (point[1] as num).toDouble();
      if (!x.isFinite || !y.isFinite) continue;
      // Keep dateline-crossing islands narrow instead of painting the globe.
      if (points.isNotEmpty) {
        final previous = points.last.$1;
        x = previous + (x - previous + 180) % 360 - 180;
      }
      points.add((x, y));
      minX = math.min(minX, x);
      maxX = math.max(maxX, x);
      minY = math.min(minY, y);
      maxY = math.max(maxY, y);
    }
  }

  late final List<(double, double)> points;
  double minX = double.infinity, maxX = double.negativeInfinity;
  double minY = double.infinity, maxY = double.negativeInfinity;

  bool nearBounds(double x, double y, double padding) {
    if (points.length < 3) return false;
    x += (((minX + maxX) / 2 - x) / 360).round() * 360;
    return x >= minX - padding &&
        x <= maxX + padding &&
        y >= minY - padding &&
        y <= maxY + padding;
  }

  bool contains(double x, double y) {
    if (points.length < 3 || y < minY || y > maxY) return false;
    x += (((minX + maxX) / 2 - x) / 360).round() * 360;
    if (x < minX || x > maxX) return false;
    var inside = false;
    for (var i = 0, j = points.length - 1; i < points.length; j = i++) {
      final a = points[i], b = points[j];
      if ((a.$2 > y) != (b.$2 > y) &&
          x < (b.$1 - a.$1) * (y - a.$2) / (b.$2 - a.$2) + a.$1) {
        inside = !inside;
      }
    }
    return inside;
  }
}
