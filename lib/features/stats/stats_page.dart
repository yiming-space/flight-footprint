import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../core/localization/app_strings.dart';
import '../../data/airport_localization.dart';
import '../../data/city_catalog.dart';
import '../../domain/flight.dart';
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
import 'country_stats_page.dart';
import 'flight_passport_card.dart';
import 'ranking_expansion_card.dart';

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
    final countryFlags = <String, String>{};
    for (final flight in flights) {
      for (final code in [flight.departureIata, flight.arrivalIata]) {
        final airport = widget.controller.airportFor(code);
        final country = airport == null ? null : _countryName(code);
        if (airport != null && country != null) {
          countryFlags[country] = airport.countryCode.trim().toUpperCase();
        }
      }
    }
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
    );
    final footprintPlaces = _footprintPlaces(flights);
    final data = _StatsViewData(
      hasAnyFlights: hasAnyFlights,
      flights: flights,
      passportYears: passportYears,
      selectedPassportYear: selectedPassportYear,
      passportFlights: passportFlights,
      passportTotal: passportTotal,
      countryFlags: countryFlags,
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
        _emptyStats(data)
      else ...[
        _footprintStatsCard(data.footprintPlaces),
        const SizedBox(height: AppSpacing.cardGap),
        _aircraftCollectionCard(data.aircraftSummaries),
        const SizedBox(height: AppSpacing.cardGap),
        _airlineRankingCard(buildAirlineRanking(data.flights)),
        const SizedBox(height: AppSpacing.cardGap),
        _cityRankingCard(data.citySummaries),
        const SizedBox(height: AppSpacing.cardGap),
        _countryRankingCard(
          _counts(
            data.flights.expand(
              (e) => [
                _countryName(e.departureIata),
                _countryName(e.arrivalIata),
              ],
            ),
          ),
          countryCodes: data.countryFlags,
        ),
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
        ] else
          _emptyStats(data),
      ],
    );
  }

  Widget _wideStatsList(_StatsViewData data) {
    return Column(
      children: [
        _footprintStatsCard(data.footprintPlaces),
        const SizedBox(height: AppSpacing.cardGap),
        _aircraftCollectionCard(data.aircraftSummaries),
        const SizedBox(height: AppSpacing.cardGap),
        _airlineRankingCard(buildAirlineRanking(data.flights)),
        const SizedBox(height: AppSpacing.cardGap),
        _cityRankingCard(data.citySummaries),
        const SizedBox(height: AppSpacing.cardGap),
        _countryRankingCard(
          _counts(
            data.flights.expand(
              (e) => [
                _countryName(e.departureIata),
                _countryName(e.arrivalIata),
              ],
            ),
          ),
          countryCodes: data.countryFlags,
        ),
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

  Widget _footprintStatsCard(List<MapPlace> places) {
    final s = context.strings;
    return FutureBuilder<CityCatalog>(
      future: _chinaCatalog,
      builder: (context, snapshot) {
        final colors = context.appColors;
        final isLight = Theme.of(context).brightness == Brightness.light;
        final visited = places
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
        final worldProgress = (countryCount / 195).clamp(0.0, 1.0).toDouble();
        final chinaProgress = (chinaCount / 34).clamp(0.0, 1.0).toDouble();
        final cardColor = isLight ? colors.cardBlue : colors.surfaceElevated;
        final worldAccent = colors.lime;
        final chinaAccent = isLight ? colors.lime : colors.purple;
        return Semantics(
          container: true,
          label: '${s.t('worldExplorer')} · ${s.t('chinaExplorer')}',
          child: Container(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
            decoration: ShapeDecoration(
              color: cardColor,
              shape: RoundedSuperellipseBorder(
                borderRadius: AppRadii.large,
                side: BorderSide.none,
              ),
              shadows: _statsCardShadow(context),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _progressSection(
                  title: s.t('worldExplorer'),
                  count: countryCount,
                  total: 195,
                  progress: worldProgress,
                  color: worldAccent,
                  detail: s.t('visitedCountriesAndRegions'),
                ),
                const SizedBox(height: 20),
                _progressSection(
                  title: s.t('chinaExplorer'),
                  count: chinaCount,
                  total: 34,
                  progress: chinaProgress,
                  color: chinaAccent,
                  detail: s.t('visitedRegions'),
                ),
              ],
            ),
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
    final colors = context.appColors;
    final percent =
        '${(progress * 100).toStringAsFixed(progress * 100 < 10 ? 1 : 0)}%';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Text(
                title,
                style: AppTextStyles.sectionTitle.copyWith(
                  color: colors.textPrimary,
                ),
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
              borderRadius: AppRadii.pill,
              backgroundColor: colors.background.withValues(alpha: .72),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '$count / $total · $detail',
          style: AppTextStyles.bodySecondary.copyWith(
            color: Theme.of(context).brightness == Brightness.light
                ? colors.textPrimary
                : colors.textSecondary,
          ),
        ),
      ],
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

  Widget _countryRankingCard(
    List<(String, int)> items, {
    required Map<String, String> countryCodes,
  }) => RankingExpansionCard(
    title: context.strings.t('countries'),
    subtitle: context.strings.isZh
        ? '已记录 ${items.length} 个国家/地区'
        : '${items.length} countries / regions recorded',
    icon: Icons.public_rounded,
    keyPrefix: 'country-stats',
    pageBuilder: (_) => CountryStatsPage(
      items: items,
      countryCodes: countryCodes,
      onCountrySelected: _openCountryFlights,
    ),
  );

  Widget _cityRankingCard(List<CityRankingEntry> items) => RankingExpansionCard(
    title: context.strings.t('cities'),
    subtitle: context.strings.isZh
        ? '涉及 ${items.length} 个城市'
        : '${items.length} ${items.length == 1 ? 'city' : 'cities'} in your flights',
    icon: Icons.location_city_rounded,
    keyPrefix: 'city-ranking',
    pageBuilder: (_) => CityRankingPage(
      items: items,
      animateEntrance: true,
      onCitySelected: (entry) =>
          _openStatsFlights(title: entry.name, flights: entry.flights),
    ),
  );

  Future<void> _openAirlineFlights(AirlineRankingEntry entry) =>
      _openStatsFlights(title: entry.name, flights: entry.flights);

  Future<void> _openCountryFlights(String country) {
    final flights =
        widget.controller.flights
            .where(
              (flight) =>
                  flight.isCompleted &&
                  (_countryName(flight.departureIata) == country ||
                      _countryName(flight.arrivalIata) == country),
            )
            .toList()
          ..sort((a, b) => b.departedAt.compareTo(a.departedAt));
    return _openStatsFlights(title: country, flights: flights);
  }

  Future<void> _openStatsFlights({
    required String title,
    required List<Flight> flights,
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
                '${_airlineCountLabel(flights.length)} · ${context.strings.t('completed')}',
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
                itemCount: flights.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: AppSpacing.cardGap),
                itemBuilder: (context, index) => FlightCard(
                  flight: flights[index],
                  controller: widget.controller,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  List<BoxShadow> _statsCardShadow(BuildContext context) =>
      AppShadows.card(context);

  List<(String, int)> _counts(Iterable<String?> values) {
    final counts = <String, int>{};
    for (final value in values) {
      if (value == null || value.trim().isEmpty) continue;
      counts.update(value.trim(), (count) => count + 1, ifAbsent: () => 1);
    }
    return counts.entries.map((e) => (e.key, e.value)).toList()
      ..sort((a, b) => b.$2.compareTo(a.$2));
  }

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

  String? _countryName(String code) {
    final airport = widget.controller.airportFor(code);
    if (airport == null) return null;
    final country = localizedCountryName(airport.countryCode);
    return country.isEmpty ? null : country;
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
    required this.countryFlags,
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
  final Map<String, String> countryFlags;
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
