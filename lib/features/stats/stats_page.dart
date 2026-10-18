import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../core/localization/app_strings.dart';
import '../../data/airport_localization.dart';
import '../../data/city_catalog.dart';
import '../../domain/flight.dart';
import '../../domain/visited_place.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/widgets/widgets.dart';
import '../flights/flight_card.dart';
import '../map/map_models.dart';
import 'aircraft_collection.dart';
import 'aircraft_collection_detail_page.dart';
import 'aircraft_collection_overview_card.dart';
import 'aircraft_collection_page.dart';
import 'airline_ranking.dart';
import 'airline_ranking_overview_card.dart';
import 'airline_ranking_page.dart';
import 'city_ranking.dart';
import 'city_ranking_page.dart';
import 'country_ranking.dart';
import 'country_stats_page.dart';
import 'exploration_overview_card.dart';
import 'flight_passport_card.dart';
import 'ranking_expansion_card.dart';
import 'world_exploration_page.dart';

class StatsPage extends StatefulWidget {
  const StatsPage({super.key, required this.controller});
  final AppController controller;
  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  static const _wideLayoutBreakpoint = 700.0;
  int? _passportYear;
  late final Future<CityCatalog> _chinaCatalog = CityCatalog.loadChina();
  CityCatalog? _rankingCityCatalog;

  @override
  void initState() {
    super.initState();
    _loadRankingCities();
  }

  Future<void> _loadRankingCities() async {
    try {
      final china = await _chinaCatalog;
      if (!mounted) return;
      final catalog = china.withAirports(widget.controller.airports);
      setState(() => _rankingCityCatalog = catalog);
    } catch (_) {
      // Exact saved names and country codes remain usable if a catalogue
      // cannot load. Never replace an unknown city with a nearby one.
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasAnyFlights = widget.controller.flights.isNotEmpty;
    final flights = widget.controller.flights
        .where((flight) => flight.isCompleted)
        .toList();
    final passportYears = _years(flights);
    final selectedPassportYear = passportYears.contains(_passportYear)
        ? _passportYear
        : null;
    final passportFlights = selectedPassportYear == null
        ? flights
        : flights
              .where(
                (flight) =>
                    flight.departedAt.toLocal().year == selectedPassportYear,
              )
              .toList();
    final passportTotal = passportFlights.fold<double>(
      0,
      (sum, flight) => sum + (flight.distanceKm ?? 0),
    );
    final countrySummaries = buildCountryRanking(
      flights,
      airportFor: widget.controller.airportFor,
      countryNameForCode: localizedCountryName,
      visitedPlaces: widget.controller.visitedPlaces,
    );
    final passportAirports = _passportAirports(passportFlights);
    final passportRoutes = _passportRoutes(passportFlights);
    final passportFlags = _passportFlags(passportFlights);
    final passportFlightTimeMinutes = _flightTimeMinutes(passportFlights);
    final passportRouteCount = _routeKeys(passportFlights).length;
    final aircraftSummaries = buildAircraftCollection(flights);
    final citySummaries = buildCityRanking(
      flights,
      airportFor: widget.controller.airportFor,
      cityNameFor: localizedAirportCity,
      countryNameFor: (airport) => localizedCountryName(airport.countryCode),
      visitedPlaces: widget.controller.visitedPlaces,
      cityCatalog: _rankingCityCatalog,
      countryNameForCode: localizedCountryName,
    );
    final footprintPlaces = _footprintPlaces(flights);
    final data = _StatsViewData(
      hasAnyFlights: hasAnyFlights,
      flights: flights,
      passportYears: passportYears,
      selectedPassportYear: selectedPassportYear,
      passportFlights: passportFlights,
      passportTotal: passportTotal,
      countrySummaries: countrySummaries,
      passportAirports: passportAirports,
      passportRoutes: passportRoutes,
      passportFlags: passportFlags,
      passportFlightTimeMinutes: passportFlightTimeMinutes,
      passportRouteCount: passportRouteCount,
      aircraftSummaries: aircraftSummaries,
      citySummaries: citySummaries,
      footprintPlaces: footprintPlaces,
    );
    return SafeArea(
      top: false,
      left: false,
      right: false,
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.page,
              AppSpacing.page,
              AppSpacing.page,
              AppSpacing.bottomBarClearance(context),
            ),
            sliver: SliverLayoutBuilder(
              builder: (context, constraints) {
                if (constraints.crossAxisExtent >= _wideLayoutBreakpoint) {
                  return SliverToBoxAdapter(child: _wideContent(data));
                }
                return SliverList.list(children: _narrowContent(data));
              },
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _narrowContent(_StatsViewData data) {
    final s = context.strings;
    return [
      if (data.flights.isNotEmpty) ...[
        _PassportYearFilterBar(
          years: data.passportYears,
          selectedYear: data.selectedPassportYear,
          allLabel: s.t('all'),
          onChanged: (year) => setState(() => _passportYear = year),
        ),
        const SizedBox(height: 8),
        _shareCard(data),
        const SizedBox(height: AppSpacing.sm),
      ],
      SizedBox(
        height: data.flights.isNotEmpty ? AppSpacing.sm : AppSpacing.section,
      ),
      if (data.flights.isEmpty)
        if (data.citySummaries.isEmpty && data.countrySummaries.isEmpty)
          _emptyStats(data)
        else ...[
          _footprintStatsCard(data),
          const SizedBox(height: AppSpacing.cardGap),
          _cityRankingCard(data.citySummaries),
          const SizedBox(height: AppSpacing.cardGap),
          _countryRankingCard(data.countrySummaries),
        ]
      else ...[
        _footprintStatsCard(data),
        const SizedBox(height: AppSpacing.cardGap),
        _aircraftCollectionCard(data.aircraftSummaries),
        const SizedBox(height: AppSpacing.cardGap),
        _airlineRankingCard(buildAirlineRanking(data.flights)),
        const SizedBox(height: AppSpacing.cardGap),
        _cityRankingCard(data.citySummaries),
        const SizedBox(height: AppSpacing.cardGap),
        _countryRankingCard(data.countrySummaries),
      ],
    ];
  }

  Widget _wideContent(_StatsViewData data) {
    final s = context.strings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (data.flights.isNotEmpty) ...[
          _PassportYearFilterBar(
            years: data.passportYears,
            selectedYear: data.selectedPassportYear,
            allLabel: s.t('all'),
            onChanged: (year) => setState(() => _passportYear = year),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 5, child: _shareCard(data)),
                  const SizedBox(width: AppSpacing.cardGap),
                  Expanded(flex: 5, child: _wideStatsList(data)),
                ],
              );
            },
          ),
        ] else if (data.citySummaries.isEmpty && data.countrySummaries.isEmpty)
          _emptyStats(data)
        else
          Column(
            children: [
              _footprintStatsCard(data),
              const SizedBox(height: AppSpacing.cardGap),
              _cityRankingCard(data.citySummaries),
              const SizedBox(height: AppSpacing.cardGap),
              _countryRankingCard(data.countrySummaries),
            ],
          ),
      ],
    );
  }

  Widget _wideStatsList(_StatsViewData data) {
    return Column(
      children: [
        _footprintStatsCard(data),
        const SizedBox(height: AppSpacing.cardGap),
        _aircraftCollectionCard(data.aircraftSummaries),
        const SizedBox(height: AppSpacing.cardGap),
        _airlineRankingCard(buildAirlineRanking(data.flights)),
        const SizedBox(height: AppSpacing.cardGap),
        _cityRankingCard(data.citySummaries),
        const SizedBox(height: AppSpacing.cardGap),
        _countryRankingCard(data.countrySummaries),
      ],
    );
  }

  Widget _emptyStats(_StatsViewData data) {
    final s = context.strings;
    return SurfaceCard(
      child: EmptyState(
        title: s.t(data.hasAnyFlights ? 'noCompletedFlights' : 'noFlights'),
        message: s.t('emptyStats'),
      ),
    );
  }

  Widget _shareCard(_StatsViewData data) => FlightPassportCard(
    year: data.selectedPassportYear ?? DateTime.now().year,
    yearLabel: data.selectedPassportYear == null ? 'ALL' : null,
    travellerName: widget.controller.travellerName,
    distanceKm: data.passportTotal,
    flightTimeMinutes: data.passportFlightTimeMinutes,
    flightCount: data.passportFlights.length,
    airportCount: data.passportAirports.length,
    routeCount: data.passportRouteCount,
    countryCodes: data.passportFlags,
    airports: data.passportAirports,
    routes: data.passportRoutes,
  );

  Widget _aircraftCollectionCard(List<AircraftCollectionEntry> items) =>
      AircraftCollectionOverviewCard(
        aircraftCount: items.length,
        pageBuilder: (_) => AircraftCollectionPage(
          items: items,
          detailBuilder: (context, entry) => AircraftCollectionDetailPage(
            entry: entry,
            flightBuilder: (context, flight) =>
                FlightCard(flight: flight, controller: widget.controller),
          ),
        ),
      );

  Widget _footprintStatsCard(_StatsViewData data) {
    return FutureBuilder<CityCatalog>(
      future: _chinaCatalog,
      builder: (context, snapshot) {
        final visited = data.footprintPlaces
            .where((place) => place.isVisited && place.name.trim().isNotEmpty)
            .toList(growable: false);
        final countryCount = visited
            .map((place) => canonicalWorldCountryCode(place.countryCode))
            .where((code) => code.isNotEmpty)
            .toSet()
            .length;
        final chinaPlaces = visited
            .where((place) => place.countryCode?.trim().toUpperCase() == 'CN')
            .toList(growable: false);
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
        // Before the offline catalogue resolves, show a useful city fallback;
        // the exact province count replaces it once the bundled data is ready.
        final chinaCount = provinceNames.isNotEmpty
            ? provinceNames.length
            : chinaPlaces.map((place) => place.name.trim()).toSet().length;
        return ExplorationOverviewCard(
          worldCount: countryCount,
          chinaCount: chinaCount,
          boxShadow: _statsCardShadow(context),
          pageBuilder: (_) => WorldExplorationPage(
            controller: widget.controller,
            flights: data.flights,
            visitedPlaces: widget.controller.visitedPlaces,
            worldCount: countryCount,
          ),
        );
      },
    );
  }

  String _airlineCountLabel(int count) => context.strings.isZh
      ? '$count 个航班'
      : '$count ${count == 1 ? 'flight' : 'flights'}';

  Widget _airlineRankingCard(List<AirlineRankingEntry> items) =>
      AirlineRankingOverviewCard(
        airlineCount: items.length,
        pageBuilder: (_) => AirlineRankingPage(
          items: items,
          onAirlineSelected: _openAirlineFlights,
          animateEntrance: true,
        ),
      );

  Widget _countryRankingCard(List<CountryRankingEntry> items) =>
      RankingExpansionCard(
        title: context.strings.t('countries'),
        subtitle: context.strings.isZh
            ? '到访 ${items.length} 个国家／地区'
            : '${items.length} countries / regions visited',
        icon: Icons.public_rounded,
        keyPrefix: 'country-stats',
        flipOnOpen: true,
        pageBuilder: (_) => CountryStatsPage(
          items: [for (final country in items) (country.name, country.count)],
          countryCodes: {
            for (final country in items) country.name: country.countryCode,
          },
          onCountrySelected: (name) {
            final entry = items.firstWhere((entry) => entry.name == name);
            _openStatsFlights(
              title: entry.name,
              flights: entry.flights,
              visitedPlaces: entry.visitedPlaces,
            );
          },
        ),
      );

  Widget _cityRankingCard(List<CityRankingEntry> items) => RankingExpansionCard(
    title: context.strings.t('cities'),
    subtitle: cityVisitSummary(items.length, isZh: context.strings.isZh),
    icon: Icons.location_city_rounded,
    keyPrefix: 'city-ranking',
    flipOnOpen: true,
    pageBuilder: (_) => CityRankingPage(
      items: items,
      animateEntrance: true,
      onCitySelected: (entry) => _openStatsFlights(
        title: entry.name,
        flights: entry.flights,
        visitedPlaces: entry.visitedPlaces,
      ),
    ),
  );

  Future<void> _openAirlineFlights(AirlineRankingEntry entry) =>
      _openStatsFlights(title: entry.name, flights: entry.flights);

  Future<void> _openStatsFlights({
    required String title,
    required List<Flight> flights,
    List<VisitedPlace> visitedPlaces = const [],
  }) => Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (context) => Scaffold(
        appBar: AppBar(
          title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          backgroundColor: context.appColors.background,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(32),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                visitedPlaces.isEmpty
                    ? '${_airlineCountLabel(flights.length)} · ${context.strings.t('completed')}'
                    : context.strings.isZh
                    ? '${flights.length} 次飞行 · ${visitedPlaces.length} 条足迹'
                    : '${flights.length} flights · ${visitedPlaces.length} footprints',
                style: TextStyle(color: context.appColors.textSecondary),
              ),
            ),
          ),
        ),
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: ListView.separated(
                padding: const EdgeInsets.all(AppSpacing.page),
                itemCount: flights.length + visitedPlaces.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: AppSpacing.cardGap),
                itemBuilder: (context, index) => index < flights.length
                    ? FlightCard(
                        flight: flights[index],
                        controller: widget.controller,
                      )
                    : _footprintRecord(visitedPlaces[index - flights.length]),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  List<BoxShadow> _statsCardShadow(BuildContext context) =>
      AppShadows.card(context);

  Widget _footprintRecord(VisitedPlace place) => SurfaceCard(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.place_rounded, color: context.appColors.lime),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                place.name,
                style: AppTextStyles.body.copyWith(
                  color: context.appColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${context.strings.isZh ? '足迹' : 'Footprint'} · ${MaterialLocalizations.of(context).formatMediumDate(place.visitedAt.toLocal())}',
                style: AppTextStyles.bodySecondary.copyWith(
                  color: context.appColors.textSecondary,
                ),
              ),
              if (place.note?.trim().isNotEmpty ?? false) ...[
                const SizedBox(height: 8),
                Text(
                  place.note!,
                  style: AppTextStyles.bodySecondary.copyWith(
                    color: context.appColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );

  List<MapPlace> _footprintPlaces(List<Flight> flights) {
    final places = <String, MapPlace>{};
    for (final flight in flights) {
      for (final code in [flight.departureIata, flight.arrivalIata]) {
        final airport = widget.controller.airportFor(code);
        if (airport == null) continue;
        final name = localizedAirportCity(airport).trim();
        if (name.isEmpty) continue;
        places[airport.iataCode] = MapPlace(
          name: name,
          latitude: airport.latitude,
          longitude: airport.longitude,
          countryCode: airport.countryCode,
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
    return places.values.toList(growable: false);
  }

  List<MapAirport> _passportAirports(List<Flight> flights) {
    final result = <MapAirport>[];
    final seen = <String>{};
    for (final flight in flights) {
      for (final code in [flight.departureIata, flight.arrivalIata]) {
        final airport = widget.controller.airportFor(code);
        if (airport == null || !seen.add(airport.iataCode)) continue;
        result.add(
          MapAirport(
            code: airport.iataCode,
            name: localizedAirportCity(airport),
            latitude: airport.latitude,
            longitude: airport.longitude,
            isPrimary: true,
          ),
        );
      }
    }
    return result;
  }

  List<MapRoute> _passportRoutes(List<Flight> flights) {
    final routes = <MapRoute>[];
    for (final flight in flights) {
      final from = widget.controller.airportFor(flight.departureIata);
      final to = widget.controller.airportFor(flight.arrivalIata);
      if (from == null || to == null) continue;
      routes.add(
        MapRoute(
          from: MapAirport(
            code: from.iataCode,
            name: localizedAirportCity(from),
            latitude: from.latitude,
            longitude: from.longitude,
            isPrimary: true,
          ),
          to: MapAirport(
            code: to.iataCode,
            name: localizedAirportCity(to),
            latitude: to.latitude,
            longitude: to.longitude,
            isPrimary: true,
          ),
          isHighlight: routes.length.isEven,
          track: [
            for (final point in flight.track)
              MapCoordinate(point.latitude, point.longitude),
          ],
        ),
      );
    }
    return routes;
  }

  List<String> _passportFlags(List<Flight> flights) {
    final flags = <String>[];
    final seen = <String>{};
    for (final flight in flights) {
      for (final code in [flight.departureIata, flight.arrivalIata]) {
        final airport = widget.controller.airportFor(code);
        final countryCode = airport?.countryCode.trim().toUpperCase();
        if (countryCode == null ||
            countryCode.isEmpty ||
            !seen.add(countryCode)) {
          continue;
        }
        flags.add(countryCode);
      }
    }
    return flags;
  }

  Set<String> _routeKeys(List<Flight> flights) => {
    for (final flight in flights)
      ([flight.departureIata, flight.arrivalIata]..sort()).join('-'),
  };

  int _flightTimeMinutes(List<Flight> flights) => flights.fold<int>(
    0,
    (total, flight) =>
        total +
        (flight.durationMinutes ??
            (flight.arrivedAt == null
                ? 0
                : math.max(
                    0,
                    flight.arrivedAt!.difference(flight.departedAt).inMinutes,
                  ))),
  );

  List<int> _years(List<Flight> flights) =>
      flights.map((flight) => flight.departedAt.toLocal().year).toSet().toList()
        ..sort((a, b) => b.compareTo(a));
}

class _StatsViewData {
  const _StatsViewData({
    required this.hasAnyFlights,
    required this.flights,
    required this.passportYears,
    required this.selectedPassportYear,
    required this.passportFlights,
    required this.passportTotal,
    required this.countrySummaries,
    required this.passportAirports,
    required this.passportRoutes,
    required this.passportFlags,
    required this.passportFlightTimeMinutes,
    required this.passportRouteCount,
    required this.aircraftSummaries,
    required this.citySummaries,
    required this.footprintPlaces,
  });

  final bool hasAnyFlights;
  final List<Flight> flights;
  final List<int> passportYears;
  final int? selectedPassportYear;
  final List<Flight> passportFlights;
  final double passportTotal;
  final List<CountryRankingEntry> countrySummaries;
  final List<MapAirport> passportAirports;
  final List<MapRoute> passportRoutes;
  final List<String> passportFlags;
  final int passportFlightTimeMinutes;
  final int passportRouteCount;
  final List<AircraftCollectionEntry> aircraftSummaries;
  final List<CityRankingEntry> citySummaries;
  final List<MapPlace> footprintPlaces;
}

class _PassportYearFilterBar extends StatelessWidget {
  const _PassportYearFilterBar({
    required this.years,
    required this.selectedYear,
    required this.allLabel,
    required this.onChanged,
  });

  final List<int> years;
  final int? selectedYear;
  final String allLabel;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final values = <int?>[null, ...years];
    return SizedBox(
      height: 44,
      child: ListView.separated(
        padding: EdgeInsets.zero,
        scrollDirection: Axis.horizontal,
        itemCount: values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final value = values[index];
          final selected = value == selectedYear;
          final label = value == null ? allLabel : '$value';
          return Semantics(
            button: true,
            selected: selected,
            label: label,
            child: InkWell(
              customBorder: AppShapes.pill,
              onTap: () => onChanged(value),
              child: AnimatedContainer(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : AppMotion.control,
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                decoration: ShapeDecoration(
                  color: selected
                      ? context.appColors.lime
                      : context.appColors.surfaceElevated,
                  shape: AppShapes.pill,
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: selected
                        ? context.appColors.onPrimary
                        : context.appColors.textSecondary,
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
