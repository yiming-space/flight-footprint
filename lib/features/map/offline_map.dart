import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'flat_map_painter.dart';
import 'geojson_map_data.dart';
import 'globe_map.dart';
import 'map_explorer_controls.dart';
import 'map_projection.dart';
import 'map_models.dart';
import '../../core/localization/app_strings.dart';
import '../../ui/theme/app_theme.dart';

class OfflineMap extends StatefulWidget {
  const OfflineMap({
    super.key,
    this.assetPath = 'assets/data/world-countries-50m.geo.json',
    this.mode = MapMode.flight,
    this.airports = const [],
    this.routes = const [],
    this.places = const [],
    this.fitPoints,
    this.fitZoomMultiplier = 1,
    this.fitVerticalBias = 0,
    this.fitDataHeightFactor = .68,
    this.fitDataCenterY = .5,
    this.fitToData = true,
    this.fillViewportHeight = false,
    this.coverViewport = false,
    this.compactWorldViewport = false,
    this.horizontalPadding = 16,
    this.verticalPadding = 14,
    this.showGrid = true,
    this.transparentBackground = false,
    this.bottomFade = false,
    this.excludePolarShelf = false,
    this.animateRouteReveal = false,
    this.routeRevealProgress = 1,
    this.routeAnimationProgress,
    this.showRouteAnimationPlane = false,
    this.enableInteraction = false,
    this.horizontalWrap = false,
    this.useLightPalette,
    this.userLocation,
    this.focusCoordinate,
    this.focusSignal = 0,
    this.onMapTap,
    this.onSelection,
    this.onInteractionChanged,
    this.onPlaceLongPress,
    this.loader = const GeoJsonMapLoader(),
  });

  final String assetPath;
  final MapMode mode;
  final List<MapAirport> airports;
  final List<MapRoute> routes;
  final List<MapPlace> places;

  /// Optional shared viewport source. When provided, the initial center and
  /// zoom are calculated from these points regardless of the active layer.
  /// The home page uses flight airports here so switching to travel footprints
  /// keeps the exact same camera instead of fitting a second time.
  final List<MapCoordinate>? fitPoints;

  /// Extra initial zoom used by focused/full-screen maps. Manual pinch zoom
  /// still uses the same InteractiveViewer limits afterwards.
  final double fitZoomMultiplier;

  /// Moves a data-fitted scene vertically within the viewport. A negative
  /// value places the recorded routes higher, leaving room for an overlay
  /// such as the statistics area on a share card.
  final double fitVerticalBias;

  /// Fraction of the viewport height reserved for a data-fitted scene. The
  /// default preserves the original map behavior; share-card artwork can use
  /// a shorter upper region so route endpoints do not fall behind metrics.
  final double fitDataHeightFactor;

  /// Vertical center of the data-fitted scene as a normalized viewport value.
  /// `0.5` is the viewport center. This is useful when the lower part of the
  /// map is intentionally occupied by an overlay such as card statistics.
  final double fitDataCenterY;

  /// When false, keeps the complete world map in view. When true, the initial
  /// frame can centre on the recorded airports or cities before the user
  /// zooms back out to the same complete-world floor.
  final bool fitToData;

  /// Makes the complete world extent fill the viewport vertically. Fullscreen
  /// maps use this as their minimum zoom so the user never pinches out to a
  /// tiny horizontal strip; embedded dashboard maps keep the old complete-
  /// world-at-width behavior.
  final bool fillViewportHeight;

  /// Scales the complete map uniformly until the viewport is occupied in
  /// both dimensions. This is useful for wide foldable layouts: the world
  /// remains proportional, while the unused side gutters are cropped from
  /// the map scene instead of leaving the card visibly letterboxed.
  final bool coverViewport;

  /// Uses the passport's tighter latitude window while retaining the full
  /// longitude extent. This removes the unused Antarctic gutter without
  /// applying a non-uniform stretch to the world map.
  final bool compactWorldViewport;

  /// Insets used when fitting the projected world. Passport artwork uses
  /// zero insets so the complete land silhouette occupies more of its map
  /// window without increasing the zoom and clipping a continent.
  final double horizontalPadding;
  final double verticalPadding;

  /// Dashboard maps show the coordinate grid; share cards hide it for a
  /// cleaner passport-like composition.
  final bool showGrid;

  /// Leaves the map canvas transparent so a surrounding composition can own
  /// its background and fade. Dashboard maps keep the opaque panel by default;
  /// passport cards opt in to prevent the translated map canvas from exposing
  /// a rectangular bottom edge over their gradient.
  final bool transparentBackground;

  /// Fades only the Antarctic landform into the transparent map surface before
  /// the scene transform is applied. Other continents and routes retain their
  /// original contrast.
  final bool bottomFade;

  /// Hides the clipped Antarctic outline in compact passport compositions.
  /// The base land fill remains visible, while the outline that can read as a
  /// straight edge beneath the map's fade is omitted.
  final bool excludePolarShelf;

  /// Animates route strokes when the supplied flight set changes. Kept off
  /// for ordinary maps; the passport card opts in for year transitions.
  final bool animateRouteReveal;

  /// Progressively reveals flight routes from departure to arrival. It is
  /// static by default so ordinary maps keep their existing behavior.
  final double routeRevealProgress;

  /// Optional external route timeline used by fullscreen controls. When
  /// supplied, it takes precedence over the small internal reveal used by
  /// passport/year transitions.
  final double? routeAnimationProgress;

  /// Shows a small moving aircraft at the head of the active route.
  final bool showRouteAnimationPlane;

  /// Embedded maps remain a quiet preview so vertical page scrolling is not
  /// hijacked by a map gesture. The dedicated full-screen map opts in.
  final bool enableInteraction;

  /// Full-screen maps repeat the world horizontally so panning across the
  /// date line never reveals an empty gutter. Embedded maps keep a single
  /// world copy and split route paths at the same seam.
  final bool horizontalWrap;

  /// Lets dashboard maps inherit the active app theme while allowing the
  /// shareable passport artwork to explicitly keep its dark palette.
  final bool? useLightPalette;

  /// Optional one-shot device position. It is rendered as a separate blue
  /// marker and never participates in flight or footprint data.
  final MapCoordinate? userLocation;

  /// When this signal changes, the map recentres on [focusCoordinate]. A
  /// separate signal lets the user tap Locate repeatedly at the same position.
  final MapCoordinate? focusCoordinate;
  final int focusSignal;
  final ValueChanged<MapCoordinate>? onMapTap;
  final ValueChanged<MapSelection>? onSelection;
  final ValueChanged<bool>? onInteractionChanged;
  final Future<void> Function(List<MapPlace> candidates)? onPlaceLongPress;
  final GeoJsonMapLoader loader;

  @override
  State<OfflineMap> createState() => _OfflineMapState();
}

/// A focused map surface used when the user wants to inspect a dense route or
/// footprint without the surrounding dashboard competing for space.
class MapFullscreenPage extends StatefulWidget {
  const MapFullscreenPage({
    super.key,
    required this.mode,
    required this.airports,
    required this.routes,
    required this.places,
    this.initialGlobeMode = false,
    this.onAddPlace,
    this.onPlaceLongPress,
    this.placesListenable,
    this.placesProvider,
    this.onSelection,
    this.restoreWindowOnDispose = true,
  });

  final MapMode mode;
  final List<MapAirport> airports;
  final List<MapRoute> routes;
  final List<MapPlace> places;
  final bool initialGlobeMode;
  final Future<void> Function(BuildContext context)? onAddPlace;
  final Future<void> Function(List<MapPlace> candidates)? onPlaceLongPress;
  final Listenable? placesListenable;
  final List<MapPlace> Function()? placesProvider;
  final void Function(BuildContext context, MapSelection selection)?
  onSelection;
  final bool restoreWindowOnDispose;

  @override
  State<MapFullscreenPage> createState() => _MapFullscreenPageState();
}

class _MapFullscreenPageState extends State<MapFullscreenPage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  // Full-screen map follows the app's portrait-first orientation. Landscape
  // remains available as an explicit user action from the floating toolbar.
  bool _landscape = false;
  bool _orientationChanging = false;
  bool _globeMode = false;
  bool _routeAnimationStarted = false;
  bool _mapInteracting = false;
  int _viewReset = 0;
  late List<MapPlace> _places;
  late List<MapRoute> _animationRoutes;
  late String _animationRouteSignature;
  AnimationController? _routeAnimation;

  /// Fullscreen animation treats repeated records with the same directed
  /// airport pair as one visual leg. The underlying flight list stays intact
  /// elsewhere in the app; this only prevents a duplicate flyover in the
  /// presentation map.
  static List<MapRoute> _deduplicateRoutes(List<MapRoute> routes) {
    final seen = <String>{};
    final result = <MapRoute>[];
    for (final route in routes) {
      final from = route.from.code.trim().toUpperCase();
      final to = route.to.code.trim().toUpperCase();
      final key = '$from->$to';
      if (seen.add(key)) result.add(route);
    }
    return result;
  }

  static String _routeSignature(List<MapRoute> routes) => [
    for (final route in routes)
      '${route.from.code.trim().toUpperCase()}->${route.to.code.trim().toUpperCase()}',
  ].join('|');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _globeMode = widget.initialGlobeMode;
    _places = widget.places;
    _animationRoutes = _deduplicateRoutes(widget.routes);
    _animationRouteSignature = _routeSignature(_animationRoutes);
    _routeController;
    widget.placesListenable?.addListener(_refreshPlaces);
  }

  @override
  void didChangeMetrics() {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    if (!_landscape || _orientationChanging) return;
    // Android can briefly reveal the system bars during a rotation. Reapply
    // immersive mode after the new layout has committed so no black status
    // strip is left above the edge-to-edge map.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _landscape) {
        unawaited(
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
        );
      }
    });
  }

  @override
  void didUpdateWidget(covariant MapFullscreenPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.placesListenable != widget.placesListenable) {
      oldWidget.placesListenable?.removeListener(_refreshPlaces);
      widget.placesListenable?.addListener(_refreshPlaces);
    }
    if (!identical(oldWidget.places, widget.places)) {
      _places = widget.places;
    }
    if (!identical(oldWidget.routes, widget.routes)) {
      final routes = _deduplicateRoutes(widget.routes);
      final signature = _routeSignature(routes);
      _animationRoutes = routes;
      if (_animationRouteSignature != signature) {
        _animationRouteSignature = signature;
        _routeController.duration = _routeAnimationDuration(routes.length);
        _routeController.value = 1;
        _routeAnimationStarted = false;
      }
    }
  }

  @override
  void reassemble() {
    super.reassemble();
    // Flutter preserves this State during hot reload. Keep the live preview
    // in sync with timing changes without requiring the user to leave the
    // fullscreen map first.
    _routeController.duration = _routeAnimationDuration(
      _animationRoutes.length,
    );
  }

  AnimationController get _routeController {
    return _routeAnimation ??= AnimationController(
      vsync: this,
      duration: _routeAnimationDuration(_animationRoutes.length),
      // Playback is explicitly requested. Keep its six-second leg timing
      // even when the platform asks decorative UI to reduce motion.
      animationBehavior: AnimationBehavior.preserve,
      value: 1,
    )..addStatusListener(_handleRouteAnimationStatus);
  }

  Duration _routeAnimationDuration(int count) {
    // Every unique leg gets the same fixed time. Geographic distance never
    // changes the rhythm, and the exact duration stays predictable when an
    // itinerary contains both short and long flights.
    return Duration(milliseconds: count.clamp(1, 1000) * 6000);
  }

  void _handleRouteAnimationStatus(AnimationStatus status) {
    if (!mounted) return;
    setState(() {});
  }

  void _toggleRouteAnimation() {
    if (_animationRoutes.isEmpty) return;
    final controller = _routeController;
    if (controller.isAnimating) {
      controller.stop();
      setState(() {});
      return;
    }
    setState(() => _routeAnimationStarted = true);
    if (controller.value >= .999) {
      controller.forward(from: 0);
    } else {
      controller.forward();
    }
  }

  String _routeAnimationTooltip(AppStrings strings) {
    final controller = _routeController;
    if (controller.isAnimating) return strings.t('pauseRoutes');
    if (_routeAnimationStarted && controller.value >= .999) {
      return strings.t('replayRoutes');
    }
    return strings.t('playRoutes');
  }

  IconData get _routeAnimationIcon {
    final controller = _routeController;
    if (controller.isAnimating) return Icons.pause_rounded;
    if (_routeAnimationStarted && controller.value >= .999) {
      return Icons.replay_rounded;
    }
    return Icons.play_arrow_rounded;
  }

  String _routeCaption(AppStrings strings) {
    final routes = _animationRoutes;
    if (!_routeAnimationStarted) {
      return strings.isZh ? '${routes.length} 条航线' : '${routes.length} routes';
    }
    final index = (_routeController.value * routes.length).floor().clamp(
      0,
      routes.length - 1,
    );
    final route = routes[index];
    return '${route.from.code} → ${route.to.code}   ·   ${index + 1} / ${routes.length}';
  }

  void _refreshPlaces() {
    final provider = widget.placesProvider;
    if (!mounted || provider == null) return;
    setState(() => _places = provider());
  }

  void _handleMapInteraction(bool interacting) {
    if (!mounted || _mapInteracting == interacting) return;
    setState(() => _mapInteracting = interacting);
  }

  Future<void> _toggleLandscape() async {
    if (_orientationChanging) return;
    await _setLandscape(!_landscape);
  }

  Future<void> _setLandscape(bool target) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    if (_orientationChanging) return;
    if (mounted) setState(() => _orientationChanging = true);

    bool windowReady;
    if (target) {
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      windowReady = await _waitForWindowShape(landscape: true);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
      ]);
      windowReady = await _waitForWindowShape(landscape: false);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }

    if (!mounted) return;
    if (!windowReady) {
      // Do not publish a new orientation state when Android did not commit
      // the requested bounds. This prevents a half-rotated map from being
      // treated as the stable destination of the transition.
      setState(() => _orientationChanging = false);
      return;
    }
    setState(() {
      _landscape = target;
      _orientationChanging = false;
    });
  }

  Future<bool> _waitForWindowShape({required bool landscape}) async {
    bool matches() {
      if (!mounted) return true;
      final view = View.of(context);
      final physicalSize = view.physicalSize;
      final physicalMatches = landscape
          ? physicalSize.width > physicalSize.height
          : physicalSize.height >= physicalSize.width;
      final size = MediaQuery.sizeOf(context);
      final logicalMatches = landscape
          ? size.width > size.height
          : size.height >= size.width;
      return physicalMatches && logicalMatches;
    }

    if (matches()) return true;
    final deadline = DateTime.now().add(const Duration(milliseconds: 2400));
    while (mounted && DateTime.now().isBefore(deadline)) {
      await WidgetsBinding.instance.endOfFrame;
      if (matches()) return true;
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
    return matches();
  }

  void _close() {
    Navigator.maybePop(context);
  }

  @override
  void dispose() {
    widget.placesListenable?.removeListener(_refreshPlaces);
    _routeAnimation
      ?..removeStatusListener(_handleRouteAnimationStatus)
      ..dispose();
    WidgetsBinding.instance.removeObserver(this);
    if (widget.restoreWindowOnDispose) unawaited(_restorePortraitWindow());
    super.dispose();
  }

  Future<void> _restorePortraitWindow() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final colors = context.appColors;
    final lightTheme = Theme.of(context).brightness == Brightness.light;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        // The bars are hidden by immersiveSticky. Transparent colors are also
        // important during the short hand-off while Android applies the new
        // orientation, otherwise the old status-bar background can flash as a
        // black strip over the map.
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        statusBarIconBrightness: lightTheme
            ? Brightness.dark
            : Brightness.light,
        systemNavigationBarIconBrightness: lightTheme
            ? Brightness.dark
            : Brightness.light,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
      ),
      child: Scaffold(
        backgroundColor: colors.background,
        resizeToAvoidBottomInset: false,
        body: Stack(
          fit: StackFit.expand,
          children: [
            RepaintBoundary(
              child: AnimatedBuilder(
                animation: _routeController,
                builder: (context, _) => Stack(
                  fit: StackFit.expand,
                  children: [
                    Offstage(
                      offstage: _globeMode,
                      child: TickerMode(
                        enabled: !_globeMode,
                        child: IgnorePointer(
                          ignoring: _globeMode,
                          child: OfflineMap(
                            key: ValueKey('flat-$_viewReset'),
                            mode: widget.mode,
                            airports: widget.airports,
                            routes: _animationRoutes,
                            places: _places,
                            // Center the first frame on the recorded routes or
                            // cities. The complete-world vertical extent
                            // remains the minimum zoom, so the user can always
                            // pinch back out to the whole map.
                            fitToData: true,
                            fillViewportHeight: true,
                            fitZoomMultiplier: 1,
                            enableInteraction: true,
                            horizontalWrap: true,
                            routeAnimationProgress: _routeController.value,
                            showRouteAnimationPlane: _routeAnimationStarted,
                            onInteractionChanged: _handleMapInteraction,
                            // Fullscreen flat maps follow the selected app
                            // theme; the light palette keeps the map readable
                            // without losing the existing interactions.
                            useLightPalette: null,
                            onPlaceLongPress: widget.onPlaceLongPress,
                            onSelection: widget.onSelection == null
                                ? null
                                : (selection) =>
                                      widget.onSelection!(context, selection),
                          ),
                        ),
                      ),
                    ),
                    Offstage(
                      offstage: !_globeMode,
                      child: TickerMode(
                        enabled: _globeMode,
                        child: IgnorePointer(
                          ignoring: !_globeMode,
                          child: GlobeMap(
                            active: _globeMode,
                            resetSignal: _viewReset,
                            mode: widget.mode,
                            // Travel footprint globe shows visited places only;
                            // flight arcs belong exclusively to flight mode.
                            routes: widget.mode == MapMode.flight
                                ? _animationRoutes
                                : const [],
                            airports: widget.airports,
                            places: _places,
                            routeAnimationProgress: _routeController.value,
                            showRouteAnimationPlane: _routeAnimationStarted,
                            onInteractionChanged: _handleMapInteraction,
                            onSelection: widget.onSelection == null
                                ? null
                                : (selection) =>
                                      widget.onSelection!(context, selection),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              child: SafeArea(
                minimum: const EdgeInsets.all(12),
                child: MapExplorerGlass(
                  blurEnabled:
                      !_mapInteracting && !_routeController.isAnimating,
                  child: MapExplorerButton(
                    label: strings.t('close'),
                    icon: Icons.close_rounded,
                    onPressed: _close,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: AnimatedBuilder(
                animation: _routeController,
                builder: (context, _) {
                  final hasRoutes =
                      widget.mode == MapMode.flight &&
                      _animationRoutes.isNotEmpty;
                  return MapExplorerControls(
                    globeMode: _globeMode,
                    mapInteracting:
                        _mapInteracting || _routeController.isAnimating,
                    landscape: _landscape,
                    onModeChanged: (globe) {
                      if (_globeMode != globe) {
                        setState(() => _globeMode = globe);
                      }
                    },
                    onOrientation:
                        _orientationChanging ||
                            (!Platform.isAndroid && !Platform.isIOS)
                        ? null
                        : _toggleLandscape,
                    onReset: () => setState(() => _viewReset++),
                    onPlayback: hasRoutes ? _toggleRouteAnimation : null,
                    playbackLabel: _routeAnimationTooltip(strings),
                    playbackIcon: _routeAnimationIcon,
                    progress: hasRoutes
                        ? (_routeAnimationStarted ? _routeController.value : 0)
                        : null,
                    routeCaption: hasRoutes ? _routeCaption(strings) : null,
                    onAddPlace:
                        widget.mode == MapMode.travelFootprint &&
                            widget.onAddPlace != null
                        ? () => unawaited(widget.onAddPlace!(context))
                        : null,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OfflineMapState extends State<OfflineMap> with TickerProviderStateMixin {
  late Future<GeoJsonMapBundle> _future;
  late final TransformationController _transform;
  // Keep this nullable so a hot reload that adds or changes the map's
  // repaint notifier can lazily initialize an already-mounted State object.
  // Flutter does not rerun initState for those objects.
  ValueNotifier<double>? _sceneScaleNotifier;
  AnimationController? _fitAnimation;
  CurvedAnimation? _fitCurve;
  AnimationController? _routeRevealAnimation;
  CurvedAnimation? _routeRevealCurve;
  Matrix4Tween? _fitTween;
  Matrix4? _pendingFitMatrix;
  int _pendingFitToken = 0;
  int _fitRevision = 0;
  int _scheduledFitRevision = -1;
  bool _showLabels = false;
  double _sceneScale = 1;
  // The interaction floor belongs to the complete map viewport, not to the
  // currently visited routes or cities. It is refreshed for each orientation.
  double _minScale = 1;
  Size? _lastMapSize;
  MillerProjectionViewport? _projectionViewport;
  FlatMapPainter? _lastPainter;
  Size? _lastFittedMapSize;
  bool _normalizingHorizontalPan = false;
  // Repainting the complete GeoJSON scene on every pinch update is much more
  // expensive than letting InteractiveViewer transform the retained layer.
  // Keep marker/line sizing stable during the gesture and refresh it once the
  // user's fingers leave the screen.
  bool _interactionActive = false;
  bool _hasPresentedFit = false;
  bool _fitAnimationActive = false;
  double _routeRevealProgress = 1;
  int _routeRevealGeneration = 0;
  Timer? _mapLongPressTimer;
  Offset? _mapPointerDownPosition;
  Matrix4? _mapPointerDownTransform;
  bool _mapPointerMoved = false;
  bool _mapLongPressTriggered = false;
  int _mapPointerCount = 0;

  @override
  void initState() {
    super.initState();
    _transform = TransformationController();
    _sceneScaleNotifier = ValueNotifier(_sceneScale);
    _transform.addListener(_onTransformChanged);
    _ensureAnimations();
    _future = _loadBundle();
  }

  void _ensureAnimations() {
    if (_fitAnimation == null || _fitCurve == null) {
      final fitAnimation = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 420),
      );
      final fitCurve = CurvedAnimation(
        parent: fitAnimation,
        curve: Curves.easeOutCubic,
      );
      _fitAnimation = fitAnimation;
      _fitCurve = fitCurve;
      fitAnimation.addListener(_applyFitAnimation);
      fitAnimation.addStatusListener(_handleFitAnimationStatus);
    }
    if (_routeRevealAnimation == null || _routeRevealCurve == null) {
      final routeRevealAnimation = AnimationController(
        vsync: this,
        // The route network needs more breathing room than the camera move,
        // especially when a world card contains many overlapping flights.
        duration: const Duration(milliseconds: 720),
      );
      final routeRevealCurve = CurvedAnimation(
        parent: routeRevealAnimation,
        curve: Curves.easeInOutCubic,
      );
      _routeRevealAnimation = routeRevealAnimation;
      _routeRevealCurve = routeRevealCurve;
      routeRevealAnimation.addListener(_applyRouteRevealAnimation);
    }
    // Keep an already-mounted controller in sync after a hot reload too.
    _routeRevealAnimation?.duration = const Duration(milliseconds: 720);
    _routeRevealCurve?.curve = Curves.easeInOutCubic;
  }

  @override
  void dispose() {
    _mapLongPressTimer?.cancel();
    _fitCurve?.dispose();
    _fitAnimation
      ?..removeListener(_applyFitAnimation)
      ..removeStatusListener(_handleFitAnimationStatus)
      ..dispose();
    _routeRevealCurve?.dispose();
    _routeRevealAnimation
      ?..removeListener(_applyRouteRevealAnimation)
      ..dispose();
    _transform.removeListener(_onTransformChanged);
    _transform.dispose();
    _sceneScaleNotifier?.dispose();
    super.dispose();
  }

  ValueNotifier<double> get _sceneScaleListenable =>
      _sceneScaleNotifier ??= ValueNotifier(_sceneScale);

  void _onTransformChanged() {
    if (!mounted) return;
    // Do not rewrite the controller while InteractiveViewer is processing a
    // gesture.  Assigning a second matrix from this listener races its
    // focal-point bookkeeping and can make a one-finger drag appear stuck.
    // The repeated world copies already cover the viewport during the active
    // gesture; normalize only after the gesture/inertia has settled.
    if (widget.horizontalWrap &&
        !_normalizingHorizontalPan &&
        !_interactionActive) {
      _normalizeHorizontalPan(_lastMapSize);
    }
    final scale = _transform.value
        .getMaxScaleOnAxis()
        .clamp(_minScale, 20.0)
        .toDouble();
    if (_interactionActive) {
      _sceneScale = scale;
      return;
    }
    if (widget.enableInteraction && (scale - _sceneScale).abs() < .01) {
      return;
    }
    _sceneScale = scale;
    // Camera fitting is a layout transition, not a user zoom gesture. Keep
    // the expensive painter static while the matrix moves, then update the
    // marker scale once at the end. User pinch/zoom still gets live feedback.
    if (_fitAnimationActive) return;
    final notifier = _sceneScaleListenable;
    if ((notifier.value - scale).abs() >= .01) {
      notifier.value = scale;
    }
  }

  void _handleFitAnimationStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed &&
        status != AnimationStatus.dismissed) {
      return;
    }
    _fitAnimationActive = false;
    _syncSceneScale();
  }

  void _syncSceneScale() {
    if (!mounted) return;
    final scale = _transform.value
        .getMaxScaleOnAxis()
        .clamp(_minScale, 20.0)
        .toDouble();
    _sceneScale = scale;
    final notifier = _sceneScaleListenable;
    if ((notifier.value - scale).abs() >= .01) {
      notifier.value = scale;
    }
  }

  void _applyFitAnimation() {
    final tween = _fitTween;
    final fitCurve = _fitCurve;
    if (!mounted || tween == null || fitCurve == null) return;
    _transform.value = tween.evaluate(fitCurve);
  }

  void _applyRouteRevealAnimation() {
    final routeRevealCurve = _routeRevealCurve;
    if (!mounted || routeRevealCurve == null) return;
    setState(() => _routeRevealProgress = routeRevealCurve.value);
  }

  void _queueRouteReveal() {
    _ensureAnimations();
    final animation = _routeRevealAnimation;
    if (animation == null) return;
    final generation = ++_routeRevealGeneration;
    animation.stop();
    _routeRevealProgress = 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _routeRevealGeneration) return;
      animation.forward(from: 0);
    });
  }

  void _commitPendingFit() {
    final pending = _pendingFitMatrix;
    if (pending == null) return;
    _pendingFitMatrix = null;
    _pendingFitToken++;
    _fitAnimation?.stop();
    _fitAnimationActive = false;
    _hasPresentedFit = true;
    _transform.value = Matrix4.copy(pending);
  }

  void _handleMapPointerDown(PointerDownEvent event, Size mapSize) {
    // A mode switch can schedule the new fit for the next frame. Commit that
    // target before taking the gesture snapshot so the first tap/drag cannot
    // start from the previous mode's camera.
    _commitPendingFit();
    _mapPointerCount++;
    // A second pointer means this is a pinch/scale gesture. Never let the
    // single-pointer long-press timer compete with InteractiveViewer.
    if (_mapPointerCount != 1) {
      _mapLongPressTimer?.cancel();
      _mapPointerMoved = true;
      return;
    }

    _mapPointerDownPosition = event.localPosition;
    // InteractiveViewer also listens to this pointer for pan/scale. Keep a
    // snapshot so a stationary tap cannot leave behind a tiny translation
    // caused by normal finger jitter.
    _mapPointerDownTransform = Matrix4.copy(_transform.value);
    _mapPointerMoved = false;
    _mapLongPressTriggered = false;
    _mapLongPressTimer?.cancel();
    if (widget.mode == MapMode.travelFootprint &&
        widget.onPlaceLongPress != null) {
      _mapLongPressTimer = Timer(const Duration(milliseconds: 500), () {
        if (!mounted ||
            _mapPointerCount != 1 ||
            _mapPointerMoved ||
            _mapPointerDownPosition == null) {
          return;
        }
        _mapLongPressTriggered = true;
        unawaited(
          _handlePlaceLongPressAt(
            _mapScenePosition(_mapPointerDownPosition!),
            mapSize,
          ),
        );
      });
    }
  }

  void _handleMapPointerMove(PointerMoveEvent event) {
    if (_mapPointerDownPosition == null || _mapPointerMoved) return;
    if ((event.localPosition - _mapPointerDownPosition!).distance > 12) {
      _mapPointerMoved = true;
      _mapLongPressTimer?.cancel();
    }
  }

  void _restoreTapTransform(Matrix4 transform) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _mapPointerCount != 0) return;
      _transform.value = Matrix4.copy(transform);
    });
  }

  void _handleMapPointerUp(PointerUpEvent event, Size mapSize) {
    final shouldTap =
        _mapPointerCount == 1 &&
        !_mapPointerMoved &&
        !_mapLongPressTriggered &&
        _mapPointerDownPosition != null;
    if (_mapPointerCount > 0) _mapPointerCount--;
    if (_mapPointerCount == 0) {
      final tapTransform = !_mapPointerMoved ? _mapPointerDownTransform : null;
      _mapLongPressTimer?.cancel();
      _mapPointerDownPosition = null;
      _mapPointerDownTransform = null;
      _mapPointerMoved = false;
      _mapLongPressTriggered = false;
      if (tapTransform != null) _restoreTapTransform(tapTransform);
    }
    if (shouldTap) {
      _handleMapTap(_mapScenePosition(event.localPosition), mapSize);
    }
  }

  void _handleMapPointerCancel(PointerCancelEvent event) {
    if (_mapPointerCount > 0) _mapPointerCount--;
    if (_mapPointerCount != 0) return;
    _mapLongPressTimer?.cancel();
    _mapPointerDownPosition = null;
    _mapPointerDownTransform = null;
    _mapPointerMoved = false;
    _mapLongPressTriggered = false;
  }

  void _handleMapTap(Offset position, Size mapSize) {
    final selection = _lastPainter?.selectionAt(position, mapSize);
    if (selection != null && widget.onSelection != null) {
      widget.onSelection!(selection);
      return;
    }
    setState(() => _showLabels = !_showLabels);
    widget.onMapTap?.call(
      MapCoordinate(
        90 - position.dy / mapSize.height * 180,
        position.dx / mapSize.width * 360 - 180,
      ),
    );
  }

  /// Pointer observers live in the viewport so they cannot compete with
  /// InteractiveViewer's scale recognizer. Convert their viewport coordinate
  /// back into the map scene before running the painter hit tests.
  Offset _mapScenePosition(Offset viewportPosition) =>
      _transform.toScene(viewportPosition);

  void _presentFit(Matrix4 target, {bool animate = true}) {
    _ensureAnimations();
    if (!_hasPresentedFit ||
        !animate ||
        MediaQuery.disableAnimationsOf(context)) {
      _fitAnimation?.stop();
      _fitAnimationActive = false;
      _transform.value = target;
      _hasPresentedFit = true;
      return;
    }

    // Retarget from the matrix currently on screen. This keeps a quick series
    // of year taps continuous instead of restarting each transition from the
    // previous logical target.
    final fitAnimation = _fitAnimation;
    if (fitAnimation == null) {
      _fitAnimationActive = false;
      _transform.value = target;
      return;
    }
    fitAnimation.stop();
    _fitAnimationActive = true;
    _fitTween = Matrix4Tween(
      begin: Matrix4.copy(_transform.value),
      end: Matrix4.copy(target),
    );
    fitAnimation.forward(from: 0);
  }

  void _scheduleFocus(MapCoordinate coordinate) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final size = _lastMapSize;
      if (size == null || size.isEmpty) return;
      final projection = _projectionFor(size);
      var projected = projection.toOffset(
        coordinate.latitude,
        coordinate.longitude,
      );
      // Choose the wrapped copy nearest to the current camera so locating a
      // point near the date line does not spin the map across the long way.
      if (widget.horizontalWrap) {
        final worldWidth = projection.worldPixelWidth;
        if (worldWidth > 0) {
          final sceneCenter = _transform.toScene(
            Offset(size.width / 2, size.height / 2),
          );
          final copies = ((projected.dx - sceneCenter.dx) / worldWidth).round();
          projected = Offset(projected.dx - copies * worldWidth, projected.dy);
        }
      }
      final scale = _transform.value
          .getMaxScaleOnAxis()
          .clamp(_minScale, 20.0)
          .toDouble();
      final baseX = (1 - scale) * size.width / 2;
      final baseY = (1 - scale) * size.height / 2;
      final maxPanX = size.width * (scale - 1) / 2;
      final maxPanY = size.height * (scale - 1) / 2;
      final panX = (size.width / 2 - projected.dx * scale - baseX).clamp(
        -maxPanX,
        maxPanX,
      );
      final panY = (size.height / 2 - projected.dy * scale - baseY).clamp(
        -maxPanY,
        maxPanY,
      );
      final target = Matrix4.identity()
        ..translateByDouble(size.width / 2 + panX, size.height / 2 + panY, 0, 1)
        ..scaleByDouble(scale, scale, 1, 1)
        ..translateByDouble(-size.width / 2, -size.height / 2, 0, 1);
      _presentFit(target);
    });
  }

  @override
  void didUpdateWidget(covariant OfflineMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final modeChanged = oldWidget.mode != widget.mode;
    if (oldWidget.assetPath != widget.assetPath ||
        oldWidget.loader != widget.loader) {
      _future = _loadBundle();
      _invalidateFit();
      _hasPresentedFit = false;
    }
    final fitInputsChanged =
        !_sameMapCoordinates(oldWidget.fitPoints, widget.fitPoints) ||
        !_sameMapAirports(oldWidget.airports, widget.airports) ||
        !_sameMapPlaces(oldWidget.places, widget.places) ||
        oldWidget.fitZoomMultiplier != widget.fitZoomMultiplier ||
        oldWidget.fitVerticalBias != widget.fitVerticalBias ||
        oldWidget.fitDataHeightFactor != widget.fitDataHeightFactor ||
        oldWidget.fitDataCenterY != widget.fitDataCenterY ||
        oldWidget.fitToData != widget.fitToData ||
        oldWidget.fillViewportHeight != widget.fillViewportHeight ||
        oldWidget.coverViewport != widget.coverViewport ||
        oldWidget.compactWorldViewport != widget.compactWorldViewport ||
        oldWidget.horizontalPadding != widget.horizontalPadding ||
        oldWidget.verticalPadding != widget.verticalPadding ||
        oldWidget.horizontalWrap != widget.horizontalWrap;
    if (fitInputsChanged) {
      _invalidateFit();
    } else if (modeChanged) {
      // Flight and footprint layers intentionally share the same fitPoints.
      // Changing only the layer must preserve the user's current pan/zoom;
      // stopping a pending presentation here also prevents the mode button
      // from looking like it moved the map by itself.
      _fitAnimation?.stop();
      _fitAnimationActive = false;
      _pendingFitToken++;
      _pendingFitMatrix = null;
    }
    if (oldWidget.focusSignal != widget.focusSignal &&
        widget.focusCoordinate != null) {
      _scheduleFocus(widget.focusCoordinate!);
    }
    final shouldRevealRoutes =
        widget.animateRouteReveal &&
        (oldWidget.routes != widget.routes ||
            oldWidget.mode != widget.mode ||
            !oldWidget.animateRouteReveal);
    if (shouldRevealRoutes) {
      _queueRouteReveal();
    } else if (!widget.animateRouteReveal) {
      _routeRevealAnimation?.stop();
      _routeRevealProgress = 1;
    }
  }

  Future<GeoJsonMapBundle> _loadBundle() async {
    if (widget.assetPath == 'assets/data/world-countries-50m.geo.json') {
      return widget.loader.loadBundle();
    }
    final countries = await widget.loader.load(widget.assetPath);
    return GeoJsonMapBundle(
      land: countries,
      countries: countries,
      provinces: const GeoJsonMapData(polygons: []),
      nationalBoundary: const GeoJsonMapData(polygons: []),
      internalBoundaries: const GeoJsonMapData(polygons: []),
      maritimeMarks: const GeoJsonMapData(polygons: []),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<GeoJsonMapBundle>(
    future: _future,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) {
        return Center(child: Text('地图加载失败：${snapshot.error}'));
      }
      final data = snapshot.data;
      if (data == null || data.land.polygons.isEmpty) {
        return const Center(child: Text('暂无地图数据'));
      }
      return LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : 800.0;
          final height = constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : width / 2;
          final mapSize = Size(width, height);
          _lastMapSize = mapSize;
          _scheduleFit(mapSize);
          // Keep the pointer observer outside the transformed scene.  A
          // Listener nested inside InteractiveViewer receives coordinates in
          // the transformed child space and can participate in the same hit
          // test as the scale recognizer; observing the viewport instead
          // leaves InteractiveViewer's one-/two-finger arena untouched while
          // still allowing us to provide map taps and long presses manually.
          Widget map = ValueListenableBuilder<double>(
            valueListenable: _sceneScaleListenable,
            builder: (context, sceneScale, _) => RepaintBoundary(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  RepaintBoundary(
                    child: CustomPaint(
                      size: mapSize,
                      isComplex: true,
                      painter: _mapPainter(
                        data,
                        sceneScale,
                        layer: FlatMapPaintLayer.base,
                      ),
                    ),
                  ),
                  RepaintBoundary(
                    child: CustomPaint(
                      size: mapSize,
                      isComplex: true,
                      willChange:
                          widget.showRouteAnimationPlane &&
                          (widget.routeAnimationProgress ?? 1) < .999,
                      painter: _lastPainter = _mapPainter(
                        data,
                        sceneScale,
                        layer: FlatMapPaintLayer.overlay,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
          if (!widget.enableInteraction) {
            // Keep the calculated data-centred fit in the embedded preview,
            // but leave drag/pinch gestures to the surrounding page.
            return Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (event) => _handleMapPointerDown(event, mapSize),
              onPointerMove: _handleMapPointerMove,
              onPointerUp: (event) => _handleMapPointerUp(event, mapSize),
              onPointerCancel: _handleMapPointerCancel,
              child: AnimatedBuilder(
                animation: _transform,
                child: RepaintBoundary(child: map),
                builder: (context, child) => Transform(
                  alignment: Alignment.topLeft,
                  transform: _transform.value,
                  child: child,
                ),
              ),
            );
          }
          return Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (event) => _handleMapPointerDown(event, mapSize),
            onPointerMove: _handleMapPointerMove,
            onPointerUp: (event) => _handleMapPointerUp(event, mapSize),
            onPointerCancel: _handleMapPointerCancel,
            child: InteractiveViewer(
              transformationController: _transform,
              panEnabled: true,
              scaleEnabled: true,
              // The complete-map vertical fill scale is the floor. Users can
              // explore closer, but a pinch-out can never shrink the world map
              // below the viewport-filling baseline (recomputed on rotation).
              minScale: _minScale,
              maxScale: 20,
              boundaryMargin: _boundaryMargin(mapSize),
              onInteractionStart: (_) {
                _interactionActive = true;
                widget.onInteractionChanged?.call(true);
                if (_fitAnimation?.isAnimating ?? false) {
                  _fitAnimation?.stop();
                  _fitAnimationActive = false;
                  _syncSceneScale();
                }
              },
              onInteractionEnd: (_) {
                _interactionActive = false;
                if (widget.horizontalWrap) {
                  _normalizeHorizontalPan(mapSize);
                }
                _syncSceneScale();
                widget.onInteractionChanged?.call(false);
              },
              child: map,
            ),
          );
        },
      );
    },
  );

  FlatMapPainter _mapPainter(
    GeoJsonMapBundle data,
    double sceneScale, {
    required FlatMapPaintLayer layer,
  }) => FlatMapPainter(
    data: data,
    airports: widget.airports,
    routes: widget.routes,
    places: widget.places,
    mode: widget.mode,
    showLabels: _showLabels,
    showGrid: widget.showGrid,
    transparentBackground: widget.transparentBackground,
    bottomFade: widget.bottomFade,
    excludePolarShelf: widget.excludePolarShelf,
    routeRevealProgress:
        widget.routeAnimationProgress ??
        (widget.animateRouteReveal ? _routeRevealProgress : 1),
    showRouteAnimationPlane: widget.showRouteAnimationPlane,
    compactWorldViewport: widget.compactWorldViewport,
    lightPalette:
        widget.useLightPalette ??
        Theme.of(context).brightness == Brightness.light,
    visualScale: sceneScale,
    horizontalPadding: widget.horizontalPadding,
    verticalPadding: widget.verticalPadding,
    horizontalWrap: widget.horizontalWrap,
    userLocation: widget.userLocation,
    paintLayer: layer,
  );

  Future<void> _handlePlaceLongPressAt(Offset position, Size mapSize) async {
    if (widget.onPlaceLongPress == null) return;
    final candidates = _placeCandidatesAt(position, mapSize);
    if (candidates.isEmpty) return;
    HapticFeedback.selectionClick();
    if (!mounted) return;
    await widget.onPlaceLongPress!(candidates);
  }

  List<MapPlace> _placeCandidatesAt(Offset position, Size mapSize) {
    final hitRadius = (44 / _sceneScale).clamp(8.0, 64.0).toDouble();
    final candidates = <({MapPlace place, double distance})>[];
    for (final place in widget.places) {
      // Only manually added footprints participate in deletion. Airports
      // inferred from flight records remain visible but are never removable
      // from the travel-footprint map.
      if (!place.isVisited || !place.isDeletable || place.id == null) continue;
      final projected = _projectPlace(place, mapSize);
      var dx = projected.dx - position.dx;
      if (widget.horizontalWrap) {
        dx = _wrappedDeltaX(dx, _worldPixelWidth(mapSize));
      }
      dx = dx.abs();
      final dy = projected.dy - position.dy;
      final distance = math.sqrt(dx * dx + dy * dy);
      if (distance <= hitRadius) {
        candidates.add((place: place, distance: distance));
      }
    }
    candidates.sort((a, b) => a.distance.compareTo(b.distance));
    return [for (final candidate in candidates) candidate.place];
  }

  Offset _projectPlace(MapPlace place, Size size) =>
      _projectCoordinate(place.latitude, place.longitude, size);

  Offset _projectCoordinate(double latitude, double longitude, Size size) {
    return _projectionFor(size).toOffset(latitude, longitude);
  }

  MillerProjectionViewport _projectionFor(Size size) {
    final cached = _projectionViewport;
    if (cached != null &&
        cached.size == size &&
        cached.horizontalPadding == widget.horizontalPadding &&
        cached.verticalPadding == widget.verticalPadding &&
        cached.minLatitude == _viewportMinLatitude &&
        cached.maxLatitude == _viewportMaxLatitude) {
      return cached;
    }
    return _projectionViewport = MillerCylindricalProjection.viewportForSize(
      size,
      horizontalPadding: widget.horizontalPadding,
      verticalPadding: widget.verticalPadding,
      minLatitude: _viewportMinLatitude,
      maxLatitude: _viewportMaxLatitude,
    );
  }

  double _worldPixelWidth(Size size) => _projectionFor(size).worldPixelWidth;

  double _wrappedDeltaX(double delta, double worldWidth) {
    if (worldWidth <= 0) return delta;
    if (delta <= worldWidth / 2 && delta >= -worldWidth / 2) return delta;
    return (delta + worldWidth / 2) % worldWidth - worldWidth / 2;
  }

  EdgeInsets _boundaryMargin(Size size) {
    final projection = _projectionFor(size);
    final worldWidth = projection.worldPixelWidth;
    final worldHeight = projection.bounds.height * projection.scale;
    // InteractiveViewer's boundary is expressed in scene coordinates. The
    // painter's world is centred inside the child canvas, so a portrait canvas
    // contains empty polar bands above and below the projected world. Negative
    // margins trim those bands from the interaction boundary; the viewport
    // can then never be dragged past the actual north/south world edges.
    final vertical = (worldHeight - size.height) / 2;
    if (!widget.horizontalWrap) {
      final horizontal = (worldWidth - size.width) / 2;
      return EdgeInsets.symmetric(horizontal: horizontal, vertical: vertical);
    }
    // Keep enough horizontal room for a complete wrapped cycle. The transform
    // listener recentres that translation after the gesture, so horizontal
    // panning remains continuous without weakening the vertical clamp.
    final horizontal = math.max(size.width * 2, worldWidth * 2);
    return EdgeInsets.symmetric(horizontal: horizontal, vertical: vertical);
  }

  void _normalizeHorizontalPan(Size? size) {
    if (size == null) return;
    final worldWidth = _worldPixelWidth(size);
    if (worldWidth <= 0) return;
    final matrix = _transform.value;
    final scale = matrix.getMaxScaleOnAxis();
    if (!scale.isFinite || scale <= 0) return;
    final baseTranslation = (1 - scale) * size.width / 2;
    var pan = matrix.storage[12] - baseTranslation;
    final cycle = worldWidth * scale;
    if (!cycle.isFinite || cycle <= 0) return;
    final normalizedPan = pan <= cycle / 2 && pan >= -cycle / 2
        ? pan
        : (pan + cycle / 2) % cycle - cycle / 2;
    if ((normalizedPan - pan).abs() < .5) return;
    final normalized = Matrix4.copy(matrix);
    normalized.storage[12] = baseTranslation + normalizedPan;
    _normalizingHorizontalPan = true;
    _transform.value = normalized;
    _normalizingHorizontalPan = false;
  }

  void _scheduleFit(Size size) {
    final revision = _fitRevision;
    if (_scheduledFitRevision == revision && _lastFittedMapSize == size) return;
    final points = _fitPointsForWidget();
    final sameFitRevision = _scheduledFitRevision == revision;
    _scheduledFitRevision = revision;
    // Fullscreen maps use the complete world's vertical extent as the floor.
    // This deliberately allows horizontal cropping in portrait orientation:
    // the user's requested reference is a map that reaches both top and
    // bottom edges, not a distorted world stretched to the phone's shape.
    _minScale = _interactionFloor(size);
    final previousSize = _lastFittedMapSize;
    _lastFittedMapSize = size;
    final viewportChanged = previousSize != null && previousSize != size;
    final preserveCameraOnResize =
        viewportChanged && sameFitRevision && _hasPresentedFit;
    final matrix = preserveCameraOnResize
        ? _resizedCameraMatrix(previousSize!, size)
        : _fitMatrix(size, points);
    final fitToken = ++_pendingFitToken;
    _pendingFitMatrix = Matrix4.copy(matrix);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          _fitRevision == revision &&
          _lastFittedMapSize == size &&
          _pendingFitToken == fitToken) {
        _pendingFitMatrix = null;
        // During a rotation Android is already animating the window bounds.
        // Do not add a second camera interpolation between portrait and
        // landscape matrices; the old matrix can temporarily leave the map
        // stranded at one edge of the newly shaped viewport.
        _presentFit(matrix, animate: !viewportChanged);
      }
    });
  }

  Matrix4 _resizedCameraMatrix(Size previousSize, Size nextSize) {
    final current = _transform.value;
    final currentScale = current
        .getMaxScaleOnAxis()
        .clamp(1.0, 20.0)
        .toDouble();
    final widthRatio = previousSize.width <= 0 || nextSize.width <= 0
        ? 1.0
        : previousSize.width / nextSize.width;
    final scale = (currentScale * widthRatio).clamp(_minScale, 20.0).toDouble();
    final previousSceneCenter = _transform.toScene(
      Offset(previousSize.width / 2, previousSize.height / 2),
    );
    final sceneCenter = Offset(
      previousSceneCenter.dx *
          (previousSize.width <= 0 ? 1 : nextSize.width / previousSize.width),
      previousSceneCenter.dy *
          (previousSize.height <= 0
              ? 1
              : nextSize.height / previousSize.height),
    );
    return Matrix4.identity()
      ..translateByDouble(nextSize.width / 2, nextSize.height / 2, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1)
      ..translateByDouble(-sceneCenter.dx, -sceneCenter.dy, 0, 1);
  }

  List<MapCoordinate> _fitPointsForWidget() {
    if (!widget.fitToData) return const <MapCoordinate>[];
    return widget.fitPoints ??
        (widget.mode == MapMode.flight
            ? [
                for (final airport in widget.airports)
                  MapCoordinate(airport.latitude, airport.longitude),
              ]
            : widget.places
                  .map(
                    (place) => MapCoordinate(place.latitude, place.longitude),
                  )
                  .toList(growable: false));
  }

  Matrix4 _fitMatrix(Size size, List<MapCoordinate> points) {
    if (points.isEmpty) {
      final initialScale = math.min(
        20.0,
        math.max(_minScale, _minScale * widget.fitZoomMultiplier),
      );
      // World-view compositions still have a deliberate content anchor. The
      // passport card reserves its lower area for distance, metrics, and
      // flags, so a complete world must follow fitDataCenterY as well; keeping
      // this branch centered made intercontinental routes fall behind those
      // overlays even though the data-fit branch already respected the same
      // setting.
      final fitCenterY = widget.fitDataCenterY.clamp(0.0, 1.0).toDouble();
      final verticalOffset =
          size.height * (fitCenterY - .5) +
          size.height * widget.fitVerticalBias;
      return _centeredScaleMatrix(
        size,
        initialScale,
        verticalOffset: verticalOffset,
      );
    }
    final projection = _projectionFor(size);
    final projectionScale = projection.scale;
    final requestedZoom = math.min(
      20.0,
      math.max(1.0, widget.fitZoomMultiplier),
    );
    final fitHeightFactor = widget.fitDataHeightFactor
        .clamp(.1, 1.0)
        .toDouble();
    final fitCenterY = widget.fitDataCenterY.clamp(0.0, 1.0).toDouble();
    final fitCenterOffsetY = size.height * (fitCenterY - .5);
    if (points.length == 1) {
      final point = points.single;
      final projected = MillerCylindricalProjection.project(
        point.latitude,
        point.longitude,
      );
      final initialZoom = math.max(_minScale, requestedZoom);
      final maxPanX = (size.width * (initialZoom - 1)) / 2;
      final maxPanY = (size.height * (initialZoom - 1)) / 2;
      final panX =
          ((projection.bounds.centerX - projected.x) *
                  projectionScale *
                  initialZoom)
              .clamp(-maxPanX, maxPanX);
      final panY =
          ((projected.y - projection.bounds.centerY) *
                      projectionScale *
                      initialZoom +
                  fitCenterOffsetY +
                  size.height * widget.fitVerticalBias)
              .clamp(-maxPanY, maxPanY);
      return Matrix4.identity()
        ..translateByDouble(size.width / 2 + panX, size.height / 2 + panY, 0, 1)
        ..scaleByDouble(initialZoom, initialZoom, 1, 1)
        ..translateByDouble(-size.width / 2, -size.height / 2, 0, 1);
    }
    final longitudes =
        points.map((point) => ((point.longitude % 360) + 360) % 360).toList()
          ..sort();
    var largestGap = -1.0;
    var boundsStart = longitudes.first;
    for (var index = 0; index < longitudes.length; index++) {
      final next = index == longitudes.length - 1
          ? longitudes.first + 360
          : longitudes[index + 1];
      final gap = next - longitudes[index];
      if (gap > largestGap) {
        largestGap = gap;
        boundsStart = next % 360;
      }
    }
    // Preserve latitude/longitude pairs while unwrapping around the largest
    // longitude gap. Miller remains continuous in longitude for a given
    // so this keeps routes crossing the date line clustered without changing
    // the geographic position of any airport.
    // Embedded maps render routes into the canonical [-180°, 180°] world
    // copy after splitting them at the seam. Fit against that same copy so a
    // trans-Pacific or trans-Atlantic route cannot be centred on an
    // unwrapped longitude that the painter later moves elsewhere. Only the
    // horizontally wrapped full-screen map benefits from the compact seam-
    // crossing representation.
    final unwrapped = widget.horizontalWrap
        ? [
            for (final point in points)
              MapCoordinate(
                point.latitude,
                ((((point.longitude % 360) + 360) % 360) < boundsStart
                    ? (((point.longitude % 360) + 360) % 360) + 360
                    : (((point.longitude % 360) + 360) % 360)),
              ),
          ]
        : [
            for (final point in points)
              MapCoordinate(
                point.latitude,
                ((((point.longitude % 360) + 360) % 360) > 180
                    ? (((point.longitude % 360) + 360) % 360) - 360
                    : (((point.longitude % 360) + 360) % 360)),
              ),
          ];
    final projectedPoints = [
      for (final point in unwrapped)
        MillerCylindricalProjection.project(point.latitude, point.longitude),
    ];
    final minX = projectedPoints.map((point) => point.x).reduce(math.min);
    final maxX = projectedPoints.map((point) => point.x).reduce(math.max);
    final minY = projectedPoints.map((point) => point.y).reduce(math.min);
    final maxY = projectedPoints.map((point) => point.y).reduce(math.max);
    final projectedCenterX = (minX + maxX) / 2;
    final projectedCenterY = (minY + maxY) / 2;
    final routeWidth = math.max(34, (maxX - minX) * projectionScale);
    final routeHeight = math.max(28, (maxY - minY) * projectionScale);
    final baseZoom = math.min(
      20.0,
      math.max(
        _minScale,
        math.min(
          (size.width * .76) / routeWidth,
          (size.height * fitHeightFactor) / routeHeight,
        ),
      ),
    );
    final zoom = math.min(
      20.0,
      math.max(_minScale, baseZoom * widget.fitZoomMultiplier),
    );
    final maxPanX = (size.width * (zoom - 1)) / 2;
    final maxPanY = (size.height * (zoom - 1)) / 2;
    final panX =
        ((projection.bounds.centerX - projectedCenterX) *
                projectionScale *
                zoom)
            .clamp(-maxPanX, maxPanX);
    final panY =
        ((projectedCenterY - projection.bounds.centerY) *
                projectionScale *
                zoom)
            .clamp(-maxPanY, maxPanY) +
        fitCenterOffsetY +
        size.height * widget.fitVerticalBias;
    return Matrix4.identity()
      ..translateByDouble(size.width / 2 + panX, size.height / 2 + panY, 0, 1)
      ..scaleByDouble(zoom, zoom, 1, 1)
      ..translateByDouble(-size.width / 2, -size.height / 2, 0, 1);
  }

  Matrix4 _centeredScaleMatrix(
    Size size,
    double scale, {
    double verticalOffset = 0,
  }) => Matrix4.identity()
    ..translateByDouble(size.width / 2, size.height / 2 + verticalOffset, 0, 1)
    ..scaleByDouble(scale, scale, 1, 1)
    ..translateByDouble(-size.width / 2, -size.height / 2, 0, 1);

  double _interactionFloor(Size size) {
    final projection = _projectionFor(size);
    final worldHeight = projection.bounds.height * projection.scale;
    final worldWidth = projection.worldPixelWidth;
    var floor = 1.0;
    if (widget.fillViewportHeight && worldHeight > 0) {
      floor = math.max(floor, size.height / worldHeight);
    }
    if (widget.coverViewport && worldWidth > 0) {
      floor = math.max(floor, size.width / worldWidth);
    }
    return floor;
  }

  double get _viewportMinLatitude => widget.compactWorldViewport
      ? MillerCylindricalProjection.passportMinLatitude
      : -90.0;

  double get _viewportMaxLatitude => widget.compactWorldViewport
      ? MillerCylindricalProjection.passportMaxLatitude
      : 90.0;

  // HomePage rebuilds while a gesture starts/ends to update the map controls.
  // Its derived map lists are recreated on those rebuilds, but their content
  // is unchanged. Compare the values instead of list identity so a control
  // repaint cannot schedule a fresh fit and snap an active pinch back out.
  bool _sameMapCoordinates(
    List<MapCoordinate>? first,
    List<MapCoordinate>? second,
  ) {
    if (identical(first, second)) return true;
    if (first == null || second == null || first.length != second.length) {
      return false;
    }
    for (var index = 0; index < first.length; index++) {
      final a = first[index];
      final b = second[index];
      if (a.latitude != b.latitude || a.longitude != b.longitude) {
        return false;
      }
    }
    return true;
  }

  bool _sameMapAirports(List<MapAirport> first, List<MapAirport> second) {
    if (identical(first, second)) return true;
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index++) {
      final a = first[index];
      final b = second[index];
      if (a.code != b.code ||
          a.name != b.name ||
          a.latitude != b.latitude ||
          a.longitude != b.longitude ||
          a.isPrimary != b.isPrimary) {
        return false;
      }
    }
    return true;
  }

  bool _sameMapPlaces(List<MapPlace> first, List<MapPlace> second) {
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

  void _invalidateFit() {
    _fitRevision++;
    _scheduledFitRevision = -1;
    _pendingFitToken++;
    _pendingFitMatrix = null;
  }
}
