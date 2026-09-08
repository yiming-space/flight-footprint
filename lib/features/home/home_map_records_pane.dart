import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/app_controller.dart';
import '../../core/localization/app_strings.dart';
import '../../data/airport_localization.dart';
import '../../domain/flight.dart';
import '../../ui/theme/app_theme.dart';
import '../add_flight/add_flight_page.dart';
import '../flights/flight_card.dart';
import '../map/map_models.dart';
import '../map/map_record_query.dart';

/// Persistent record details shown beside the map on wide and unfolded layouts.
class HomeMapRecordsPane extends StatefulWidget {
  const HomeMapRecordsPane({
    super.key,
    required this.controller,
    required this.selection,
    required this.onClose,
  });

  final AppController controller;
  final MapSelection selection;
  final VoidCallback onClose;

  @override
  State<HomeMapRecordsPane> createState() => _HomeMapRecordsPaneState();
}

class _HomeMapRecordsPaneState extends State<HomeMapRecordsPane> {
  int? _year;

  @override
  void didUpdateWidget(covariant HomeMapRecordsPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_selectionSignature(oldWidget.selection) !=
        _selectionSignature(widget.selection)) {
      _year = null;
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      final selection = widget.selection;
      final zh = context.strings.isZh;
      final colors = context.appColors;

      MapAirport? airportFor(String code) {
        final airport = controller.airportFor(code);
        if (airport == null) return null;
        return MapAirport(
          code: code,
          name: localizedAirportCity(airport),
          latitude: airport.latitude,
          longitude: airport.longitude,
        );
      }

      final flights =
          controller.flights
              .where(
                (flight) =>
                    flight.isCompleted &&
                    flightMatchesMapSelection(
                      flight,
                      selection,
                      airportFor: airportFor,
                    ),
              )
              .toList()
            ..sort((a, b) => b.departedAt.compareTo(a.departedAt));
      final places =
          controller.visitedPlaces
              .where((place) => placeMatchesMapSelection(place, selection))
              .toList()
            ..sort((a, b) => b.visitedAt.compareTo(a.visitedAt));
      final years = {
        ...flights.map((flight) => flight.departedAt.toLocal().year),
        ...places.map((place) => place.visitedAt.toLocal().year),
      }.toList()..sort((a, b) => b.compareTo(a));
      final year = years.contains(_year) ? _year : null;
      final visibleFlights = flights
          .where(
            (flight) =>
                year == null || flight.departedAt.toLocal().year == year,
          )
          .toList(growable: false);
      final visiblePlaces = places
          .where(
            (place) => year == null || place.visitedAt.toLocal().year == year,
          )
          .toList(growable: false);
      final title = _selectionTitle(selection);

      return Semantics(
        container: true,
        label: zh ? '$title 相关记录' : '$title related records',
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: colors.surface,
            shape: RoundedSuperellipseBorder(
              borderRadius: AppRadii.large,
              side: BorderSide(color: colors.border),
            ),
            shadows: AppShadows.card(context),
          ),
          child: ClipPath(
            clipper: const ShapeBorderClipper(shape: AppShapes.large),
            child: Material(
              color: colors.surface,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 8, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.sectionTitle.copyWith(
                              color: colors.textPrimary,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: context.strings.t('close'),
                          onPressed: widget.onClose,
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                  if (years.isNotEmpty)
                    SizedBox(
                      height: 44,
                      child: ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        scrollDirection: Axis.horizontal,
                        children: [
                          for (final candidate in <int?>[null, ...years])
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(
                                  candidate == null
                                      ? context.strings.t('all')
                                      : '$candidate',
                                ),
                                selected: candidate == year,
                                onSelected: (_) =>
                                    setState(() => _year = candidate),
                                side: BorderSide.none,
                              ),
                            ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
                      children: [
                        Text(
                          zh
                              ? '${visibleFlights.length} 次飞行 · ${visiblePlaces.length} 条足迹'
                              : '${visibleFlights.length} flights · ${visiblePlaces.length} visits',
                          style: AppTextStyles.bodySecondary.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (visibleFlights.isEmpty && visiblePlaces.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(AppSpacing.lg),
                            child: Text(
                              zh ? '该年份暂无记录' : 'No records for this year',
                              style: TextStyle(color: colors.textSecondary),
                            ),
                          ),
                        for (var i = 0; i < visibleFlights.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: FlightCard(
                              flight: visibleFlights[i],
                              controller: controller,
                              index: i,
                              onEdit: () =>
                                  _editFlight(context, visibleFlights[i]),
                            ),
                          ),
                        for (final place in visiblePlaces)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Container(
                              padding: const EdgeInsets.all(AppSpacing.md),
                              decoration: ShapeDecoration(
                                color: colors.cardMint,
                                shape: AppShapes.medium,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    place.name,
                                    style: TextStyle(
                                      color: colors.cardText,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.xs),
                                  Text(
                                    DateFormat('yyyy-MM-dd')
                                        .format(place.visitedAt.toLocal()),
                                    style: TextStyle(color: colors.cardText),
                                  ),
                                  if (place.note?.trim().isNotEmpty ?? false)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Text(
                                        place.note!,
                                        style: TextStyle(
                                          color: colors.cardText,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );

  void _editFlight(BuildContext context, Flight flight) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      requestFocus: false,
      backgroundColor: Colors.transparent,
      builder: (_) => FractionallySizedBox(
        heightFactor: .94,
        child: ClipPath(
          clipper: const ShapeBorderClipper(shape: AppShapes.sheet),
          child: AddFlightPage(
            controller: widget.controller,
            initialFlight: flight,
          ),
        ),
      ),
    );
  }

  String _selectionTitle(MapSelection selection) {
    final route = selection.route;
    if (route != null) return '${route.from.code} → ${route.to.code}';
    return {
      ...selection.airports.map((airport) => airport.name),
      ...selection.places.map((place) => place.name),
    }.join(' · ');
  }

  String _selectionSignature(MapSelection selection) {
    final route = selection.route;
    if (route != null) return '${route.from.code}>${route.to.code}';
    return [
      ...selection.airports.map((airport) => 'a:${airport.code}'),
      ...selection.places.map(
        (place) =>
            'p:${place.id ?? '${place.name}:${place.latitude}:${place.longitude}'}',
      ),
    ].join('|');
  }
}
