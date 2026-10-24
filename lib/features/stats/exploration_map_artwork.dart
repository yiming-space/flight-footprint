import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/airport.dart';
import '../../ui/theme/app_theme.dart';
import 'world_exploration.dart';

/// Offline cartographic artwork, sharing one pre-clipped Natural Earth cache.
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
      'assets/data/exploration-outlines.json',
    );
    final outlines = await compute(
      _decodeOutlineRings,
      source,
      debugLabel: 'exploration outlines',
    );
    Path pathFor(String name) {
      final path = Path()..fillType = PathFillType.evenOdd;
      for (final ring in outlines[name]!) {
        path.moveTo(ring[0], -ring[1]);
        for (var index = 2; index < ring.length; index += 2) {
          path.lineTo(ring[index], -ring[index + 1]);
        }
        path.close();
      }
      return path;
    }

    return _MapOutlines(
      _MapOutline(
        pathFor('world'),
        bounds: const Rect.fromLTWH(-180, -90, 360, 180),
      ),
      {
        for (final continent in TravelContinent.values)
          continent: _MapOutline(pathFor(continent.name)),
      },
    );
  }

  _MapOutline forContinent(TravelContinent? continent) =>
      continent == null ? world : continents[continent]!;
}

/// Decode the small, pre-clipped asset off the UI isolate. Coastline
/// simplification and polygon intersections belong to the build-time generator.
Map<String, List<Float64List>> _decodeOutlineRings(String source) {
  final document = jsonDecode(source) as Map<String, dynamic>;
  if (document['version'] != 1) {
    throw const FormatException('Unsupported exploration outline version');
  }
  final outlines = document['outlines'] as Map<String, dynamic>;
  return {
    for (final entry in outlines.entries)
      entry.key: [
        for (final ring in entry.value as List)
          Float64List.fromList([
            for (final value in ring as List) (value as num).toDouble(),
          ]),
      ],
  };
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
