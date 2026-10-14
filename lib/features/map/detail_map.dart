import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:maplibre/maplibre.dart' as ml;

import '../../core/localization/app_strings.dart';
import '../../ui/theme/app_theme.dart';
import 'detail_map_data.dart';
import 'detail_map_attribution.dart';
import 'detail_map_style.dart';
import 'map_models.dart';
import 'map_camera.dart';
export 'map_camera.dart';

/// Experimental online basemap. The original map is always the fallback.
class DetailMap extends StatefulWidget {
  const DetailMap({
    super.key,
    required this.mode,
    required this.airports,
    required this.routes,
    required this.places,
    required this.fallback,
    required this.onUseOffline,
    this.userLocation,
    this.onSelection,
    this.onPlaceLongPress,
    this.loader,
    this.headerTopOffset = 0,
    this.initialCamera,
    this.onCameraChanged,
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
  final VoidCallback onUseOffline;
  final MapCoordinate? userLocation;
  final ValueChanged<MapSelection>? onSelection;
  final Future<void> Function(List<MapPlace>)? onPlaceLongPress;
  final DetailMapStyleLoader? loader;
  final double headerTopOffset;
  final DetailMapCamera? initialCamera;
  final ValueChanged<DetailMapCamera>? onCameraChanged;

  @override
  State<DetailMap> createState() => _DetailMapState();
}

class _DetailMapState extends State<DetailMap> {
  Map<String, dynamic>? _base;
  ml.MapController? _controller;
  Timer? _deadline;
  Timer? _readinessCheck;
  Size _viewport = Size.zero;
  bool _failed = false;
  bool _ready = false;
  int _revision = 0;
  String? _palette;
  String? _composedStyle;

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
    _composedStyle = null;
    _palette = null;
    setState(() {
      _failed = false;
      _ready = false;
      _base = null;
    });
    _deadline = Timer(const Duration(seconds: 25), () {
      if (mounted && revision == _revision && !_ready) {
        _readinessCheck?.cancel();
        setState(() => _failed = true);
      }
    });
    try {
      final base = await (widget.loader ?? DetailMapStyleLoader()).load();
      if (mounted && revision == _revision) setState(() => _base = base);
    } catch (_) {
      if (mounted && revision == _revision) {
        _deadline?.cancel();
        setState(() => _failed = true);
      }
    }
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
        !identical(oldWidget.airports, widget.airports) ||
        !identical(oldWidget.places, widget.places) ||
        !identical(oldWidget.routes, widget.routes) ||
        oldWidget.userLocation != widget.userLocation) {
      unawaited(_updateRecords());
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
        )
    else
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

  Map<String, dynamic> get _routes => detailFeatureCollection([
    if (widget.mode == MapMode.flight)
      for (var i = 0; i < widget.routes.length; i++)
        {
          'type': 'Feature',
          'properties': {'kind': 'route', 'index': i},
          'geometry': {
            'type': 'LineString',
            'coordinates': detailRouteCoordinates(widget.routes[i]),
          },
        },
  ]);

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
      location: _location,
    ),
  );

  Future<void> _updateRecords() async {
    final style = _controller?.style;
    if (style == null || _failed) return;
    try {
      // Deliberately no camera calls: locating or editing a record must not
      // pull the user away from the area they are looking at.
      await style.updateGeoJsonSource(
        id: 'ff-points',
        data: jsonEncode(_points),
      );
      if (!mounted) return;
      await style.updateGeoJsonSource(
        id: 'ff-routes',
        data: jsonEncode(_routes),
      );
      if (!mounted) return;
      await style.updateGeoJsonSource(
        id: 'ff-location',
        data: jsonEncode(_location),
      );
    } catch (_) {
      // A style switch may destroy the previous sources mid-update. The new
      // onStyleLoaded callback reapplies the current records.
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
      widget.onSelection?.call(
        MapSelection(airports: airports, places: places),
      );
      return;
    }
    final hits = controller.featuresInRect(
      Rect.fromCircle(center: input.screenPoint, radius: 6),
      layerIds: const ['ff-routes'],
    );
    if (hits.isEmpty) return;
    final index = (hits.first.properties['index'] as num?)?.toInt();
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
      }
    } catch (_) {
      // The bounded deadline falls back if the native surface never loads.
    }
  }

  void _onStyleLoaded(ml.StyleController _) {
    unawaited(_updateRecords());
    _readinessCheck?.cancel();
    if (!_ready && !_failed) {
      _readinessCheck = Timer.periodic(
        const Duration(milliseconds: 500),
        (_) => _checkBasemapReady(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final colors = context.appColors;
    final light = Theme.of(context).brightness == Brightness.light;
    final palette = '$light-${strings.isZh}';
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
        if (_base == null || _failed)
          widget.fallback
        else
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
                  widget.onCameraChanged?.call(
                    MapCamera(center, widget.initialCamera?.zoom ?? zoom),
                  );
                },
                onStyleLoaded: _onStyleLoaded,
                onEvent: _onEvent,
                children: [
                  DetailMapAttribution(topOffset: widget.headerTopOffset),
                ],
              );
            },
          ),
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
                            _failed
                                ? 'detailMapFailed'
                                : _ready
                                ? 'detailMapPreview'
                                : 'detailMapLoading',
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
                        if (_failed)
                          TextButton(
                            onPressed: widget.onUseOffline,
                            child: Text(strings.t('offlineBasemap')),
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
