import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/airport.dart';
import '../../ui/theme/app_theme.dart';
import 'world_exploration.dart';

/// Offline cartographic artwork, sharing one simplified Natural Earth cache.
///
/// The parent supplies the size. A null [continent] shows the complete world;
/// continent silhouettes retain the source coastline rather than icon shapes.
class ExplorationMapArtwork extends StatefulWidget {
  const ExplorationMapArtwork({
    super.key,
    this.continent,
    this.color,
    this.places = const [],
    this.home,
    this.destination,
    this.routeProgress = 1,
    this.showVisitedMarkers = false,
  });

  final TravelContinent? continent;
  final Color? color;
  final List<ExplorationPlace> places;
  final Airport? home;
  final ExplorationPlace? destination;
  final double routeProgress;
  final bool showVisitedMarkers;

  /// Warms the same process-wide geometry cache used by every artwork.
  static Future<void> preload() async {
    await _MapOutlines.load();
  }

  @override
  State<ExplorationMapArtwork> createState() => _ExplorationMapArtworkState();
}

class _ExplorationMapArtworkState extends State<ExplorationMapArtwork> {
  late final Future<_MapOutlines> _outlines = _MapOutlines.load();
  _RouteTrace? _route;
  List<Offset> _markers = const [];

  @override
  void initState() {
    super.initState();
    _updateCoordinates();
  }

  @override
  void didUpdateWidget(covariant ExplorationMapArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.home != widget.home ||
        oldWidget.destination != widget.destination ||
        oldWidget.places != widget.places ||
        oldWidget.showVisitedMarkers != widget.showVisitedMarkers) {
      _updateCoordinates();
    }
  }

  void _updateCoordinates() {
    final home = widget.home;
    final destination = widget.destination;
    _route =
        home != null &&
            destination != null &&
            _validCoordinate(home.longitude, home.latitude) &&
            _validCoordinate(destination.longitude, destination.latitude)
        ? _RouteTrace.between(
            Offset(home.longitude, -home.latitude),
            Offset(destination.longitude, -destination.latitude),
          )
        : null;
    _markers = widget.showVisitedMarkers
        ? widget.places
              .where(
                (place) => _validCoordinate(place.longitude, place.latitude),
              )
              .map((place) => Offset(place.longitude, -place.latitude))
              .toSet()
              .toList(growable: false)
        : const [];
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: FutureBuilder<_MapOutlines>(
          future: _outlines,
          builder: (context, snapshot) {
            final outlines = snapshot.data;
            // Loading and failures stay empty: never substitute invented land
            // or a decorative route that could be read as somebody's travels.
            if (outlines == null) {
              return SizedBox.expand(
                key: ValueKey(
                  snapshot.hasError
                      ? 'exploration-map-unavailable'
                      : 'exploration-map-loading',
                ),
              );
            }
            final outline = outlines.forContinent(widget.continent);
            return CustomPaint(
              key: ValueKey(
                'exploration-map-artwork-${widget.continent?.name ?? 'world'}',
              ),
              painter: _ExplorationMapPainter(
                outline: outline,
                world: widget.continent == null,
                color: widget.color ?? colors.textTertiary,
                markerColor: colors.lime,
                homeColor: colors.purple,
                surfaceColor: colors.surface,
                markers: _markers,
                route: widget.continent == null ? _route : null,
                routeProgress: widget.routeProgress.isFinite
                    ? widget.routeProgress.clamp(0.0, 1.0)
                    : 1,
              ),
              child: const SizedBox.expand(),
            );
          },
        ),
      ),
    );
  }
}

bool _validCoordinate(double longitude, double latitude) =>
    longitude.isFinite &&
    latitude.isFinite &&
    longitude.abs() <= 180 &&
    latitude.abs() <= 90;

class _MapOutline {
  _MapOutline(this.path, {Rect? bounds}) : bounds = bounds ?? path.getBounds();

  final Path path;
  final Rect bounds;
}

class _MapOutlines {
  _MapOutlines(this.world, this.continents);

  static Future<_MapOutlines>? _cache;

  final _MapOutline world;
  final Map<TravelContinent, _MapOutline> continents;

  static Future<_MapOutlines> load() => _cache ??= _load();

  static Future<_MapOutlines> _load() async {
    final source = await rootBundle.loadString(
      'assets/data/world-land-50m.geo.json',
    );
    final rings = await compute(
      _simplifiedLandRings,
      source,
      debugLabel: 'exploration coastline',
    );
    final worldPath = Path()..fillType = PathFillType.evenOdd;
    for (final ring in rings) {
      worldPath.moveTo(ring[0], -ring[1]);
      for (var index = 2; index < ring.length; index += 2) {
        worldPath.lineTo(ring[index], -ring[index + 1]);
      }
      worldPath.close();
    }
    // Repeated copies keep Fiji, eastern Siberia and the Aleutians adjacent
    // to their mainland when fitting an individual continent across ±180°.
    final repeated = Path()
      ..fillType = PathFillType.evenOdd
      ..addPath(worldPath, Offset.zero)
      ..addPath(worldPath, const Offset(-360, 0))
      ..addPath(worldPath, const Offset(360, 0));
    final continents = <TravelContinent, _MapOutline>{};
    for (final entry in _continentWindows.entries) {
      final mask = Path();
      for (var index = 0; index < entry.value.length; index++) {
        final point = entry.value[index];
        if (index == 0) {
          mask.moveTo(point.dx, -point.dy);
        } else {
          mask.lineTo(point.dx, -point.dy);
        }
      }
      mask.close();
      continents[entry.key] = _MapOutline(
        Path.combine(PathOperation.intersect, repeated, mask),
      );
    }
    return _MapOutlines(
      _MapOutline(worldPath, bounds: const Rect.fromLTWH(-180, -90, 360, 180)),
      continents,
    );
  }

  _MapOutline forContinent(TravelContinent? continent) =>
      continent == null ? world : continents[continent]!;
}

// These are geographic partition windows, not substitute coastlines. Every
// visible coast comes from world-land-50m. The Mediterranean, Suez, Urals,
// Panama and Bering Strait divide connected land or adjacent island groups.
const _continentWindows = <TravelContinent, List<Offset>>{
  TravelContinent.europe: [
    Offset(-25, 35.5),
    Offset(-25, 66),
    Offset(-12, 75),
    Offset(-10, 90),
    Offset(60, 90),
    Offset(60, 55),
    Offset(52, 45),
    Offset(40, 42),
    Offset(28, 41),
    Offset(26, 38),
    Offset(25, 34),
    Offset(10, 38),
    Offset(6, 38),
    Offset(-6, 35.95),
  ],
  TravelContinent.asia: [
    Offset(60, 90),
    Offset(191.5, 90),
    Offset(191.5, 60),
    Offset(180, 56),
    Offset(180, 5),
    Offset(153, 5),
    Offset(141, 0),
    Offset(141, -10),
    Offset(130, -10),
    Offset(130, -12),
    Offset(60, -12),
    Offset(43, 12),
    Offset(35, 29),
    Offset(32.3, 31.2),
    Offset(25, 34),
    Offset(26, 38),
    Offset(28, 41),
    Offset(40, 42),
    Offset(52, 45),
    Offset(60, 55),
  ],
  TravelContinent.africa: [
    Offset(-25, 35.5),
    Offset(-6, 35.95),
    Offset(6, 38),
    Offset(10, 38),
    Offset(25, 34),
    Offset(32.3, 31.2),
    Offset(35, 29),
    Offset(43, 12),
    Offset(60, -12),
    Offset(60, -48),
    Offset(-25, -48),
  ],
  TravelContinent.northAmerica: [
    Offset(-168.5, 90),
    Offset(-10, 90),
    Offset(-10, 16),
    Offset(-60, 16),
    Offset(-77.2, 9),
    Offset(-77.4, 7.2),
    Offset(-83, 7.2),
    Offset(-170, 7.2),
    Offset(-195, 50),
    Offset(-195, 56),
    Offset(-180, 56),
    Offset(-168.5, 60),
  ],
  TravelContinent.southAmerica: [
    Offset(-83, 7.2),
    Offset(-77.4, 7.2),
    Offset(-77.2, 9),
    Offset(-60, 16),
    Offset(-25, 16),
    Offset(-25, -60),
    Offset(-83, -60),
  ],
  TravelContinent.oceania: [
    Offset(110, -12),
    Offset(130, -12),
    Offset(130, -10),
    Offset(141, -10),
    Offset(141, 0),
    Offset(153, 5),
    Offset(220, 5),
    Offset(220, -55),
    Offset(110, -55),
  ],
  TravelContinent.antarctica: [
    Offset(-180, -60),
    Offset(180, -60),
    Offset(180, -90),
    Offset(-180, -90),
  ],
};

/// Decode and simplify once off the UI isolate. The original 60k vertices
/// become a lightweight path; paint never walks that source coordinate graph.
List<Float64List> _simplifiedLandRings(String source) {
  final document = jsonDecode(source) as Map<String, dynamic>;
  final result = <Float64List>[];
  for (final feature in document['features'] as List<dynamic>) {
    final geometry = (feature as Map<String, dynamic>)['geometry'] as Map;
    final coordinates = geometry['coordinates'] as List;
    final polygons = geometry['type'] == 'Polygon'
        ? [coordinates]
        : coordinates;
    for (final polygon in polygons) {
      for (final rawRing in polygon as List) {
        final points = <Offset>[
          for (final point in rawRing as List)
            Offset((point[0] as num).toDouble(), (point[1] as num).toDouble()),
        ];
        if (points.length < 4) continue;
        final middle = points.length ~/ 2;
        final simplified = [
          ..._simplifyLine(points.sublist(0, middle + 1)),
          ..._simplifyLine(points.sublist(middle)).skip(1),
        ];
        final kept = simplified.length >= 4 ? simplified : points;
        result.add(
          Float64List.fromList([
            for (final point in kept) ...[point.dx, point.dy],
          ]),
        );
      }
    }
  }
  return result;
}

List<Offset> _simplifyLine(List<Offset> points) {
  if (points.length <= 2) return points;
  const toleranceSquared = .13 * .13;
  final kept = <int>{0, points.length - 1};
  final pending = <(int, int)>[(0, points.length - 1)];
  while (pending.isNotEmpty) {
    final (start, end) = pending.removeLast();
    final a = points[start];
    final delta = points[end] - a;
    final lengthSquared = delta.distanceSquared;
    var farthest = -1;
    var greatestDistance = toleranceSquared;
    for (var index = start + 1; index < end; index++) {
      final point = points[index];
      final t = lengthSquared == 0
          ? 0.0
          : (((point.dx - a.dx) * delta.dx + (point.dy - a.dy) * delta.dy) /
                    lengthSquared)
                .clamp(0.0, 1.0);
      final distance = (point - (a + delta * t)).distanceSquared;
      if (distance > greatestDistance) {
        greatestDistance = distance;
        farthest = index;
      }
    }
    if (farthest != -1) {
      kept.add(farthest);
      pending.add((start, farthest));
      pending.add((farthest, end));
    }
  }
  final indices = kept.toList()..sort();
  return [for (final index in indices) points[index]];
}

class _RouteTrace {
  _RouteTrace(this.home, this.destination, this.metrics)
    : length = metrics.fold(0, (total, metric) => total + metric.length);

  final Offset home;
  final Offset destination;
  final List<ui.PathMetric> metrics;
  final double length;

  factory _RouteTrace.between(Offset home, Offset destination) {
    final path = Path()..moveTo(home.dx, home.dy);
    var previous = home;
    for (var step = 1; step <= 96; step++) {
      final point = _greatCirclePoint(home, destination, step / 96);
      final delta = point.dx - previous.dx;
      if (delta.abs() > 180) {
        final unwrapped = point.dx + (delta > 0 ? -360 : 360);
        final edge = previous.dx > 0 ? 180.0 : -180.0;
        final t = (edge - previous.dx) / (unwrapped - previous.dx);
        final y = previous.dy + (point.dy - previous.dy) * t;
        path.lineTo(edge, y);
        path.moveTo(-edge, y);
      }
      path.lineTo(point.dx, point.dy);
      previous = point;
    }
    return _RouteTrace(home, destination, path.computeMetrics().toList());
  }
}

Offset _greatCirclePoint(Offset from, Offset to, double t) {
  if (t == 1) return to;
  List<double> vector(Offset coordinate) {
    final longitude = coordinate.dx * math.pi / 180;
    final latitude = -coordinate.dy * math.pi / 180;
    return [
      math.cos(latitude) * math.cos(longitude),
      math.cos(latitude) * math.sin(longitude),
      math.sin(latitude),
    ];
  }

  final a = vector(from);
  final b = vector(to);
  final dot = (a[0] * b[0] + a[1] * b[1] + a[2] * b[2]).clamp(-1.0, 1.0);
  final angle = math.acos(dot);
  final sine = math.sin(angle);
  late List<double> point;
  if (dot > .999999) {
    point = [for (var i = 0; i < 3; i++) a[i] * (1 - t) + b[i] * t];
  } else if (sine.abs() < .000001) {
    // Antipodes have no unique shortest arc. Select a stable orthogonal plane.
    final tangent = a[2].abs() < .9 ? [-a[1], a[0], 0.0] : [0.0, -a[2], a[1]];
    final norm = math.sqrt(
      tangent.fold(0.0, (sum, value) => sum + value * value),
    );
    point = [
      for (var i = 0; i < 3; i++)
        a[i] * math.cos(math.pi * t) +
            tangent[i] / norm * math.sin(math.pi * t),
    ];
  } else {
    final startWeight = math.sin((1 - t) * angle) / sine;
    final endWeight = math.sin(t * angle) / sine;
    point = [for (var i = 0; i < 3; i++) a[i] * startWeight + b[i] * endWeight];
  }
  return Offset(
    math.atan2(point[1], point[0]) * 180 / math.pi,
    -math.atan2(
          point[2],
          math.sqrt(point[0] * point[0] + point[1] * point[1]),
        ) *
        180 /
        math.pi,
  );
}

class _ExplorationMapPainter extends CustomPainter {
  _ExplorationMapPainter({
    required this.outline,
    required this.world,
    required this.color,
    required this.markerColor,
    required this.homeColor,
    required this.surfaceColor,
    required this.markers,
    required this.route,
    required this.routeProgress,
  });

  final _MapOutline outline;
  final bool world;
  final Color color;
  final Color markerColor;
  final Color homeColor;
  final Color surfaceColor;
  final List<Offset> markers;
  final _RouteTrace? route;
  final double routeProgress;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || outline.bounds.isEmpty) return;
    final inset = world ? 7.0 : 3.0;
    final available = Size(
      math.max(0, size.width - inset * 2),
      math.max(0, size.height - inset * 2),
    );
    final scale = math.min(
      available.width / outline.bounds.width,
      available.height / outline.bounds.height,
    );
    if (scale <= 0) return;
    final translation = Offset(
      size.width / 2 - outline.bounds.center.dx * scale,
      size.height / 2 - outline.bounds.center.dy * scale,
    );
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(translation.dx, translation.dy);
    canvas.scale(scale);
    canvas.drawPath(outline.path, Paint()..color = color);
    final trace = route;
    if (trace != null && routeProgress > 0) {
      var remaining = trace.length * routeProgress;
      final paint = Paint()
        ..color = homeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.65 / scale
        ..strokeCap = StrokeCap.round;
      for (final metric in trace.metrics) {
        if (remaining <= 0) break;
        canvas.drawPath(
          metric.extractPath(0, math.min(remaining, metric.length)),
          paint,
        );
        remaining -= metric.length;
      }
    }
    canvas.restore();

    Offset project(Offset point) {
      var longitude = point.dx;
      if (!world) {
        while (longitude - outline.bounds.center.dx > 180) {
          longitude -= 360;
        }
        while (longitude - outline.bounds.center.dx < -180) {
          longitude += 360;
        }
      }
      return Offset(longitude, point.dy) * scale + translation;
    }

    final markerPaint = Paint()..color = markerColor.withValues(alpha: .85);
    for (final marker in markers) {
      final position = project(marker);
      if ((Offset.zero & size).contains(position)) {
        canvas.drawCircle(position, 1.8, markerPaint);
      }
    }
    if (trace != null) {
      for (final endpoint in [
        (trace.home, homeColor),
        (trace.destination, markerColor),
      ]) {
        final position = project(endpoint.$1);
        canvas.drawCircle(position, 4.2, Paint()..color = surfaceColor);
        canvas.drawCircle(position, 2.7, Paint()..color = endpoint.$2);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ExplorationMapPainter oldDelegate) =>
      oldDelegate.outline != outline ||
      oldDelegate.color != color ||
      oldDelegate.markerColor != markerColor ||
      oldDelegate.homeColor != homeColor ||
      oldDelegate.surfaceColor != surfaceColor ||
      oldDelegate.markers != markers ||
      oldDelegate.route != route ||
      oldDelegate.routeProgress != routeProgress;
}
