import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:maplibre/maplibre.dart' as ml;

import '../../core/localization/app_strings.dart';
import '../../ui/theme/app_theme.dart';
import 'detail_map_data.dart';
import 'detail_map_footprint.dart';
import 'detail_map_routes.dart';
import 'detail_map_attribution.dart';
import 'detail_map_style.dart';
import 'map_models.dart';
import 'route_arrow.dart';
import 'map_camera.dart';
export 'map_camera.dart';

/// Default online flat map, with the local map as an automatic fallback.
class DetailMap extends StatefulWidget {
  const DetailMap({
    super.key,
    required this.mode,
    required this.airports,
    required this.routes,
    required this.places,
    required this.fallback,
    this.onFallbackChanged,
    this.userLocation,
    this.onSelection,
    this.onPlaceLongPress,
    this.loader,
    this.headerTopOffset = 0,
    this.attributionBottomOffset = 92,
    this.attributionAlignment = Alignment.bottomLeft,
    this.initialCamera,
    this.onCameraChanged,
    this.showRouteArrows = false,
    this.attributionOpacity = 1,
    this.focusCoordinate,
    this.focusSignal = 0,
  });

  static bool get supported =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  final MapMode mode;
  final List<MapAirport> airports;
  final List<MapRoute> routes;
  final List<MapPlace> places;
  final Widget fallback;
  final ValueChanged<bool>? onFallbackChanged;
  final MapCoordinate? userLocation;
  final ValueChanged<MapSelection>? onSelection;
  final Future<void> Function(List<MapPlace>)? onPlaceLongPress;
  final DetailMapStyleLoader? loader;
  final double headerTopOffset;
  final double attributionBottomOffset;
  final Alignment attributionAlignment;
  final DetailMapCamera? initialCamera;
  final ValueChanged<DetailMapCamera>? onCameraChanged;
  final bool showRouteArrows;
  final double attributionOpacity;
  final MapCoordinate? focusCoordinate;
  final int focusSignal;

  @override
  State<DetailMap> createState() => _DetailMapState();
}

class _DetailMapState extends State<DetailMap> {
  static Future<void>? _ambientCacheSetup;

  static Future<void> _configureAmbientCache() async {
    if (!ml.OfflineManager.isSupported) return;
    ml.OfflineManager? manager;
    try {
      manager = await ml.OfflineManager.createInstance();
      await manager.setMaximumAmbientCacheSize(bytes: 96 * 1024 * 1024);
    } catch (_) {
      // The map remains usable if the platform cache cannot be configured.
    } finally {
      manager?.dispose();
    }
  }

  Map<String, dynamic>? _base;
  ml.MapController? _controller;
  ml.StyleController? _activeStyle;
  ml.StyleController? _arrowImageStyle;
  Timer? _deadline;
  Timer? _readinessCheck;
  Size _viewport = Size.zero;
  bool _failed = false;
  bool _ready = false;
  bool? _reportedFallback;
  int _revision = 0;
  String? _palette;
  String? _composedStyle;
  DetailFootprintResult? _footprint;
  List<MapPlace>? _footprintPlaces;
  Future<DetailFootprintResult>? _footprintTask;
  int _recordsRevision = 0;
  final _routeCache = DetailRouteCache();
  final _sourceCache = DetailSourceCache();
  int? _selectedRouteIndex;
  MapCoordinate? _pendingFocusCoordinate;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final revision = ++_revision;
    _deadline?.cancel();
    _readinessCheck?.cancel();
    _controller = null;
    _activeStyle = null;
    _arrowImageStyle = null;
    _composedStyle = null;
    _palette = null;
    setState(() {
      _failed = false;
      _ready = false;
      _base = null;
    });
    _notifyFallback(false);
    _deadline = Timer(const Duration(seconds: 25), () {
      if (mounted && revision == _revision && !_ready) {
        _readinessCheck?.cancel();
        setState(() => _failed = true);
        _notifyFallback(true);
      }
    });
    try {
      final base = await (widget.loader ?? DetailMapStyleLoader()).load();
      if (mounted && revision == _revision) setState(() => _base = base);
    } catch (_) {
      if (mounted && revision == _revision) {
        _deadline?.cancel();
        setState(() => _failed = true);
        _notifyFallback(true);
      }
    }
  }

  void _notifyFallback(bool fallback) {
    // Loading can begin during a parent's build. Report after that frame,
    // and ignore callbacks from a no-longer-current readiness state.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _failed != fallback || _reportedFallback == fallback) {
        return;
      }
      _reportedFallback = fallback;
      widget.onFallbackChanged?.call(fallback);
    });
  }

  @override
  void dispose() {
    _deadline?.cancel();
    _readinessCheck?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant DetailMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode != widget.mode ||
        !identical(oldWidget.routes, widget.routes)) {
      _selectedRouteIndex = null;
    }
    if (oldWidget.mode != widget.mode ||
        !identical(oldWidget.airports, widget.airports) ||
        !identical(oldWidget.places, widget.places) ||
        !identical(oldWidget.routes, widget.routes) ||
        oldWidget.userLocation != widget.userLocation) {
      unawaited(_updateRecords());
    }
    if (oldWidget.focusSignal != widget.focusSignal &&
        widget.focusCoordinate != null) {
      _pendingFocusCoordinate = widget.focusCoordinate;
      _focusPendingCoordinate();
    }
  }

  void _focusPendingCoordinate() {
    final controller = _controller;
    final coordinate = _pendingFocusCoordinate;
    if (!mounted || !_ready || controller == null || coordinate == null) {
      return;
    }
    _pendingFocusCoordinate = null;
    final center = ml.Geographic(
      lon: coordinate.longitude,
      lat: coordinate.latitude,
    );
    if (MediaQuery.disableAnimationsOf(context)) {
      unawaited(controller.moveCamera(center: center));
    } else {
      unawaited(
        controller.animateCamera(
          center: center,
          nativeDuration: const Duration(milliseconds: 700),
          webMaxDuration: const Duration(milliseconds: 700),
        ),
      );
    }
  }

  Map<String, dynamic> get _points => detailFeatureCollection([
    if (widget.mode == MapMode.flight)
      for (var i = 0; i < widget.airports.length; i++)
        detailPointFeature(
          MapCoordinate(
            widget.airports[i].latitude,
            widget.airports[i].longitude,
          ),
          kind: 'airport',
          index: i,
          label: widget.airports[i].name,
        ),
    if (widget.mode == MapMode.travelFootprint)
      for (var i = 0; i < widget.places.length; i++)
        if (widget.places[i].isVisited)
          detailPointFeature(
            MapCoordinate(
              widget.places[i].latitude,
              widget.places[i].longitude,
            ),
            kind: 'place',
            index: i,
            label: widget.places[i].name,
          ),
  ]);

  DetailRouteData get _routeData =>
      _routeCache.data(widget.routes, enabled: widget.mode == MapMode.flight);
  Map<String, dynamic> get _routes => _routeData.collection;
  Map<String, dynamic> get _selectedRoute =>
      _routeData.selected(_selectedRouteIndex);

  Map<String, dynamic> get _location => detailFeatureCollection([
    if (widget.userLocation case final location?)
      detailPointFeature(location, kind: 'location', index: 0, label: ''),
  ]);
  String _style(bool light, bool chinese) => jsonEncode(
    buildDetailMapStyle(
      jsonDecode(jsonEncode(_base)) as Map<String, dynamic>,
      light: light,
      chinese: chinese,
      points: _points,
      routes: _routes,
      showRouteArrows: widget.showRouteArrows,
      selectedRoute: _selectedRoute,
      location: _location,
      regions:
          widget.mode == MapMode.travelFootprint &&
              identical(_footprintPlaces, widget.places)
          ? _footprint?.collection ?? emptyDetailFootprint
          : emptyDetailFootprint,
    ),
  );

  Future<void> _updateRecords() async {
    final style = _activeStyle ?? _controller?.style;
    if (style == null || _failed) return;
    final revision = ++_recordsRevision;
    try {
      // Deliberately no camera calls: locating or editing a record must not
      // pull the user away from the area they are looking at.
      await _updateSource(style, id: 'ff-points', data: jsonEncode(_points));
      if (!mounted || revision != _recordsRevision || style != _activeStyle) {
        return;
      }
      await _updateSource(style, id: 'ff-routes', data: _routeData.encoded);
      if (!mounted || revision != _recordsRevision || style != _activeStyle) {
        return;
      }
      await _updateSource(
        style,
        id: 'ff-location',
        data: jsonEncode(_location),
      );
      if (!mounted || revision != _recordsRevision) return;
      await _updateSource(
        style,
        id: 'ff-route-selection',
        data: jsonEncode(_selectedRoute),
      );
      if (!mounted || revision != _recordsRevision) return;
      var encoded = jsonEncode(emptyDetailFootprint);
      if (widget.mode == MapMode.travelFootprint &&
          widget.places.any((place) => place.isVisited)) {
        if (!identical(_footprintPlaces, widget.places)) {
          _footprintPlaces = widget.places;
          _footprint = null;
          _footprintTask = DetailFootprintLoader().load(widget.places);
        }
        try {
          final result = await _footprintTask!;
          if (!mounted || revision != _recordsRevision) return;
          _footprint = result;
          encoded = result.encoded;
        } catch (_) {
          // Optional highlighting must never take away the detailed map or
          // its tappable city markers if local boundary loading fails.
          if (!mounted || revision != _recordsRevision) return;
          _footprintPlaces = null;
          _footprintTask = null;
        }
      }
      if (!mounted || revision != _recordsRevision || style != _activeStyle) {
        return;
      }
      await _updateSource(style, id: 'ff-regions', data: encoded);
      if (!mounted || revision != _recordsRevision || style != _activeStyle) {
        return;
      }
    } catch (_) {
      // A style switch may destroy the previous sources mid-update. The new
      // onStyleLoaded callback reapplies the current records.
    }
  }

  Future<void> _updateSource(
    ml.StyleController style, {
    required String id,
    required String data,
  }) => _sourceCache.update(
    style: style,
    id: id,
    data: data,
    send: () => style.updateGeoJsonSource(id: id, data: data),
  );

  void _selectRoute(int? index) {
    if (_selectedRouteIndex == index) return;
    _selectedRouteIndex = index;
    final style = _activeStyle;
    if (style != null && !_failed) {
      unawaited(
        _updateSource(
          style,
          id: 'ff-route-selection',
          data: jsonEncode(_selectedRoute),
        ).catchError((Object _) {}),
      );
    }
  }

  void _onEvent(ml.MapEvent event) {
    if (event is ml.MapEventMoveCamera) {
      widget.onCameraChanged?.call(
        DetailMapCamera(
          MapCoordinate(event.camera.center.lat, event.camera.center.lon),
          event.camera.zoom,
        ),
      );
    }
    if (event is! ml.MapEventClick && event is! ml.MapEventLongClick) return;
    final input = event as ml.MapEventUserInput;
    final controller = _controller;
    if (controller == null || controller.style == null) return;
    final features = controller.featuresInRect(
      Rect.fromCircle(center: input.screenPoint, radius: 18),
      layerIds: const ['ff-points'],
    );
    final airports = <MapAirport>[];
    final places = <MapPlace>[];
    final seen = <String>{};
    for (final feature in features) {
      final properties = feature.properties;
      final index = (properties['index'] as num?)?.toInt();
      final kind = properties['kind'];
      if (index == null || !seen.add('$kind-$index')) continue;
      if (kind == 'airport' && index >= 0 && index < widget.airports.length) {
        airports.add(widget.airports[index]);
      }
      if (kind == 'place' && index >= 0 && index < widget.places.length) {
        places.add(widget.places[index]);
      }
    }
    if (event is ml.MapEventLongClick) {
      final deletable = places
          .where((p) => p.isDeletable && p.id != null)
          .toList();
      if (deletable.isNotEmpty) widget.onPlaceLongPress?.call(deletable);
      return;
    }
    if (airports.isNotEmpty || places.isNotEmpty) {
      _selectRoute(null);
      widget.onSelection?.call(
        MapSelection(airports: airports, places: places),
      );
      return;
    }
    final hits = controller.featuresInRect(
      Rect.fromCircle(center: input.screenPoint, radius: 6),
      layerIds: const ['ff-routes'],
    );
    int? index;
    var nearest = double.infinity;
    final checked = <int>{};
    final worldWidth = (512 * math.pow(2, controller.getCamera().zoom))
        .toDouble();
    for (final hit in hits) {
      final candidate = (hit.properties['index'] as num?)?.toInt();
      if (candidate == null || !checked.add(candidate)) continue;
      final feature = _routeData.byIndex[candidate];
      if (feature == null) continue;
      final geometry = feature['geometry'] as Map;
      final projected = controller.toScreenLocations([
        for (final point in geometry['coordinates'] as List)
          ml.Geographic(
            lon: (point[0] as num).toDouble(),
            lat: (point[1] as num).toDouble(),
          ),
      ]);
      final distance = detailRouteScreenDistance(
        input.screenPoint,
        projected,
        offset: ((feature['properties'] as Map)['offset'] as num).toDouble(),
        worldWidth: worldWidth,
      );
      if (distance < nearest) {
        nearest = distance;
        index = candidate;
      }
    }
    _selectRoute(index);
    if (index != null && index >= 0 && index < widget.routes.length) {
      widget.onSelection?.call(MapSelection(route: widget.routes[index]));
    }
  }

  void _checkBasemapReady() {
    final controller = _controller;
    if (!mounted ||
        _failed ||
        _ready ||
        controller?.style == null ||
        _viewport.isEmpty) {
      return;
    }
    final ids = [
      for (final layer in _base!['layers'] as List)
        if (layer['source'] == 'openmaptiles' &&
            layer['type'] != 'symbol' &&
            layer['type'] != 'raster')
          layer['id'] as String,
    ];
    try {
      // Android does not emit MapEventIdle in this plugin version. Also,
      // style-loaded alone does not prove that remote tiles were rendered.
      // Require actual basemap geometry, not our local route/point layers.
      final features = controller!.featuresInRect(
        Offset.zero & _viewport,
        layerIds: ids,
      );
      if (features.isNotEmpty) {
        _deadline?.cancel();
        _readinessCheck?.cancel();
        setState(() => _ready = true);
        _notifyFallback(false);
        _focusPendingCoordinate();
      }
    } catch (_) {
      // The bounded deadline falls back if the native surface never loads.
    }
  }

  void _onStyleLoaded(ml.StyleController style) {
    // Let native map resources persist without delaying the visible map.
    unawaited(_ambientCacheSetup ??= _configureAmbientCache());
    // Native style-loaded can precede onMapCreated. Use the supplied style
    // directly so first-entry highlighting does not depend on a later toggle.
    _activeStyle = style;
    if (widget.showRouteArrows) unawaited(_registerArrowImage(style));
    unawaited(_updateRecords());
    _readinessCheck?.cancel();
    if (!_ready && !_failed) {
      _readinessCheck = Timer.periodic(
        const Duration(milliseconds: 200),
        (_) => _checkBasemapReady(),
      );
    }
  }

  Future<void> _registerArrowImage(ml.StyleController style) async {
    if (_arrowImageStyle == style) return;
    _arrowImageStyle = style;
    final light = Theme.of(context).brightness == Brightness.light;
    final color = light
        ? context.appColors.displaySecondary
        : AppColors.routePurple;
    try {
      await style.addImageFromCanvas(
        id: 'ff-route-arrow',
        width: 32,
        height: 32,
        painter: (canvas) {
          canvas.drawPath(
            routeArrowPath(
              center: const Offset(16, 16),
              direction: const Offset(1, 0),
              length: 28,
            ),
            Paint()..color = color,
          );
        },
      );
    } catch (_) {
      if (_arrowImageStyle == style) _arrowImageStyle = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final colors = context.appColors;
    final light = Theme.of(context).brightness == Brightness.light;
    final palette = '$light-${strings.isZh}-${widget.showRouteArrows}';
    if (_base != null && _palette != palette) {
      _palette = palette;
      final composed = _composedStyle = _style(light, strings.isZh);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _composedStyle == composed) {
          _controller?.setStyle(composed);
        }
      });
    }
    final points = widget.mode == MapMode.flight
        ? [
            for (final p in widget.airports)
              MapCoordinate(p.latitude, p.longitude),
          ]
        : [
            for (final p in widget.places)
              if (p.isVisited) MapCoordinate(p.latitude, p.longitude),
          ];
    final center = widget.initialCamera?.center ?? detailMapCenter(points);
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_base != null && !_failed)
          LayoutBuilder(
            builder: (context, constraints) {
              _viewport = constraints.biggest;
              var span = 180.0;
              if (points.isNotEmpty) {
                span = points.fold<double>(2, (s, p) {
                  final dx =
                      ((p.longitude - center.longitude + 540) % 360 - 180)
                          .abs();
                  return math.max(s, dx * 2);
                });
              }
              final widthZoom =
                  (math.log(constraints.maxWidth * 360 / (512 * span * 1.3)) /
                  math.ln2);
              double mercatorY(double lat) {
                final radians = lat.clamp(-80, 80) * math.pi / 180;
                return math.log(math.tan(math.pi / 4 + radians / 2));
              }

              final centerY = mercatorY(center.latitude);
              final verticalSpan = points.fold<double>(
                .02,
                (s, p) =>
                    math.max(s, (mercatorY(p.latitude) - centerY).abs() * 2),
              );
              final heightZoom =
                  math.log(
                    math.max(120, constraints.maxHeight - 200) *
                        2 *
                        math.pi /
                        (512 * verticalSpan * 1.3),
                  ) /
                  math.ln2;
              final zoom = math.min(widthZoom, heightZoom).clamp(.5, 6.0);
              return ml.MapLibreMap(
                key: ValueKey(_revision),
                options: ml.MapOptions(
                  initStyle: _composedStyle!,
                  initCenter: ml.Geographic(
                    lon: center.longitude,
                    lat: center.latitude,
                  ),
                  initZoom: widget.initialCamera?.zoom ?? zoom,
                  maxZoom: 17,
                  maxPitch: 0,
                  gestures: const ml.MapGestures.all(
                    rotate: false,
                    pitch: false,
                  ),
                  androidForegroundLoadColor: colors.background,
                ),
                onMapCreated: (controller) {
                  _controller = controller;
                  _activeStyle ??= controller.style;
                  widget.onCameraChanged?.call(
                    MapCamera(center, widget.initialCamera?.zoom ?? zoom),
                  );
                },
                onStyleLoaded: _onStyleLoaded,
                onEvent: _onEvent,
                children: [
                  DetailMapAttribution(
                    bottomOffset: widget.attributionBottomOffset,
                    alignment: widget.attributionAlignment,
                    opacity: widget.attributionOpacity,
                  ),
                ],
              );
            },
          ),
        // Once the native map is available, show tiles as they arrive instead
        // of covering a rendered map until the next readiness check. The
        // offline projection still only appears on failure.
        if (_base == null && !_failed)
          AbsorbPointer(child: ColoredBox(color: colors.background)),
        if (_failed) widget.fallback,
        if (!_ready || _failed)
          Positioned(
            top: widget.headerTopOffset,
            left: 0,
            right: 80,
            child: SafeArea(
              bottom: false,
              child: Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Material(
                    color: colors.surface,
                    shape: const StadiumBorder(),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        children: [
                          Text(
                            strings.t(
                              _failed ? 'detailMapFailed' : 'detailMapLoading',
                            ),
                            style: TextStyle(
                              color: colors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                          if (_failed)
                            TextButton(
                              onPressed: _load,
                              child: Text(strings.t('retry')),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
