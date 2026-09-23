import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'geojson_map_data.dart';
import 'galaxy_background.dart';
import 'globe_surface.dart';
import 'map_models.dart';
import '../../ui/theme/app_theme.dart';

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
    this.active = true,
    this.airports = const [],
    this.routes = const [],
    this.places = const [],
    this.routeAnimationProgress = 1,
    this.showRouteAnimationPlane = false,
    this.userLocation,
    this.focusCoordinate,
    this.focusSignal = 0,
    this.onSelection,
    this.onInteractionChanged,
    this.resetSignal = 0,
    this.loader = const GeoJsonMapLoader(),
  });

  final MapMode mode;

  /// Whether this map is the visible projection. Inactive home maps stay
  /// mounted so their camera survives a projection switch, but their entry
  /// and idle-rotation animations remain paused.
  final bool active;
  final List<MapAirport> airports;
  final List<MapRoute> routes;
  final List<MapPlace> places;
  final double routeAnimationProgress;
  final bool showRouteAnimationPlane;
  final MapCoordinate? userLocation;
  final MapCoordinate? focusCoordinate;
  final int focusSignal;
  final ValueChanged<MapSelection>? onSelection;
  final ValueChanged<bool>? onInteractionChanged;
  // Nullable keeps hot reload compatible with a State created before this
  // optional control was added; a missing value behaves like the initial 0.
  final int? resetSignal;
  final GeoJsonMapLoader loader;

  @override
  State<GlobeMap> createState() => _GlobeMapState();
}

/// Mutable camera values used directly by [GlobePainter].
///
/// Keeping the camera in the painter's repaint listenable lets drag, momentum,
/// entry, and idle-rotation frames repaint only the globe layer instead of
/// rebuilding the surrounding [FutureBuilder], layout, and gesture widgets.
class GlobeCamera extends ChangeNotifier {
  GlobeCamera({
    this.yaw = 0,
    this.pitch = 0,
    this.scale = 1,
    this.entryScale = 1,
    this.entryYawOffset = 0,
    this.entryArtworkOpacity = 1,
  });

  double yaw;
  double pitch;
  double scale;
  double entryScale;
  double entryYawOffset;
  double entryArtworkOpacity;

  void update({
    double? yaw,
    double? pitch,
    double? scale,
    double? entryScale,
    double? entryYawOffset,
    double? entryArtworkOpacity,
    bool notify = true,
  }) {
    final nextYaw = yaw ?? this.yaw;
    final nextPitch = pitch ?? this.pitch;
    final nextScale = scale ?? this.scale;
    final nextEntryScale = entryScale ?? this.entryScale;
    final nextEntryYawOffset = entryYawOffset ?? this.entryYawOffset;
    final nextEntryArtworkOpacity =
        entryArtworkOpacity ?? this.entryArtworkOpacity;
    if (nextYaw == this.yaw &&
        nextPitch == this.pitch &&
        nextScale == this.scale &&
        nextEntryScale == this.entryScale &&
        nextEntryYawOffset == this.entryYawOffset &&
        nextEntryArtworkOpacity == this.entryArtworkOpacity) {
      return;
    }
    this.yaw = nextYaw;
    this.pitch = nextPitch;
    this.scale = nextScale;
    this.entryScale = nextEntryScale;
    this.entryYawOffset = nextEntryYawOffset;
    this.entryArtworkOpacity = nextEntryArtworkOpacity;
    if (notify) notifyListeners();
  }
}

class _GlobeMapState extends State<GlobeMap> with TickerProviderStateMixin {
  static const _entryDuration = Duration(milliseconds: 2000);
  static const _entryStartScale = 2.3;
  // Positive yaw advances eastward like the globe's idle rotation, so enter
  // from a negative offset and rotate forward into the resting orientation.
  static const _entryStartYawOffset = -math.pi * .4;
  static const _autoRotationDuration = Duration(seconds: 120);

  late Future<({GeoJsonMapBundle data, GlobeSurface surface})> _future;
  ui.FragmentShader? _surfaceShader;
  late final AnimationController _momentum;
  AnimationController? _entryControllerValue;
  AnimationController? _autoRotateControllerValue;
  late final AnimationController _focusController;
  double _releaseYaw = 0;
  double _releasePitch = 0;
  Offset _releaseVelocity = Offset.zero;
  bool _pinching = false;
  late final GlobeCamera _camera;
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
  double _focusStartYaw = 0;
  double _focusStartPitch = 0;
  double _focusTargetYaw = 0;
  double _focusTargetPitch = 0;
  late SolarPosition _solarPosition;
  Timer? _solarTimer;
  String? _selectedLabel;
  MapCoordinate? _selectedCoordinate;

  @override
  void initState() {
    super.initState();
    _camera = GlobeCamera(
      yaw: -.35,
      pitch: .12,
      entryScale: _entryStartScale,
      entryYawOffset: _entryStartYawOffset,
      entryArtworkOpacity: 0,
    );
    _focusController =
        AnimationController(
            vsync: this,
            duration: const Duration(milliseconds: 420),
          )
          ..addListener(_handleFocusTick)
          ..addStatusListener(_handleFocusStatus);
    _solarPosition = SolarPosition.now();
    _solarTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      final next = SolarPosition.now();
      if (next.x == _solarPosition.x &&
          next.y == _solarPosition.y &&
          next.z == _solarPosition.z) {
        return;
      }
      setState(() => _solarPosition = next);
    });
    _future = _loadScene();
    _momentum =
        AnimationController(
            vsync: this,
            duration: const Duration(milliseconds: 900),
          )
          ..addListener(() {
            final travel = (1 - math.exp(-6 * _momentum.value)) / 6;
            _camera.update(
              yaw: _releaseYaw + _releaseVelocity.dx * travel,
              pitch: (_releasePitch + _releaseVelocity.dy * travel)
                  .clamp(-math.pi / 2, math.pi / 2)
                  .toDouble(),
            );
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
    final surface = await GlobeSurface.load(data.land);
    return (data: data, surface: surface);
  }

  bool get _following =>
      widget.showRouteAnimationPlane && widget.routeAnimationProgress < .999;

  void _handleEntryTick() {
    if (!mounted) return;
    final rawProgress = _entryController.value.clamp(0.0, 1.0).toDouble();
    // Keep the globe's shrinking and eastward spin on one shared trajectory.
    // The ease-out carries the initial hero momentum into a coordinated,
    // gentle settle instead of letting rotation finish ahead of the scale.
    final progress = Curves.easeOutCubic.transform(rawProgress);
    final artworkProgress = Curves.easeOutCubic.transform(
      ((rawProgress - .48) / .52).clamp(0.0, 1.0).toDouble(),
    );
    _camera.update(
      entryScale: _entryStartScale + (1 - _entryStartScale) * progress,
      entryYawOffset: _entryStartYawOffset * (1 - progress),
      entryArtworkOpacity: artworkProgress,
    );
  }

  void _handleEntryStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _camera.update(entryScale: 1, entryYawOffset: 0, entryArtworkOpacity: 1);
      _maybeResumeAutoRotation();
    }
  }

  void _handleAutoRotationTick() {
    if (!mounted ||
        !widget.active ||
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
    _camera.update(yaw: _wrappedAngle(_camera.yaw + delta * math.pi * 2));
  }

  void _handleFocusTick() {
    if (!mounted) return;
    final progress = Curves.easeOutCubic.transform(_focusController.value);
    _camera.update(
      yaw: _focusStartYaw + (_focusTargetYaw - _focusStartYaw) * progress,
      pitch:
          _focusStartPitch + (_focusTargetPitch - _focusStartPitch) * progress,
    );
  }

  void _handleFocusStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) _maybeResumeAutoRotation();
  }

  void _focusCoordinate(MapCoordinate coordinate) {
    _focusController.stop();
    _momentum.stop();
    _pauseAutoRotation();
    _focusStartYaw = _camera.yaw;
    final targetYaw = -coordinate.longitude * math.pi / 180;
    _focusTargetYaw =
        _focusStartYaw + _wrappedAngle(targetYaw - _focusStartYaw);
    _focusStartPitch = _camera.pitch;
    _focusTargetPitch = (coordinate.latitude * math.pi / 180)
        .clamp(-math.pi / 2, math.pi / 2)
        .toDouble();
    if (MediaQuery.disableAnimationsOf(context)) {
      _camera.update(yaw: _focusTargetYaw, pitch: _focusTargetPitch);
      _maybeResumeAutoRotation();
      return;
    }
    _focusController.forward(from: 0);
  }

  void _startPresentationIfNeeded() {
    if (_presentationStarted || !mounted || !widget.active) return;
    _presentationStarted = true;
    if (_following || MediaQuery.disableAnimationsOf(context)) {
      _entryController.stop();
      _entryController.value = 1;
      _camera.update(entryScale: 1, entryYawOffset: 0, entryArtworkOpacity: 1);
      _maybeResumeAutoRotation();
      return;
    }
    _camera.update(
      entryScale: _entryStartScale,
      entryYawOffset: _entryStartYawOffset,
      entryArtworkOpacity: 0,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_presentationStarted) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        _entryController.value = 1;
        _camera.update(
          entryScale: 1,
          entryYawOffset: 0,
          entryArtworkOpacity: 1,
        );
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

  // HomePage rebuilds while a map gesture starts/ends so it can update the
  // bottom navigation state. Its derived lists are new Dart list instances on
  // each rebuild, even when the records themselves did not change. Comparing
  // the list identity here made every drag look like a data refresh: the
  // FutureBuilder was restarted and the globe entry scale briefly returned to
  // .86, which users experienced as the globe snapping back after a swipe.
  // Compare the values that are actually used to build the globe surface so a
  // parent rebuild preserves the current camera and gesture position.
  static bool _sameMapPlaces(List<MapPlace> first, List<MapPlace> second) {
    if (identical(first, second)) return true;
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index++) {
      final a = first[index];
      final b = second[index];
      if (a.name != b.name ||
          a.latitude != b.latitude ||
          a.longitude != b.longitude ||
          a.isVisited != b.isVisited ||
          a.countryCode != b.countryCode ||
          a.visits != b.visits ||
          a.id != b.id ||
          a.visitedAt != b.visitedAt ||
          a.isDeletable != b.isDeletable) {
        return false;
      }
    }
    return true;
  }

  void _resumeAutoRotation() {
    if (_autoRotationRunning ||
        !widget.active ||
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
    while (result > math.pi) {
      result -= math.pi * 2;
    }
    while (result < -math.pi) {
      result += math.pi * 2;
    }
    return result;
  }

  @override
  void dispose() {
    _solarTimer?.cancel();
    _entryControllerValue
      ?..removeListener(_handleEntryTick)
      ..removeStatusListener(_handleEntryStatus)
      ..dispose();
    _autoRotateControllerValue
      ?..removeListener(_handleAutoRotationTick)
      ..dispose();
    _focusController
      ..removeListener(_handleFocusTick)
      ..removeStatusListener(_handleFocusStatus)
      ..dispose();
    _momentum.dispose();
    _camera.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant GlobeMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final activeChanged = oldWidget.active != widget.active;
    if (activeChanged && !widget.active) {
      _momentum.stop();
      _focusController.stop();
      _pauseAutoRotation();
      _entryControllerValue?.stop();
      _camera.update(entryScale: 1, entryYawOffset: 0, entryArtworkOpacity: 1);
      _reportInteraction(false);
    }
    if (oldWidget.loader != widget.loader) {
      _surfaceShader = null;
      _future = _loadScene();
      _resetPresentation();
    }
    final modeChanged = oldWidget.mode != widget.mode;
    final placesChanged =
        widget.mode == MapMode.travelFootprint &&
        !_sameMapPlaces(oldWidget.places, widget.places);
    if (modeChanged || placesChanged) {
      if (modeChanged) {
        // Both map modes share the same earth surface. Switching only changes
        // markers and routes, so the current camera and shader can stay put.
        _momentum.stop();
        _entryController.stop();
        _entryController.value = 1;
        _presentationStarted = true;
        _maybeResumeAutoRotation();
      } else {
        _resetPresentation();
      }
    }
    if ((oldWidget.resetSignal ?? 0) != (widget.resetSignal ?? 0)) {
      _momentum.stop();
      _camera.update(
        yaw: -.35,
        pitch: .12,
        scale: 1,
        entryScale: _entryStartScale,
        entryYawOffset: _entryStartYawOffset,
        entryArtworkOpacity: 0,
      );
      _followYawOffset = 0;
      _followPitchOffset = 0;
      _showLabels = false;
      _selectedLabel = null;
      _selectedCoordinate = null;
      _resetPresentation();
    }
    if (oldWidget.focusSignal != widget.focusSignal &&
        widget.focusCoordinate != null) {
      _focusCoordinate(widget.focusCoordinate!);
    }
    if (activeChanged && widget.active) {
      // Preserve the exact final camera pose, then stage a temporary hero
      // entrance around it. The rotation is an offset, not a camera reset.
      _momentum.stop();
      _focusController.stop();
      _resetPresentation();
      _startPresentationIfNeeded();
    }
    if (!oldWidget.showRouteAnimationPlane && widget.showRouteAnimationPlane) {
      _followYawOffset = 0;
      _followPitchOffset = 0;
      if (_entryController.isAnimating) {
        _entryController.stop();
        _entryController.value = 1;
        _camera.update(
          entryScale: 1,
          entryYawOffset: 0,
          entryArtworkOpacity: 1,
        );
      }
    }
    if (!widget.active) {
      _pauseAutoRotation();
    } else if (_following) {
      _pauseAutoRotation();
    } else {
      _maybeResumeAutoRotation();
    }
  }

  void _onScaleStart(ScaleStartDetails details) {
    if (_entryController.isAnimating) {
      // Fold the transient hero transform into the real camera before handing
      // control to the gesture, so the globe stays exactly under the finger.
      final visualYaw = _wrappedAngle(_camera.yaw + _camera.entryYawOffset);
      final visualScale = (_camera.scale * _camera.entryScale)
          .clamp(.82, 2.5)
          .toDouble();
      _entryController.stop();
      _entryController.value = 1;
      _camera.update(
        yaw: visualYaw,
        scale: visualScale,
        entryScale: 1,
        entryYawOffset: 0,
        entryArtworkOpacity: 1,
      );
    }
    _presentationStarted = true;
    _pauseAutoRotation();
    _reportInteraction(true);
    _momentum.stop();
    _pinching = false;
    _startYaw = _camera.yaw;
    _startPitch = _camera.pitch;
    _startScale = _camera.scale;
    _startFocalPoint = details.focalPoint;
    _startFollowYawOffset = _followYawOffset;
    _startFollowPitchOffset = _followPitchOffset;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final delta = details.focalPoint - _startFocalPoint;
    _pinching = _pinching || details.pointerCount > 1;
    double? nextYaw;
    double? nextPitch;
    if (_following) {
      // Keep the aircraft follow camera adjustable without allowing a drag
      // to push the active flight permanently behind the globe.
      final nextYawOffset = (_startFollowYawOffset + delta.dx / 240)
          .clamp(-.62, .62)
          .toDouble();
      final nextPitchOffset = (_startFollowPitchOffset + delta.dy / 240)
          .clamp(-.48, .48)
          .toDouble();
      nextYaw = _camera.yaw + nextYawOffset - _followYawOffset;
      nextPitch = (_camera.pitch + nextPitchOffset - _followPitchOffset)
          .clamp(-math.pi / 2, math.pi / 2)
          .toDouble();
      _followYawOffset = nextYawOffset;
      _followPitchOffset = nextPitchOffset;
    } else {
      nextYaw = _startYaw + delta.dx / 240;
      nextPitch = (_startPitch + delta.dy / 240)
          .clamp(-math.pi / 2, math.pi / 2)
          .toDouble();
    }
    _camera.update(
      yaw: nextYaw,
      pitch: nextPitch,
      scale: (_startScale * details.scale).clamp(.82, 2.5).toDouble(),
    );
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
    _releaseYaw = _camera.yaw;
    _releasePitch = _camera.pitch;
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
      // Globe mode is an independent visual world. The app theme still owns
      // the surrounding controls, while the Earth keeps natural day/night
      // colors in both Ice White and Dark Night Green.
      const lightPalette = false;
      if (snapshot.connectionState != ConnectionState.done) {
        return ColoredBox(
          color: lightPalette
              ? const Color(0xfff6f1ed)
              : const Color(0xff000000),
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
        return ColoredBox(
          color: lightPalette
              ? const Color(0xfff6f1ed)
              : const Color(0xff000000),
          child: Center(
            child: Text(
              '地球加载失败',
              style: TextStyle(
                color: lightPalette
                    ? const Color(0xff24324f)
                    : AppThemeColors.dark.textPrimary,
              ),
            ),
          ),
        );
      }
      _surfaceShader ??= snapshot.data!.surface.createShader();
      _startPresentationIfNeeded();
      final animationCamera = _following
          ? GlobePainter.animationCameraForProgress(
              widget.routes,
              widget.routeAnimationProgress,
            )
          : null;
      if (animationCamera != null) {
        _camera.update(
          yaw: animationCamera.yaw + _followYawOffset,
          pitch: (animationCamera.pitch + _followPitchOffset)
              .clamp(-math.pi / 2, math.pi / 2)
              .toDouble(),
          // The parent route-animation frame already rebuilds this widget.
          notify: false,
        );
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
            userLocation: widget.userLocation,
            camera: _camera,
            solarPosition: _solarPosition,
            routeAnimationProgress: widget.routeAnimationProgress,
            showRouteAnimationPlane: widget.showRouteAnimationPlane,
            drawBackdrop: false,
            lightPalette: lightPalette,
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
            child: Stack(
              fit: StackFit.expand,
              children: [
                RepaintBoundary(
                  child: CustomPaint(
                    painter: GlobeBackdropPainter(lightPalette: lightPalette),
                  ),
                ),
                RepaintBoundary(
                  child: CustomPaint(
                    painter: painter,
                    child: const SizedBox.expand(),
                  ),
                ),
              ],
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
    this.camera,
    this.solarPosition = const SolarPosition(x: 0, y: 1, z: 0),
    this.yaw = 0,
    this.pitch = 0,
    this.scale = 1,
    this.routeAnimationProgress = 1,
    this.showRouteAnimationPlane = false,
    this.showLabels = false,
    this.drawBackdrop = true,
    this.lightPalette = false,
    this.userLocation,
    this.selectedLabel,
    this.selectedCoordinate,
  }) : super(repaint: camera);

  final GeoJsonMapBundle data;
  final ui.FragmentShader? surfaceShader;
  final MapMode mode;
  final List<MapAirport> airports;
  final List<MapRoute> routes;
  final List<MapPlace> places;
  final GlobeCamera? camera;
  final SolarPosition solarPosition;
  final double yaw;
  final double pitch;
  final double scale;
  final double routeAnimationProgress;
  final bool showRouteAnimationPlane;
  final bool showLabels;
  final bool drawBackdrop;
  final bool lightPalette;
  final MapCoordinate? userLocation;
  final String? selectedLabel;
  final MapCoordinate? selectedCoordinate;

  double get _yaw => (camera?.yaw ?? yaw) + (camera?.entryYawOffset ?? 0);
  double get _pitch => camera?.pitch ?? pitch;
  double get _scale => (camera?.scale ?? scale) * (camera?.entryScale ?? 1);
  double get _artworkOpacity => camera?.entryArtworkOpacity ?? 1;

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

  // Keep the globe's route hue independent of the app theme, with enough
  // chroma and depth to remain distinct over sunlit land and ocean.
  static const _globeRouteColor = Color(0xff9682de);
  static const _darkRouteColors = <Color>[
    _globeRouteColor,
    _globeRouteColor,
    _globeRouteColor,
    _globeRouteColor,
    _globeRouteColor,
  ];
  static const _lightRouteColors = <Color>[
    _globeRouteColor,
    _globeRouteColor,
    _globeRouteColor,
    _globeRouteColor,
    _globeRouteColor,
  ];
  static const _darkPointColor = Color(0xffa8e85c);
  static const _darkTravelColors = <Color>[
    _darkPointColor,
    _darkPointColor,
    _darkPointColor,
    _darkPointColor,
    _darkPointColor,
  ];
  static const _lightTravelColors = <Color>[
    Color(0xff78a2d2),
    Color(0xff78a2d2),
    Color(0xffeaf3b2),
    Color(0xff78a2d2),
    Color(0xffb4cbe7),
  ];

  List<Color> get _routeColors =>
      lightPalette ? _lightRouteColors : _darkRouteColors;

  List<Color> get _travelColors =>
      lightPalette ? _lightTravelColors : _darkTravelColors;

  static final _routeGeometries = Expando<_GlobeRouteGeometry>();

  static _GlobeRouteGeometry _geometryFor(MapRoute route) {
    final cached = _routeGeometries[route];
    if (cached != null) return cached;
    final start = _cameraVectorFor(route.from.latitude, route.from.longitude);
    final end = _cameraVectorFor(route.to.latitude, route.to.longitude);
    final dot = (start.x * end.x + start.y * end.y + start.z * end.z)
        .clamp(-1.0, 1.0)
        .toDouble();
    final angle = math.acos(dot);
    final sine = math.sin(angle);
    final stepCount = math.max(
      48,
      math.min(180, (angle * 180 / math.pi).ceil()),
    );
    final height = (angle / math.pi * .065).clamp(.006, .050).toDouble();
    return _routeGeometries[route] = _GlobeRouteGeometry(
      start: start,
      end: end,
      angle: angle,
      sine: sine,
      stepCount: stepCount,
      maxLift: height,
    );
  }

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
    final geometry = _geometryFor(route);
    final start = geometry.start;
    final end = geometry.end;
    final angle = geometry.angle;
    final sine = geometry.sine;
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
    if (drawBackdrop) {
      GlobeBackdropPainter(lightPalette: lightPalette).paint(canvas, size);
    }
    final radius = math.min(size.width, size.height) * .43 * _scale;
    final projection = _GlobeProjection(
      center: Offset(size.width / 2, size.height * .46),
      radius: radius,
      yaw: _yaw,
      pitch: _pitch,
    );
    final sphere = Path()..addOval(projection.bounds);
    // Keep the atmosphere as a broad, low-alpha falloff. The shader and the
    // painted circle use the same radius so the glow can fade all the way out
    // instead of being clipped into a hard outer ring.
    final atmosphereRadius = radius * 1.20;
    canvas.drawCircle(
      projection.center,
      atmosphereRadius,
      Paint()
        ..shader =
            RadialGradient(
              colors: lightPalette
                  ? const [
                      Color(0x0078a2d2),
                      Color(0x0078a2d2),
                      Color(0x0878a2d2),
                      Color(0x1e78a2d2),
                      Color(0x124f83b6),
                      Color(0x0078a2d2),
                    ]
                  : const [
                      Color(0x0078a2d2),
                      Color(0x0078a2d2),
                      Color(0x0878a2d2),
                      Color(0x1e78a2d2),
                      Color(0x124f83b6),
                      Color(0x0078a2d2),
                    ],
              stops: const [0, .64, .78, .88, .96, 1],
            ).createShader(
              Rect.fromCircle(
                center: projection.center,
                radius: atmosphereRadius,
              ),
            ),
    );
    final shader = surfaceShader;
    if (shader != null) {
      GlobeSurface.paint(
        canvas,
        shader: shader,
        center: projection.center,
        radius: radius,
        yaw: _yaw,
        pitch: _pitch,
        solarPosition: solarPosition,
      );
    } else {
      canvas.drawPath(
        sphere,
        Paint()
          ..color = lightPalette
              ? const Color(0xff78a2d2)
              : AppThemeColors.dark.surfaceDeep,
      );
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
    _drawUserLocation(canvas, projection);
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
        ..color = const Color(0xff78a2d2).withValues(alpha: .42)
        ..style = PaintingStyle.stroke
        ..strokeWidth = .7,
    );
  }

  void _drawGrid(Canvas canvas, _GlobeProjection projection) {
    final paint = Paint()
      ..color =
          (lightPalette ? const Color(0xff78a2d2) : AppThemeColors.dark.border)
              .withValues(alpha: (lightPalette ? .08 : .018) * _artworkOpacity)
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
      final samples = _greatCircleRoute(route);
      if (samples.length < 2 || progress <= 0) continue;
      final path = _elevatedRoutePath(projection, samples, progress, route);
      if (path.getBounds().isEmpty) continue;
      canvas.drawPath(
        path,
        Paint()
          ..color = _routeColors[index % _routeColors.length].withValues(
            alpha: .78 * _artworkOpacity,
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
      const color = _darkPointColor;
      if (!_isAirportVisibleForPlayback(airport)) continue;
      _drawGlowingMarker(
        canvas,
        point,
        color,
        coreRadius: 1.8,
        opacity: _artworkOpacity,
      );
    }
  }

  void _drawGlowingMarker(
    Canvas canvas,
    Offset point,
    Color color, {
    required double coreRadius,
    double opacity = 1,
  }) {
    // Keep flight and footprint points on one shared, restrained glow style.
    canvas.drawCircle(
      point,
      coreRadius * 3.4,
      Paint()..color = color.withValues(alpha: .035 * opacity),
    );
    canvas.drawCircle(
      point,
      coreRadius * 2.2,
      Paint()..color = color.withValues(alpha: .095 * opacity),
    );
    canvas.drawCircle(
      point,
      coreRadius,
      Paint()..color = color.withValues(alpha: opacity),
    );
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
      final color = lightPalette
          ? _travelColors[index % _travelColors.length]
          : _darkPointColor;
      _drawGlowingMarker(
        canvas,
        point,
        color,
        coreRadius: 1.8,
        opacity: _artworkOpacity,
      );
    }
  }

  void _drawUserLocation(Canvas canvas, _GlobeProjection projection) {
    final coordinate = userLocation;
    if (coordinate == null) return;
    final point = projection.project(coordinate.latitude, coordinate.longitude);
    if (point == null) return;
    const color = Color(0xff72b9ff);
    canvas.drawCircle(
      point,
      12,
      Paint()..color = color.withValues(alpha: .18 * _artworkOpacity),
    );
    canvas.drawCircle(
      point,
      6.5,
      Paint()..color = Colors.white.withValues(alpha: _artworkOpacity),
    );
    canvas.drawCircle(
      point,
      4.5,
      Paint()..color = color.withValues(alpha: _artworkOpacity),
    );
    canvas.drawCircle(
      point,
      1.6,
      Paint()..color = Colors.white.withValues(alpha: _artworkOpacity),
    );
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
        style: TextStyle(
          color: lightPalette
              ? const Color(0xff24324f).withValues(alpha: _artworkOpacity)
              : AppThemeColors.dark.textPrimary.withValues(
                  alpha: _artworkOpacity,
                ),
          fontSize: 10,
          fontWeight: FontWeight.w500,
          shadows: [
            Shadow(
              color: lightPalette
                  ? const Color(0xfffdfdf5).withValues(alpha: _artworkOpacity)
                  : AppThemeColors.dark.background.withValues(
                      alpha: _artworkOpacity,
                    ),
              blurRadius: 3,
            ),
          ],
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
          style: TextStyle(
            color: lightPalette
                ? const Color(0xff24324f).withValues(alpha: _artworkOpacity)
                : AppThemeColors.dark.textPrimary.withValues(
                    alpha: _artworkOpacity,
                  ),
            fontSize: 11,
            fontWeight: FontWeight.w600,
            shadows: [
              Shadow(
                color: lightPalette
                    ? const Color(0xfffdfdf5).withValues(alpha: _artworkOpacity)
                    : AppThemeColors.dark.background.withValues(
                        alpha: _artworkOpacity,
                      ),
                blurRadius: 3,
              ),
            ],
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
        style: TextStyle(
          color: lightPalette
              ? const Color(0xff24324f).withValues(alpha: _artworkOpacity)
              : AppThemeColors.dark.textPrimary.withValues(
                  alpha: _artworkOpacity,
                ),
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
      Paint()
        ..color = lightPalette
            ? const Color(0xfffdfdf5).withValues(alpha: _artworkOpacity)
            : AppThemeColors.dark.surfaceElevated.withValues(
                alpha: _artworkOpacity,
              ),
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
    radius: math.min(size.width, size.height) * .39 * _scale,
    yaw: _yaw,
    pitch: _pitch,
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

  Path _elevatedRoutePath(
    _GlobeProjection projection,
    List<MapCoordinate> points,
    double progress,
    MapRoute route,
  ) {
    final normalized = progress.clamp(0.0, 1.0).toDouble();
    final position = normalized * (points.length - 1);
    final last = position.floor().clamp(0, points.length - 1).toInt();
    final hasPartialEnd = last < points.length - 1;
    final itemCount = last + 1 + (hasPartialEnd ? 1 : 0);
    final path = Path();
    var active = false;
    MapCoordinate? previousCoordinate;
    var previousProgress = 0.0;
    Offset? previousPoint;
    Offset? project(MapCoordinate coordinate, double routeProgress) =>
        projection.projectElevated(
          coordinate.latitude,
          coordinate.longitude,
          _routeLift(routeProgress, route),
        );
    for (var index = 0; index < itemCount; index++) {
      final isPartialEnd = hasPartialEnd && index == itemCount - 1;
      final routeProgress = isPartialEnd
          ? normalized
          : index / (points.length - 1);
      final coordinate = isPartialEnd
          ? _interpolateRoute(points, normalized)
          : points[index];
      final point = project(coordinate, routeProgress);
      if (previousCoordinate != null &&
          (previousPoint == null) != (point == null)) {
        var low = previousProgress;
        var high = routeProgress;
        Offset? boundary = previousPoint ?? point;
        for (var iteration = 0; iteration < 16; iteration++) {
          final t = (low + high) / 2;
          final sample = project(_coordinateAtRouteProgress(route, t), t);
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
      previousCoordinate = coordinate;
      previousProgress = routeProgress;
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
    final height = _geometryFor(route).maxLift;
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
    final geometry = _geometryFor(route);
    final cached = geometry.samples;
    if (cached != null) return cached;
    final start = geometry.start;
    final end = geometry.end;
    final angle = geometry.angle;
    final steps = geometry.stepCount;
    final sinAngle = geometry.sine;
    return geometry.samples = [
      for (var index = 0; index <= geometry.stepCount; index++)
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
      old.camera != camera ||
      old.solarPosition.x != solarPosition.x ||
      old.solarPosition.y != solarPosition.y ||
      old.solarPosition.z != solarPosition.z ||
      old.yaw != yaw ||
      old.pitch != pitch ||
      old.scale != scale ||
      old.routeAnimationProgress != routeAnimationProgress ||
      old.showRouteAnimationPlane != showRouteAnimationPlane ||
      old.showLabels != showLabels ||
      old.drawBackdrop != drawBackdrop ||
      old.userLocation != userLocation ||
      old.selectedLabel != selectedLabel ||
      old.selectedCoordinate != selectedCoordinate;
}

class _GlobeProjection {
  _GlobeProjection({
    required this.center,
    required this.radius,
    required this.yaw,
    required this.pitch,
  }) : _cosYaw = math.cos(yaw),
       _sinYaw = math.sin(yaw),
       _cosPitch = math.cos(pitch),
       _sinPitch = math.sin(pitch);

  final Offset center;
  final double radius;
  final double yaw;
  final double pitch;
  final double _cosYaw;
  final double _sinYaw;
  final double _cosPitch;
  final double _sinPitch;

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
    final rotatedX = original.x * _cosYaw + original.z * _sinYaw;
    final rotatedZ = -original.x * _sinYaw + original.z * _cosYaw;
    final rotatedY = original.y * _cosPitch - rotatedZ * _sinPitch;
    final front = original.y * _sinPitch + rotatedZ * _cosPitch;
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

class _GlobeRouteGeometry {
  _GlobeRouteGeometry({
    required this.start,
    required this.end,
    required this.angle,
    required this.sine,
    required this.stepCount,
    required this.maxLift,
  });

  final _GlobeVector start;
  final _GlobeVector end;
  final double angle;
  final double sine;
  final int stepCount;
  final double maxLift;
  List<MapCoordinate>? samples;
}

class _GlobeCoordinate {
  const _GlobeCoordinate(this.latitude, this.longitude);
  final double latitude;
  final double longitude;
}
