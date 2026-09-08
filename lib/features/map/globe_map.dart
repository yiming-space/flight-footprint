import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'geojson_map_data.dart';
import 'galaxy_background.dart';
import 'globe_surface.dart';
import 'map_models.dart';

/// A lightweight, dependency-free orthographic globe for the fullscreen map.
///
/// It deliberately keeps the same bundled GeoJSON and route colors as the
/// flat map, but turns the map into a tactile surface: drag to rotate and
/// pinch to zoom. No network tiles or map SDK are needed, so the experience
/// remains available offline.
class GlobeMap extends StatefulWidget {
  const GlobeMap({
    super.key,
    this.mode = MapMode.flight,
    this.airports = const [],
    this.routes = const [],
    this.places = const [],
    this.routeAnimationProgress = 1,
    this.showRouteAnimationPlane = false,
    this.onSelection,
    this.onInteractionChanged,
    this.resetSignal = 0,
    this.loader = const GeoJsonMapLoader(),
  });

  final MapMode mode;
  final List<MapAirport> airports;
  final List<MapRoute> routes;
  final List<MapPlace> places;
  final double routeAnimationProgress;
  final bool showRouteAnimationPlane;
  final ValueChanged<MapSelection>? onSelection;
  final ValueChanged<bool>? onInteractionChanged;
  // Nullable keeps hot reload compatible with a State created before this
  // optional control was added; a missing value behaves like the initial 0.
  final int? resetSignal;
  final GeoJsonMapLoader loader;

  @override
  State<GlobeMap> createState() => _GlobeMapState();
}

class _GlobeMapState extends State<GlobeMap> with TickerProviderStateMixin {
  static const _entryDuration = Duration(milliseconds: 680);
  static const _autoRotationDuration = Duration(seconds: 120);

  late Future<({GeoJsonMapBundle data, GlobeSurface surface})> _future;
  ui.FragmentShader? _surfaceShader;
  late final AnimationController _momentum;
  AnimationController? _entryControllerValue;
  AnimationController? _autoRotateControllerValue;
  double _releaseYaw = 0;
  double _releasePitch = 0;
  Offset _releaseVelocity = Offset.zero;
  bool _pinching = false;
  double _yaw = -.35;
  double _pitch = .12;
  double _scale = 1;
  double _startYaw = 0;
  double _startPitch = 0;
  double _startScale = 1;
  Offset _startFocalPoint = Offset.zero;
  double _followYawOffset = 0;
  double _followPitchOffset = 0;
  double _startFollowYawOffset = 0;
  double _startFollowPitchOffset = 0;
  bool _showLabels = false;
  bool _interactionReported = false;
  bool _presentationStarted = false;
  bool _autoRotationRunning = false;
  double _autoRotationLastValue = 0;
  String? _selectedLabel;
  MapCoordinate? _selectedCoordinate;

  @override
  void initState() {
    super.initState();
    _future = _loadScene();
    _momentum =
        AnimationController(
            vsync: this,
            duration: const Duration(milliseconds: 900),
          )
          ..addListener(() {
            final travel = (1 - math.exp(-6 * _momentum.value)) / 6;
            setState(() {
              _yaw = _releaseYaw + _releaseVelocity.dx * travel;
              _pitch = (_releasePitch + _releaseVelocity.dy * travel)
                  .clamp(-math.pi / 2, math.pi / 2)
                  .toDouble();
            });
          })
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed ||
                status == AnimationStatus.dismissed) {
              _reportInteraction(false);
            }
          });
  }

  AnimationController get _entryController => _entryControllerValue ??=
      (AnimationController(
          vsync: this,
          duration: _entryDuration,
          animationBehavior: AnimationBehavior.normal,
        )
        ..addListener(_handleEntryTick)
        ..addStatusListener(_handleEntryStatus));

  AnimationController get _autoRotateController =>
      _autoRotateControllerValue ??= (AnimationController(
        vsync: this,
        duration: _autoRotationDuration,
        animationBehavior: AnimationBehavior.preserve,
      )..addListener(_handleAutoRotationTick));

  Future<({GeoJsonMapBundle data, GlobeSurface surface})> _loadScene() async {
    final data = await widget.loader.loadBundle();
    final surface = await GlobeSurface.load(
      data.land,
      countries: data.countries,
      places: widget.mode == MapMode.travelFootprint ? widget.places : const [],
    );
    return (data: data, surface: surface);
  }

  bool get _following =>
      widget.showRouteAnimationPlane && widget.routeAnimationProgress < .999;

  void _handleEntryTick() {
    if (mounted) setState(() {});
  }

  void _handleEntryStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _maybeResumeAutoRotation();
    }
  }

  void _handleAutoRotationTick() {
    if (!mounted ||
        !_autoRotationRunning ||
        _interactionReported ||
        _momentum.isAnimating ||
        _following) {
      return;
    }
    final value = _autoRotateController.value;
    var delta = value - _autoRotationLastValue;
    // repeat() wraps from 1 back to 0; keep that seam continuous.
    if (delta < -.5) delta += 1;
    _autoRotationLastValue = value;
    if (delta <= 0) return;
    setState(() {
      _yaw = _wrappedAngle(_yaw + delta * math.pi * 2);
    });
  }

  void _startPresentationIfNeeded() {
    if (_presentationStarted || !mounted) return;
    _presentationStarted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_presentationStarted) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        _entryController.value = 1;
        _maybeResumeAutoRotation();
      } else {
        _entryController.forward(from: 0);
      }
    });
  }

  void _resetPresentation() {
    _pauseAutoRotation();
    _presentationStarted = false;
    _entryController.stop();
    _entryController.value = 0;
  }

  void _resumeAutoRotation() {
    if (_autoRotationRunning ||
        !_presentationStarted ||
        _entryController.value < .999 ||
        _interactionReported ||
        _momentum.isAnimating ||
        _following ||
        MediaQuery.disableAnimationsOf(context)) {
      return;
    }
    _autoRotateController.stop();
    _autoRotateController.value = 0;
    _autoRotationLastValue = 0;
    _autoRotationRunning = true;
    _autoRotateController.repeat(period: _autoRotationDuration);
  }

  void _pauseAutoRotation() {
    _autoRotationRunning = false;
    _autoRotateController.stop();
  }

  void _maybeResumeAutoRotation() {
    if (!mounted) return;
    _resumeAutoRotation();
  }

  static double _wrappedAngle(double value) {
    var result = value;
    while (result > math.pi) result -= math.pi * 2;
    while (result < -math.pi) result += math.pi * 2;
    return result;
  }

  @override
  void dispose() {
    _entryControllerValue
      ?..removeListener(_handleEntryTick)
      ..removeStatusListener(_handleEntryStatus)
      ..dispose();
    _autoRotateControllerValue
      ?..removeListener(_handleAutoRotationTick)
      ..dispose();
    _momentum.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant GlobeMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.loader != widget.loader) {
      _surfaceShader = null;
      _future = _loadScene();
      _resetPresentation();
    }
    if (oldWidget.mode != widget.mode ||
        (widget.mode == MapMode.travelFootprint &&
            oldWidget.places != widget.places)) {
      _surfaceShader = null;
      _future = _loadScene();
      _resetPresentation();
    }
    if ((oldWidget.resetSignal ?? 0) != (widget.resetSignal ?? 0)) {
      _momentum.stop();
      _yaw = -.35;
      _pitch = .12;
      _scale = 1;
      _followYawOffset = 0;
      _followPitchOffset = 0;
      _showLabels = false;
      _selectedLabel = null;
      _selectedCoordinate = null;
      _resetPresentation();
    }
    if (!oldWidget.showRouteAnimationPlane && widget.showRouteAnimationPlane) {
      _followYawOffset = 0;
      _followPitchOffset = 0;
    }
    if (_following) {
      _pauseAutoRotation();
    } else {
      _maybeResumeAutoRotation();
    }
  }

  void _onScaleStart(ScaleStartDetails details) {
    if (_entryController.isAnimating) {
      _entryController.stop();
      _entryController.value = 1;
    }
    _presentationStarted = true;
    _pauseAutoRotation();
    _reportInteraction(true);
    _momentum.stop();
    _pinching = false;
    _startYaw = _yaw;
    _startPitch = _pitch;
    _startScale = _scale;
    _startFocalPoint = details.focalPoint;
    _startFollowYawOffset = _followYawOffset;
    _startFollowPitchOffset = _followPitchOffset;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final delta = details.focalPoint - _startFocalPoint;
    _pinching = _pinching || details.pointerCount > 1;
    setState(() {
      if (_following) {
        // Keep the aircraft follow camera adjustable without allowing a drag
        // to push the active flight permanently behind the globe.
        _followYawOffset = (_startFollowYawOffset + delta.dx / 240)
            .clamp(-.62, .62)
            .toDouble();
        _followPitchOffset = (_startFollowPitchOffset + delta.dy / 240)
            .clamp(-.48, .48)
            .toDouble();
      } else {
        _yaw = _startYaw + delta.dx / 240;
        _pitch = (_startPitch + delta.dy / 240)
            .clamp(-math.pi / 2, math.pi / 2)
            .toDouble();
      }
      _scale = (_startScale * details.scale).clamp(.82, 2.05).toDouble();
    });
  }

  void _onScaleEnd(ScaleEndDetails details) {
    if (_following || _pinching || MediaQuery.disableAnimationsOf(context)) {
      _reportInteraction(false);
      return;
    }
    final velocity = details.velocity.pixelsPerSecond / 240;
    if (velocity.distance < .15) {
      _reportInteraction(false);
      return;
    }
    _releaseVelocity = Offset(
      velocity.dx.clamp(-5.0, 5.0),
      velocity.dy.clamp(-5.0, 5.0),
    );
    _releaseYaw = _yaw;
    _releasePitch = _pitch;
    _momentum.forward(from: 0);
  }

  void _reportInteraction(bool value) {
    if (_interactionReported == value) return;
    _interactionReported = value;
    widget.onInteractionChanged?.call(value);
    if (!value) _maybeResumeAutoRotation();
  }

  @override
  Widget build(
    BuildContext context,
  ) => FutureBuilder<({GeoJsonMapBundle data, GlobeSurface surface})>(
    future: _future,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const ColoredBox(
          color: Color(0xff0b1015),
          child: Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      }
      if (snapshot.hasError || snapshot.data == null) {
        return const ColoredBox(
          color: Color(0xff0b1015),
          child: Center(
            child: Text('地球加载失败', style: TextStyle(color: Color(0xfff4f6f8))),
          ),
        );
      }
      _surfaceShader ??= snapshot.data!.surface.createShader();
      _startPresentationIfNeeded();
      final entryProgress = Curves.easeOutCubic.transform(
        _entryController.value.clamp(0.0, 1.0).toDouble(),
      );
      final entryScale = .86 + entryProgress * .14;
      final animationCamera = _following
          ? GlobePainter.animationCameraForProgress(
              widget.routes,
              widget.routeAnimationProgress,
            )
          : null;
      if (animationCamera != null) {
        _yaw = animationCamera.yaw + _followYawOffset;
        _pitch = (animationCamera.pitch + _followPitchOffset)
            .clamp(-math.pi / 2, math.pi / 2)
            .toDouble();
      }
      return LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(
            constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : MediaQuery.sizeOf(context).width,
            constraints.maxHeight.isFinite
                ? constraints.maxHeight
                : MediaQuery.sizeOf(context).height,
          );
          final painter = GlobePainter(
            data: snapshot.data!.data,
            surfaceShader: _surfaceShader,
            mode: widget.mode,
            airports: widget.airports,
            routes: widget.routes,
            places: widget.places,
            yaw: _yaw,
            pitch: _pitch,
            scale: _scale * entryScale,
            routeAnimationProgress: widget.routeAnimationProgress,
            showRouteAnimationPlane: widget.showRouteAnimationPlane,
            showLabels: _showLabels,
            selectedLabel: _selectedLabel,
            selectedCoordinate: _selectedCoordinate,
          );
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) {
              final selection = painter.selectionAt(
                details.localPosition,
                size,
              );
              if (selection == null) {
                setState(() {
                  _showLabels = !_showLabels;
                  _selectedLabel = null;
                  _selectedCoordinate = null;
                });
                return;
              }
              if (!mounted) {
                return;
              }
              setState(() {
                _selectedLabel = painter.labelForSelection(selection);
                _selectedCoordinate = painter.coordinateForSelection(selection);
              });
              widget.onSelection?.call(selection);
            },
            onScaleStart: _onScaleStart,
            onScaleUpdate: _onScaleUpdate,
            onScaleEnd: _onScaleEnd,
            child: CustomPaint(
              painter: painter,
              child: const SizedBox.expand(),
            ),
          );
        },
      );
    },
  );
}

class GlobePainter extends CustomPainter {
  static const _routeTravelShare = .86;

  GlobePainter({
    required this.data,
    this.surfaceShader,
    this.mode = MapMode.flight,
    this.airports = const [],
    this.routes = const [],
    this.places = const [],
    this.yaw = 0,
    this.pitch = 0,
    this.scale = 1,
    this.routeAnimationProgress = 1,
    this.showRouteAnimationPlane = false,
    this.showLabels = false,
    this.selectedLabel,
    this.selectedCoordinate,
  });

  final GeoJsonMapBundle data;
  final ui.FragmentShader? surfaceShader;
  final MapMode mode;
  final List<MapAirport> airports;
  final List<MapRoute> routes;
  final List<MapPlace> places;
  final double yaw;
  final double pitch;
  final double scale;
  final double routeAnimationProgress;
  final bool showRouteAnimationPlane;
  final bool showLabels;
  final String? selectedLabel;
  final MapCoordinate? selectedCoordinate;

  // The fullscreen map receives both flight-derived airports and manually
  // visited places. In flight mode only airports that are actual endpoints
  // of a rendered route belong on the globe; keep the lookup cached because
  // the painter is rebuilt while the globe rotates.
  late final Set<String> _routeAirportCodes = {
    for (final route in routes) ...[
      route.from.code.trim().toUpperCase(),
      route.to.code.trim().toUpperCase(),
    ],
  };

  static const _routeColors = <Color>[
    Color(0xff68b7ff),
    Color(0xff68b7ff),
    Color(0xff68b7ff),
    Color(0xff68b7ff),
    Color(0xff68b7ff),
  ];
  static const _travelColors = <Color>[
    Color(0xff75688f),
    Color(0xffc6ff32),
    Color(0xff75dce9),
    Color(0xffa58aff),
    Color(0xfff6e68a),
  ];

  static final _routeSamples = Expando<List<MapCoordinate>>();

  /// Returns a camera target that keeps the animated aircraft near the centre
  /// of the globe. Both the yaw and pitch follow the same eased route position
  /// as the plane, so a long polar arc cannot disappear behind the horizon.
  static ({double yaw, double pitch}) animationCameraForProgress(
    List<MapRoute> routes,
    double value,
  ) {
    if (routes.isEmpty) return (yaw: 0, pitch: 0);
    final progress = value.clamp(0.0, 1.0).toDouble();
    final scaled = progress * routes.length;
    final activeIndex = math
        .min(math.max(scaled.floor(), 0), routes.length - 1)
        .toInt();
    final windowProgress = progress >= 1
        ? 1.0
        : (scaled - activeIndex).clamp(0.0, 1.0).toDouble();
    final travelProgress = Curves.easeInOutCubic.transform(
      (windowProgress / _routeTravelShare).clamp(0.0, 1.0).toDouble(),
    );
    final route = routes[activeIndex];
    final current = _coordinateAtRouteProgress(route, travelProgress);
    final unwrappedLongitude =
        route.from.longitude +
        _shortestLongitudeDelta(route.from.longitude, current.longitude);
    return (
      yaw: -unwrappedLongitude * math.pi / 180,
      pitch: (current.latitude * math.pi / 180).clamp(-1.18, 1.18).toDouble(),
    );
  }

  static MapCoordinate _coordinateAtRouteProgress(
    MapRoute route,
    double progress,
  ) {
    final start = _cameraVectorFor(route.from.latitude, route.from.longitude);
    final end = _cameraVectorFor(route.to.latitude, route.to.longitude);
    final dot = (start.x * end.x + start.y * end.y + start.z * end.z)
        .clamp(-1.0, 1.0)
        .toDouble();
    final angle = math.acos(dot);
    final sine = math.sin(angle);
    if (sine.abs() < .000001) {
      return MapCoordinate(route.from.latitude, route.from.longitude);
    }
    final first = math.sin((1 - progress) * angle) / sine;
    final second = math.sin(progress * angle) / sine;
    return _cameraCoordinateFor(
      _GlobeVector(
        x: first * start.x + second * end.x,
        y: first * start.y + second * end.y,
        z: first * start.z + second * end.z,
      ),
    );
  }

  static _GlobeVector _cameraVectorFor(double latitude, double longitude) {
    final lat = latitude * math.pi / 180;
    final lon = longitude * math.pi / 180;
    final cosLatitude = math.cos(lat);
    return _GlobeVector(
      x: cosLatitude * math.sin(lon),
      y: math.sin(lat),
      z: cosLatitude * math.cos(lon),
    );
  }

  static MapCoordinate _cameraCoordinateFor(_GlobeVector vector) =>
      MapCoordinate(
        math.asin(vector.y.clamp(-1.0, 1.0).toDouble()) * 180 / math.pi,
        math.atan2(vector.x, vector.z) * 180 / math.pi,
      );

  static double _shortestLongitudeDelta(double from, double to) {
    var delta = to - from;
    while (delta > 180) {
      delta -= 360;
    }
    while (delta < -180) {
      delta += 360;
    }
    return delta;
  }

  @override
  void paint(Canvas canvas, Size size) {
    const GalaxyBackgroundPainter().paint(canvas, size);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0x9208182b), Color(0xF302050d)],
          radius: .92,
        ).createShader(Offset.zero & size),
    );
    final radius = math.min(size.width, size.height) * .39 * scale;
    final projection = _GlobeProjection(
      center: size.center(Offset.zero),
      radius: radius,
      yaw: yaw,
      pitch: pitch,
    );
    final sphere = Path()..addOval(projection.bounds);
    // A small radial falloff keeps the atmosphere outside the surface and
    // avoids a full-screen blur pass while the camera moves.
    canvas.drawCircle(
      projection.center,
      radius * 1.09,
      Paint()
        ..shader =
            const RadialGradient(
              colors: [
                Color(0x007cbfdc),
                Color(0x007cbfdc),
                Color(0x387cbfdc),
                Color(0x147cbfdc),
                Color(0x007cbfdc),
              ],
              stops: [0, .89, .918, .95, 1],
            ).createShader(
              Rect.fromCircle(center: projection.center, radius: radius * 1.09),
            ),
    );
    final shader = surfaceShader;
    if (shader != null) {
      GlobeSurface.paint(
        canvas,
        shader: shader,
        center: projection.center,
        radius: radius,
        yaw: yaw,
        pitch: pitch,
      );
    } else {
      canvas.drawPath(sphere, Paint()..color = const Color(0xff102a3b));
    }

    canvas.save();
    canvas.clipPath(sphere);
    if (showLabels) _drawGrid(canvas, projection);
    canvas.restore();

    // Routes are raised above the sphere, so they need to be painted outside
    // the globe clip. Their depth test still hides the part that is behind
    // the opaque globe.
    _drawRoutes(canvas, projection);

    canvas.save();
    canvas.clipPath(sphere);
    _drawAirports(canvas, projection);
    _drawPlaces(canvas, projection);
    if (showLabels) _drawAllLabels(canvas, projection);
    canvas.restore();

    if (showRouteAnimationPlane) {
      _drawRouteAnimationPlane(canvas, projection);
    }

    // Arrival labels sit above the globe clip so a destination near the
    // horizon can still reveal its city name without being cut in half.
    if (showRouteAnimationPlane) {
      _drawArrivalLabels(canvas, projection);
    }
    _drawSelectedLabel(canvas, projection);

    canvas.drawPath(
      sphere,
      Paint()
        ..color = const Color(0xff91cedb).withValues(alpha: .32)
        ..style = PaintingStyle.stroke
        ..strokeWidth = .7,
    );
  }

  void _drawGrid(Canvas canvas, _GlobeProjection projection) {
    final paint = Paint()
      ..color = const Color(0xffaac0cb).withValues(alpha: .018)
      ..style = PaintingStyle.stroke
      ..strokeWidth = .7;
    for (var longitude = -180.0; longitude < 180; longitude += 30) {
      _drawSphericalLine(canvas, projection, [
        for (var latitude = -90.0; latitude <= 90; latitude += 4)
          _GlobeCoordinate(latitude, longitude),
      ], paint);
    }
    for (var latitude = -60.0; latitude <= 60; latitude += 30) {
      _drawSphericalLine(canvas, projection, [
        for (var longitude = -180.0; longitude <= 180; longitude += 4)
          _GlobeCoordinate(latitude, longitude),
      ], paint);
    }
  }

  void _drawRoutes(Canvas canvas, _GlobeProjection projection) {
    for (var index = 0; index < routes.length; index++) {
      final route = routes[index];
      final progress = _routeProgressForIndex(index, routes.length);
      final samples = _partialRoute(_greatCircleRoute(route), progress);
      if (samples.length < 2) continue;
      final path = _elevatedRoutePath(projection, samples, route);
      if (path.getBounds().isEmpty) continue;
      canvas.drawPath(
        path,
        Paint()
          ..color = _routeColors[index % _routeColors.length].withValues(
            alpha: route.isHighlight ? .88 : .48,
          )
          ..style = PaintingStyle.stroke
          // The globe already gives routes extra visual weight through
          // elevation and perspective. Keep every route at the same delicate
          // weight so long and highlighted routes do not overpower the globe.
          ..strokeWidth = .75
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  void _drawAirports(Canvas canvas, _GlobeProjection projection) {
    for (var index = 0; index < airports.length; index++) {
      final airport = airports[index];
      if (mode == MapMode.flight && !_hasRenderedRoute(airport)) continue;
      final point = projection.project(airport.latitude, airport.longitude);
      if (point == null) continue;
      final color = _routeColors[index % _routeColors.length];
      if (!_isAirportVisibleForPlayback(airport)) continue;
      _drawGlowingMarker(canvas, point, color, coreRadius: 1.8);
    }
  }

  void _drawGlowingMarker(
    Canvas canvas,
    Offset point,
    Color color, {
    required double coreRadius,
  }) {
    // Concentric alpha layers give the marker a soft halo without a blur pass.
    canvas.drawCircle(
      point,
      coreRadius * 4.0,
      Paint()..color = color.withValues(alpha: .055),
    );
    canvas.drawCircle(
      point,
      coreRadius * 2.6,
      Paint()..color = color.withValues(alpha: .14),
    );
    canvas.drawCircle(point, coreRadius, Paint()..color = color);
  }

  bool _isAirportVisibleForPlayback(MapAirport airport) {
    if (!showRouteAnimationPlane || routes.isEmpty) return true;
    var revealProgress = 0.0;
    var hasIncomingRoute = false;
    for (var routeIndex = 0; routeIndex < routes.length; routeIndex++) {
      if (routes[routeIndex].to.code != airport.code) continue;
      hasIncomingRoute = true;
      revealProgress = math.max(
        revealProgress,
        _routeProgressForIndex(routeIndex, routes.length),
      );
    }
    if (!hasIncomingRoute && routeAnimationProgress < .999) return false;
    return !hasIncomingRoute || revealProgress >= .999;
  }

  bool _hasRenderedRoute(MapAirport airport) =>
      _routeAirportCodes.contains(airport.code.trim().toUpperCase());

  void _drawPlaces(Canvas canvas, _GlobeProjection projection) {
    if (mode != MapMode.travelFootprint) return;
    for (var index = 0; index < places.length; index++) {
      final place = places[index];
      if (!place.isVisited) continue;
      final point = projection.project(place.latitude, place.longitude);
      if (point == null) continue;
      final color = _travelColors[index % _travelColors.length];
      _drawGlowingMarker(canvas, point, color, coreRadius: 2.5);
    }
  }

  void _drawAllLabels(Canvas canvas, _GlobeProjection projection) {
    final occupied = <Rect>[];
    if (mode == MapMode.travelFootprint) {
      for (final place in places) {
        if (!place.isVisited) continue;
        final name = normalizedMapLabel(place.name);
        final point = projection.project(place.latitude, place.longitude);
        if (name.isEmpty || isProvinceMapLabel(name) || point == null) {
          continue;
        }
        _drawGlobeLabel(canvas, projection, point, name, occupied);
      }
      return;
    }
    for (final airport in airports) {
      if (!_hasRenderedRoute(airport)) continue;
      if (!_isAirportVisibleForPlayback(airport)) continue;
      final name = normalizedMapLabel(airport.name);
      final point = projection.project(airport.latitude, airport.longitude);
      if (name.isEmpty || isProvinceMapLabel(name) || point == null) continue;
      _drawGlobeLabel(canvas, projection, point, name, occupied);
    }
  }

  void _drawGlobeLabel(
    Canvas canvas,
    _GlobeProjection projection,
    Offset point,
    String name,
    List<Rect> occupied,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: name,
        style: const TextStyle(
          color: Color(0xfff4f6f8),
          fontSize: 10,
          fontWeight: FontWeight.w500,
          shadows: [Shadow(color: Color(0xff0b1015), blurRadius: 3)],
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 132);
    final bounds = projection.bounds;
    final left = (point.dx + 7).clamp(
      bounds.left + 4,
      bounds.right - painter.width - 4,
    );
    final top = (point.dy - painter.height / 2).clamp(
      bounds.top + 4,
      bounds.bottom - painter.height - 4,
    );
    final rect = Rect.fromLTWH(
      left.toDouble(),
      top.toDouble(),
      painter.width,
      painter.height,
    );
    if (occupied.any((other) => other.overlaps(rect.inflate(4)))) return;
    occupied.add(rect);
    painter.paint(canvas, rect.topLeft);
  }

  void _drawArrivalLabels(Canvas canvas, _GlobeProjection projection) {
    for (final airport in airports) {
      final name = normalizedMapLabel(airport.name);
      if (name.isEmpty || isProvinceMapLabel(name)) continue;
      var arrived = false;
      for (var routeIndex = 0; routeIndex < routes.length; routeIndex++) {
        if (routes[routeIndex].to.code != airport.code) continue;
        if (_routeProgressForIndex(routeIndex, routes.length) >= .999) {
          arrived = true;
          break;
        }
      }
      if (!arrived) continue;
      final point = projection.project(airport.latitude, airport.longitude);
      if (point == null) continue;
      final painter = TextPainter(
        text: TextSpan(
          text: name,
          style: const TextStyle(
            color: Color(0xfff4f6f8),
            fontSize: 11,
            fontWeight: FontWeight.w600,
            shadows: [Shadow(color: Color(0xff0b1015), blurRadius: 3)],
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: 132);
      final topLeft = point + Offset(8, -painter.height - 6);
      painter.paint(canvas, topLeft);
    }
  }

  void _drawSelectedLabel(Canvas canvas, _GlobeProjection projection) {
    final label = selectedLabel?.trim();
    final coordinate = selectedCoordinate;
    if (label == null || label.isEmpty || coordinate == null) return;
    final point = projection.project(coordinate.latitude, coordinate.longitude);
    if (point == null) return;
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Color(0xfff4f6f8),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 160);
    final padding = const EdgeInsets.symmetric(horizontal: 9, vertical: 6);
    var left = point.dx + 10;
    var top = point.dy - painter.height - 13;
    final bounds = projection.bounds;
    final labelWidth = painter.width + padding.horizontal;
    final labelHeight = painter.height + padding.vertical;
    left = left.clamp(bounds.left + 6, bounds.right - labelWidth - 6);
    top = top.clamp(bounds.top + 6, bounds.bottom - labelHeight - 6);
    final rect = Rect.fromLTWH(left, top, labelWidth, labelHeight);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(10)),
      Paint()..color = const Color(0xff101820),
    );
    painter.paint(canvas, Offset(left + padding.left, top + padding.top));
  }

  MapSelection? selectionAt(Offset position, Size size, {double radius = 26}) {
    final projection = _projectionFor(size);
    double distanceTo(Offset point) => (point - position).distance;

    if (mode == MapMode.travelFootprint) {
      final hits =
          places.where((place) {
            if (!place.isVisited) return false;
            final point = projection.project(place.latitude, place.longitude);
            return point != null && distanceTo(point) <= radius;
          }).toList()..sort((a, b) {
            final aPoint = projection.project(a.latitude, a.longitude)!;
            final bPoint = projection.project(b.latitude, b.longitude)!;
            return distanceTo(aPoint).compareTo(distanceTo(bPoint));
          });
      return hits.isEmpty ? null : MapSelection(places: hits);
    }

    final airportHits =
        airports.where((airport) {
          if (!_hasRenderedRoute(airport)) return false;
          final point = projection.project(airport.latitude, airport.longitude);
          return point != null && distanceTo(point) <= radius;
        }).toList()..sort((a, b) {
          final aPoint = projection.project(a.latitude, a.longitude)!;
          final bPoint = projection.project(b.latitude, b.longitude)!;
          return distanceTo(aPoint).compareTo(distanceTo(bPoint));
        });
    if (airportHits.isNotEmpty) return MapSelection(airports: airportHits);

    MapRoute? nearestRoute;
    var bestDistance = radius;
    for (final route in routes) {
      final points = _greatCircleRoute(route);
      for (var index = 1; index < points.length; index++) {
        final start = projection.projectElevated(
          points[index - 1].latitude,
          points[index - 1].longitude,
          _routeLift((index - 1) / (points.length - 1), route),
        );
        final end = projection.projectElevated(
          points[index].latitude,
          points[index].longitude,
          _routeLift(index / (points.length - 1), route),
        );
        if (start == null || end == null) continue;
        final delta = end - start;
        final lengthSquared = delta.distanceSquared;
        if (lengthSquared == 0) continue;
        final t =
            (((position - start).dx * delta.dx +
                        (position - start).dy * delta.dy) /
                    lengthSquared)
                .clamp(0.0, 1.0)
                .toDouble();
        final distance = (position - (start + delta * t)).distance;
        if (distance < bestDistance) {
          bestDistance = distance;
          nearestRoute = route;
        }
      }
    }
    return nearestRoute == null ? null : MapSelection(route: nearestRoute);
  }

  String? labelForSelection(MapSelection selection) {
    if (selection.airports.isNotEmpty) {
      final name = normalizedMapLabel(selection.airports.first.name);
      return name.isEmpty ? selection.airports.first.code : name;
    }
    if (selection.places.isNotEmpty) {
      final name = normalizedMapLabel(selection.places.first.name);
      return name.isEmpty ? null : name;
    }
    final route = selection.route;
    if (route == null) return null;
    final from = normalizedMapLabel(route.from.name);
    final to = normalizedMapLabel(route.to.name);
    if (from.isEmpty) return to.isEmpty ? null : to;
    if (to.isEmpty) return from;
    return '$from → $to';
  }

  MapCoordinate? coordinateForSelection(MapSelection selection) {
    if (selection.airports.isNotEmpty) {
      final airport = selection.airports.first;
      return MapCoordinate(airport.latitude, airport.longitude);
    }
    if (selection.places.isNotEmpty) {
      final place = selection.places.first;
      return MapCoordinate(place.latitude, place.longitude);
    }
    final route = selection.route;
    if (route == null) return null;
    return MapCoordinate(route.to.latitude, route.to.longitude);
  }

  _GlobeProjection _projectionFor(Size size) => _GlobeProjection(
    center: size.center(Offset.zero),
    radius: math.min(size.width, size.height) * .39 * scale,
    yaw: yaw,
    pitch: pitch,
  );

  void _drawRouteAnimationPlane(Canvas canvas, _GlobeProjection projection) {
    if (routes.isEmpty) return;
    final progress = routeAnimationProgress.clamp(0.0, 1.0).toDouble();
    // Once the last leg settles, leave the completed route artwork and
    // destination markers in place without leaving a plane parked on top.
    if (progress >= .999) return;
    final scaled = progress * routes.length;
    final index = math
        .min(math.max(scaled.floor(), 0), routes.length - 1)
        .toInt();
    final localWindowProgress = progress >= 1
        ? 1.0
        : (scaled - index).clamp(0.0, 1.0).toDouble();
    final localProgress = Curves.easeInOutCubic.transform(
      (localWindowProgress / _routeTravelShare).clamp(0.0, 1.0).toDouble(),
    );
    final route = _greatCircleRoute(routes[index]);
    if (route.length < 2) return;
    final current = _interpolateRoute(route, localProgress);
    final before = _interpolateRoute(
      route,
      (localProgress - .018).clamp(0.0, 1.0).toDouble(),
    );
    final after = _interpolateRoute(
      route,
      (localProgress + .018).clamp(0.0, 1.0).toDouble(),
    );
    final position = projection.projectElevated(
      current.latitude,
      current.longitude,
      _routeLift(localProgress, routes[index]),
    );
    final beforePoint = projection.projectElevated(
      before.latitude,
      before.longitude,
      _routeLift(
        (localProgress - .018).clamp(0.0, 1.0).toDouble(),
        routes[index],
      ),
    );
    final afterPoint = projection.projectElevated(
      after.latitude,
      after.longitude,
      _routeLift(
        (localProgress + .018).clamp(0.0, 1.0).toDouble(),
        routes[index],
      ),
    );
    if (position == null) return;

    final color = _routeColors[index % _routeColors.length];
    final painter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(Icons.flight_rounded.codePoint),
        style: TextStyle(
          color: color,
          fontFamily: Icons.flight_rounded.fontFamily,
          package: Icons.flight_rounded.fontPackage,
          fontSize: 28,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    // Use a centred tangent so the nose follows the local curvature rather
    // than aiming at the route's final airport. At either endpoint, fall back
    // to the one-sided tangent that is still available on screen.
    final tangentStart = beforePoint ?? position;
    final tangentEnd = afterPoint ?? position;
    if (tangentStart == tangentEnd) return;
    canvas.save();
    canvas.translate(position.dx, position.dy);
    canvas.rotate(
      math.atan2(
            tangentEnd.dy - tangentStart.dy,
            tangentEnd.dx - tangentStart.dx,
          ) +
          math.pi / 2,
    );
    painter.paint(canvas, Offset(-painter.width / 2, -painter.height / 2));
    canvas.restore();
  }

  double _routeProgressForIndex(int index, int count) {
    final windowProgress = _routeWindowProgressForIndex(index, count);
    return Curves.easeInOutCubic.transform(
      (windowProgress / _routeTravelShare).clamp(0.0, 1.0).toDouble(),
    );
  }

  double _routeWindowProgressForIndex(int index, int count) {
    final progress = routeAnimationProgress.clamp(0.0, 1.0).toDouble();
    if (count <= 1) return progress;
    final start = index / count;
    return ((progress - start) * count).clamp(0.0, 1.0).toDouble();
  }

  List<_GlobeRoutePoint> _partialRoute(
    List<MapCoordinate> route,
    double progress,
  ) {
    if (route.length < 2) return const [];
    final normalized = progress.clamp(0.0, 1.0).toDouble();
    final position = normalized * (route.length - 1);
    final last = position.floor().clamp(0, route.length - 1).toInt();
    final result = <_GlobeRoutePoint>[
      for (var index = 0; index <= last; index++)
        _GlobeRoutePoint(route[index], index / (route.length - 1)),
    ];
    if (last < route.length - 1) {
      result.add(
        _GlobeRoutePoint(_interpolateRoute(route, normalized), normalized),
      );
    }
    return result;
  }

  Path _elevatedRoutePath(
    _GlobeProjection projection,
    List<_GlobeRoutePoint> points,
    MapRoute route,
  ) {
    final path = Path();
    var active = false;
    _GlobeRoutePoint? previous;
    Offset? previousPoint;
    Offset? project(_GlobeRoutePoint p) => projection.projectElevated(
      p.coordinate.latitude,
      p.coordinate.longitude,
      _routeLift(p.progress, route),
    );
    for (final routePoint in points) {
      final point = project(routePoint);
      if (previous != null && (previousPoint == null) != (point == null)) {
        var low = previous.progress;
        var high = routePoint.progress;
        Offset? boundary = previousPoint ?? point;
        for (var iteration = 0; iteration < 16; iteration++) {
          final t = (low + high) / 2;
          final sample = project(
            _GlobeRoutePoint(_coordinateAtRouteProgress(route, t), t),
          );
          if (sample != null) boundary = sample;
          if ((sample != null) == (previousPoint != null)) {
            low = t;
          } else {
            high = t;
          }
        }
        if (boundary != null) {
          if (active) {
            path.lineTo(boundary.dx, boundary.dy);
          } else {
            path.moveTo(boundary.dx, boundary.dy);
            active = true;
          }
        }
      }
      previous = routePoint;
      previousPoint = point;
      if (point == null) {
        active = false;
        continue;
      }
      if (!active) {
        path.moveTo(point.dx, point.dy);
        active = true;
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    return path;
  }

  double _routeLift(double progress, MapRoute route) {
    final angle = _surfaceAngleDegrees(
      _GlobeCoordinate(route.from.latitude, route.from.longitude),
      _GlobeCoordinate(route.to.latitude, route.to.longitude),
    );
    final height = (angle / 180 * .10).clamp(.008, .075);
    return math.sin(progress.clamp(0.0, 1.0) * math.pi) * height;
  }

  MapCoordinate _interpolateRoute(List<MapCoordinate> route, double progress) {
    final position = progress.clamp(0.0, 1.0) * (route.length - 1);
    final index = position.floor().clamp(0, route.length - 2).toInt();
    final local = position - index;
    final from = route[index];
    final to = route[index + 1];
    final coordinate = _interpolateGlobeCoordinate(
      _GlobeCoordinate(from.latitude, from.longitude),
      _GlobeCoordinate(to.latitude, to.longitude),
      local,
    );
    return MapCoordinate(coordinate.latitude, coordinate.longitude);
  }

  List<MapCoordinate> _greatCircleRoute(MapRoute route) {
    final cached = _routeSamples[route];
    if (cached != null) return cached;
    final start = _vectorFor(route.from.latitude, route.from.longitude);
    final end = _vectorFor(route.to.latitude, route.to.longitude);
    final dot = (start.x * end.x + start.y * end.y + start.z * end.z)
        .clamp(-1.0, 1.0)
        .toDouble();
    final angle = math.acos(dot);
    final steps = math.max(48, math.min(180, (angle * 180 / math.pi).ceil()));
    final sinAngle = math.sin(angle);
    return _routeSamples[route] = [
      for (var index = 0; index <= steps; index++)
        _coordinateFor(
          sinAngle.abs() < .000001
              ? start
              : _GlobeVector(
                  x:
                      (math.sin((1 - index / steps) * angle) / sinAngle) *
                          start.x +
                      (math.sin(index / steps * angle) / sinAngle) * end.x,
                  y:
                      (math.sin((1 - index / steps) * angle) / sinAngle) *
                          start.y +
                      (math.sin(index / steps * angle) / sinAngle) * end.y,
                  z:
                      (math.sin((1 - index / steps) * angle) / sinAngle) *
                          start.z +
                      (math.sin(index / steps * angle) / sinAngle) * end.z,
                ),
        ),
    ];
  }

  _GlobeVector _vectorFor(double latitude, double longitude) {
    final lat = latitude * math.pi / 180;
    final lon = longitude * math.pi / 180;
    final cosLatitude = math.cos(lat);
    return _GlobeVector(
      x: cosLatitude * math.sin(lon),
      y: math.sin(lat),
      z: cosLatitude * math.cos(lon),
    );
  }

  MapCoordinate _coordinateFor(_GlobeVector vector) => MapCoordinate(
    math.asin(vector.y.clamp(-1.0, 1.0).toDouble()) * 180 / math.pi,
    math.atan2(vector.x, vector.z) * 180 / math.pi,
  );

  void _drawSphericalLine(
    Canvas canvas,
    _GlobeProjection projection,
    List<_GlobeCoordinate> coordinates,
    Paint paint,
  ) {
    canvas.drawPath(_visiblePath(projection, coordinates), paint);
  }

  Path _visiblePath(
    _GlobeProjection projection,
    List<_GlobeCoordinate> coordinates, {
    bool closeRuns = false,
  }) {
    if (coordinates.isEmpty) return Path();
    final sampledCoordinates = _densifyForHorizon(projection, coordinates);
    final path = Path();
    var active = false;
    var visiblePoints = 0;
    _GlobeCoordinate? previousCoordinate;
    var previousVisible = false;
    for (final coordinate in sampledCoordinates) {
      final point = projection.project(
        coordinate.latitude,
        coordinate.longitude,
      );
      final visible = point != null;
      if (previousCoordinate != null && visible != previousVisible) {
        final horizon = _horizonIntersection(
          projection,
          previousCoordinate,
          coordinate,
          previousVisible,
        );
        if (previousVisible) {
          if (active) {
            path.lineTo(horizon.dx, horizon.dy);
            visiblePoints++;
            if (closeRuns && visiblePoints >= 3) path.close();
          }
          active = false;
          visiblePoints = 0;
        } else {
          path.moveTo(horizon.dx, horizon.dy);
          active = true;
          visiblePoints = 1;
        }
      }
      if (!visible) {
        if (active && closeRuns && visiblePoints >= 3) path.close();
        active = false;
        visiblePoints = 0;
      } else {
        if (!active) {
          path.moveTo(point.dx, point.dy);
          active = true;
          visiblePoints = 1;
        } else {
          path.lineTo(point.dx, point.dy);
          visiblePoints++;
        }
      }
      previousCoordinate = coordinate;
      previousVisible = visible;
    }
    if (active && closeRuns && visiblePoints >= 3) path.close();
    return path;
  }

  /// Inserts a midpoint when a coarse GeoJSON edge can cross the horizon
  /// between two vertices. Sampling only the source vertices is not enough:
  /// a long coastline segment can be visible at both ends while passing
  /// behind the sphere in the middle, which produces the apparent fragments
  /// seen while the globe rotates.
  List<_GlobeCoordinate> _densifyForHorizon(
    _GlobeProjection projection,
    List<_GlobeCoordinate> coordinates,
  ) {
    if (coordinates.length < 2) return coordinates;
    final result = <_GlobeCoordinate>[coordinates.first];
    for (var index = 1; index < coordinates.length; index++) {
      final segment = _subdivideGlobeSegment(
        projection,
        coordinates[index - 1],
        coordinates[index],
      );
      result.addAll(segment.skip(1));
    }
    return result;
  }

  List<_GlobeCoordinate> _subdivideGlobeSegment(
    _GlobeProjection projection,
    _GlobeCoordinate from,
    _GlobeCoordinate to, {
    int depth = 0,
  }) {
    const maxDepth = 5;
    final midpoint = _interpolateGlobeCoordinate(from, to, .5);
    final fromVisible = projection.isVisible(from.latitude, from.longitude);
    final midpointVisible = projection.isVisible(
      midpoint.latitude,
      midpoint.longitude,
    );
    final toVisible = projection.isVisible(to.latitude, to.longitude);
    final angularDistance = _surfaceAngleDegrees(from, to);
    final shouldSplit =
        depth < maxDepth &&
        (fromVisible != midpointVisible ||
            midpointVisible != toVisible ||
            angularDistance > 16);
    if (!shouldSplit) return [from, to];

    final first = _subdivideGlobeSegment(
      projection,
      from,
      midpoint,
      depth: depth + 1,
    );
    final second = _subdivideGlobeSegment(
      projection,
      midpoint,
      to,
      depth: depth + 1,
    );
    return [...first, ...second.skip(1)];
  }

  double _surfaceAngleDegrees(_GlobeCoordinate from, _GlobeCoordinate to) {
    final first = _vectorFor(from.latitude, from.longitude);
    final second = _vectorFor(to.latitude, to.longitude);
    final dot = (first.x * second.x + first.y * second.y + first.z * second.z)
        .clamp(-1.0, 1.0)
        .toDouble();
    return math.acos(dot) * 180 / math.pi;
  }

  _GlobeCoordinate _interpolateGlobeCoordinate(
    _GlobeCoordinate from,
    _GlobeCoordinate to,
    double progress,
  ) {
    final first = _vectorFor(from.latitude, from.longitude);
    final second = _vectorFor(to.latitude, to.longitude);
    final dot = (first.x * second.x + first.y * second.y + first.z * second.z)
        .clamp(-1.0, 1.0)
        .toDouble();
    final angle = math.acos(dot);
    final sine = math.sin(angle);
    if (sine.abs() < .000001) {
      return _GlobeCoordinate(
        from.latitude + (to.latitude - from.latitude) * progress,
        from.longitude + (to.longitude - from.longitude) * progress,
      );
    }
    final firstWeight = math.sin((1 - progress) * angle) / sine;
    final secondWeight = math.sin(progress * angle) / sine;
    final coordinate = _coordinateFor(
      _GlobeVector(
        x: firstWeight * first.x + secondWeight * second.x,
        y: firstWeight * first.y + secondWeight * second.y,
        z: firstWeight * first.z + secondWeight * second.z,
      ),
    );
    return _GlobeCoordinate(coordinate.latitude, coordinate.longitude);
  }

  Offset _horizonIntersection(
    _GlobeProjection projection,
    _GlobeCoordinate from,
    _GlobeCoordinate to,
    bool fromVisible,
  ) {
    var low = 0.0;
    var high = 1.0;
    for (var iteration = 0; iteration < 14; iteration++) {
      final middle = (low + high) / 2;
      final coordinate = _interpolateGlobeCoordinate(from, to, middle);
      if (projection.isVisible(coordinate.latitude, coordinate.longitude) ==
          fromVisible) {
        low = middle;
      } else {
        high = middle;
      }
    }
    final coordinate = _interpolateGlobeCoordinate(
      from,
      to,
      fromVisible ? low : high,
    );
    return projection.project(coordinate.latitude, coordinate.longitude) ??
        Offset.zero;
  }

  @override
  bool shouldRepaint(covariant GlobePainter old) =>
      old.data != data ||
      old.surfaceShader != surfaceShader ||
      old.mode != mode ||
      old.airports != airports ||
      old.routes != routes ||
      old.places != places ||
      old.yaw != yaw ||
      old.pitch != pitch ||
      old.scale != scale ||
      old.routeAnimationProgress != routeAnimationProgress ||
      old.showRouteAnimationPlane != showRouteAnimationPlane ||
      old.showLabels != showLabels ||
      old.selectedLabel != selectedLabel ||
      old.selectedCoordinate != selectedCoordinate;
}

class _GlobeProjection {
  const _GlobeProjection({
    required this.center,
    required this.radius,
    required this.yaw,
    required this.pitch,
  });

  final Offset center;
  final double radius;
  final double yaw;
  final double pitch;

  Rect get bounds => Rect.fromCircle(center: center, radius: radius);

  Offset? project(double latitude, double longitude) {
    final projected = _project(latitude, longitude);
    if (projected.front < 0) return null;
    return projected.point;
  }

  /// Projects an elevated route point and performs an actual depth check
  /// against the opaque sphere. An arc can therefore rise above the rim of
  /// the globe without drawing its hidden half through the earth.
  Offset? projectElevated(double latitude, double longitude, double elevation) {
    final projected = _project(
      latitude,
      longitude,
      elevation: elevation.clamp(0.0, .5).toDouble(),
    );
    final screenDistanceSquared =
        projected.screenX * projected.screenX +
        projected.screenY * projected.screenY;
    if (screenDistanceSquared > 1) return projected.point;
    final sphereFront = math.sqrt(math.max(0.0, 1 - screenDistanceSquared));
    return projected.front * projected.radial >= sphereFront - .000001
        ? projected.point
        : null;
  }

  bool isVisible(double latitude, double longitude) =>
      _project(latitude, longitude).front >= 0;

  _GlobeProjectionValue _project(
    double latitude,
    double longitude, {
    double elevation = 0,
  }) {
    final lat = latitude * math.pi / 180;
    final lon = longitude * math.pi / 180;
    final cosLatitude = math.cos(lat);
    final original = _GlobeVector(
      x: cosLatitude * math.sin(lon),
      y: math.sin(lat),
      z: cosLatitude * math.cos(lon),
    );
    final cosYaw = math.cos(yaw);
    final sinYaw = math.sin(yaw);
    final rotatedX = original.x * cosYaw + original.z * sinYaw;
    final rotatedZ = -original.x * sinYaw + original.z * cosYaw;
    final cosPitch = math.cos(pitch);
    final sinPitch = math.sin(pitch);
    final rotatedY = original.y * cosPitch - rotatedZ * sinPitch;
    final front = original.y * sinPitch + rotatedZ * cosPitch;
    final radial = 1 + elevation;
    return _GlobeProjectionValue(
      point: Offset(
        center.dx + rotatedX * radius * radial,
        center.dy - rotatedY * radius * radial,
      ),
      front: front,
      radial: radial,
      screenX: rotatedX * radial,
      screenY: rotatedY * radial,
    );
  }
}

class _GlobeProjectionValue {
  const _GlobeProjectionValue({
    required this.point,
    required this.front,
    required this.radial,
    required this.screenX,
    required this.screenY,
  });
  final Offset point;
  final double front;
  final double radial;
  final double screenX;
  final double screenY;
}

class _GlobeVector {
  const _GlobeVector({required this.x, required this.y, required this.z});
  final double x;
  final double y;
  final double z;
}

class _GlobeCoordinate {
  const _GlobeCoordinate(this.latitude, this.longitude);
  final double latitude;
  final double longitude;
}

class _GlobeRoutePoint {
  const _GlobeRoutePoint(this.coordinate, this.progress);
  final MapCoordinate coordinate;
  final double progress;
}
