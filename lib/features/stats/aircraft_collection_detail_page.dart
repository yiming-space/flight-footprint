import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/localization/app_strings.dart';
import '../../domain/flight.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/widgets/app_page_background.dart';
import 'aircraft_collection.dart';
import 'aircraft_collection_page.dart';

class AircraftCollectionDetailPage extends StatelessWidget {
  const AircraftCollectionDetailPage({
    super.key,
    required this.entry,
    required this.flightBuilder,
  });

  final AircraftCollectionEntry entry;
  final Widget Function(BuildContext, Flight) flightBuilder;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isZh = context.strings.isZh;
    final uniqueFlights = <String, Flight>{};
    for (final flight in entry.flights) {
      uniqueFlights.putIfAbsent(flight.id, () => flight);
    }
    final flights = uniqueFlights.values.toList()
      ..sort((left, right) {
        final dateOrder = right.departedAt.compareTo(left.departedAt);
        return dateOrder != 0 ? dateOrder : left.id.compareTo(right.id);
      });
    final preparedEntry = AircraftCollectionEntry(
      key: entry.key,
      type: entry.type,
      manufacturer: entry.manufacturer,
      flights: flights,
    );
    final dateFormat = DateFormat(
      isZh ? 'yyyy年M月d日' : 'MMM d, yyyy',
      isZh ? 'zh' : 'en',
    );
    final first = flights.isEmpty
        ? null
        : dateFormat.format(flights.last.departedAt.toLocal());
    final latest = flights.isEmpty
        ? null
        : dateFormat.format(flights.first.departedAt.toLocal());
    final manufacturer = aircraftManufacturerLabel(entry.manufacturer, isZh);

    return AppPageBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        key: ValueKey('aircraft-detail-page-${entry.key}'),
        appBar: AppBar(
          title: Text(isZh ? '机型记录' : 'Aircraft history'),
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
        ),
        body: SafeArea(
          top: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),
              child: CustomScrollView(
                key: PageStorageKey('aircraft-detail-list-${entry.key}'),
                primary: false,
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                    sliver: SliverToBoxAdapter(
                      child: DecoratedBox(
                        key: const ValueKey('aircraft-detail-presentation'),
                        decoration: BoxDecoration(
                          color: colors.cardSurface,
                          borderRadius: AppRadii.medium,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Tooltip(
                                    message: entry.type,
                                    child: Text(
                                      entry.type,
                                      softWrap: true,
                                      style: AppTextStyles.pageTitle.copyWith(
                                        fontSize: 32,
                                        height: 1.08,
                                        letterSpacing: -.7,
                                        color: colors.textPrimary,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    manufacturer,
                                    style: AppTextStyles.label.copyWith(
                                      color: colors.textSecondary,
                                      fontWeight: FontWeight.w400,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                              child: _AircraftDetailHero(entry: entry),
                            ),
                            _DetailSummary(
                              count: aircraftFlightCountLabel(
                                flights.length,
                                isZh,
                              ),
                              distance: aircraftDistanceLabel(
                                preparedEntry,
                                isZh,
                              ),
                              first: first,
                              latest: latest,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                    sliver: SliverToBoxAdapter(
                      child: Text(
                        isZh ? '搭乘航班' : 'Flights flown',
                        style: AppTextStyles.sectionTitle.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                  if (flights.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(32, 20, 32, 40),
                        child: Center(
                          child: Text(
                            isZh
                                ? '暂无这款机型的航班记录'
                                : 'No flights recorded for this aircraft yet',
                            textAlign: TextAlign.center,
                            style: AppTextStyles.body.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                      sliver: SliverList.separated(
                        itemCount: flights.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: AppSpacing.cardGap),
                        itemBuilder: (context, index) {
                          final flight = flights[index];
                          return KeyedSubtree(
                            key: ValueKey(
                              'aircraft-detail-flight-${flight.id}',
                            ),
                            child: flightBuilder(context, flight),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AircraftDetailHero extends StatelessWidget {
  const _AircraftDetailHero({required this.entry});

  final AircraftCollectionEntry entry;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isLight = colors.isLightPalette;
    final family = _aircraftModelFamily(entry.type);
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxWidth / 2.6;
        return ConstrainedBox(
          key: const ValueKey('aircraft-detail-hero'),
          constraints: BoxConstraints(minHeight: height),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: ExcludeSemantics(
                  child: IgnorePointer(
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: Text(
                        family,
                        key: const ValueKey('aircraft-detail-family-label'),
                        textScaler: TextScaler.noScaling,
                        style: TextStyle(
                          color:
                              (isLight ? colors.displaySecondary : colors.lime)
                                  .withValues(alpha: isLight ? .11 : .09),
                          fontSize: 132,
                          height: 1,
                          letterSpacing: -4,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              AircraftExhibitArtwork(
                key: const ValueKey('aircraft-detail-exhibit'),
                entry: entry,
                aspectRatio: 2.6,
              ),
            ],
          ),
        );
      },
    );
  }
}

String _aircraftModelFamily(String model) {
  final match = RegExp(
    r'\b((?:A|B|E|C|CRJ|ERJ|ARJ)?\d{3})(?=$|[\s-]|NEO|CEO|XLR|LR|MAX)',
    caseSensitive: false,
  ).firstMatch(model);
  return match?.group(1)?.toUpperCase() ?? model.trim().toUpperCase();
}

/// One shared grid for the two metrics and their supporting flight dates.
/// Natural-height cells reflow rather than shrinking user-selected text.
class _DetailSummary extends StatelessWidget {
  const _DetailSummary({
    required this.count,
    required this.distance,
    required this.first,
    required this.latest,
  });

  final String count;
  final String distance;
  final String? first;
  final String? latest;

  @override
  Widget build(BuildContext context) {
    final isZh = context.strings.isZh;
    final colors = context.appColors;
    return LayoutBuilder(
      key: const ValueKey('aircraft-detail-summary'),
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
        final columns = constraints.maxWidth >= 320 && scale < 1.5 ? 2 : 1;
        final width =
            (constraints.maxWidth - 40 - 24 * (columns - 1)) / columns;
        Widget cell(Widget child) => SizedBox(width: width, child: child);
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 24,
                runSpacing: 20,
                children: [
                  cell(
                    _DetailMetric(
                      key: const ValueKey('aircraft-detail-count'),
                      label: isZh ? '搭乘次数' : 'Flights flown',
                      value: count,
                      valueColor: colors.textPrimary,
                    ),
                  ),
                  cell(
                    _DetailMetric(
                      key: const ValueKey('aircraft-detail-distance'),
                      label: isZh ? '飞行里程' : 'Flight distance',
                      value: distance,
                      valueColor: colors.textPrimary,
                    ),
                  ),
                ],
              ),
              if (first != null && latest != null) ...[
                const SizedBox(height: 24),
                Wrap(
                  spacing: 24,
                  runSpacing: 16,
                  children: [
                    cell(
                      _FlightDate(
                        key: const ValueKey('aircraft-detail-first-flight'),
                        label: isZh ? '首次搭乘' : 'First flown',
                        date: first!,
                      ),
                    ),
                    cell(
                      _FlightDate(
                        key: const ValueKey('aircraft-detail-latest-flight'),
                        label: isZh ? '最近搭乘' : 'Last flown',
                        date: latest!,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _DetailMetric extends StatelessWidget {
  const _DetailMetric({
    super.key,
    required this.label,
    required this.value,
    required this.valueColor,
  });

  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final number = RegExp(r'\d[\d,]*(?:\.\d+)?').firstMatch(value);
    final recorded = value.startsWith('已记录') || value.endsWith(' recorded');
    final metricLabel = recorded
        ? (context.strings.isZh ? '已记录里程' : 'Recorded distance')
        : label;
    final suffix = number == null
        ? ''
        : value
              .substring(number.end)
              .replaceFirst(RegExp(r'\s+(?:total|recorded)$'), '');
    final style = AppTextStyles.label.copyWith(
      color: colors.textSecondary,
      fontWeight: FontWeight.w500,
      height: 1.35,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Semantics(
      label: '$label, $value',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            metricLabel,
            style: AppTextStyles.label.copyWith(
              color: colors.textSecondary,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 6),
          if (number == null)
            Text(value, style: style.copyWith(fontSize: 18))
          else
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: number.group(0),
                    style: TextStyle(
                      fontSize: 28,
                      height: 1.15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -.5,
                      color: valueColor,
                    ),
                  ),
                  TextSpan(text: suffix),
                ],
              ),
              style: style,
            ),
        ],
      ),
    );
  }
}

class _FlightDate extends StatelessWidget {
  const _FlightDate({super.key, required this.label, required this.date});

  final String label;
  final String date;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Semantics(
      label: '$label, $date',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTextStyles.label.copyWith(
              color: colors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            date,
            style: AppTextStyles.label.copyWith(
              color: colors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
