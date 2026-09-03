import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'geojson_map_data.dart';
import 'map_projection.dart';
import 'map_models.dart';
import '../../ui/theme/app_theme.dart';

/// Paints the app's deliberately flat map language in either the dark or light
/// product palette.
///
/// The painter stays offline and dependency-free, while keeping the web
/// projection and great-circle route math in one place. The map is therefore
/// deterministic on a phone and remains useful when the device is offline.
class FlatMapPainter extends CustomPainter {
  static final Expando<_ProjectedGeometryCache> _geometryCaches = Expando();

  FlatMapPainter({
    required this.data,
    this.airports = const [],
    this.routes = const [],
    this.places = const [],
    this.mode = MapMode.flight,
    this.showLabels = false,
    this.showGrid = true,
    this.minimalWorldStyle = false,
    this.transparentBackground = false,
    this.bottomFade = false,
    this.excludePolarShelf = false,
    this.routeRevealProgress = 1,
    this.showPassportTexture = false,
    this.compactWorldViewport = false,
    this.visualScale = 1,
    this.horizontalPadding = 16,
    this.verticalPadding = 14,
    this.horizontalWrap = false,
    this.lightPalette = false,
  });

  final GeoJsonMapBundle data;
  final List<MapAirport> airports;
  final List<MapRoute> routes;
  final List<MapPlace> places;
  final MapMode mode;
  final bool showLabels;
  final bool showGrid;
  final bool minimalWorldStyle;

  /// Keeps the surrounding composition visible through the map canvas. This
  /// is useful for the passport card, whose map is translated independently
  /// from its bottom gradient.
  final bool transparentBackground;

  /// Fades only the Antarctic landform into the transparent composition
  /// surface. Routes and the rest of the world keep their original contrast.
  final bool bottomFade;

  /// Hides Antarctica's country-outline layer in compact passport artwork.
  /// The base land fill remains visible; only the clipped outline that can
  /// read as a straight line below Antarctica is omitted.
  final bool excludePolarShelf;

  /// Reveals flight paths progressively from departure to arrival. The
  /// default keeps dashboard maps static; passport cards drive this value
  /// during a year change.
  final double routeRevealProgress;

  /// Paints a restrained engraved texture for the passport artwork. The
  /// texture is drawn before routes and markers so those remain crisp.
  final bool showPassportTexture;

  /// Crops only the unused polar latitude band for the passport composition.
  /// Longitude remains fully visible, and the geographic projection itself is
  /// unchanged, so no continent is stretched or cut at the map edges.
  final bool compactWorldViewport;

  /// The scene scale applied by [InteractiveViewer]. Geometry should zoom,
  /// while visual marks stay approximately the same size on the screen.
  final double visualScale;

  /// Insets used when fitting the projected world into the map viewport. A
  /// share-card map can opt into edge-to-edge fitting while dashboard maps
  /// retain a small breathing room around the complete world.
  final double horizontalPadding;
  final double verticalPadding;

  /// Repeats the world horizontally so a full-screen map can be panned across
  /// the date line without exposing an empty gutter. Embedded maps keep a
  /// single world copy and split routes at the same seam instead.
  final bool horizontalWrap;

  /// Dashboard maps inherit the app theme. Passport artwork explicitly keeps
  /// this false so its shareable card remains an independent dark composition.
  final bool lightPalette;

  static const _darkRouteColors = <Color>[
    Color(0xffc6ff32),
    Color(0xffa58aff),
    Color(0xff75dce9),
    Color(0xfff6e68a),
    Color(0xffff8b7a),
  ];
  static const _lightRouteColors = <Color>[
    Color(0xff78b82f),
    Color(0xff7e65c7),
    Color(0xff2a9cab),
    Color(0xffc49e2a),
    Color(0xffd86479),
  ];
  static const _darkLandColors = <Color>[
    Color(0xff1b222b),
    Color(0xff202832),
    Color(0xff182028),
    Color(0xff242d37),
    Color(0xff1e2730),
  ];
  static const _lightLandColors = <Color>[
    Color(0xffd5e0e4),
    Color(0xffdee7ea),
    Color(0xffd0dde2),
    Color(0xffe4ebee),
    Color(0xffd9e4e7),
  ];
  // A muted lavender keeps visited regions visible without competing with
  // the flight-map markers and lime route accents.
  static const _darkFootprintFill = Color(0xff75688f);
  static const _lightFootprintFill = Color(0xffc0cdee);

  List<Color> get _routeColors =>
      lightPalette ? _lightRouteColors : _darkRouteColors;

  List<Color> get _landColors =>
      lightPalette ? _lightLandColors : _darkLandColors;

  Color get _mapBackground =>
      lightPalette ? const Color(0xfff0f3f4) : const Color(0xff0b1015);

  Color get _maritimeFill =>
      lightPalette ? const Color(0xffe4ebee) : const Color(0xff222b35);

  Color get _maritimeStroke =>
      lightPalette ? const Color(0xffc7d3d9) : const Color(0xff334250);

  Color get _countryBoundary =>
      lightPalette ? const Color(0xffa8b7c0) : const Color(0xff3a4757);

  Color get _nationalBoundary =>
      lightPalette ? const Color(0xff8496a0) : const Color(0xff66788b);

  Color get _internalBoundary =>
      lightPalette ? const Color(0xffc3d0d6) : const Color(0xff344454);

  Color get _gridColor =>
      lightPalette ? const Color(0xffd6e0e4) : const Color(0xff5a6977);

  Color get _footprintFill =>
      lightPalette ? _lightFootprintFill : _darkFootprintFill;

  Color get _markerOutline =>
      lightPalette ? const Color(0xfff7fafc) : const Color(0xff0b1015);

  double get _scale => visualScale.clamp(1.0, 30.0).toDouble();

  double _screen(double value) => value / _scale;

  /// Projects every map layer through the same Miller cylindrical projection.
  /// Keeping this as the painter's single entry point prevents routes,
  /// markers, labels, and GeoJSON geometry from drifting apart.
  Offset project(double latitude, double longitude, Size size) {
    final minLatitude = compactWorldViewport
        ? MillerCylindricalProjection.passportMinLatitude
        : -90.0;
    final maxLatitude = compactWorldViewport
        ? MillerCylindricalProjection.passportMaxLatitude
        : 90.0;
    return MillerCylindricalProjection.toOffset(
      latitude,
      longitude,
      size,
      horizontalPadding: horizontalPadding,
      verticalPadding: verticalPadding,
      minLatitude: minLatitude,
      maxLatitude: maxLatitude,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    // The passport card supplies its own dark surface. Leave the compact map
    // canvas untouched so only the world silhouette, routes, and markers
    // appear; dashboard maps retain their themed opaque map panel.
    if (!minimalWorldStyle && !transparentBackground) {
      canvas.drawColor(_mapBackground, BlendMode.src);
    }
    if (horizontalWrap) {
      final worldWidth = _worldPixelWidth(size);
      // Three copies are sufficient for the full-screen viewport in both
      // orientations. The center copy remains the reference world; its
      // neighbours provide the seamless date-line continuation.
      for (final copy in const <int>[-1, 0, 1]) {
        canvas.save();
        canvas.translate(copy * worldWidth, 0);
        _paintWorld(canvas, size);
        canvas.restore();
      }
      return;
    }
    _paintWorld(canvas, size);
  }

  double _worldPixelWidth(Size size) =>
      MillerCylindricalProjection.worldPixelWidthForSize(
        size,
        horizontalPadding: horizontalPadding,
        verticalPadding: verticalPadding,
        minLatitude: compactWorldViewport
            ? MillerCylindricalProjection.passportMinLatitude
            : -90.0,
        maxLatitude: compactWorldViewport
            ? MillerCylindricalProjection.passportMaxLatitude
            : 90.0,
      );

  void _paintWorld(Canvas canvas, Size size) {
    if (showGrid && !minimalWorldStyle) _drawGrid(canvas, size);
    if (minimalWorldStyle) {
      _drawMinimalWorld(canvas, size);
      if (showPassportTexture) _drawPassportTexture(canvas, size);
    } else {
      _drawPolygons(
        canvas,
        size,
        data.land.polygons,
        _landFill,
        null,
        fadeAntarctic: bottomFade,
      );
    }

    if (!minimalWorldStyle && mode == MapMode.travelFootprint) {
      _drawFootprintPolygons(
        canvas,
        size,
        data.countries.polygons,
        skipChinaCountry: true,
      );
      _drawFootprintPolygons(
        canvas,
        size,
        data.provinces.polygons,
        china: true,
      );
    }

    if (!minimalWorldStyle) {
      _drawPolygons(
        canvas,
        size,
        data.maritimeMarks.polygons,
        (_) => _maritimeFill,
        _maritimeStroke,
      );
      _drawPolygonOutlines(
        canvas,
        size,
        data.countries.polygons,
        _countryBoundary,
        .65,
        skipPolarShelf: excludePolarShelf,
      );
      _drawPolygonOutlines(
        canvas,
        size,
        data.nationalBoundary.polygons,
        _nationalBoundary,
        1.05,
      );
      _drawLines(
        canvas,
        size,
        data.countries.lines,
        _countryBoundary,
        .65,
        skipPolarShelf: excludePolarShelf,
      );
      _drawLines(
        canvas,
        size,
        data.nationalBoundary.lines,
        _nationalBoundary,
        1.05,
      );
      _drawLines(
        canvas,
        size,
        data.internalBoundaries.lines,
        _internalBoundary,
        .55,
      );
    }

    if (mode == MapMode.flight) {
      for (var index = 0; index < routes.length; index++) {
        final route = routes[index];
        final reverseIndex = routes.indexWhere(
          (other) =>
              other.from.code == route.to.code &&
              other.to.code == route.from.code &&
              !identical(other, route),
        );
        final offset = reverseIndex >= 0
            ? (index < reverseIndex ? -2.4 : 2.4)
            : 0.0;
        _drawRoute(
          canvas,
          size,
          route,
          index,
          offset: _screen(offset),
          routeProgress: _routeProgressForIndex(index, routes.length),
        );
      }
      _drawAirports(canvas, size);
    } else {
      _drawPlaces(canvas, size);
    }
  }

  double _routeProgressForIndex(int index, int count) {
    final progress = routeRevealProgress.clamp(0.0, 1.0).toDouble();
    if (count < 2) return progress;
    // A small stagger gives the network a readable rhythm without making a
    // dense year feel slow. The paths still overlap heavily and settle with
    // the camera in one continuous transition.
    final start = index / (count - 1) * .24;
    return ((progress - start) / .78).clamp(0.0, 1.0).toDouble();
  }

  _ProjectedGeometry _geometryFor(Size size) {
    final cache = _geometryCaches[data] ??= _ProjectedGeometryCache();
    return cache.forSize(this, size);
  }

  List<Path> _polygonPaths(List<MapPolygon> polygons, Size size) {
    final geometry = _geometryFor(size);
    if (identical(polygons, data.land.polygons)) return geometry.land;
    if (identical(polygons, data.countries.polygons)) {
      return geometry.countries;
    }
    if (identical(polygons, data.provinces.polygons)) {
      return geometry.provinces;
    }
    if (identical(polygons, data.nationalBoundary.polygons)) {
      return geometry.nationalBoundary;
    }
    if (identical(polygons, data.maritimeMarks.polygons)) {
      return geometry.maritimeMarks;
    }
    return [for (final polygon in polygons) _pathForPolygon(polygon, size)];
  }

  List<Path> _linePaths(List<MapLine> lines, Size size) {
    final geometry = _geometryFor(size);
    if (identical(lines, data.internalBoundaries.lines)) {
      return geometry.internalBoundaries;
    }
    if (identical(lines, data.maritimeMarks.lines)) {
      return geometry.maritimeLines;
    }
    return [for (final line in lines) _pathForLine(line, size)];
  }

  Color _landFill(int index) => _landColors[index % _landColors.length];

  void _drawMinimalWorld(Canvas canvas, Size size) {
    final paths = _polygonPaths(data.land.polygons, size);
    final paint = Paint()
      ..color = lightPalette
          ? const Color(0xffcbd5dc)
          : const Color(0xff303a45);
    for (var index = 0; index < paths.length; index++) {
      canvas.drawPath(paths[index], paint);
    }
  }

  void _drawPassportTexture(Canvas canvas, Size size) {
    final ringPaint = Paint()
      ..color = const Color(0xffcfc4ef).withValues(alpha: .13)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..isAntiAlias = true;

    // A single dense concentric-circle texture is clipped to the complete
    // land silhouette. This follows the supplied material reference instead
    // of repeating small circular motifs across the continents.
    final paths = _polygonPaths(data.land.polygons, size);
    final land = Path();
    for (var index = 0; index < paths.length; index++) {
      land.addPath(paths[index], Offset.zero);
    }
    canvas.save();
    canvas.clipPath(land);
    // Keep the origin just beyond the northern edge. The visible continents
    // therefore receive only expanding arcs, never the texture's focal dot.
    final center = Offset(size.width * .5, -size.height * .18);
    final maxRadius = math.sqrt(
      math.pow(size.width, 2) + math.pow(size.height, 2),
    );
    // The supplied reference is a very dense engraving. Increase the current
    // density by roughly another 0.5x while keeping one lightweight layer.
    const ringSpacing = 2.35;
    for (var radius = 2.0; radius <= maxRadius; radius += ringSpacing) {
      canvas.drawCircle(center, radius, ringPaint);
    }
    canvas.restore();
  }

  bool _isAntarctica(MapPolygon polygon) {
    final points = [
      for (final ring in polygon.rings)
        for (final point in ring)
          if (point.length > 1) point[1],
    ];
    if (points.isEmpty) return false;
    final maxLatitude = points.reduce(math.max);
    final minLatitude = points.reduce(math.min);
    // The Natural Earth land layer contains Antarctica as a detached polygon
    // below roughly 60°S. Keep southern islands separate from the Antarctic
    // mainland when deciding whether its outline should be suppressed.
    return maxLatitude < -58 && minLatitude < -60;
  }

  void _drawGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _gridColor.withValues(alpha: lightPalette ? .22 : .15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = _screen(.55);
    // Keep the graticule sampled through the projection entry point. This
    // makes the grid safe to reuse if the map projection changes again.
    for (final longitude in const [-120, -60, 0, 60, 120]) {
      _drawProjectedGridLine(canvas, [
        for (var latitude = -90.0; latitude <= 90.0; latitude += 5)
          project(latitude, longitude.toDouble(), size),
      ], paint);
    }
    for (final latitude in const [-60, -30, 0, 30, 60]) {
      _drawProjectedGridLine(canvas, [
        for (var longitude = -180.0; longitude <= 180.0; longitude += 5)
          project(latitude.toDouble(), longitude, size),
      ], paint);
    }
  }

  void _drawProjectedGridLine(Canvas canvas, List<Offset> points, Paint paint) {
    for (var index = 1; index < points.length; index++) {
      _drawDashedLine(canvas, points[index - 1], points[index], paint);
    }
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
    final delta = end - start;
    final length = delta.distance;
    if (length == 0) return;
    final direction = delta / length;
    final dash = _screen(4);
    final gap = _screen(5);
    for (var distance = 0.0; distance < length; distance += dash + gap) {
      final from = start + direction * distance;
      final to = start + direction * math.min(distance + dash, length);
      canvas.drawLine(from, to, paint);
    }
  }

  void _drawPolygons(
    Canvas canvas,
    Size size,
    List<MapPolygon> polygons,
    Color Function(int index) fill,
    Color? stroke, {
    bool fadeAntarctic = false,
  }) {
    final strokePaint = stroke == null
        ? null
        : (Paint()
            ..color = stroke
            ..style = PaintingStyle.stroke
            ..strokeWidth = _screen(.55));
    final paths = _polygonPaths(polygons, size);
    for (var index = 0; index < paths.length; index++) {
      final path = paths[index];
      final color = fill(index);
      final paint = fadeAntarctic && _isAntarctica(polygons[index])
          ? _antarcticFadePaint(path.getBounds(), color, size.height)
          : (Paint()..color = color);
      canvas.drawPath(path, paint);
      if (strokePaint != null) canvas.drawPath(path, strokePaint);
    }
  }

  Paint _antarcticFadePaint(
    Rect bounds,
    Color landColor,
    double viewportBottom,
  ) {
    // The source Antarctica polygon reaches the geographic South Pole, which
    // can sit below the compact passport canvas. Use the visible canvas edge
    // as the fade's end so the rendered strip dissolves before it is clipped.
    final fadeBottom = math.min(bounds.bottom, viewportBottom);
    final visibleHeight = math.max(1.0, fadeBottom - bounds.top);
    // Start the shader slightly above the coastline. The polygon still keeps
    // its fill, but its first visible pixels enter the composition already
    // softened instead of creating a second, hard horizontal card edge.
    final fadeTop = math.max(0.0, bounds.top - visibleHeight * .18);
    final fadeBounds = Rect.fromLTRB(
      bounds.left,
      fadeTop,
      bounds.right,
      math.max(bounds.top + 1, fadeBottom),
    );
    final surfaceColor = _mapBackground;
    // Antarctica is part of the map, not another visual panel. Keeping a
    // quieter version of the land tone at the coastline lets the lower edge
    // become genuinely transparent and hand off to the card's fixed fade.
    final polarLandColor = Color.lerp(surfaceColor, landColor, .42)!;
    final shader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        polarLandColor,
        polarLandColor.withValues(alpha: .94),
        polarLandColor.withValues(alpha: .85),
        polarLandColor.withValues(alpha: .72),
        polarLandColor.withValues(alpha: .56),
        polarLandColor.withValues(alpha: .38),
        polarLandColor.withValues(alpha: .21),
        polarLandColor.withValues(alpha: .08),
        surfaceColor.withValues(alpha: 0),
      ],
      stops: const [0.0, .12, .27, .43, .59, .73, .85, .95, 1.0],
    ).createShader(fadeBounds);
    return Paint()..shader = shader;
  }

  void _drawFootprintPolygons(
    Canvas canvas,
    Size size,
    List<MapPolygon> polygons, {
    bool china = false,
    bool skipChinaCountry = false,
  }) {
    final paths = _polygonPaths(polygons, size);
    for (var index = 0; index < polygons.length; index++) {
      final polygon = polygons[index];
      var visited = false;
      for (final place in places) {
        if (!place.isVisited) continue;
        if (skipChinaCountry &&
            place.countryCode?.trim().toUpperCase() == 'CN' &&
            _contains(polygon, place.longitude, place.latitude)) {
          // China is intentionally rendered like the world base map here;
          // only the visited province layer below receives a fill.
          visited = false;
          break;
        }
        if (_contains(polygon, place.longitude, place.latitude)) {
          visited = true;
          break;
        }
      }
      if (!visited) continue;
      canvas.drawPath(
        paths[index],
        Paint()..color = _footprintFill.withValues(alpha: china ? .86 : .74),
      );
    }
  }

  Path _pathForPolygon(MapPolygon polygon, Size size) {
    final path = Path()..fillType = PathFillType.evenOdd;
    for (final ring in polygon.rings) {
      if (ring.isEmpty) continue;
      final first = project(ring.first[1], ring.first[0], size);
      path.moveTo(first.dx, first.dy);
      for (final point in ring.skip(1)) {
        final projected = project(point[1], point[0], size);
        path.lineTo(projected.dx, projected.dy);
      }
      path.close();
    }
    return path;
  }

  Path _pathForLine(MapLine line, Size size) {
    final path = Path();
    for (var index = 0; index < line.points.length; index++) {
      final point = line.points[index];
      final projected = project(point[1], point[0], size);
      if (index == 0) {
        path.moveTo(projected.dx, projected.dy);
      } else {
        path.lineTo(projected.dx, projected.dy);
      }
    }
    return path;
  }

  void _drawLines(
    Canvas canvas,
    Size size,
    List<MapLine> lines,
    Color color,
    double width, {
    bool skipPolarShelf = false,
  }) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _screen(width);
    final paths = _linePaths(lines, size);
    for (var index = 0; index < paths.length; index++) {
      if (skipPolarShelf &&
          index < lines.length &&
          _isAntarcticaLine(lines[index])) {
        continue;
      }
      canvas.drawPath(paths[index], paint);
    }
  }

  void _drawPolygonOutlines(
    Canvas canvas,
    Size size,
    List<MapPolygon> polygons,
    Color color,
    double width, {
    bool skipPolarShelf = false,
  }) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _screen(width);
    final paths = _polygonPaths(polygons, size);
    for (var index = 0; index < paths.length; index++) {
      if (skipPolarShelf && _isAntarctica(polygons[index])) continue;
      canvas.drawPath(paths[index], paint);
    }
  }

  bool _isAntarcticaLine(MapLine line) {
    if (line.points.isEmpty) return false;
    final latitudes = [for (final point in line.points) point[1]];
    return latitudes.reduce(math.max) < -58 && latitudes.reduce(math.min) < -60;
  }

  void _drawRoute(
    Canvas canvas,
    Size size,
    MapRoute route,
    int index, {
    double offset = 0,
    double routeProgress = 1,
  }) {
    // Use one consistent spherical interpolation for every flight. Besides
    // keeping the map visually coherent, this prevents imported sampled
    // tracks from turning into harsh straight segments at this zoom level.
    final angularDistance = _greatCircleAngularDistance(route.from, route.to);
    final coordinates = _greatCircleRoute(route.from, route.to);
    if (coordinates.length < 2) return;
    final normalized = _unwrap(coordinates);
    final projectedPoints = [
      for (final point in normalized)
        project(point.latitude, point.longitude, size),
    ];
    final offsetPoints = _archedProjectedRoute(
      _offsetProjectedRoute(projectedPoints, offset),
      angularDistance,
      size: size,
    );
    final color = _routeColors[index % _routeColors.length];
    final paint = Paint()
      ..color = color.withValues(alpha: route.isHighlight ? .94 : .72)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      // Keep the route rhythm consistent; highlight is conveyed by color and
      // opacity rather than a distracting change in line weight.
      ..strokeWidth = _screen(1.1);

    // Always split at the canonical world seam. In the full-screen wrapped
    // mode the already-canonical segments are then repeated with the world
    // copies, so a route never leaks through a neighbouring tile or leaves
    // its endpoint in a different copy.
    final routeSegments = _splitRouteAtWorldSeam(offsetPoints, size);
    final segmentPaths = <Path>[];
    var routeLength = 0.0;
    for (final segment in routeSegments) {
      if (segment.length < 2) continue;
      final path = Path()..moveTo(segment.first.dx, segment.first.dy);
      for (final projected in segment.skip(1)) {
        path.lineTo(projected.dx, projected.dy);
      }
      segmentPaths.add(path);
      for (final metric in path.computeMetrics()) {
        routeLength += metric.length;
      }
    }
    if (routeLength <= 0) return;
    final revealLength = routeLength * routeProgress.clamp(0.0, 1.0).toDouble();
    var remaining = revealLength;
    outer:
    for (final path in segmentPaths) {
      for (final metric in path.computeMetrics()) {
        final visibleLength = math.min(remaining, metric.length).toDouble();
        if (visibleLength > 0) {
          canvas.drawPath(metric.extractPath(0, visibleLength), paint);
        }
        remaining -= visibleLength;
        if (remaining <= 0) break outer;
      }
    }

    // The arrow appears exactly when the stroke reaches the route midpoint,
    // so it feels discovered by the drawing rather than popping in globally.
    if (routeProgress >= .5) {
      final arrowIndex = (((offsetPoints.length - 1) / 2).round())
          .clamp(1, offsetPoints.length - 1)
          .toInt();
      final rawArrowEnd = offsetPoints[arrowIndex];
      final rawArrowBefore = offsetPoints[arrowIndex - 1];
      final arrowEnd = _canonicalWorldPoint(rawArrowEnd, size);
      var arrowDirection =
          _canonicalWorldPoint(rawArrowEnd, size) -
          _canonicalWorldPoint(rawArrowBefore, size);
      final worldWidth = _worldPixelWidth(size);
      if (arrowDirection.dx > worldWidth / 2) {
        arrowDirection = Offset(
          arrowDirection.dx - worldWidth,
          arrowDirection.dy,
        );
      } else if (arrowDirection.dx < -worldWidth / 2) {
        arrowDirection = Offset(
          arrowDirection.dx + worldWidth,
          arrowDirection.dy,
        );
      }
      final arrowBefore = arrowEnd - arrowDirection;
      _drawArrowhead(canvas, arrowBefore, arrowEnd, color);
    }
    final endpointRadius = showPassportTexture ? 1.92 : 3.2;
    if (routeProgress > 0) {
      final start = _canonicalWorldPoint(offsetPoints.first, size);
      canvas.drawCircle(start, _screen(endpointRadius), Paint()..color = color);
    }
    if (routeProgress >= 1) {
      final end = _canonicalWorldPoint(offsetPoints.last, size);
      canvas.drawCircle(end, _screen(endpointRadius), Paint()..color = color);
    }
  }

  /// Splits an unwrapped route whenever it crosses the map's date-line seam.
  /// Each segment is translated into the canonical [-180°, 180°] world copy,
  /// preventing a trans-Pacific route from drawing a false line through the
  /// empty space beyond the right edge of a single-world map.
  List<List<Offset>> _splitRouteAtWorldSeam(List<Offset> points, Size size) {
    if (points.length < 2) return [points];
    final worldWidth = _worldPixelWidth(size);
    if (worldWidth <= 0) return [points];
    final minX = size.width / 2 - worldWidth / 2;
    int tileFor(double x) => ((x - minX) / worldWidth).floor();
    final segments = <List<Offset>>[];
    var previous = points.first;
    var tile = tileFor(previous.dx);
    var current = <Offset>[_canonicalWorldPoint(previous, size, tile: tile)];

    for (final point in points.skip(1)) {
      final targetTile = tileFor(point.dx);
      while (targetTile != tile) {
        final direction = targetTile > tile ? 1 : -1;
        final boundary = direction > 0
            ? minX + (tile + 1) * worldWidth
            : minX + tile * worldWidth;
        final deltaX = point.dx - previous.dx;
        // Samples are dense, but keep a safe fallback for a degenerate pair.
        final fraction = deltaX.abs() < .000001
            ? 0.5
            : ((boundary - previous.dx) / deltaX).clamp(0.0, 1.0);
        final seam = Offset.lerp(previous, point, fraction)!;
        current.add(_canonicalWorldPoint(seam, size, tile: tile));
        segments.add(current);
        tile += direction;
        current = <Offset>[_canonicalWorldPoint(seam, size, tile: tile)];
        previous = seam;
      }
      current.add(_canonicalWorldPoint(point, size, tile: tile));
      previous = point;
    }
    segments.add(current);
    return segments;
  }

  Offset _canonicalWorldPoint(Offset point, Size size, {int? tile}) {
    final worldWidth = _worldPixelWidth(size);
    if (worldWidth <= 0) return point;
    final minX = size.width / 2 - worldWidth / 2;
    final worldTile = tile ?? ((point.dx - minX) / worldWidth).floor();
    return Offset(point.dx - worldTile * worldWidth, point.dy);
  }

  List<Offset> _offsetProjectedRoute(List<Offset> points, double offset) {
    if (offset == 0 || points.length < 2) return points;
    final result = <Offset>[];
    for (var index = 0; index < points.length; index++) {
      final before = points[index == 0 ? index : index - 1];
      final after = points[index == points.length - 1 ? index : index + 1];
      final tangent = after - before;
      final length = tangent.distance;
      if (length < .001) {
        result.add(points[index]);
        continue;
      }
      final normal = Offset(-tangent.dy / length, tangent.dx / length);
      result.add(points[index] + normal * offset);
    }
    return result;
  }

  /// Converts the projected great-circle samples into a controlled circular
  /// arc whose curvature is derived from the geographic angular distance.
  ///
  /// The sagitta equation keeps short hops subtle and gives long-haul routes
  /// a clear, mathematically stable bow without a hand-tuned Bezier control
  /// point. It is applied after Miller projection so the route remains
  /// visually legible while the world itself stays a clean flat map.
  List<Offset> _archedProjectedRoute(
    List<Offset> points,
    double angularDistance, {
    required Size size,
  }) {
    if (points.length < 3) return points;
    final start = points.first;
    final end = points.last;
    final chord = end - start;
    final length = chord.distance;
    if (length < 1) return points;
    final normal = Offset(-chord.dy / length, chord.dx / length);
    final centralAngle = angularDistance.clamp(.04, math.pi * .92).toDouble();
    final sagitta = math.min(
      length * .38,
      math.max(1.2, length * .5 * math.tan(centralAngle / 4)),
    );
    List<Offset> buildArc(double factor) {
      final adjustedSagitta = sagitta * factor;
      final radius =
          length * length / (8 * adjustedSagitta) + adjustedSagitta / 2;
      final midpoint = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
      final center = midpoint + normal * (radius - adjustedSagitta);
      final startVector = start - center;
      final endVector = end - center;
      final startAngle = math.atan2(startVector.dy, startVector.dx);
      final cross =
          startVector.dx * endVector.dy - startVector.dy * endVector.dx;
      final sweep =
          (cross < 0 ? -1.0 : 1.0) *
          (2 * math.asin((length / (2 * radius)).clamp(0.0, 1.0)));
      return [
        for (var index = 0; index < points.length; index++)
          center +
              Offset(
                math.cos(startAngle + sweep * index / (points.length - 1)) *
                    radius,
                math.sin(startAngle + sweep * index / (points.length - 1)) *
                    radius,
              ),
      ];
    }

    final initial = buildArc(1);
    // The passport map lives in a fixed 3:4 card. Long routes can have a
    // mathematically valid bow whose lowest point falls just outside the map
    // slot, where ClipRect would make the line look broken. Preserve the
    // route's endpoints and progressively soften only the curvature until
    // the interior of the arc has a small vertical safety margin. This does
    // not change the geographic path or the line width, and only activates
    // when the decorative bow would leave the viewport.
    final safety = math.min(10.0, size.height * .04);
    final top = safety;
    final bottom = size.height - safety;
    bool fitsVertically(List<Offset> candidate) {
      for (final point in candidate.skip(1).take(candidate.length - 2)) {
        if (point.dy < top || point.dy > bottom) return false;
      }
      return true;
    }

    if (fitsVertically(initial)) return initial;
    var low = .03;
    var high = 1.0;
    var best = points;
    for (var iteration = 0; iteration < 7; iteration++) {
      final factor = (low + high) / 2;
      final candidate = buildArc(factor);
      if (fitsVertically(candidate)) {
        best = candidate;
        low = factor;
      } else {
        high = factor;
      }
    }
    return best;
  }

  List<MapCoordinate> _greatCircleRoute(MapAirport from, MapAirport to) {
    double radians(double value) => value * math.pi / 180;
    double degrees(double value) => value * 180 / math.pi;
    final angle = _greatCircleAngularDistance(from, to);
    final lat1 = radians(from.latitude);
    final lat2 = radians(to.latitude);
    final lon1 = radians(from.longitude);
    final lon2 = radians(to.longitude);
    final x1 = math.cos(lat1) * math.cos(lon1);
    final y1 = math.cos(lat1) * math.sin(lon1);
    final z1 = math.sin(lat1);
    final x2 = math.cos(lat2) * math.cos(lon2);
    final y2 = math.cos(lat2) * math.sin(lon2);
    final z2 = math.sin(lat2);
    final segments = math.min(
      180,
      math.max(18, (degrees(angle) / 1.25).ceil()),
    );
    final points = <MapCoordinate>[];
    for (var index = 0; index <= segments; index++) {
      final fraction = index / segments;
      final sinAngle = math.sin(angle);
      final weightA = sinAngle.abs() < .000001
          ? 1 - fraction
          : math.sin((1 - fraction) * angle) / sinAngle;
      final weightB = sinAngle.abs() < .000001
          ? fraction
          : math.sin(fraction * angle) / sinAngle;
      final x = weightA * x1 + weightB * x2;
      final y = weightA * y1 + weightB * y2;
      final z = weightA * z1 + weightB * z2;
      points.add(
        MapCoordinate(
          degrees(math.atan2(z, math.sqrt(x * x + y * y))),
          degrees(math.atan2(y, x)),
        ),
      );
    }
    return points;
  }

  double _greatCircleAngularDistance(MapAirport from, MapAirport to) {
    double radians(double value) => value * math.pi / 180;
    final lat1 = radians(from.latitude);
    final lat2 = radians(to.latitude);
    final lon1 = radians(from.longitude);
    final lon2 = radians(to.longitude);
    final x1 = math.cos(lat1) * math.cos(lon1);
    final y1 = math.cos(lat1) * math.sin(lon1);
    final z1 = math.sin(lat1);
    final x2 = math.cos(lat2) * math.cos(lon2);
    final y2 = math.cos(lat2) * math.sin(lon2);
    final z2 = math.sin(lat2);
    final dot = (x1 * x2 + y1 * y2 + z1 * z2).clamp(-1.0, 1.0);
    return math.acos(dot);
  }

  List<MapCoordinate> _unwrap(List<MapCoordinate> points) {
    if (points.isEmpty) return points;
    final result = <MapCoordinate>[points.first];
    var previousLongitude = points.first.longitude;
    for (final point in points.skip(1)) {
      var longitude = point.longitude;
      while (longitude - previousLongitude > 180) {
        longitude -= 360;
      }
      while (longitude - previousLongitude < -180) {
        longitude += 360;
      }
      result.add(MapCoordinate(point.latitude, longitude));
      previousLongitude = longitude;
    }
    return result;
  }

  void _drawArrowhead(Canvas canvas, Offset before, Offset end, Color color) {
    final direction = end - before;
    if (direction.distance < 1) return;
    final angle = math.atan2(direction.dy, direction.dx);
    final size = _screen(4.8);
    final left =
        end -
        Offset(math.cos(angle - .55) * size, math.sin(angle - .55) * size);
    final right =
        end -
        Offset(math.cos(angle + .55) * size, math.sin(angle + .55) * size);
    final path = Path()
      ..moveTo(end.dx, end.dy)
      ..lineTo(left.dx, left.dy)
      ..moveTo(end.dx, end.dy)
      ..lineTo(right.dx, right.dy);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = _screen(1.15)
        ..strokeCap = StrokeCap.round,
    );
  }

  void _drawAirports(Canvas canvas, Size size) {
    final labels = <_MapLabelCandidate>[];
    // Passport artwork has a much denser route field than the dashboard. A
    // half-size marker keeps the map legible without changing the shared
    // flight-map marker scale elsewhere in the app.
    final markerScale = showPassportTexture ? .6 : 1.0;
    for (final airport in airports) {
      final point = project(airport.latitude, airport.longitude, size);
      // Flight-map points use the same semantic lime as the rest of the UI.
      // Route lines keep their five-color rhythm; only the airport marker
      // itself is unified so a dense itinerary reads as one clear layer.
      final color = lightPalette ? _lightRouteColors.first : AppColors.lime;
      canvas.drawCircle(
        point,
        _screen(3.8 * markerScale),
        Paint()..color = _markerOutline,
      );
      canvas.drawCircle(
        point,
        _screen(2.55 * markerScale),
        Paint()..color = color,
      );
      if (showLabels && airport.name.trim().isNotEmpty) {
        final name = normalizedMapLabel(airport.name);
        if (name.isNotEmpty && !isProvinceMapLabel(name)) {
          labels.add(
            _MapLabelCandidate(
              value: name,
              point: point,
              priority: airport.isPrimary ? 3 : 2,
            ),
          );
        }
      }
    }
    _drawLabels(canvas, labels);
  }

  void _drawPlaces(Canvas canvas, Size size) {
    final labels = <_MapLabelCandidate>[];
    for (var index = 0; index < places.length; index++) {
      final place = places[index];
      if (!place.isVisited) continue;
      final point = project(place.latitude, place.longitude, size);
      _drawPlaceMarker(
        canvas,
        point,
        _routeColors[index % _routeColors.length],
      );
      if (showLabels && place.name.trim().isNotEmpty) {
        final name = normalizedMapLabel(
          place.name,
          countryCode: place.countryCode,
        );
        if (name.isNotEmpty && !isProvinceMapLabel(name)) {
          labels.add(
            _MapLabelCandidate(
              value: name,
              point: point,
              priority: place.isDeletable ? 3 : 2,
            ),
          );
        }
      }
    }
    _drawLabels(canvas, labels);
  }

  void _drawPlaceMarker(Canvas canvas, Offset point, Color color) {
    canvas.drawCircle(point, _screen(4.15), Paint()..color = _markerOutline);
    canvas.drawCircle(point, _screen(2.8), Paint()..color = color);
  }

  /// Draw labels progressively: a world-fit view shows the clearest subset,
  /// then more names become available as the user zooms in. A greedy bounds
  /// pass prevents nearby cities from painting over one another while the
  /// marker itself remains visible at every scale.
  void _drawLabels(Canvas canvas, List<_MapLabelCandidate> candidates) {
    if (!showLabels || candidates.isEmpty) return;
    final unique = <String, _MapLabelCandidate>{};
    for (final candidate in candidates) {
      final key = candidate.value.trim().toLowerCase();
      final existing = unique[key];
      if (existing == null || candidate.priority > existing.priority) {
        unique[key] = candidate;
      }
    }
    final ordered = unique.values.toList()
      ..sort((left, right) => right.priority.compareTo(left.priority));
    final limit = _labelLimit(ordered.length);
    final occupied = <Rect>[];
    var drawn = 0;
    for (final candidate in ordered) {
      final painter = _labelPainter(candidate.value);
      final topLeft = Offset(
        candidate.point.dx + _screen(6),
        candidate.point.dy - painter.height / 2,
      );
      final bounds = Rect.fromLTWH(
        topLeft.dx,
        topLeft.dy,
        painter.width,
        painter.height,
      ).inflate(_screen(4));
      if (occupied.any(bounds.overlaps)) continue;
      painter.paint(canvas, topLeft);
      occupied.add(bounds);
      drawn++;
      if (drawn >= limit) break;
    }
  }

  int _labelLimit(int total) {
    if (_scale < 1.5) return math.min(total, 10);
    if (_scale < 2.5) return math.min(total, 18);
    if (_scale < 4.5) return math.min(total, 32);
    if (_scale < 8) return math.min(total, 56);
    return total;
  }

  TextPainter _labelPainter(String value) => TextPainter(
    text: TextSpan(
      text: value,
      style: TextStyle(
        color: lightPalette ? const Color(0xff30404c) : const Color(0xfff4f6f8),
        fontWeight: FontWeight.w500,
        fontSize: _screen(10),
        shadows: [
          Shadow(
            color: lightPalette
                ? const Color(0xfff7fafc)
                : const Color(0xff0b1015),
            blurRadius: _screen(2.5),
          ),
        ],
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: _screen(120));

  bool _contains(MapPolygon polygon, double longitude, double latitude) {
    if (polygon.rings.isEmpty ||
        !_ringContains(polygon.rings.first, longitude, latitude)) {
      return false;
    }
    for (final hole in polygon.rings.skip(1)) {
      if (_ringContains(hole, longitude, latitude)) return false;
    }
    return true;
  }

  bool _ringContains(
    List<List<double>> ring,
    double longitude,
    double latitude,
  ) {
    var inside = false;
    for (
      var index = 0, previous = ring.length - 1;
      index < ring.length;
      previous = index++
    ) {
      final x1 = ring[index][0];
      final y1 = ring[index][1];
      final x2 = ring[previous][0];
      final y2 = ring[previous][1];
      final intersects =
          (y1 > latitude) != (y2 > latitude) &&
          longitude < (x2 - x1) * (latitude - y1) / (y2 - y1 + .0000001) + x1;
      if (intersects) inside = !inside;
    }
    return inside;
  }

  @override
  bool shouldRepaint(covariant FlatMapPainter old) =>
      old.data != data ||
      old.airports != airports ||
      old.routes != routes ||
      old.places != places ||
      old.mode != mode ||
      old.showLabels != showLabels ||
      old.minimalWorldStyle != minimalWorldStyle ||
      old.transparentBackground != transparentBackground ||
      old.bottomFade != bottomFade ||
      old.excludePolarShelf != excludePolarShelf ||
      old.routeRevealProgress != routeRevealProgress ||
      old.showPassportTexture != showPassportTexture ||
      old.compactWorldViewport != compactWorldViewport ||
      old.visualScale != visualScale ||
      old.horizontalPadding != horizontalPadding ||
      old.verticalPadding != verticalPadding ||
      old.horizontalWrap != horizontalWrap ||
      old.lightPalette != lightPalette;
}

class _MapLabelCandidate {
  const _MapLabelCandidate({
    required this.value,
    required this.point,
    required this.priority,
  });

  final String value;
  final Offset point;
  final int priority;
}

/// Reprojects the static GeoJSON geometry only once for each recent canvas
/// size. Rotation changes the map's layout size, but the same size is painted
/// for many frames while the system settles; keeping those Paths avoids doing
/// tens of thousands of longitude/latitude projections during that animation.
class _ProjectedGeometryCache {
  final LinkedHashMap<String, _ProjectedGeometry> _entries = LinkedHashMap();

  _ProjectedGeometry forSize(FlatMapPainter painter, Size size) {
    final key =
        '${size.width.toStringAsFixed(1)}:${size.height.toStringAsFixed(1)}:'
        '${painter.horizontalPadding.toStringAsFixed(1)}:'
        '${painter.verticalPadding.toStringAsFixed(1)}:'
        '${painter.compactWorldViewport}';
    final existing = _entries.remove(key);
    if (existing != null) {
      _entries[key] = existing;
      return existing;
    }

    final data = painter.data;
    final geometry = _ProjectedGeometry(
      land: [
        for (final polygon in data.land.polygons)
          painter._pathForPolygon(polygon, size),
      ],
      countries: [
        for (final polygon in data.countries.polygons)
          painter._pathForPolygon(polygon, size),
      ],
      provinces: [
        for (final polygon in data.provinces.polygons)
          painter._pathForPolygon(polygon, size),
      ],
      nationalBoundary: [
        for (final polygon in data.nationalBoundary.polygons)
          painter._pathForPolygon(polygon, size),
      ],
      maritimeMarks: [
        for (final polygon in data.maritimeMarks.polygons)
          painter._pathForPolygon(polygon, size),
      ],
      internalBoundaries: [
        for (final line in data.internalBoundaries.lines)
          painter._pathForLine(line, size),
      ],
      maritimeLines: [
        for (final line in data.maritimeMarks.lines)
          painter._pathForLine(line, size),
      ],
    );
    _entries[key] = geometry;
    while (_entries.length > 2) {
      _entries.remove(_entries.keys.first);
    }
    return geometry;
  }
}

class _ProjectedGeometry {
  const _ProjectedGeometry({
    required this.land,
    required this.countries,
    required this.provinces,
    required this.nationalBoundary,
    required this.maritimeMarks,
    required this.internalBoundaries,
    required this.maritimeLines,
  });

  final List<Path> land;
  final List<Path> countries;
  final List<Path> provinces;
  final List<Path> nationalBoundary;
  final List<Path> maritimeMarks;
  final List<Path> internalBoundaries;
  final List<Path> maritimeLines;
}
