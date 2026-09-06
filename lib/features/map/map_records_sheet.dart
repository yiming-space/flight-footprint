import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/app_controller.dart';
import '../../core/localization/app_strings.dart';
import '../../data/airport_localization.dart';
import '../../ui/theme/app_theme.dart';
import '../add_flight/add_flight_page.dart';
import '../flights/flight_card.dart';
import 'map_models.dart';
import 'map_record_query.dart';

/// Read-only exploration of the records behind a city or directional route.
class MapRecordsSheet extends StatefulWidget {
  const MapRecordsSheet({
    super.key,
    required this.controller,
    required this.selection,
  });
  final AppController controller;
  final MapSelection selection;

  @override
  State<MapRecordsSheet> createState() => _MapRecordsSheetState();
}

class _MapRecordsSheetState extends State<MapRecordsSheet> {
  int? _year;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      final selection = widget.selection;
      final zh = context.strings.isZh;
      final colors = context.appColors;
      MapAirport? airportFor(String code) {
        final a = controller.airportFor(code);
        return a == null
            ? null
            : MapAirport(
                code: code,
                name: localizedAirportCity(a),
                latitude: a.latitude,
                longitude: a.longitude,
              );
      }

      final flights =
          controller.flights
              .where(
                (f) =>
                    f.isCompleted &&
                    flightMatchesMapSelection(
                      f,
                      selection,
                      airportFor: airportFor,
                    ),
              )
              .toList()
            ..sort((a, b) => b.departedAt.compareTo(a.departedAt));
      final places =
          controller.visitedPlaces
              .where((p) => placeMatchesMapSelection(p, selection))
              .toList()
            ..sort((a, b) => b.visitedAt.compareTo(a.visitedAt));
      final years = {
        ...flights.map((f) => f.departedAt.toLocal().year),
        ...places.map((p) => p.visitedAt.toLocal().year),
      }.toList()..sort((a, b) => b.compareTo(a));
      final year = years.contains(_year) ? _year : null;
      final visibleFlights = flights
          .where((f) => year == null || f.departedAt.toLocal().year == year)
          .toList();
      final visiblePlaces = places
          .where((p) => year == null || p.visitedAt.toLocal().year == year)
          .toList();
      final route = selection.route;
      final title = route != null
          ? '${route.from.code} → ${route.to.code}'
          : {
              ...selection.airports.map((a) => a.name),
              ...selection.places.map((p) => p.name),
            }.join(' · ');
      return Material(
        color: colors.background,
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: context.strings.t('close'),
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              if (years.isNotEmpty)
                SizedBox(
                  height: 48,
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final y in <int?>[null, ...years])
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(
                              y == null ? context.strings.t('all') : '$y',
                            ),
                            selected: y == year,
                            onSelected: (_) => setState(() => _year = y),
                            side: BorderSide.none,
                          ),
                        ),
                    ],
                  ),
                ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                  children: [
                    Text(
                      zh
                          ? '${visibleFlights.length} 次飞行 · ${visiblePlaces.length} 条足迹'
                          : '${visibleFlights.length} flights · ${visiblePlaces.length} visits',
                      style: TextStyle(color: colors.textSecondary),
                    ),
                    const SizedBox(height: 16),
                    if (visibleFlights.isEmpty && visiblePlaces.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          zh ? '该年份暂无记录' : 'No records for this year',
                        ),
                      ),
                    for (var i = 0; i < visibleFlights.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: FlightCard(
                          flight: visibleFlights[i],
                          controller: controller,
                          index: i,
                          onEdit: () => showModalBottomSheet<void>(
                            context: context,
                            isScrollControlled: true,
                            useSafeArea: true,
                            requestFocus: false,
                            backgroundColor: Colors.transparent,
                            builder: (_) => FractionallySizedBox(
                              heightFactor: .94,
                              child: ClipPath(
                                clipper: ShapeBorderClipper(
                                  shape: AppShapes.sheet,
                                ),
                                child: AddFlightPage(
                                  controller: controller,
                                  initialFlight: visibleFlights[i],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    for (final p in visiblePlaces)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: ShapeDecoration(
                            color: colors.cardMint,
                            shape: AppShapes.medium,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                p.name,
                                style: TextStyle(
                                  color: colors.cardText,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                DateFormat('yyyy-MM-dd')
                                    .format(p.visitedAt.toLocal()),
                                style: TextStyle(color: colors.cardText),
                              ),
                              if (p.note?.trim().isNotEmpty ?? false)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    p.note!,
                                    style: TextStyle(color: colors.cardText),
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
      );
    },
  );
}
