import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../core/localization/app_strings.dart';
import '../../data/airport_localization.dart';
import '../../data/flight_time_resolver.dart';
import '../../domain/flight.dart';
import '../../domain/flight_query.dart';
import '../../domain/record_health.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/widgets/frosted_glass_surface.dart';
import '../../ui/widgets/widgets.dart';
import '../add_flight/add_flight_page.dart';
import '../add_flight/flight_entry_sheet.dart';
import 'flight_card.dart';
import 'record_issues_sheet.dart';
import 'suspected_transit_panel.dart';

class FlightsPage extends StatefulWidget {
  const FlightsPage({
    super.key,
    required this.controller,
    required this.onAdd,
    this.onRecord,
  });
  final AppController controller;
  final VoidCallback onAdd;
  final ValueChanged<FlightEntryMethod>? onRecord;

  @override
  State<FlightsPage> createState() => _FlightsPageState();
}

class _FlightsPageState extends State<FlightsPage> {
  static const _twoColumnBreakpoint = 600.0;

  late final TextEditingController _searchController;
  ScrollController? _scrollController;
  int _filter = 0;
  bool _hadFlights = false;
  int? _selectedYear;
  FlightQuery _query = const FlightQuery();
  bool _showBackToTop = false;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _ensureScrollController();
    _selectInitialStatus();
  }

  void _selectInitialStatus() {
    final flights = widget.controller.flights;
    if (!_hadFlights && flights.isNotEmpty) {
      _filter = flights.any((flight) => flight.isUpcoming) ? 0 : 1;
    }
    _hadFlights = flights.isNotEmpty;
  }

  @override
  void didUpdateWidget(covariant FlightsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _selectInitialStatus();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController
      ?..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  ScrollController _ensureScrollController() {
    return _scrollController ??= ScrollController()..addListener(_handleScroll);
  }

  void _handleScroll() {
    final controller = _scrollController;
    final shouldShow =
        controller != null && controller.hasClients && controller.offset > 520;
    if (shouldShow == _showBackToTop || !mounted) return;
    setState(() => _showBackToTop = shouldShow);
  }

  void _scrollToTop() {
    final controller = _scrollController;
    if (controller == null || !controller.hasClients) return;
    controller.animateTo(
      0,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  String _airportSearchText(String iata) {
    final airport = widget.controller.airports.findByIata(iata);
    if (airport == null) return iata;
    return [
      iata,
      airport.city,
      localizedAirportCity(airport),
      airport.name,
      localizedAirportName(airport),
      ...airport.keywords,
    ].join(' ');
  }

  List<Flight> _filteredFlights() {
    final status = _filter == 0
        ? FlightStatus.upcoming
        : FlightStatus.completed;
    final source = widget.controller.flights.where((flight) {
      return status == FlightStatus.upcoming
          ? flight.isUpcoming
          : flight.isCompleted;
    }).toList();
    final flights = source.where((flight) {
      return (_selectedYear == null ||
              _departureYear(flight) == _selectedYear) &&
          _query.matches(flight, airportText: _airportSearchText);
    }).toList();
    flights.sort(
      (a, b) => status == FlightStatus.upcoming
          ? a.departedAt.compareTo(b.departedAt)
          : b.departedAt.compareTo(a.departedAt),
    );
    return flights;
  }

  List<int> _availableYears() {
    final status = _filter == 0
        ? FlightStatus.upcoming
        : FlightStatus.completed;
    return widget.controller.flights
        .where(
          (flight) => status == FlightStatus.upcoming
              ? flight.isUpcoming
              : flight.isCompleted,
        )
        .map(_departureYear)
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a));
  }

  int _departureYear(Flight flight) => FlightTimeResolver.calendarYearAtAirport(
    flight.departedAt,
    widget.controller.airports.timeZoneIdForIata(flight.departureIata),
  );

  bool get _hasQueryFilters => !_query.isEmpty || _selectedYear != null;

  void _setQuery(FlightQuery query) => setState(() => _query = query);

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _query = const FlightQuery();
      _selectedYear = null;
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => _buildPage(context),
  );

  Widget _buildPage(BuildContext context) {
    final s = context.strings;
    final allFlights = widget.controller.flights;
    final upcomingCount = allFlights
        .where((flight) => flight.isUpcoming)
        .length;
    final completedCount = allFlights
        .where((flight) => flight.isCompleted)
        .length;
    final status = _filter == 0
        ? FlightStatus.upcoming
        : FlightStatus.completed;
    final flights = _filteredFlights();
    final years = _availableYears();
    final recordHealth = inspectRecordHealth(
      flights: allFlights,
      places: widget.controller.visitedPlaces,
      airportFor: widget.controller.airportFor,
    );
    return SafeArea(
      bottom: false,
      top: false,
      left: false,
      right: false,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomScrollView(
            controller: _ensureScrollController(),
            slivers: [
              SliverToBoxAdapter(child: _buildToolbar(s)),
              if (recordHealth.count > 0)
                SliverToBoxAdapter(
                  child: _recordHealthNotice(recordHealth.count),
                ),
              SliverToBoxAdapter(
                child: SuspectedTransitPanel(controller: widget.controller),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.page,
                    AppSpacing.md,
                    AppSpacing.page,
                    0,
                  ),
                  child: AppSegmentedControl(
                    labels: [
                      '${s.t('upcoming')} $upcomingCount',
                      '${s.t('completed')} $completedCount',
                    ],
                    selectedIndex: _filter,
                    pill: true,
                    height: 44,
                    onChanged: (index) => setState(() {
                      _filter = index;
                      _selectedYear = null;
                    }),
                  ),
                ),
              ),
              if (years.isNotEmpty)
                SliverToBoxAdapter(
                  child: _YearFilterBar(
                    years: years,
                    selectedYear: _selectedYear,
                    onChanged: (year) => setState(() => _selectedYear = year),
                    allLabel: s.t('all'),
                  ),
                ),
              if (allFlights.isEmpty && !_hasQueryFilters)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      24,
                      32,
                      24,
                      AppSpacing.bottomBarClearance(context),
                    ),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 440),
                        child: FlightFirstRecord(
                          onSelected: widget.onRecord ?? (_) => widget.onAdd(),
                        ),
                      ),
                    ),
                  ),
                )
              else if (flights.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    title: _hasQueryFilters
                        ? _local('没有匹配的航班', 'No matching flights')
                        : s.t(
                            status == FlightStatus.upcoming
                                ? 'noUpcomingFlights'
                                : 'noCompletedFlights',
                          ),
                    message: _hasQueryFilters
                        ? _local(
                            '试试清除搜索或筛选条件。',
                            'Try clearing your search or filters.',
                          )
                        : s.t(
                            status == FlightStatus.upcoming
                                ? 'noUpcomingFlightsHint'
                                : 'noCompletedFlightsHint',
                          ),
                    action: _hasQueryFilters
                        ? PrimaryButton(
                            label: s.t('clear'),
                            onPressed: _clearFilters,
                            expand: false,
                          )
                        : PrimaryButton(
                            label: s.t('startRecord'),
                            onPressed: widget.onAdd,
                            expand: false,
                          ),
                  ),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.page,
                    20,
                    AppSpacing.page,
                    AppSpacing.bottomBarClearance(context),
                  ),
                  sliver: SliverLayoutBuilder(
                    builder: (context, constraints) =>
                        constraints.crossAxisExtent >= _twoColumnBreakpoint
                        ? _TwoColumnFlightSliver(
                            flights: flights,
                            cardBuilder: _flightCard,
                          )
                        : SliverList.separated(
                            itemCount: flights.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: AppSpacing.cardGap),
                            itemBuilder: (context, index) =>
                                _flightCard(flights[index]),
                          ),
                  ),
                ),
            ],
          ),
          Positioned(
            right: AppSpacing.page,
            bottom: AppSpacing.bottomBarClearance(context) - AppSpacing.sm,
            child: _BackToTopButton(
              visible: _showBackToTop,
              onPressed: _scrollToTop,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(AppStrings s) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.lg,
        AppSpacing.page,
        0,
      ),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            onChanged: (value) => _setQuery(_query.copyWith(text: value)),
            decoration: InputDecoration(
              hintText: _local(
                '搜索城市、机场、航司、机型或航班号',
                'Search city, airport, airline, aircraft or flight',
              ),
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.text.trim().isEmpty
                  ? null
                  : IconButton(
                      tooltip: s.t('clear'),
                      onPressed: () {
                        _searchController.clear();
                        _setQuery(_query.copyWith(text: ''));
                      },
                      icon: const Icon(Icons.close),
                    ),
              filled: true,
              fillColor: colors.surfaceElevated,
              border: OutlineInputBorder(
                borderRadius: AppRadii.pill,
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _recordHealthNotice(int issueCount) {
    final zh = context.strings.isZh;
    final colors = context.appColors;
    final hasIssues = issueCount > 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.md,
        AppSpacing.page,
        0,
      ),
      child: Material(
        color: hasIssues
            ? colors.danger.withValues(alpha: .09)
            : colors.surface,
        shape: AppShapes.medium,
        child: InkWell(
          customBorder: AppShapes.medium,
          onTap: _openRecordIssues,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(
                  hasIssues
                      ? Icons.warning_amber_rounded
                      : Icons.fact_check_outlined,
                  color: hasIssues ? colors.danger : colors.textSecondary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    hasIssues
                        ? (zh
                              ? '$issueCount 项需要查看或修正'
                              : '$issueCount items need review or a fix')
                        : (zh ? '记录检查 · 暂无需要修正' : 'Record check · All clear'),
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: colors.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openRecordIssues() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    requestFocus: false,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: .68),
    builder: (_) => FractionallySizedBox(
      heightFactor: .9,
      child: ClipPath(
        clipper: ShapeBorderClipper(shape: AppShapes.sheet),
        child: RecordIssuesSheet(controller: widget.controller),
      ),
    ),
  );

  Widget _flightCard(Flight flight) {
    return FlightCard(
      flight: flight,
      controller: widget.controller,
      index: widget.controller.flights.indexOf(flight),
      onEdit: () => _editFlight(flight),
      onDelete: () => _confirmDelete(flight),
    );
  }

  String _local(String zh, String en) => context.strings.isZh ? zh : en;

  Future<void> _confirmDelete(Flight flight) async {
    final s = context.strings;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.t('deleteFlight')),
        content: Text(s.t('deleteHint')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.t('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.appColors.danger,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.t('delete')),
          ),
        ],
      ),
    );
    if (confirmed == true) await widget.controller.deleteFlight(flight.id);
  }

  Future<void> _editFlight(Flight flight) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: .68),
      builder: (_) => FractionallySizedBox(
        heightFactor: .94,
        child: ClipPath(
          clipper: ShapeBorderClipper(shape: AppShapes.sheet),
          child: AddFlightPage(
            controller: widget.controller,
            initialFlight: flight,
          ),
        ),
      ),
    );
  }
}

class _BackToTopButton extends StatelessWidget {
  const _BackToTopButton({required this.visible, required this.onPressed});

  final bool visible;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        child: RepaintBoundary(
          child: SizedBox.square(
            dimension: 48,
            child: FrostedGlassSurface(
              shape: const CircleBorder(),
              edgeThickness: 2,
              adaptiveContrast: true,
              visible: visible,
              child: IconButton(
                onPressed: onPressed,
                tooltip: context.strings.isZh ? '回到顶部' : 'Back to top',
                icon: Icon(
                  Icons.keyboard_arrow_up_rounded,
                  color: context.appColors.textPrimary,
                ),
                iconSize: 26,
                constraints: const BoxConstraints.tightFor(
                  width: 48,
                  height: 48,
                ),
                padding: EdgeInsets.zero,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TwoColumnFlightSliver extends StatelessWidget {
  const _TwoColumnFlightSliver({
    required this.flights,
    required this.cardBuilder,
  });

  final List<Flight> flights;
  final Widget Function(Flight flight) cardBuilder;

  @override
  Widget build(BuildContext context) {
    final rowCount = (flights.length + 1) ~/ 2;
    return SliverList.separated(
      itemCount: rowCount,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.cardGap),
      itemBuilder: (context, row) {
        final first = row * 2;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: cardBuilder(flights[first])),
            const SizedBox(width: AppSpacing.cardGap),
            Expanded(
              child: first + 1 < flights.length
                  ? cardBuilder(flights[first + 1])
                  : const SizedBox.shrink(),
            ),
          ],
        );
      },
    );
  }
}

class _YearFilterBar extends StatelessWidget {
  const _YearFilterBar({
    required this.years,
    required this.selectedYear,
    required this.onChanged,
    required this.allLabel,
  });

  final List<int> years;
  final int? selectedYear;
  final ValueChanged<int?> onChanged;
  final String allLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final values = <int?>[null, ...years];
    return SizedBox(
      height: 56,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.page,
          8,
          AppSpacing.page,
          8,
        ),
        scrollDirection: Axis.horizontal,
        itemCount: values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final value = values[index];
          final selected = value == selectedYear;
          return Semantics(
            button: true,
            selected: selected,
            label: value == null ? allLabel : '$value',
            child: InkWell(
              customBorder: AppShapes.pill,
              onTap: () => onChanged(value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(horizontal: 17),
                alignment: Alignment.center,
                decoration: ShapeDecoration(
                  color: selected ? colors.actionFill : colors.surfaceElevated,
                  shape: AppShapes.pill,
                ),
                child: Text(
                  value == null ? allLabel : '$value',
                  style: TextStyle(
                    color: selected ? colors.onPrimary : colors.textSecondary,
                    fontSize: 14,
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
