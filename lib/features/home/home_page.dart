import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../app/app_controller.dart';
import '../../core/localization/app_strings.dart';
import '../../data/airport_localization.dart';
import '../../data/city_catalog.dart';
import '../../data/device_location_service.dart';
import '../../domain/flight.dart';
import '../../domain/footprint_sources.dart';
import '../../domain/transfer_decision.dart';
import '../../domain/visited_place.dart';
import '../../features/map/map.dart';
import '../map/map_records_sheet.dart';
import '../add_flight/flight_entry_sheet.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/widgets/widgets.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.controller,
    this.onMapModeChanged,
    this.isActive = true,
    this.onRecord,
  });
  final AppController controller;
  final ValueChanged<MapMode>? onMapModeChanged;
  final bool isActive;
  final ValueChanged<FlightEntryMethod>? onRecord;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // The first frame opens on the itinerary; the footprint remains one tap
  // away through the map mode control.
  MapMode _mode = MapMode.flight;
  // Flat map is the practical daily view; globe remains the immersive
  // presentation behind the second round control.
  bool _globeMode = false;
  // Online detail is the normal flat map; the local renderer is automatic
  // fallback (and remains the native desktop renderer).
  bool get _detailedMap => DetailMap.supported;
  bool _detailFallback = false;
  DetailMapCamera? _detailCamera;
  CityCatalog? _mapCatalog;
  _HomeMapData? _mapDataCache;
  final _mapPreviewKey = GlobalKey();
  bool _openingHorizontalMap = false;
  MapCoordinate? _userLocation;
  int _focusSignal = 0;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    // Resolve legacy pinyin/province labels as soon as the bundled world
    // index is ready. The first frame still renders immediately, then the map
    // quietly refreshes with canonical Chinese names and deduplicated dots.
    CityCatalog.load().then((catalog) {
      if (!mounted) return;
      setState(() => _mapCatalog = catalog);
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mapData = _homeMapData();
    final mapAirports = mapData.airports;
    final routes = mapData.routes;
    final mapPlaces = mapData.places;
    final mapFitPoints = mapData.fitPoints;
    final lightTheme = Theme.of(context).brightness == Brightness.light;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: lightTheme
            ? Brightness.dark
            : Brightness.light,
        statusBarBrightness: lightTheme ? Brightness.light : Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: lightTheme
            ? Brightness.dark
            : Brightness.light,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _homeMapExperience(
            airports: mapAirports,
            routes: routes,
            places: mapPlaces,
            fitPoints: mapFitPoints,
            userLocation: _userLocation,
          ),
          if (widget.onRecord != null &&
              _mode == MapMode.flight &&
              widget.controller.flights.isEmpty &&
              !widget.controller.isLoading)
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = MediaQuery.sizeOf(context);
                  final desktopLayout =
                      size.width >= 840 &&
                      (Platform.isMacOS ||
                          Platform.isWindows ||
                          Platform.isLinux ||
                          (Platform.isAndroid && size.width > size.height));
                  final bottom = desktopLayout
                      ? 16.0
                      : AppSpacing.bottomBarClearance(context);
                  final availableHeight = (constraints.maxHeight - bottom - 16)
                      .clamp(0.0, constraints.maxHeight);
                  return Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(20, 0, 20, bottom),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: 440,
                          maxHeight: availableHeight,
                        ),
                        child: Material(
                          color: context.appColors.surface,
                          shape: AppShapes.large,
                          elevation: 4,
                          shadowColor: Colors.black.withValues(alpha: .16),
                          clipBehavior: Clip.antiAlias,
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(24),
                            child: FlightFirstRecord(
                              onSelected: widget.onRecord!,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          Positioned(
            top: 0,
            right: 0,
            child: SafeArea(
              left: false,
              bottom: false,
              minimum: const EdgeInsets.fromLTRB(0, 12, 16, 0),
              child: _HomeMapControls(
                mode: _mode,
                globeMode: _globeMode,
                onToggleMode: () {
                  setState(() {
                    _mode = _mode == MapMode.flight
                        ? MapMode.travelFootprint
                        : MapMode.flight;
                  });
                  widget.onMapModeChanged?.call(_mode);
                },
                onToggleProjection: () => setState(() {
                  _globeMode = !_globeMode;
                }),
                onLocate: _locateUser,
                locating: _locating,
                onFullscreen: () => unawaited(() async {
                  if (!mounted) return;
                  await _openHorizontalMap(
                    mode: _mode,
                    globeMode: _globeMode,
                    airports: mapAirports,
                    routes: routes,
                    places: mapPlaces,
                  );
                }()),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _homeMapExperience({
    required List<MapAirport> airports,
    required List<MapRoute> routes,
    required List<MapPlace> places,
    required List<MapCoordinate> fitPoints,
    required MapCoordinate? userLocation,
  }) {
    final mapRoutes = _mode == MapMode.flight ? routes : const <MapRoute>[];
    return RepaintBoundary(
      key: _mapPreviewKey,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Offstage(
            offstage: _globeMode,
            child: TickerMode(
              enabled: !_globeMode,
              child: IgnorePointer(
                ignoring: _globeMode,
                child:
                    _detailedMap &&
                        !_globeMode &&
                        widget.isActive &&
                        !_openingHorizontalMap
                    ? DetailMap(
                        mode: _mode,
                        showRouteArrows: true,
                        attributionAlignment: Alignment.bottomCenter,
                        attributionBottomOffset: 86,
                        attributionOpacity: .72,
                        airports: airports,
                        routes: mapRoutes,
                        places: places,
                        userLocation: userLocation,
                        focusCoordinate: userLocation,
                        focusSignal: _focusSignal,
                        initialCamera: _detailCamera,
                        onCameraChanged: (camera) => _detailCamera = camera,
                        fallback: _offlineHomeMap(
                          airports,
                          mapRoutes,
                          places,
                          fitPoints,
                          userLocation,
                        ),
                        onFallbackChanged: (fallback) {
                          if (mounted && _detailFallback != fallback) {
                            setState(() => _detailFallback = fallback);
                          }
                        },
                        onSelection: _handleMapSelection,
                        onPlaceLongPress: _handlePlaceLongPress,
                      )
                    : _offlineHomeMap(
                        airports,
                        mapRoutes,
                        places,
                        fitPoints,
                        userLocation,
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
                  key: const ValueKey('home-globe'),
                  showRouteArrows: true,
                  active: _globeMode,
                  mode: _mode,
                  routes: mapRoutes,
                  airports: airports,
                  places: places,
                  userLocation: userLocation,
                  focusCoordinate: userLocation,
                  focusSignal: _focusSignal,
                  onSelection: _handleMapSelection,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _offlineHomeMap(
    List<MapAirport> airports,
    List<MapRoute> mapRoutes,
    List<MapPlace> places,
    List<MapCoordinate> fitPoints,
    MapCoordinate? userLocation,
  ) => OfflineMap(
    key: const ValueKey('home-flat-map'),
    showRouteArrows: true,
    mode: _mode,
    airports: airports,
    routes: mapRoutes,
    places: places,
    fitPoints: fitPoints,
    fitToData: true,
    fillViewportHeight: true,
    coverViewport: true,
    enableInteraction: true,
    horizontalWrap: true,
    horizontalPadding: 0,
    verticalPadding: 0,
    userLocation: userLocation,
    focusCoordinate: userLocation,
    focusSignal: _focusSignal,
    initialCamera: _detailCamera,
    onCameraChanged: (camera) {
      if ((!_detailedMap || _detailFallback) &&
          !_globeMode &&
          widget.isActive &&
          !_openingHorizontalMap) {
        _detailCamera = camera;
      }
    },
    // The cartographic colors follow the selected app theme.
    // In dark mode this keeps the existing deep map; Ice White
    // gets a cool, low-contrast map with glacier-blue routes.
    useLightPalette: null,
    onPlaceLongPress: _handlePlaceLongPress,
    onSelection: _handleMapSelection,
  );

  _HomeMapData _homeMapData() {
    final allFlights = widget.controller.flights;
    final visitedPlaces = widget.controller.visitedPlaces;
    final transferDecisions = widget.controller.transferDecisions;
    final cached = _mapDataCache;
    if (cached != null &&
        identical(cached.flightsSource, allFlights) &&
        identical(cached.visitedPlacesSource, visitedPlaces) &&
        identical(cached.transferDecisionsSource, transferDecisions) &&
        identical(cached.catalog, _mapCatalog) &&
        cached.includeTransitArrivals ==
            widget.controller.countTransitArrivals) {
      return cached;
    }

    final flights = allFlights.where((flight) => flight.isCompleted).toList();
    final mapAirportsByCode = <String, MapAirport>{};
    final routes = <MapRoute>[];
    final places = <String, MapPlace>{};
    for (final source in buildFootprintSources(
      flights: flights,
      visitedPlaces: visitedPlaces,
      airportFor: widget.controller.airportFor,
      includeTransitArrivals: widget.controller.countTransitArrivals,
      confirmedTransfers: transferDecisions,
    )) {
      if (source.airport case final airport?) {
        final name = localizedAirportCity(airport);
        mapAirportsByCode[airport.iataCode] = MapAirport(
          code: airport.iataCode,
          name: name,
          latitude: airport.latitude,
          longitude: airport.longitude,
        );
        places[airport.iataCode] = MapPlace(
          name: name,
          latitude: airport.latitude,
          longitude: airport.longitude,
          countryCode: airport.countryCode,
        );
      } else if (source.visitedPlace case final place?) {
        places['visited:${place.id}'] = MapPlace(
          name: place.name,
          latitude: place.latitude,
          longitude: place.longitude,
          countryCode: place.countryCode,
          id: place.id,
          visitedAt: place.visitedAt,
          isDeletable: true,
        );
      }
    }
    for (final flight in flights) {
      final from = widget.controller.airportFor(flight.departureIata);
      final to = widget.controller.airportFor(flight.arrivalIata);
      if (from == null ||
          to == null ||
          !validFootprintCoordinates(from.latitude, from.longitude) ||
          !validFootprintCoordinates(to.latitude, to.longitude)) {
        continue;
      }
      final a = MapAirport(
        code: from.iataCode,
        name: localizedAirportCity(from),
        latitude: from.latitude,
        longitude: from.longitude,
      );
      final b = MapAirport(
        code: to.iataCode,
        name: localizedAirportCity(to),
        latitude: to.latitude,
        longitude: to.longitude,
      );
      routes.add(
        MapRoute(
          from: a,
          to: b,
          isHighlight: routes.length % 3 == 1,
          label: flight.flightNumber,
          track: [
            for (final point in flight.track)
              MapCoordinate(point.latitude, point.longitude),
          ],
        ),
      );
    }
    final mapPlaces = _normalizeAndDedupeMapPlaces(places.values);
    final airports = mapAirportsByCode.values.toList(growable: false);
    // Flights are the primary viewport source; if there are no flights yet,
    // use the available travel footprints for a useful first frame.
    final flightFitPoints = [
      for (final airport in airports)
        MapCoordinate(airport.latitude, airport.longitude),
    ];
    final mapFitPoints = flightFitPoints.isNotEmpty
        ? flightFitPoints
        : [
            for (final place in mapPlaces)
              MapCoordinate(place.latitude, place.longitude),
          ];
    return _mapDataCache = _HomeMapData(
      flightsSource: allFlights,
      visitedPlacesSource: visitedPlaces,
      transferDecisionsSource: transferDecisions,
      catalog: _mapCatalog,
      includeTransitArrivals: widget.controller.countTransitArrivals,
      airports: airports,
      routes: List.unmodifiable(routes),
      places: mapPlaces,
      fitPoints: List.unmodifiable(mapFitPoints),
    );
  }

  void _handleMapSelection(MapSelection selection) {
    _openMapRecords(context, selection);
  }

  Future<void> _locateUser() async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      final coordinate = await DeviceLocationService.readOnce();
      if (!mounted) return;
      setState(() {
        _userLocation = MapCoordinate(
          coordinate.latitude,
          coordinate.longitude,
        );
        _focusSignal++;
      });
    } on DeviceLocationException catch (error) {
      if (!mounted) return;
      final key = switch (error.reason) {
        DeviceLocationFailure.serviceDisabled => 'locationServiceDisabled',
        DeviceLocationFailure.permissionDenied => 'locationPermissionDenied',
        DeviceLocationFailure.unavailable => 'locationUnavailable',
      };
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(context.strings.t(key))));
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _openHorizontalMap({
    required MapMode mode,
    required bool globeMode,
    required List<MapAirport> airports,
    required List<MapRoute> routes,
    required List<MapPlace> places,
  }) async {
    if (_openingHorizontalMap) return;
    setState(() => _openingHorizontalMap = true);
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        await SystemChrome.setPreferredOrientations(const [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      }
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => MapFullscreenPage(
            mode: mode,
            initialGlobeMode: globeMode,
            showRouteArrows: true,
            initialDetailCamera: _detailCamera,
            onDetailCameraChanged: (camera) => _detailCamera = camera,
            userLocation: _userLocation,
            airports: airports,
            routes: routes,
            places: places,
            onPlaceLongPress: _handlePlaceLongPress,
            restoreWindowOnDispose: false,
            onSelection: _openMapRecords,
          ),
        ),
      );
    } finally {
      if (Platform.isAndroid || Platform.isIOS) {
        await SystemChrome.setPreferredOrientations(const []);
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }
      if (mounted) setState(() => _openingHorizontalMap = false);
    }
  }

  Future<void> _handlePlaceLongPress(List<MapPlace> candidates) async {
    final deletable = candidates
        .where((place) => place.isDeletable && place.id != null)
        .toList(growable: false);
    if (deletable.isEmpty || !mounted) return;

    final selected = deletable.length == 1
        ? deletable.single
        : await showModalBottomSheet<MapPlace>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            backgroundColor: Colors.transparent,
            barrierColor: Colors.black.withValues(alpha: .68),
            builder: (_) => _FootprintCandidateSheet(candidates: deletable),
          );
    if (selected == null || !mounted) return;

    VisitedPlace? removedPlace;
    for (final place in widget.controller.visitedPlaces) {
      if (place.id == selected.id) {
        removedPlace = place;
        break;
      }
    }
    final place = removedPlace;
    if (place == null) return;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: .68),
      builder: (_) => _DeleteFootprintSheet(place: place),
    );
    if (confirmed != true || !mounted) return;

    await widget.controller.deleteVisitedPlace(place.id);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(context.strings.t('footprintDeleted')),
          action: SnackBarAction(
            label: context.strings.t('undo'),
            onPressed: () =>
                unawaited(widget.controller.restoreVisitedPlace(place)),
          ),
        ),
      );
  }

  void _openMapRecords(BuildContext hostContext, MapSelection selection) {
    unawaited(
      showModalBottomSheet<void>(
        context: hostContext,
        isScrollControlled: true,
        useSafeArea: true,
        requestFocus: false,
        backgroundColor: Colors.transparent,
        builder: (_) => FractionallySizedBox(
          heightFactor: .86,
          child: ClipPath(
            clipper: ShapeBorderClipper(shape: AppShapes.sheet),
            child: MapRecordsSheet(
              controller: widget.controller,
              selection: selection,
            ),
          ),
        ),
      ),
    );
  }

  List<MapPlace> _normalizeAndDedupeMapPlaces(Iterable<MapPlace> source) {
    final normalizedPlaces = <MapPlace>[];
    final indexesByCityKey = <String, int>{};
    final identityResolver = CityIdentityResolver(_mapCatalog);
    for (final place in source) {
      // Do not let the coordinate fallback turn a legacy province row into a
      // nearby city. Province records are intentionally absent from the map;
      // real city/airport points still provide the province progress signal.
      if (isProvinceMapLabel(place.name)) continue;
      final catalog = _mapCatalog;
      final name =
          catalog?.canonicalCityName(
            place.name,
            countryCode: place.countryCode,
            latitude: place.latitude,
            longitude: place.longitude,
            allowCoordinateFallback: false,
          ) ??
          normalizedMapLabel(place.name, countryCode: place.countryCode);
      if (name.trim().isEmpty || isProvinceMapLabel(name)) continue;
      final normalized = MapPlace(
        name: name,
        latitude: place.latitude,
        longitude: place.longitude,
        isVisited: place.isVisited,
        countryCode: place.countryCode,
        visits: place.visits,
        id: place.id,
        visitedAt: place.visitedAt,
        isDeletable: place.isDeletable,
      );
      final cityKey = identityResolver.keyFor(
        name: normalized.name,
        countryCode: normalized.countryCode,
        latitude: normalized.latitude,
        longitude: normalized.longitude,
      );
      final duplicateIndex = indexesByCityKey[cityKey];
      if (duplicateIndex == null) {
        indexesByCityKey[cityKey] = normalizedPlaces.length;
        normalizedPlaces.add(normalized);
        continue;
      }

      // A flight endpoint is the source of truth when a manually added travel
      // footprint names the same city. Keep the airport-derived point (the
      // non-deletable representative) so the travel map and its statistics do
      // not count or render the city twice. This also handles the defensive
      // case where a caller supplies manual places before flight places.
      final existing = normalizedPlaces[duplicateIndex];
      if (existing.isDeletable && !normalized.isDeletable) {
        normalizedPlaces[duplicateIndex] = normalized;
      }
    }
    return List.unmodifiable(normalizedPlaces);
  }
}

/// Derived map inputs are intentionally kept stable between widget rebuilds.
/// Reusing the same list instances lets the map painters retain their cached
/// geometry while the surrounding page responds to theme, menu, or gesture
/// state changes.
class _HomeMapData {
  const _HomeMapData({
    required this.flightsSource,
    required this.visitedPlacesSource,
    required this.transferDecisionsSource,
    required this.catalog,
    required this.includeTransitArrivals,
    required this.airports,
    required this.routes,
    required this.places,
    required this.fitPoints,
  });

  final List<Flight> flightsSource;
  final List<VisitedPlace> visitedPlacesSource;
  final List<TransferDecision> transferDecisionsSource;
  final CityCatalog? catalog;
  final bool includeTransitArrivals;
  final List<MapAirport> airports;
  final List<MapRoute> routes;
  final List<MapPlace> places;
  final List<MapCoordinate> fitPoints;
}

/// Home map controls stay deliberately icon-only so the artwork remains the
/// first thing the user reads. Each button changes one map dimension: data
/// layer or projection.
class _HomeMapControls extends StatelessWidget {
  const _HomeMapControls({
    required this.mode,
    required this.globeMode,
    required this.onToggleMode,
    required this.onToggleProjection,
    required this.onLocate,
    required this.locating,
    required this.onFullscreen,
  });

  final MapMode mode;
  final bool globeMode;
  final VoidCallback onToggleMode;
  final VoidCallback onToggleProjection;
  final VoidCallback onLocate;
  final bool locating;
  final VoidCallback onFullscreen;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final colors = context.appColors;
    final modeIsFlight = mode == MapMode.flight;
    final controlForeground = colors.textPrimary;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: true,
          label: modeIsFlight
              ? (strings.isZh
                    ? '航线地图，点击切换至旅行足迹'
                    : 'Flight map, tap to switch to travel footprint')
              : (strings.isZh
                    ? '旅行足迹，点击切换至航线地图'
                    : 'Travel footprint, tap to switch to flight map'),
          child: LiquidGlassIconButton(
            tooltip: modeIsFlight
                ? strings.t('travelMap')
                : (strings.isZh ? '航线地图' : 'Flight map'),
            icon: modeIsFlight
                ? Icons.flight_rounded
                : Icons.directions_walk_rounded,
            size: 48,
            iconSize: 22,
            foregroundColor: controlForeground,
            onPressed: onToggleMode,
          ),
        ),
        const SizedBox(height: 10),
        Semantics(
          button: true,
          label: globeMode ? '地球模式，点击切换' : '平面地图，点击切换',
          child: LiquidGlassIconButton(
            tooltip: globeMode
                ? strings.t('flatMapMode')
                : strings.t('globeMode'),
            icon: globeMode ? Icons.public_rounded : Icons.map_outlined,
            size: 48,
            iconSize: 22,
            foregroundColor: controlForeground,
            onPressed: onToggleProjection,
          ),
        ),
        const SizedBox(height: 10),
        Semantics(
          button: true,
          label: locating ? strings.t('locating') : strings.t('locateMe'),
          child: LiquidGlassIconButton(
            tooltip: locating ? strings.t('locating') : strings.t('locateMe'),
            icon: locating
                ? Icons.hourglass_top_rounded
                : Icons.my_location_rounded,
            size: 48,
            iconSize: 22,
            foregroundColor: controlForeground,
            onPressed: locating ? null : onLocate,
          ),
        ),
        const SizedBox(height: 10),
        Semantics(
          button: true,
          label: '横向全屏地图',
          child: LiquidGlassIconButton(
            tooltip: '横向全屏地图',
            icon: Icons.screen_rotation_alt_rounded,
            size: 48,
            iconSize: 22,
            foregroundColor: controlForeground,
            onPressed: onFullscreen,
          ),
        ),
      ],
    );
  }
}

class _FootprintCandidateSheet extends StatelessWidget {
  const _FootprintCandidateSheet({required this.candidates});

  final List<MapPlace> candidates;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final colors = context.appColors;
    final dateFormat = DateFormat('yyyy-MM-dd');
    return Material(
      color: colors.surface,
      shape: AppShapes.sheet,
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(
                alignment: Alignment.center,
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.textTertiary,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      strings.t('selectFootprint'),
                      style: AppTextStyles.sectionTitle.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: strings.t('close'),
                    onPressed: () => Navigator.maybePop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * .52,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: candidates.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final candidate = candidates[index];
                    final visitedAt = candidate.visitedAt;
                    final subtitle = visitedAt == null
                        ? strings.t('visitedDate')
                        : dateFormat.format(visitedAt.toLocal());
                    return Material(
                      color: colors.surfaceElevated,
                      shape: AppShapes.medium,
                      clipBehavior: Clip.antiAlias,
                      child: ListTile(
                        minVerticalPadding: 10,
                        shape: AppShapes.medium,
                        leading: Container(
                          width: 44,
                          height: 44,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: colors.lime.withValues(alpha: .16),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.location_on_rounded,
                            color: colors.lime,
                          ),
                        ),
                        title: Text(
                          candidate.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: Text(subtitle),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => Navigator.pop(context, candidate),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeleteFootprintSheet extends StatelessWidget {
  const _DeleteFootprintSheet({required this.place});

  final VisitedPlace place;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final colors = context.appColors;
    return Material(
      color: colors.surface,
      shape: AppShapes.sheet,
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                strings.t('deleteFootprintTitle'),
                style: AppTextStyles.sectionTitle.copyWith(
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                place.name,
                style: AppTextStyles.body.copyWith(color: colors.textPrimary),
              ),
              const SizedBox(height: 8),
              Text(
                strings.t('deleteFootprintMessage'),
                style: AppTextStyles.bodySecondary.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        foregroundColor: colors.textPrimary,
                        side: BorderSide(color: colors.border),
                        shape: AppShapes.large,
                      ),
                      child: Text(strings.t('cancel')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => Navigator.pop(context, true),
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: Text(strings.t('delete')),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        backgroundColor: colors.danger,
                        foregroundColor: Colors.black,
                        shape: AppShapes.large,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
