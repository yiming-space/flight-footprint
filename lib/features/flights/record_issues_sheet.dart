import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/app_controller.dart';
import '../../core/localization/app_strings.dart';
import '../../data/airport_localization.dart';
import '../../domain/flight.dart';
import '../../domain/record_health.dart';
import '../../domain/visited_place.dart';
import '../../ui/theme/app_theme.dart';
import '../add_flight/add_flight_page.dart';
import '../map/add_visited_place_sheet.dart';

class RecordIssuesSheet extends StatelessWidget {
  const RecordIssuesSheet({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final zh = context.strings.isZh;
      final report = inspectRecordHealth(
        flights: controller.flights,
        places: controller.visitedPlaces,
        airportFor: controller.airportFor,
      );
      final colors = context.appColors;
      return Material(
        color: colors.background,
        child: SafeArea(
          top: true,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 8, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            zh ? '记录检查' : 'Record check',
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: 21,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            zh ? '这些记录暂时无法准确显示在地图上。逐条打开并修正。' : 'These records cannot be placed accurately on the map. Open each one to fix it.',
                            style: TextStyle(color: colors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: context.strings.t('close'),
                      onPressed: () => Navigator.maybePop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: report.count == 0
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.check_circle_outline_rounded,
                              size: 42,
                              color: colors.lime,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              zh ? '没有需要修正的记录' : 'No records need attention',
                              style: TextStyle(
                                color: colors.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                        children: [
                          if (report.flights.isNotEmpty) ...[
                            _SectionTitle(
                              title: zh ? '已完成航班' : 'Completed flights',
                              count: report.flights.length,
                            ),
                            for (final issue in report.flights)
                              _IssueCard(
                                title: _flightTitle(issue, controller, zh),
                                subtitle: _flightSubtitle(issue, zh),
                                actionLabel: zh ? '修正航班' : 'Fix flight',
                                onPressed: () =>
                                    _editFlight(context, issue.flight!),
                              ),
                          ],
                          if (report.suspectedDuplicateGroups.isNotEmpty) ...[
                            _SectionTitle(
                              title: zh
                                  ? '疑似重复航班'
                                  : 'Possible duplicate flights',
                              count: report.suspectedDuplicateGroups.length,
                            ),
                            for (final group in report.suspectedDuplicateGroups)
                              _DuplicateFlightGroupCard(
                                flights: group,
                                title: _duplicateTitle(group.first, controller),
                                subtitle: zh
                                    ? '航班号、起降机场和精确出发时刻一致。请逐条核对，记录不会自动合并。'
                                    : 'Flight number, airports and exact departure time match. Review each record; nothing is merged automatically.',
                                onOpen: (flight) =>
                                    _editFlight(context, flight),
                              ),
                          ],
                          if (report.places.isNotEmpty) ...[
                            _SectionTitle(
                              title: zh ? '保存的足迹' : 'Saved footprints',
                              count: report.places.length,
                            ),
                            for (final issue in report.places)
                              _IssueCard(
                                title: issue.place!.name.trim().isEmpty
                                    ? (zh ? '未命名足迹' : 'Unnamed footprint')
                                    : issue.place!.name,
                                subtitle: [
                                  DateFormat('yyyy-MM-dd')
                                      .format(issue.place!.visitedAt.toLocal()),
                                  _problemText(issue.problems, zh),
                                ].join(' · '),
                                actionLabel: zh ? '修正足迹' : 'Fix footprint',
                                onPressed: () =>
                                    _editPlace(context, issue.place!),
                              ),
                          ],
                        ],
                      ),
              ),
            ],
          ),
        ),
      );
    },
  );

  String _flightTitle(
    RecordHealthIssue issue,
    AppController controller,
    bool zh,
  ) {
    final flight = issue.flight!;
    final from = controller.airportFor(flight.departureIata);
    final to = controller.airportFor(flight.arrivalIata);
    final route =
        '${from == null ? flight.departureIata : localizedAirportCity(from)}'
        ' → ${to == null ? flight.arrivalIata : localizedAirportCity(to)}';
    final number = flight.flightNumber?.trim();
    return '${number == null || number.isEmpty ? (zh ? '航班记录' : 'Flight record') : number} · $route';
  }

  String _flightSubtitle(RecordHealthIssue issue, bool zh) => [
    DateFormat('yyyy-MM-dd').format(issue.flight!.departedAt.toLocal()),
    _problemText(issue.problems, zh),
  ].join(' · ');

  String _duplicateTitle(Flight flight, AppController controller) {
    final number = flight.flightNumber?.trim() ?? '';
    final from = controller.airportFor(flight.departureIata);
    final to = controller.airportFor(flight.arrivalIata);
    final route =
        '${from == null ? flight.departureIata : localizedAirportCity(from)}'
        ' → ${to == null ? flight.arrivalIata : localizedAirportCity(to)}';
    return '$number · $route';
  }

  String _problemText(List<RecordHealthProblem> problems, bool zh) => problems
      .map(
        (problem) => switch (problem) {
          RecordHealthProblem.unknownDepartureAirport =>
            zh ? '出发机场无法识别' : 'Departure airport not found',
          RecordHealthProblem.unknownArrivalAirport =>
            zh ? '到达机场无法识别' : 'Arrival airport not found',
          RecordHealthProblem.invalidDepartureCoordinates =>
            zh ? '出发机场坐标无效' : 'Invalid departure coordinates',
          RecordHealthProblem.invalidArrivalCoordinates =>
            zh ? '到达机场坐标无效' : 'Invalid arrival coordinates',
          RecordHealthProblem.emptyPlaceName =>
            zh ? '足迹名称为空' : 'Footprint name is empty',
          RecordHealthProblem.invalidPlaceCoordinates =>
            zh ? '足迹坐标无效' : 'Invalid footprint coordinates',
        },
      )
      .join(' · ');

  Future<void> _editFlight(BuildContext context, Flight flight) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        barrierColor: Colors.black.withValues(alpha: .68),
        builder: (_) => FractionallySizedBox(
          heightFactor: .94,
          child: ClipPath(
            clipper: ShapeBorderClipper(shape: AppShapes.sheet),
            child: AddFlightPage(controller: controller, initialFlight: flight),
          ),
        ),
      );

  Future<void> _editPlace(BuildContext context, VisitedPlace place) =>
      showModalBottomSheet<void>(
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
            child: AddVisitedPlaceSheet(
              controller: controller,
              initialPlace: place,
            ),
          ),
        ),
      );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 18, 0, 8),
    child: Text(
      '$title · $count',
      style: TextStyle(
        color: context.appColors.textSecondary,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _IssueCard extends StatelessWidget {
  const _IssueCard({
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onPressed,
  });

  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
      decoration: ShapeDecoration(
        color: colors.surface,
        shape: AppShapes.medium,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          Text(subtitle, style: TextStyle(color: colors.textSecondary)),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onPressed,
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: Text(actionLabel),
            ),
          ),
        ],
      ),
    );
  }
}

class _DuplicateFlightGroupCard extends StatelessWidget {
  const _DuplicateFlightGroupCard({
    required this.flights,
    required this.title,
    required this.subtitle,
    required this.onOpen,
  });

  final List<Flight> flights;
  final String title;
  final String subtitle;
  final ValueChanged<Flight> onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final zh = context.strings.isZh;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 8),
      decoration: ShapeDecoration(
        color: colors.surface,
        shape: AppShapes.medium,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          Text(subtitle, style: TextStyle(color: colors.textSecondary)),
          const SizedBox(height: 8),
          for (var index = 0; index < flights.length; index++) ...[
            if (index > 0) const Divider(height: 1),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${zh ? '记录' : 'Record'} ${index + 1} · ${DateFormat('yyyy-MM-dd HH:mm').format(flights[index].departedAt.toLocal())}',
                        style: TextStyle(color: colors.textPrimary),
                      ),
                      Text(
                        flights[index].id,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.textTertiary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => onOpen(flights[index]),
                  child: Text(zh ? '查看' : 'Review'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
