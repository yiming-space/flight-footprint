import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../core/localization/app_strings.dart';
import '../../domain/flight.dart';
import '../add_flight/add_flight_page.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/widgets/widgets.dart';
import 'flight_card.dart';

class FlightsPage extends StatefulWidget {
  const FlightsPage({super.key, required this.controller, required this.onAdd});
  final AppController controller;
  final VoidCallback onAdd;
  @override
  State<FlightsPage> createState() => _FlightsPageState();
}

class _FlightsPageState extends State<FlightsPage> {
  int _filter = 0;
  int? _selectedYear;

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    final allFlights = widget.controller.flights;
    final upcomingCount = allFlights
        .where((flight) => flight.isUpcoming)
        .length;
    final completedFlights = allFlights
        .where((flight) => flight.isCompleted)
        .toList();
    final status = _filter == 0
        ? FlightStatus.upcoming
        : FlightStatus.completed;
    final sourceFlights = status == FlightStatus.upcoming
        ? allFlights.where((flight) => flight.isUpcoming).toList()
        : completedFlights;
    final availableYears =
        sourceFlights
            .map((flight) => flight.departedAt.toLocal().year)
            .toSet()
            .toList()
          ..sort((a, b) => b.compareTo(a));
    final selectedYear = availableYears.contains(_selectedYear)
        ? _selectedYear
        : null;
    final flights =
        sourceFlights
            .where(
              (flight) =>
                  selectedYear == null ||
                  flight.departedAt.toLocal().year == selectedYear,
            )
            .toList()
          ..sort(
            (a, b) => status == FlightStatus.upcoming
                ? a.departedAt.compareTo(b.departedAt)
                : b.departedAt.compareTo(a.departedAt),
          );
    final filters = [
      '${s.t('upcoming')} $upcomingCount',
      '${s.t('completed')} ${completedFlights.length}',
    ];
    return SafeArea(
      top: false,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.page,
                AppSpacing.lg,
                AppSpacing.page,
                AppSpacing.md,
              ),
              child: AppSegmentedControl(
                labels: filters,
                selectedIndex: _filter,
                pill: true,
                height: 52,
                onChanged: (index) => setState(() {
                  _filter = index;
                  _selectedYear = null;
                }),
              ),
            ),
          ),
          if (availableYears.isNotEmpty)
            SliverToBoxAdapter(
              child: _YearFilterBar(
                years: availableYears,
                selectedYear: selectedYear,
                onChanged: (year) => setState(() => _selectedYear = year),
                allLabel: s.t('all'),
              ),
            ),
          if (flights.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                title: s.t(
                  status == FlightStatus.upcoming
                      ? 'noUpcomingFlights'
                      : 'noCompletedFlights',
                ),
                message: s.t(
                  status == FlightStatus.upcoming
                      ? 'noUpcomingFlightsHint'
                      : 'noCompletedFlightsHint',
                ),
                action: PrimaryButton(
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
              sliver: SliverList.separated(
                itemCount: flights.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: AppSpacing.cardGap),
                itemBuilder: (context, index) => FlightCard(
                  flight: flights[index],
                  controller: widget.controller,
                  index: index,
                  onEdit: () => _editFlight(flights[index]),
                  onDelete: () => _confirmDelete(flights[index]),
                ),
              ),
            ),
        ],
      ),
    );
  }

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
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
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
                  color: selected ? AppColors.lime : AppColors.surfaceElevated,
                  shape: AppShapes.pill,
                ),
                child: Text(
                  value == null ? allLabel : '$value',
                  style: TextStyle(
                    color: selected ? Colors.black : AppColors.textSecondary,
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
