import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../core/localization/app_strings.dart';
import '../../data/airport_localization.dart';
import '../../domain/flight.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/widgets/country_flag.dart';
import '../../ui/widgets/widgets.dart';
import '../map/map_models.dart';
import 'flight_passport_card.dart';

class StatsPage extends StatefulWidget {
  const StatsPage({super.key, required this.controller});
  final AppController controller;
  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  int? _passportYear;

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
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
    final aircraftSummaries = _aircraftSummaries(flights);
    return SafeArea(
      top: false,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: PageHeader(
              title: s.t('statistics'),
              subtitle: s.t('statsSubtitle'),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              20,
              0,
              20,
              AppSpacing.bottomBarClearance(context),
            ),
            sliver: SliverList.list(
              children: [
                if (flights.isNotEmpty) ...[
                  _PassportYearFilterBar(
                    years: passportYears,
                    selectedYear: selectedPassportYear,
                    allLabel: s.t('all'),
                    onChanged: (year) => setState(() => _passportYear = year),
                  ),
                  const SizedBox(height: 8),
                  FlightPassportCard(
                    year: selectedPassportYear ?? DateTime.now().year,
                    yearLabel: selectedPassportYear == null ? 'ALL' : null,
                    travellerName: widget.controller.travellerName,
                    distanceKm: passportTotal,
                    flightTimeMinutes: passportFlightTimeMinutes,
                    flightCount: passportFlights.length,
                    airportCount: passportAirports.length,
                    routeCount: passportRouteCount,
                    countryCodes: passportFlags,
                    airports: passportAirports,
                    routes: passportRoutes,
                  ),
                  const SizedBox(height: 14),
                ],
                SizedBox(height: flights.isNotEmpty ? 14 : 28),
                if (flights.isEmpty)
                  SurfaceCard(
                    child: EmptyState(
                      title: s.t(
                        hasAnyFlights ? 'noCompletedFlights' : 'noFlights',
                      ),
                      message: s.t('emptyStats'),
                    ),
                  )
                else ...[
                  _aircraftCollectionCard(aircraftSummaries),
                  const SizedBox(height: 12),
                  _rankingCard(
                    'airline',
                    s.t('airlineRanking'),
                    _counts(flights.map((e) => e.airline)),
                  ),
                  const SizedBox(height: 12),
                  _rankingCard(
                    'cities',
                    s.t('cities'),
                    _counts(
                      flights.expand(
                        (e) => [
                          _cityName(e.departureIata),
                          _cityName(e.arrivalIata),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _rankingCard(
                    'countries',
                    s.t('countries'),
                    _counts(
                      flights.expand(
                        (e) => [
                          _countryName(e.departureIata),
                          _countryName(e.arrivalIata),
                        ],
                      ),
                    ),
                    leadingIcons: countryFlags,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _aircraftCollectionCard(List<_AircraftSummary> items) {
    final s = context.strings;
    final secondary = <String, String>{
      for (final item in items)
        item.type: '${_formatDistance(item.distanceKm)} ${s.t('km')}',
    };
    return Semantics(
      button: true,
      label: s.t('aircraftCollection'),
      child: SurfaceCard(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
        onTap: () => _openRankingDetail(
          title: s.t('aircraftCollection'),
          icon: Icons.flight_rounded,
          subtitle: s
              .t('aircraftTypesCount')
              .replaceFirst('{count}', '${items.length}'),
          items: [for (final item in items) (item.type, item.flights.length)],
          secondaryByName: secondary,
          emptyMessage: s.t('aircraftCollectionEmpty'),
        ),
        child: _rankingCardHeader(
          title: s.t('aircraftCollection'),
          subtitle: s
              .t('aircraftTypesCount')
              .replaceFirst('{count}', '${items.length}'),
          icon: Icons.flight_rounded,
          accentColor: AppColors.lime,
        ),
      ),
    );
  }

  Widget _rankingCardHeader({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
  }) => Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(
                color: AppColors.textTertiary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
      Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: accentColor.withValues(alpha: .12),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: accentColor, size: 20),
      ),
    ],
  );

  Widget _rankingCard(
    String key,
    String title,
    List<(String, int)> items, {
    Map<String, String>? leadingIcons,
  }) {
    final s = context.strings;
    final subtitle = items.isEmpty
        ? s.t('rankingEmpty')
        : s.t('rankingEntries').replaceFirst('{count}', '${items.length}');
    final icon = _rankingIcon(key);
    final accentColor = _rankingAccentColor(key);
    return Semantics(
      button: true,
      label: title,
      child: SurfaceCard(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
        onTap: () => _openRankingDetail(
          title: title,
          icon: icon,
          subtitle: subtitle,
          items: items,
          leadingIcons: leadingIcons,
        ),
        child: _rankingCardHeader(
          title: title,
          subtitle: subtitle,
          icon: icon,
          accentColor: accentColor,
        ),
      ),
    );
  }

  Color _rankingAccentColor(String key) => switch (key) {
    'airline' || 'countries' => AppColors.purple,
    _ => AppColors.lime,
  };

  IconData _rankingIcon(String key) => switch (key) {
    'airline' => Icons.flight_takeoff_rounded,
    'cities' => Icons.location_city_rounded,
    'countries' => Icons.public_rounded,
    _ => Icons.bar_chart_rounded,
  };

  Future<void> _openRankingDetail({
    required String title,
    required IconData icon,
    required String subtitle,
    required List<(String, int)> items,
    Map<String, String>? leadingIcons,
    Map<String, String>? secondaryByName,
    String? emptyMessage,
  }) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: .72),
    builder: (sheetContext) => FractionallySizedBox(
      heightFactor: .82,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        child: Material(
          color: AppColors.background,
          child: SafeArea(
            top: false,
            child: _RankingDetailSheet(
              title: title,
              icon: icon,
              subtitle: subtitle,
              items: items,
              leadingIcons: leadingIcons,
              secondaryByName: secondaryByName,
              emptyMessage: emptyMessage,
              onClose: () => Navigator.of(sheetContext).pop(),
            ),
          ),
        ),
      ),
    ),
  );

  List<(String, int)> _counts(Iterable<String?> values) {
    final counts = <String, int>{};
    for (final value in values) {
      if (value == null || value.trim().isEmpty) continue;
      counts.update(value.trim(), (count) => count + 1, ifAbsent: () => 1);
    }
    return counts.entries.map((e) => (e.key, e.value)).toList()
      ..sort((a, b) => b.$2.compareTo(a.$2));
  }

  static String _formatDistance(double value) {
    final rounded = value.round().toString();
    return rounded.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
  }

  List<_AircraftSummary> _aircraftSummaries(List<Flight> flights) {
    final groups = <String, List<Flight>>{};
    final labels = <String, String>{};
    for (final flight in flights) {
      final raw = flight.aircraftType?.trim();
      if (raw == null || raw.isEmpty) continue;
      final key = raw.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
      labels.putIfAbsent(key, () => raw);
      groups.putIfAbsent(key, () => <Flight>[]).add(flight);
    }
    final summaries = [
      for (final entry in groups.entries)
        _AircraftSummary(type: labels[entry.key]!, flights: entry.value),
    ];
    summaries.sort((a, b) {
      final count = b.flights.length.compareTo(a.flights.length);
      return count == 0 ? a.type.compareTo(b.type) : count;
    });
    return summaries;
  }

  String? _cityName(String code) {
    final airport = widget.controller.airportFor(code);
    if (airport == null) return null;
    final city = localizedAirportCity(airport);
    return city.isEmpty ? null : city;
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
      height: 48,
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
              borderRadius: AppRadii.pill,
              onTap: () => onChanged(value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? AppColors.lime : AppColors.surface,
                  borderRadius: AppRadii.pill,
                  border: Border.all(
                    color: selected ? AppColors.lime : AppColors.border,
                  ),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: selected ? Colors.black : AppColors.textSecondary,
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

class _AircraftSummary {
  const _AircraftSummary({required this.type, required this.flights});

  final String type;
  final List<Flight> flights;

  double get distanceKm =>
      flights.fold<double>(0, (sum, flight) => sum + (flight.distanceKm ?? 0));
}

class _RankingDetailSheet extends StatelessWidget {
  const _RankingDetailSheet({
    required this.title,
    required this.icon,
    required this.subtitle,
    required this.items,
    required this.onClose,
    this.leadingIcons,
    this.secondaryByName,
    this.emptyMessage,
  });

  final String title;
  final IconData icon;
  final String subtitle;
  final List<(String, int)> items;
  final Map<String, String>? leadingIcons;
  final Map<String, String>? secondaryByName;
  final String? emptyMessage;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final maxCount = items.isEmpty ? 0 : items.first.$2;
    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: IconButton(
            tooltip: context.strings.t('close'),
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.lime.withValues(alpha: .12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: AppColors.lime, size: 22),
              ),
            ],
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: Text(
                    emptyMessage ?? context.strings.t('rankingEmpty'),
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return _RankingProgressRow(
                      name: item.$1,
                      count: item.$2,
                      maxCount: maxCount,
                      leadingCode: leadingIcons?[item.$1],
                      secondary: secondaryByName?[item.$1],
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _RankingProgressRow extends StatelessWidget {
  const _RankingProgressRow({
    required this.name,
    required this.count,
    required this.maxCount,
    this.leadingCode,
    this.secondary,
  });

  final String name;
  final int count;
  final int maxCount;
  final String? leadingCode;
  final String? secondary;

  @override
  Widget build(BuildContext context) {
    final progress = maxCount <= 0 ? 0.0 : count / maxCount;
    return Semantics(
      label: '$name, $count',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (leadingCode != null && leadingCode!.isNotEmpty) ...[
                  CountryFlag(code: leadingCode!, size: 22),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$count',
                      style: const TextStyle(
                        color: AppColors.lime,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (secondary != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        secondary!,
                        style: const TextStyle(
                          color: AppColors.textTertiary,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: AppColors.border,
                valueColor: const AlwaysStoppedAnimation<Color>(AppColors.lime),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
