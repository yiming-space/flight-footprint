import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../core/localization/app_strings.dart';
import '../../data/airport_catalog.dart';
import '../../data/airport_localization.dart';
import '../../domain/airport.dart';
import '../../domain/flight.dart';
import '../../domain/visited_place.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/widgets/app_page_background.dart';
import 'exploration_passport.dart';
import 'personal_travel_summary.dart';
import 'personal_travel_card.dart';
import '../flights/flight_card.dart';
import 'world_exploration.dart';

class WorldExplorationPage extends StatefulWidget {
  const WorldExplorationPage({
    super.key,
    required this.controller,
    required this.flights,
    required this.visitedPlaces,
    required this.worldCount,
    this.memoryYear,
  });

  final AppController controller;
  final List<Flight> flights;
  final List<VisitedPlace> visitedPlaces;
  final int worldCount;
  final int? memoryYear;

  @override
  State<WorldExplorationPage> createState() => _WorldExplorationPageState();
}

class _WorldExplorationPageState extends State<WorldExplorationPage> {
  static const _homeAirportMetaKey = 'world_explorer_home_airport';

  Airport? _homeAirport;
  bool _homeAirportLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadHomeAirport();
  }

  Future<void> _loadHomeAirport() async {
    try {
      final code = await widget.controller.repository.getMeta(
        _homeAirportMetaKey,
      );
      if (!mounted) return;
      setState(() {
        _homeAirport = code == null ? null : widget.controller.airportFor(code);
        _homeAirportLoaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _homeAirportLoaded = true);
    }
  }

  Future<void> _chooseHomeAirport() async {
    final airport = await showModalBottomSheet<Airport>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: context.appColors.surface,
      builder: (_) => _HomeCityPicker(catalog: widget.controller.airports),
    );
    if (airport == null || !mounted) return;
    try {
      await widget.controller.repository.setMeta(
        _homeAirportMetaKey,
        airport.iataCode,
      );
      if (!mounted) return;
      setState(() => _homeAirport = airport);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.strings.t('homeCitySet'))));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.strings.t('homeCitySaveFailed'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final places = buildExplorationPlaces(
      flights: widget.flights,
      visitedPlaces: widget.visitedPlaces,
      airportFor: widget.controller.airportFor,
      isZh: context.strings.isZh,
    );
    final memories = buildPersonalTravelSummary(
      widget.flights,
      year: widget.memoryYear ?? DateTime.now().year,
      airportFor: widget.controller.airportFor,
      cityNameFor: (airport) =>
          context.strings.isZh ? localizedAirportCity(airport) : airport.city,
    );
    return AppPageBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(context.strings.t('worldExplorer')),
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
        ),
        body: SafeArea(
          top: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ExplorationPassport(
                places: places,
                worldCount: widget.worldCount,
                home: _homeAirport,
                homeLoaded: _homeAirportLoaded,
                onChooseHome: _chooseHomeAirport,
                memorySummary: memories,
                onMemorySelected: (kind) => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => PersonalTravelDetailPage(
                      summary: memories,
                      kind: kind,
                      flightBuilder: (context, flight) => FlightCard(
                        flight: flight,
                        controller: widget.controller,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeCityPicker extends StatefulWidget {
  const _HomeCityPicker({required this.catalog});

  final AirportCatalog catalog;

  @override
  State<_HomeCityPicker> createState() => _HomeCityPickerState();
}

class _HomeCityPickerState extends State<_HomeCityPicker> {
  final _queryController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  List<Airport> get _results {
    if (_query.trim().isEmpty) return const [];
    final unique = <String, Airport>{};
    for (final airport in widget.catalog.search(_query, limit: 60)) {
      final city = _cityLabel(airport, context.strings.isZh);
      if (city.isEmpty ||
          !airport.latitude.isFinite ||
          !airport.longitude.isFinite) {
        continue;
      }
      final key = '${airport.countryCode.toUpperCase()}|${city.toLowerCase()}';
      unique.putIfAbsent(key, () => airport);
      if (unique.length >= 24) break;
    }
    return unique.values.toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final colors = context.appColors;
    final results = _results;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .78,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.page,
          18,
          AppSpacing.page,
          12 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              strings.t('chooseHomeCity'),
              style: AppTextStyles.sectionTitle.copyWith(
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _queryController,
              autofocus: true,
              onChanged: (value) => setState(() => _query = value),
              style: TextStyle(color: colors.textPrimary),
              decoration: InputDecoration(
                hintText: strings.t('searchHomeCityHint'),
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: colors.surfaceElevated,
                border: OutlineInputBorder(
                  borderRadius: AppRadii.medium,
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: results.isEmpty
                  ? Center(
                      child: Text(
                        _query.trim().isEmpty
                            ? strings.t('searchHomeCityHint')
                            : strings.t('noHomeCityResults'),
                        textAlign: TextAlign.center,
                        style: AppTextStyles.bodySecondary.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: results.length,
                      separatorBuilder: (_, _) =>
                          Divider(height: 1, color: colors.border),
                      itemBuilder: (context, index) {
                        final airport = results[index];
                        final country = strings.isZh
                            ? localizedCountryName(airport.countryCode)
                            : localizedCountryEnglishName(airport.countryCode);
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            _cityLabel(airport, strings.isZh),
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            '${strings.isZh ? localizedAirportName(airport) : airport.name} · $country',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: colors.textSecondary),
                          ),
                          trailing: Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 15,
                            color: colors.textTertiary,
                          ),
                          onTap: () => Navigator.of(context).pop(airport),
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

String _cityLabel(Airport airport, bool isZh) => isZh
    ? localizedAirportCity(airport)
    : (airport.city.trim().isEmpty
          ? localizedAirportCity(airport)
          : airport.city.trim());
