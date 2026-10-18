import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'detail_map_data.dart';
import 'map_models.dart';

typedef DetailRouteBuilder = List<List<double>> Function(MapRoute route);

/// Visual aggregation only. Original indices still select the original
/// directed route and its complete underlying flight history.
class DetailRouteData {
  DetailRouteData(this.collection, this.byIndex)
    : encoded = jsonEncode(collection);
  final Map<String, dynamic> collection;
  final String encoded;
  final Map<int, Map<String, dynamic>> byIndex;

  Map<String, dynamic> selected(int? index) =>
      detailFeatureCollection([?byIndex[index]]);
}

class DetailRouteCache {
  DetailRouteCache({DetailRouteBuilder? coordinateBuilder})
    : _coordinateBuilder =
          coordinateBuilder ?? detailIllustratedRouteCoordinates;

  final DetailRouteBuilder _coordinateBuilder;
  final _geometry = <String, List<List<double>>>{};
  List<MapRoute>? _source;
  DetailRouteData? _data;
  final _empty = DetailRouteData(detailFeatureCollection([]), {});

  DetailRouteData data(List<MapRoute> routes, {bool enabled = true}) {
    if (!enabled) return _empty;
    if (identical(routes, _source)) return _data!;
    final groups = <String, _RouteGroup>{};
    final directedPairs = <String>{};
    for (var i = 0; i < routes.length; i++) {
      final route = routes[i];
      final from = _endpoint(route.from), to = _endpoint(route.to);
      final pair = jsonEncode([from, to]);
      directedPairs.add(pair);
      // Distinct recorded tracks must not collapse into an inferred arc or
      // each other, even when the airport pair happens to be the same.
      final key = jsonEncode([
        from,
        to,
        [
          if (route.track.length >= 2)
            for (final point in route.track) [point.longitude, point.latitude],
        ],
      ]);
      final group = groups.putIfAbsent(
        key,
        () => _RouteGroup(route, i, key, jsonEncode([to, from])),
      );
      group.count++;
    }
    final features = <Map<String, dynamic>>[];
    final byIndex = <int, Map<String, dynamic>>{};
    for (final group in groups.values) {
      var coordinates = _geometry.remove(group.key);
      coordinates ??= _coordinateBuilder(group.route);
      _geometry[group.key] = coordinates;
      if (_geometry.length > 256) _geometry.remove(_geometry.keys.first);
      final feature = <String, dynamic>{
        'type': 'Feature',
        'properties': {
          'kind': 'route', 'index': group.index, 'count': group.count,
          // Inferred arcs already bow to opposite sides. Only separate
          // overlapping recorded tracks with a display-only pixel offset.
          'offset':
              group.route.track.length >= 2 &&
                  directedPairs.contains(group.reversePair)
              ? 1.3
              : 0.0,
        },
        'geometry': {'type': 'LineString', 'coordinates': coordinates},
      };
      features.add(feature);
      byIndex[group.index] = feature;
    }
    _source = routes;
    return _data = DetailRouteData(detailFeatureCollection(features), byIndex);
  }

  static List<Object> _endpoint(MapAirport airport) => [
    airport.code.trim().toUpperCase(),
    airport.latitude,
    airport.longitude,
  ];
}

class _RouteGroup {
  _RouteGroup(this.route, this.index, this.key, this.reversePair);
  final MapRoute route;
  final int index;
  final String key;
  final String reversePair;
  int count = 0;
}

/// Avoid resending unchanged geometry when location/footprint state changes.
/// Style replacement invalidates every sent value, including selection.
class DetailSourceCache {
  Object? _style;
  final _sent = <String, String>{};
  final _versions = <String, int>{};

  Future<void> update({
    required Object style,
    required String id,
    required String data,
    required Future<void> Function() send,
  }) async {
    if (!identical(style, _style)) {
      _style = style;
      _sent.clear();
      _versions.clear();
    }
    if (_sent[id] == data) return;
    final version = (_versions[id] ?? 0) + 1;
    _versions[id] = version;
    await send();
    if (identical(style, _style) && _versions[id] == version) _sent[id] = data;
  }
}

/// Rank fat-finger hits by distance to the actual offset stroke, so tapping
/// one of the two nearby directions doesn't always choose the last drawn one.
double detailRouteScreenDistance(
  Offset point,
  List<Offset> path, {
  double offset = 0,
  double? worldWidth,
}) {
  var nearest = double.infinity;
  for (var i = 1; i < path.length; i++) {
    var a = path[i - 1], b = path[i];
    if (!a.dx.isFinite || !a.dy.isFinite || !b.dx.isFinite || !b.dy.isFinite) {
      continue;
    }
    if (worldWidth != null && worldWidth.isFinite && worldWidth > 0) {
      b = Offset(
        a.dx + (b.dx - a.dx + worldWidth / 2) % worldWidth - worldWidth / 2,
        b.dy,
      );
      final shift =
          ((point.dx - (a.dx + b.dx) / 2) / worldWidth).round() * worldWidth;
      a += Offset(shift, 0);
      b += Offset(shift, 0);
    }
    var segment = b - a;
    final length = segment.distance;
    if (length < 1e-10) continue;
    final normal = Offset(-segment.dy, segment.dx) * (offset / length);
    a += normal;
    b += normal;
    segment = b - a;
    final fraction =
        ((point - a).dx * segment.dx + (point - a).dy * segment.dy) /
        segment.distanceSquared;
    nearest = math.min(
      nearest,
      (point - (a + segment * fraction.clamp(0.0, 1.0))).distance,
    );
  }
  return nearest;
}
