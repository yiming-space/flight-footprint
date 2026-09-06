import 'dart:async';
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
    this.minimalWorldStyle = false,
    this.transparentBackground = false,
    this.bottomFade = false,
    this.excludePolarShelf = false,
    this.animateRouteReveal = false,
    this.routeRevealProgress = 1,
    this.routeAnimationProgress,
    this.showRouteAnimationPlane = false,
    this.showPassportTexture = false,
    this.enableInteraction = false,
    this.horizontalWrap = false,
    this.useLightPalette,
    this.onMapTap,
    this.onSelection,
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

  /// Paint a single clean world silhouette without country, province, or
  /// maritime boundaries. This is used by the share card's editorial map.
  final bool minimalWorldStyle;

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

  /// Adds the static engraved texture used by the shareable passport card.
  /// It is opt-in so dashboard and fullscreen maps keep their existing clean
  /// rendering path.
  final bool showPassportTexture;

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
  final ValueChanged<MapCoordinate>? onMapTap;
  final ValueChanged<MapSelection>? onSelection;
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
  int _viewReset = 0;
  late List<MapPlace> _places;
  AnimationController? _routeAnimation;

  /// Fullscreen animation treats repeated records with the same directed
  /// airport pair as one visual leg. The underlying flight list stays intact
  /// elsewhere in the app; this only prevents a duplicate flyover in the
  /// presentation map.
  List<MapRoute> get _animationRoutes => _deduplicateRoutes(widget.routes);

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
    for (final route in _deduplicateRoutes(routes))
      '${route.from.code.trim().toUpperCase()}->${route.to.code.trim().toUpperCase()}',
  ].join('|');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _places = widget.places;
    _routeController;
    widget.placesListenable?.addListener(_refreshPlaces);
  }

  @override
  void didChangeMetrics() {
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
    if (_routeSignature(oldWidget.routes) != _routeSignature(widget.routes)) {
      _routeController.duration = _routeAnimationDuration(
        _animationRoutes.length,
      );
      _routeController.value = 1;
      _routeAnimationStarted = false;
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

  Future<void> _toggleLandscape() async {
    if (_orientationChanging) return;
    await _setLandscape(!_landscape);
  }

  Future<void> _setLandscape(bool target) async {
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
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final colors = context.appColors;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        // The bars are hidden by immersiveSticky. Transparent colors are also
        // important during the short hand-off while Android applies the new
        // orientation, otherwise the old status-bar background can flash as a
        // black strip over the map.
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarIconBrightness: Brightness.light,
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
                builder: (context, _) => _globeMode
                    ? GlobeMap(
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
                        onSelection: widget.onSelection == null
                            ? null
                            : (selection) =>
                                  widget.onSelection!(context, selection),
                      )
                    : OfflineMap(
                        key: ValueKey('flat-$_viewReset'),
                        mode: widget.mode,
                        airports: widget.airports,
                        routes: _animationRoutes,
                        places: _places,
                        // Center the first frame on the recorded routes or cities.
                        // The complete-world vertical extent remains the minimum
                        // zoom, so the user can always pinch back out to the whole
                        // map without losing the fullscreen boundary behavior.
                        fitToData: true,
                        fillViewportHeight: true,
                        fitZoomMultiplier: 1,
                        enableInteraction: true,
                        horizontalWrap: true,
                        routeAnimationProgress: _routeController.value,
                        showRouteAnimationPlane: _routeAnimationStarted,
                        // The map is a visual data surface, so keep its established
                        // dark cartographic palette independent of page brightness.
                        useLightPalette: false,
                        onPlaceLongPress: widget.onPlaceLongPress,
                        onSelection: widget.onSelection == null
                            ? null
                            : (selection) =>
                                  widget.onSelection!(context, selection),
                      ),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              child: SafeArea(
                minimum: const EdgeInsets.all(12),
                child: MapExplorerGlass(
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
                    landscape: _landscape,
                    onModeChanged: (globe) {
                      if (_globeMode != globe) {
                        setState(() => _globeMode = globe);
                      }
                    },
                    onOrientation: _orientationChanging
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
  String _fitKey = '';
  bool _showLabels = false;
  double _sceneScale = 1;
  // The interaction floor belongs to the complete map viewport, not to the
  // currently visited routes or cities. It is refreshed for each orientation.
  double _minScale = 1;
  Size? _lastMapSize;
  FlatMapPainter? _lastPainter;
  Size? _lastFittedMapSize;
  bool _normalizingHorizontalPan = false;
  bool _hasPresentedFit = false;
  bool _fitAnimationActive = false;
  double _routeRevealProgress = 1;
  int _routeRevealGeneration = 0;

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
    if (widget.horizontalWrap && !_normalizingHorizontalPan) {
      _normalizeHorizontalPan(_lastMapSize);
    }
    final scale = _transform.value
        .getMaxScaleOnAxis()
        .clamp(_minScale, 30.0)
        .toDouble();
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
        .clamp(_minScale, 30.0)
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

  @override
  void didUpdateWidget(covariant OfflineMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assetPath != widget.assetPath ||
        oldWidget.loader != widget.loader) {
      _future = _loadBundle();
      _fitKey = '';
      _hasPresentedFit = false;
    }
    if (oldWidget.fitZoomMultiplier != widget.fitZoomMultiplier ||
        oldWidget.fitVerticalBias != widget.fitVerticalBias ||
        oldWidget.fitDataHeightFactor != widget.fitDataHeightFactor ||
        oldWidget.fitDataCenterY != widget.fitDataCenterY ||
        oldWidget.fitToData != widget.fitToData ||
        oldWidget.fillViewportHeight != widget.fillViewportHeight ||
        oldWidget.coverViewport != widget.coverViewport ||
        oldWidget.compactWorldViewport != widget.compactWorldViewport ||
        oldWidget.horizontalPadding != widget.horizontalPadding ||
        oldWidget.verticalPadding != widget.verticalPadding ||
        oldWidget.horizontalWrap != widget.horizontalWrap) {
      _fitKey = '';
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
          Widget map = GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) {
              final selection = _lastPainter?.selectionAt(
                details.localPosition,
                mapSize,
              );
              if (selection != null && widget.onSelection != null) {
                widget.onSelection!(selection);
                return;
              }
              setState(() => _showLabels = !_showLabels);
              final point = details.localPosition;
              widget.onMapTap?.call(
                MapCoordinate(
                  90 - point.dy / mapSize.height * 180,
                  point.dx / mapSize.width * 360 - 180,
                ),
              );
            },
            onLongPressStart: widget.mode == MapMode.travelFootprint
                ? (details) {
                    unawaited(_handlePlaceLongPress(details, mapSize));
                  }
                : null,
            child: ValueListenableBuilder<double>(
              valueListenable: _sceneScaleListenable,
              builder: (context, sceneScale, _) => CustomPaint(
                size: mapSize,
                painter: _lastPainter = FlatMapPainter(
                  data: data,
                  airports: widget.airports,
                  routes: widget.routes,
                  places: widget.places,
                  mode: widget.mode,
                  showLabels: _showLabels,
                  showGrid: widget.showGrid,
                  minimalWorldStyle: widget.minimalWorldStyle,
                  transparentBackground: widget.transparentBackground,
                  bottomFade: widget.bottomFade,
                  excludePolarShelf: widget.excludePolarShelf,
                  routeRevealProgress:
                      widget.routeAnimationProgress ??
                      (widget.animateRouteReveal ? _routeRevealProgress : 1),
                  showRouteAnimationPlane: widget.showRouteAnimationPlane,
                  showPassportTexture: widget.showPassportTexture,
                  compactWorldViewport: widget.compactWorldViewport,
                  lightPalette:
                      widget.useLightPalette ??
                      Theme.of(context).brightness == Brightness.light,
                  visualScale: sceneScale,
                  horizontalPadding: widget.horizontalPadding,
                  verticalPadding: widget.verticalPadding,
                  horizontalWrap: widget.horizontalWrap,
                ),
              ),
            ),
          );
          if (!widget.enableInteraction) {
            // Keep the calculated data-centred fit in the embedded preview,
            // but leave drag/pinch gestures to the surrounding page.
            return AnimatedBuilder(
              animation: _transform,
              child: RepaintBoundary(child: map),
              builder: (context, child) => Transform(
                alignment: Alignment.topLeft,
                transform: _transform.value,
                child: child,
              ),
            );
          }
          return InteractiveViewer(
            transformationController: _transform,
            panEnabled: true,
            scaleEnabled: true,
            // The complete-map vertical fill scale is the floor. Users can
            // explore closer, but a pinch-out can never shrink the world map
            // below the viewport-filling baseline (recomputed on rotation).
            minScale: _minScale,
            maxScale: 30,
            boundaryMargin: _boundaryMargin(mapSize),
            onInteractionStart: (_) {
              if (_fitAnimation?.isAnimating ?? false) {
                _fitAnimation?.stop();
                _fitAnimationActive = false;
                _syncSceneScale();
              }
            },
            child: map,
          );
        },
      );
    },
  );

  Future<void> _handlePlaceLongPress(
    LongPressStartDetails details,
    Size mapSize,
  ) async {
    if (widget.onPlaceLongPress == null) return;
    final candidates = _placeCandidatesAt(details.localPosition, mapSize);
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
      final distance = math.sqrt(
        dx * dx + math.pow(projected.dy - position.dy, 2),
      );
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
    return MillerCylindricalProjection.toOffset(
      latitude,
      longitude,
      size,
      horizontalPadding: widget.horizontalPadding,
      verticalPadding: widget.verticalPadding,
      minLatitude: _viewportMinLatitude,
      maxLatitude: _viewportMaxLatitude,
    );
  }

  double _worldPixelWidth(Size size) =>
      MillerCylindricalProjection.worldPixelWidthForSize(
        size,
        horizontalPadding: widget.horizontalPadding,
        verticalPadding: widget.verticalPadding,
        minLatitude: _viewportMinLatitude,
        maxLatitude: _viewportMaxLatitude,
      );

  double _wrappedDeltaX(double delta, double worldWidth) {
    if (worldWidth <= 0) return delta;
    while (delta > worldWidth / 2) {
      delta -= worldWidth;
    }
    while (delta < -worldWidth / 2) {
      delta += worldWidth;
    }
    return delta;
  }

  EdgeInsets _boundaryMargin(Size size) {
    if (!widget.horizontalWrap) return const EdgeInsets.all(120);
    // InteractiveViewer's boundary is expressed in scene coordinates. Leave
    // enough horizontal room for a complete wrapped cycle; the transform
    // listener recentres the translation periodically so this never becomes
    // an unbounded pan in practice.
    final worldWidth = _worldPixelWidth(size);
    final horizontal = math.max(size.width * 2, worldWidth * 2);
    return EdgeInsets.symmetric(horizontal: horizontal, vertical: 120);
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
    var normalizedPan = pan;
    while (normalizedPan > cycle / 2) {
      normalizedPan -= cycle;
    }
    while (normalizedPan < -cycle / 2) {
      normalizedPan += cycle;
    }
    if ((normalizedPan - pan).abs() < .5) return;
    final normalized = Matrix4.copy(matrix);
    normalized.storage[12] = baseTranslation + normalizedPan;
    _normalizingHorizontalPan = true;
    _transform.value = normalized;
    _normalizingHorizontalPan = false;
  }

  void _scheduleFit(Size size) {
    final points = !widget.fitToData
        ? const <MapCoordinate>[]
        : widget.fitPoints ??
              (widget.mode == MapMode.flight
                  ? [
                      for (final airport in widget.airports)
                        MapCoordinate(airport.latitude, airport.longitude),
                    ]
                  : widget.places
                        .map(
                          (place) =>
                              MapCoordinate(place.latitude, place.longitude),
                        )
                        .toList(growable: false));
    final fitSource = widget.fitPoints == null ? widget.mode.name : 'shared';
    final key = [
      fitSource,
      size.width.toStringAsFixed(1),
      size.height.toStringAsFixed(1),
      for (final point in points)
        '${point.latitude.toStringAsFixed(3)},${point.longitude.toStringAsFixed(3)}',
      widget.fitZoomMultiplier.toStringAsFixed(2),
      widget.fitVerticalBias.toStringAsFixed(2),
      widget.fitDataHeightFactor.toStringAsFixed(2),
      widget.fitDataCenterY.toStringAsFixed(2),
      widget.fitToData,
      widget.horizontalPadding.toStringAsFixed(1),
      widget.verticalPadding.toStringAsFixed(1),
      widget.coverViewport,
      widget.compactWorldViewport,
    ].join('|');
    if (_fitKey == key) return;
    _fitKey = key;
    // Fullscreen maps use the complete world's vertical extent as the floor.
    // This deliberately allows horizontal cropping in portrait orientation:
    // the user's requested reference is a map that reaches both top and
    // bottom edges, not a distorted world stretched to the phone's shape.
    _minScale = _interactionFloor(size);
    final previousSize = _lastFittedMapSize;
    _lastFittedMapSize = size;
    final viewportChanged = previousSize != null && previousSize != size;
    final matrix = _fitMatrix(size, points);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _fitKey == key) {
        // During a rotation Android is already animating the window bounds.
        // Do not add a second camera interpolation between portrait and
        // landscape matrices; the old matrix can temporarily leave the map
        // stranded at one edge of the newly shaped viewport.
        _presentFit(matrix, animate: !viewportChanged);
      }
    });
  }

  Matrix4 _fitMatrix(Size size, List<MapCoordinate> points) {
    if (points.isEmpty) {
      final initialScale = math.min(
        30.0,
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
    final projectionScale = MillerCylindricalProjection.scaleForSize(
      size,
      horizontalPadding: widget.horizontalPadding,
      verticalPadding: widget.verticalPadding,
      minLatitude: _viewportMinLatitude,
      maxLatitude: _viewportMaxLatitude,
    );
    final requestedZoom = math.min(
      30.0,
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
          ((_viewportBounds.centerX - projected.x) *
                  projectionScale *
                  initialZoom)
              .clamp(-maxPanX, maxPanX);
      final panY =
          ((projected.y - _viewportBounds.centerY) *
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
      30.0,
      math.max(
        _minScale,
        math.min(
          (size.width * .76) / routeWidth,
          (size.height * fitHeightFactor) / routeHeight,
        ),
      ),
    );
    final zoom = math.min(
      30.0,
      math.max(_minScale, baseZoom * widget.fitZoomMultiplier),
    );
    final maxPanX = (size.width * (zoom - 1)) / 2;
    final maxPanY = (size.height * (zoom - 1)) / 2;
    final panX =
        ((_viewportBounds.centerX - projectedCenterX) * projectionScale * zoom)
            .clamp(-maxPanX, maxPanX);
    final panY =
        ((projectedCenterY - _viewportBounds.centerY) * projectionScale * zoom)
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
    final projectionScale = MillerCylindricalProjection.scaleForSize(
      size,
      horizontalPadding: widget.horizontalPadding,
      verticalPadding: widget.verticalPadding,
      minLatitude: _viewportMinLatitude,
      maxLatitude: _viewportMaxLatitude,
    );
    final worldHeight = _viewportBounds.height * projectionScale;
    final worldWidth = _viewportBounds.width * projectionScale;
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

  MapProjectionBounds get _viewportBounds =>
      MillerCylindricalProjection.boundsForLatitudeRange(
        minLatitude: _viewportMinLatitude,
        maxLatitude: _viewportMaxLatitude,
      );
}
