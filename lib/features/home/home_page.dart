import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/app_controller.dart';
import '../../core/localization/app_strings.dart';
import '../../data/airport_localization.dart';
import '../../data/city_catalog.dart';
import '../../domain/visited_place.dart';
import '../../features/map/map.dart';
import '../../features/map/add_visited_place_sheet.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/widgets/widgets.dart';
import '../flights/flight_card.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.controller,
    required this.onShowFlights,
    required this.onAdd,
  });
  final AppController controller;
  final VoidCallback onShowFlights;
  final VoidCallback onAdd;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  MapMode _mode = MapMode.flight;
  late final Future<CityCatalog> _chinaCatalog = CityCatalog.loadChina();
  CityCatalog? _mapCatalog;

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
  Widget build(BuildContext context) {
    final s = context.strings;
    final allFlights = widget.controller.flights;
    final hasAnyFlights = allFlights.isNotEmpty;
    final flights = allFlights.where((flight) => flight.isCompleted).toList();
    final upcomingFlights =
        allFlights.where((flight) => flight.isUpcoming).toList()
          ..sort((a, b) => a.departedAt.compareTo(b.departedAt));
    final nextFlight = upcomingFlights.isEmpty ? null : upcomingFlights.first;
    final totalDistance = flights.fold<double>(
      0,
      (sum, flight) => sum + (flight.distanceKm ?? 0),
    );
    final mapAirports = <String, MapAirport>{};
    final routes = <MapRoute>[];
    final places = <String, MapPlace>{};
    for (final flight in flights) {
      final from = widget.controller.airportFor(flight.departureIata);
      final to = widget.controller.airportFor(flight.arrivalIata);
      if (from == null || to == null) continue;
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
      mapAirports[a.code] = a;
      mapAirports[b.code] = b;
      places[a.code] = MapPlace(
        name: localizedAirportCity(from),
        latitude: from.latitude,
        longitude: from.longitude,
        countryCode: from.countryCode,
      );
      places[b.code] = MapPlace(
        name: localizedAirportCity(to),
        latitude: to.latitude,
        longitude: to.longitude,
        countryCode: to.countryCode,
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
    for (final place in widget.controller.visitedPlaces) {
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
    final mapPlaces = _normalizeAndDedupeMapPlaces(places.values);
    // The home map owns one camera for both layers. Flights are the primary
    // viewport source; if there are no flights yet, use the available travel
    // footprints so a newly started user still gets a useful first frame.
    final flightFitPoints = [
      for (final airport in mapAirports.values)
        MapCoordinate(airport.latitude, airport.longitude),
    ];
    final mapFitPoints = flightFitPoints.isNotEmpty
        ? flightFitPoints
        : [
            for (final place in mapPlaces)
              MapCoordinate(place.latitude, place.longitude),
          ];
    return SafeArea(
      top: false,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: PageHeader(title: s.t('map'), subtitle: s.t('mapSubtitle')),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverList.list(
              children: [
                AppSegmentedControl(
                  labels: [s.t('flightMap'), s.t('travelMap')],
                  selectedIndex: _mode == MapMode.flight ? 0 : 1,
                  onChanged: (value) => setState(
                    () => _mode = value == 0
                        ? MapMode.flight
                        : MapMode.travelFootprint,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  height: 390,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      OfflineMap(
                        mode: _mode,
                        airports: mapAirports.values.toList(),
                        routes: routes,
                        places: mapPlaces,
                        fitPoints: mapFitPoints,
                        fitToData: true,
                        fitZoomMultiplier: 1,
                        // The dashboard preview should use the same visual
                        // cover treatment as the full-screen map: the whole
                        // card is occupied, while the camera remains centred
                        // on the recorded flight region. The projection is
                        // still uniformly scaled, so filling the portrait
                        // card never stretches the world silhouette.
                        fillViewportHeight: true,
                        horizontalPadding: 0,
                        verticalPadding: 0,
                        onPlaceLongPress: _handlePlaceLongPress,
                      ),
                      Positioned(
                        bottom: 14,
                        right: 14,
                        child: Semantics(
                          button: true,
                          label: s.t('fullscreen'),
                          child: IconButton(
                            tooltip: s.t('fullscreen'),
                            onPressed: () => _openMapFullscreen(
                              mode: _mode,
                              airports: mapAirports.values.toList(),
                              routes: routes,
                              places: mapPlaces,
                              onPlaceLongPress: _handlePlaceLongPress,
                            ),
                            icon: const Icon(Icons.fullscreen_rounded),
                            style: IconButton.styleFrom(
                              fixedSize: const Size(46, 46),
                              backgroundColor: AppColors.surface.withValues(
                                alpha: .94,
                              ),
                              foregroundColor: AppColors.textPrimary,
                              side: const BorderSide(color: AppColors.border),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (_mode == MapMode.travelFootprint)
                  _explorationProgressCard(
                    context,
                    places: mapPlaces,
                    onAdd: _openAddPlace,
                  )
                else
                  _totalDistanceCard(context, totalDistance: totalDistance),
                const SizedBox(height: 34),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        s.t('nextTrip'),
                        style: AppTextStyles.sectionTitle,
                      ),
                    ),
                    TextButton(
                      onPressed: widget.onShowFlights,
                      child: Text('${s.t('viewAll')}  →'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (nextFlight == null)
                  SurfaceCard(
                    child: EmptyState(
                      title: s.t(
                        hasAnyFlights ? 'noUpcomingFlights' : 'noFlights',
                      ),
                      message: s.t(
                        hasAnyFlights
                            ? 'noUpcomingFlightsHint'
                            : 'noFlightsHint',
                      ),
                      action: PrimaryButton(
                        label: s.t('startRecord'),
                        onPressed: widget.onAdd,
                        expand: false,
                      ),
                    ),
                  )
                else
                  FlightCard(flight: nextFlight, controller: widget.controller),
                SizedBox(height: AppSpacing.bottomBarClearance(context)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatNumber(int value) {
    final raw = value.toString();
    return raw.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (match) => ',',
    );
  }

  Widget _totalDistanceCard(
    BuildContext context, {
    required double totalDistance,
  }) {
    final s = context.strings;
    return SurfaceCard(
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.lime.withValues(alpha: .12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.radar_rounded, color: AppColors.lime),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              s.t('totalDistance'),
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            _formatNumber(totalDistance.round()),
            style: const TextStyle(
              color: AppColors.lime,
              fontSize: 36,
              fontWeight: FontWeight.w700,
              letterSpacing: -1.4,
            ),
          ),
          const SizedBox(width: 6),
          const Text(
            'KM',
            style: TextStyle(
              color: AppColors.lime,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _explorationProgressCard(
    BuildContext context, {
    required List<MapPlace> places,
    required VoidCallback onAdd,
  }) {
    final s = context.strings;
    final visited = places
        .where((place) => place.isVisited && place.name.trim().isNotEmpty)
        .toList(growable: false);
    final countryCount = visited
        .map((place) => place.countryCode?.trim().toUpperCase() ?? '')
        .where((code) => code.isNotEmpty)
        .toSet()
        .length;
    final chinaPlaces = visited
        .where((place) => place.countryCode?.trim().toUpperCase() == 'CN')
        .toList(growable: false);

    return FutureBuilder<CityCatalog>(
      future: _chinaCatalog,
      builder: (context, snapshot) {
        final provinceNames = <String>{};
        final catalog = snapshot.data;
        if (catalog != null) {
          for (final place in chinaPlaces) {
            final province = catalog.provinceFor(
              place.name,
              longitude: place.longitude,
              latitude: place.latitude,
            );
            if (province != null && province.trim().isNotEmpty) {
              provinceNames.add(province.trim());
            }
          }
        }
        // Until the catalogue finishes loading, keep the card useful with a
        // conservative city count; it is replaced by province count once the
        // exact offline resolver is ready.
        final chinaCount = provinceNames.isNotEmpty
            ? provinceNames.length
            : chinaPlaces.map((place) => place.name.trim()).toSet().length;
        final worldProgress = (countryCount / 195).clamp(0.0, 1.0).toDouble();
        final chinaProgress = (chinaCount / 34).clamp(0.0, 1.0).toDouble();
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The page title and map already establish the context, so the
              // card starts directly with its two progress sections.
              _progressSection(
                title: s.t('worldExplorer'),
                count: countryCount,
                total: 195,
                progress: worldProgress,
                color: AppColors.lime,
                detail: s.t('visitedCountries'),
              ),
              const SizedBox(height: 16),
              Divider(height: 1, color: AppColors.border.withValues(alpha: .7)),
              const SizedBox(height: 16),
              _progressSection(
                title: s.t('chinaExplorer'),
                count: chinaCount,
                total: 34,
                progress: chinaProgress,
                color: AppColors.purple,
                detail: s.t('visitedRegions'),
              ),
              const SizedBox(height: 18),
              PrimaryButton(
                label: s.t('addPlace'),
                icon: Icons.add_location_alt_rounded,
                onPressed: onAdd,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _progressSection({
    required String title,
    required int count,
    required int total,
    required double progress,
    required Color color,
    required String detail,
  }) {
    final percent =
        '${(progress * 100).toStringAsFixed(progress * 100 < 10 ? 1 : 0)}%';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [Text(title, style: AppTextStyles.sectionTitle)],
              ),
            ),
            Text(
              percent,
              style: TextStyle(
                color: color,
                fontSize: 30,
                fontWeight: FontWeight.w700,
                letterSpacing: -1,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: AppRadii.pill,
          child: SizedBox(
            height: 10,
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: AppColors.surfaceElevated,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text('$count / $total · $detail', style: AppTextStyles.bodySecondary),
      ],
    );
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

  void _openMapFullscreen({
    required MapMode mode,
    required List<MapAirport> airports,
    required List<MapRoute> routes,
    required List<MapPlace> places,
    required Future<void> Function(List<MapPlace> candidates) onPlaceLongPress,
  }) {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        fullscreenDialog: true,
        transitionDuration: const Duration(milliseconds: 360),
        reverseTransitionDuration: const Duration(milliseconds: 280),
        pageBuilder: (_, animation, secondaryAnimation) => MapFullscreenPage(
          mode: mode,
          airports: airports,
          routes: routes,
          places: places,
          onPlaceLongPress: onPlaceLongPress,
          placesListenable: widget.controller,
          placesProvider: _mapPlacesSnapshot,
          onAddPlace: mode == MapMode.travelFootprint
              ? (hostContext) => _openAddPlace(hostContext)
              : null,
        ),
        transitionsBuilder: (_, animation, secondaryAnimation, child) {
          final curve = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: curve,
            child: ScaleTransition(
              scale: Tween<double>(begin: .94, end: 1).animate(curve),
              child: child,
            ),
          );
        },
      ),
    );
  }

  List<MapPlace> _mapPlacesSnapshot() {
    final places = <String, MapPlace>{};
    final completedFlights = widget.controller.flights.where(
      (flight) => flight.isCompleted,
    );
    for (final flight in completedFlights) {
      final departure = widget.controller.airportFor(flight.departureIata);
      final arrival = widget.controller.airportFor(flight.arrivalIata);
      if (departure != null) {
        places[departure.iataCode] = MapPlace(
          name: localizedAirportCity(departure),
          latitude: departure.latitude,
          longitude: departure.longitude,
          countryCode: departure.countryCode,
        );
      }
      if (arrival != null) {
        places[arrival.iataCode] = MapPlace(
          name: localizedAirportCity(arrival),
          latitude: arrival.latitude,
          longitude: arrival.longitude,
          countryCode: arrival.countryCode,
        );
      }
    }
    for (final place in widget.controller.visitedPlaces) {
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
    return _normalizeAndDedupeMapPlaces(places.values);
  }

  List<MapPlace> _normalizeAndDedupeMapPlaces(Iterable<MapPlace> source) {
    final normalizedPlaces = <MapPlace>[];
    final indexesByCityKey = <String, int>{};
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
      final cityKey = _mapPlaceCityKey(normalized);
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

  String _mapPlaceCityKey(MapPlace place) {
    final catalog = _mapCatalog;
    if (catalog != null) {
      // Resolve aliases such as “丽江市”/“丽江” and source-language photo
      // labels first. The resolver's name match keeps nearby cities (for
      // example Shenzhen and Hong Kong) distinct instead of merging by a
      // broad distance threshold.
      final resolved = catalog.resolveCity(
        place.name,
        countryCode: place.countryCode,
      );
      if (resolved != null) {
        return '${resolved.countryCode.trim().toUpperCase()}|${CityCatalog.normalizeLookup(resolved.name)}';
      }
    }
    final country = place.countryCode?.trim().toUpperCase() ?? '';
    final name = normalizedMapLabel(
      place.name,
      countryCode: place.countryCode,
    ).trim().toLowerCase();
    return '$country|$name';
  }

  Future<void> _openAddPlace([BuildContext? hostContext]) async {
    await showModalBottomSheet<bool>(
      // When launched from the fullscreen map, use that route's navigator so
      // the sheet transition starts on the visible page immediately.
      context: hostContext ?? context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: .68),
      builder: (_) => FractionallySizedBox(
        heightFactor: .9,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          child: AddVisitedPlaceSheet(controller: widget.controller),
        ),
      ),
    );
  }
}

class _FootprintCandidateSheet extends StatelessWidget {
  const _FootprintCandidateSheet({required this.candidates});

  final List<MapPlace> candidates;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final dateFormat = DateFormat('yyyy-MM-dd');
    return Material(
      color: AppColors.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
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
                    color: AppColors.textTertiary,
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
                      style: AppTextStyles.sectionTitle,
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
                      color: AppColors.surfaceElevated,
                      borderRadius: AppRadii.medium,
                      child: ListTile(
                        minVerticalPadding: 10,
                        shape: const RoundedRectangleBorder(
                          borderRadius: AppRadii.medium,
                        ),
                        leading: Container(
                          width: 44,
                          height: 44,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.lime.withValues(alpha: .16),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.location_on_rounded,
                            color: AppColors.lime,
                          ),
                        ),
                        title: Text(
                          candidate.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
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
    return Material(
      color: AppColors.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
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
                style: AppTextStyles.sectionTitle,
              ),
              const SizedBox(height: 10),
              Text(place.name, style: AppTextStyles.body),
              const SizedBox(height: 8),
              Text(
                strings.t('deleteFootprintMessage'),
                style: AppTextStyles.bodySecondary,
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        foregroundColor: AppColors.textPrimary,
                        side: const BorderSide(color: AppColors.border),
                        shape: const RoundedRectangleBorder(
                          borderRadius: AppRadii.large,
                        ),
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
                        backgroundColor: AppColors.danger,
                        foregroundColor: Colors.black,
                        shape: const RoundedRectangleBorder(
                          borderRadius: AppRadii.large,
                        ),
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
