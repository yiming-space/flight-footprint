import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/localization/app_strings.dart';
import '../../domain/flight.dart';
import '../../data/airport_localization.dart';
import '../../ui/widgets/country_flag.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/widgets/app_page_background.dart';
import '../../ui/widgets/surface_card.dart';
import 'aircraft_collection.dart';
import 'aircraft_collection_page.dart' show AircraftExhibitArtwork;
import 'personal_travel_summary.dart';
import 'exploration_memory_layout.dart';

enum PersonalTravelKind { newCities, frequentRoute, newAircraft }

/// One memory per page, matching the exploration memento surface.
class PersonalTravelMomentCard extends StatelessWidget {
  const PersonalTravelMomentCard({
    super.key,
    required this.summary,
    required this.kind,
    required this.onOpen,
  });

  final PersonalTravelSummary summary;
  final PersonalTravelKind kind;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final zh = context.strings.isZh;
    final colors = context.appColors;
    final city = summary.newCities.firstOrNull;
    final aircraft = summary.newAircraft.firstOrNull;
    final route = summary.frequentRoute;
    final available = switch (kind) {
      PersonalTravelKind.newCities => city != null,
      PersonalTravelKind.frequentRoute => route != null,
      PersonalTravelKind.newAircraft => aircraft != null,
    };
    final title = switch (kind) {
      PersonalTravelKind.newCities => zh ? '新抵达的城市' : 'New cities reached',
      PersonalTravelKind.frequentRoute => zh ? '最常飞的航线' : 'Most-flown route',
      PersonalTravelKind.newAircraft =>
        zh ? '首次记录的机型' : 'Aircraft first recorded',
    };
    final empty = switch (kind) {
      PersonalTravelKind.newCities =>
        zh ? '这一年还没有记录新城市' : 'No new cities recorded this year',
      PersonalTravelKind.frequentRoute =>
        zh ? '飞过两段同一航线后，就会出现在这里' : 'Fly a route twice to see it here',
      PersonalTravelKind.newAircraft =>
        zh ? '这一年还没有记录新机型' : 'No new aircraft types recorded this year',
    };
    final count = switch (kind) {
      PersonalTravelKind.newCities => summary.newCities.length,
      PersonalTravelKind.frequentRoute => route?.flights.length ?? 0,
      PersonalTravelKind.newAircraft => summary.newAircraft.length,
    };
    final date = switch (kind) {
      PersonalTravelKind.newCities => city?.arrivedAt,
      PersonalTravelKind.frequentRoute =>
        route?.flights.firstOrNull?.departedAt,
      PersonalTravelKind.newAircraft => aircraft?.firstFlight.departedAt,
    };
    return LayoutBuilder(
      builder: (context, constraints) {
        final content = _buildContent(
          context,
          zh,
          colors,
          title,
          empty,
          available,
          city,
          route,
          aircraft,
          count,
          date,
          minHeight: constraints.minHeight,
        );
        return SurfaceCard(
          key: ValueKey('personal-travel-${kind.name}'),
          onTap: available ? onOpen : null,
          padding: ExplorationMemoryLayout.padding,
          color: colors.cardSurface,
          borderRadius: AppRadii.medium,
          child: constraints.hasBoundedHeight
              ? SingleChildScrollView(child: content)
              : content,
        );
      },
    );
  }

  Widget _buildContent(
    BuildContext context,
    bool zh,
    AppThemeColors colors,
    String title,
    String empty,
    bool available,
    NewCityMoment? city,
    FrequentRouteMoment? route,
    NewAircraftMoment? aircraft,
    int count,
    DateTime? date, {
    double minHeight = 0,
  }) {
    final aircraftEntry = aircraft == null
        ? null
        : buildAircraftCollection([aircraft.firstFlight]).firstOrNull;

    return ExplorationMemoryLayout(
      minHeight: minHeight,
      heading: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text(
              title,
              style: AppTextStyles.label.copyWith(
                color: colors.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: .15,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${summary.year}',
            style: AppTextStyles.label.copyWith(
              color: colors.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
      body: !available
          ? _EmptyTravelMoment(message: empty, colors: colors)
          : switch (kind) {
              PersonalTravelKind.newCities => _NewCityMomentHero(
                city: city!,
                colors: colors,
                isZh: zh,
                count: count,
              ),
              PersonalTravelKind.frequentRoute => _FrequentRouteMomentHero(
                route: route!,
                colors: colors,
              ),
              PersonalTravelKind.newAircraft => _AircraftMomentHero(
                entry: aircraftEntry,
              ),
            },
      footer: !available
          ? null
          : _buildFooter(context, kind, count, date, aircraft),
    );
  }

  Widget _buildFooter(
    BuildContext context,
    PersonalTravelKind kind,
    int count,
    DateTime? date,
    NewAircraftMoment? aircraft,
  ) {
    final zh = context.strings.isZh;
    final colors = context.appColors;
    final leftLabel = switch (kind) {
      PersonalTravelKind.newCities => zh ? '本年新增城市' : 'New cities',
      PersonalTravelKind.frequentRoute => zh ? '本年搭乘' : 'Flights this year',
      PersonalTravelKind.newAircraft => zh ? '首次机型' : 'Aircraft',
    };
    final leftValue = kind == PersonalTravelKind.newAircraft && aircraft != null
        ? aircraft.type
        : switch (kind) {
            PersonalTravelKind.newCities =>
              '$count${zh ? ' 座' : (count == 1 ? ' city' : ' cities')}',
            PersonalTravelKind.frequentRoute =>
              '$count${zh ? ' 次' : (count == 1 ? ' flight' : ' flights')}',
            PersonalTravelKind.newAircraft =>
              '$count${zh ? ' 种' : (count == 1 ? ' type' : ' types')}',
          };
    final dateLabel = switch (kind) {
      PersonalTravelKind.newCities => zh ? '首次抵达' : 'First arrival',
      PersonalTravelKind.frequentRoute => zh ? '首次搭乘' : 'First flown',
      PersonalTravelKind.newAircraft => zh ? '首次记录' : 'First recorded',
    };
    final dateText = Text(
      date == null
          ? '—'
          : DateFormat.yMMMd(zh ? 'zh' : 'en').format(date.toLocal()),
      key: const ValueKey('personal-travel-date'),
      maxLines: 2,
      overflow: TextOverflow.clip,
      style: AppTextStyles.label.copyWith(
        color: colors.textPrimary,
        fontSize: 14,
        fontWeight: FontWeight.w500,
        height: 1.35,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
    final cityFooter = kind == PersonalTravelKind.newCities;
    return ExplorationMemoryFooter(
      leftLabel: cityFooter ? (zh ? '首次抵达' : 'First arrival') : leftLabel,
      leftValue: Text(
        cityFooter ? '' : leftValue,
        key: const ValueKey('personal-travel-count'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyles.label.copyWith(
          color: colors.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          height: 1.35,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      rightLabel: cityFooter ? '' : dateLabel,
      rightValue: dateText,
      inline: cityFooter,
    );
  }
}

class _NewCityMomentHero extends StatelessWidget {
  const _NewCityMomentHero({
    required this.city,
    required this.colors,
    required this.isZh,
    required this.count,
  });

  final NewCityMoment city;
  final AppThemeColors colors;
  final bool isZh;
  final int count;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final largeText = MediaQuery.textScalerOf(context).scale(16) / 16 > 1.15;
      final rightFlex = largeText ? 3 : 1;
      final leftFlex = largeText ? 2 : 2;
      final leftWidth =
          constraints.maxWidth * leftFlex / (leftFlex + rightFlex);
      final fontSize = math.min(44.0, math.max(28.0, leftWidth * .24));
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: leftFlex,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  city.name,
                  key: const ValueKey('personal-travel-city-name'),
                  softWrap: true,
                  style: AppTextStyles.sectionTitle.copyWith(
                    color: colors.textPrimary,
                    fontSize: fontSize,
                    height: 1.12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -.5,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    CountryFlag(
                      code: city.countryCode,
                      size: 18,
                      showBorder: false,
                    ),
                    Text(
                      isZh
                          ? localizedCountryName(city.countryCode)
                          : localizedCountryEnglishName(city.countryCode),
                      key: const ValueKey('personal-travel-city-country'),
                      style: AppTextStyles.bodySecondary.copyWith(
                        color: colors.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: rightFlex,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Wrap(
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 4,
                  children: [
                    Text(
                      '$count',
                      key: const ValueKey('personal-travel-new-city-count'),
                      textAlign: TextAlign.end,
                      style: AppTextStyles.metric.copyWith(
                        color: colors.displayPrimary,
                        fontSize: 44,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      isZh ? '座' : (count == 1 ? 'city' : 'cities'),
                      style: AppTextStyles.label.copyWith(
                        color: colors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  isZh ? '本年新增' : 'New cities',
                  textAlign: TextAlign.end,
                  softWrap: true,
                  maxLines: 2,
                  style: AppTextStyles.label.copyWith(
                    color: colors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    },
  );
}

class _FrequentRouteMomentHero extends StatelessWidget {
  const _FrequentRouteMomentHero({required this.route, required this.colors});

  final FrequentRouteMoment route;
  final AppThemeColors colors;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final codeSize = math.min(
        44.0,
        math.max(32.0, constraints.maxWidth * .13),
      );
      final routePair = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: _RouteEndpoint(
              code: route.departureIata,
              city: route.fromCity,
              codeSize: codeSize,
              colors: colors,
              textAlign: TextAlign.start,
            ),
          ),
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: SizedBox(
                height: codeSize,
                child: CustomPaint(
                  key: const ValueKey('personal-travel-route-connector'),
                  painter: _BidirectionalRoutePainter(
                    color: colors.displaySecondary,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: _RouteEndpoint(
              code: route.arrivalIata,
              city: route.toCity,
              codeSize: codeSize,
              colors: colors,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      );
      return routePair;
    },
  );
}

class _RouteEndpoint extends StatelessWidget {
  const _RouteEndpoint({
    required this.code,
    required this.city,
    required this.codeSize,
    required this.colors,
    required this.textAlign,
  });

  final String code;
  final String city;
  final double codeSize;
  final AppThemeColors colors;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: textAlign == TextAlign.end
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start,
    children: [
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: textAlign == TextAlign.end
            ? AlignmentDirectional.centerEnd
            : AlignmentDirectional.centerStart,
        child: Text(
          code,
          key: ValueKey('personal-travel-route-code-$code'),
          maxLines: 1,
          style: AppTextStyles.sectionTitle.copyWith(
            color: colors.textPrimary,
            fontSize: codeSize,
            height: 1,
            fontWeight: FontWeight.w600,
            letterSpacing: -.8,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
      const SizedBox(height: 10),
      Text(
        city,
        softWrap: true,
        textAlign: textAlign,
        style: AppTextStyles.label.copyWith(
          color: colors.textSecondary,
          fontSize: 14,
          height: 1.15,
        ),
      ),
    ],
  );
}

class _AircraftMomentHero extends StatelessWidget {
  const _AircraftMomentHero({required this.entry});

  final AircraftCollectionEntry? entry;

  @override
  Widget build(BuildContext context) => entry == null
      ? const SizedBox.shrink()
      : SizedBox(
          key: const ValueKey('personal-travel-aircraft-artwork'),
          width: double.infinity,
          child: AircraftExhibitArtwork(
            entry: entry!,
            aspectRatio: 2.35,
            useHero: false,
          ),
        );
}

class _EmptyTravelMoment extends StatelessWidget {
  const _EmptyTravelMoment({required this.message, required this.colors});

  final String message;
  final AppThemeColors colors;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(
      message,
      key: const ValueKey('personal-travel-empty-message'),
      softWrap: true,
      style: AppTextStyles.bodySecondary.copyWith(
        color: colors.textSecondary,
        fontSize: 16,
        height: 1.35,
      ),
    ),
  );
}

class _BidirectionalRoutePainter extends CustomPainter {
  const _BidirectionalRoutePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: .72)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    final left = Offset(3, size.height * .6);
    final right = Offset(size.width - 3, size.height * .6);
    canvas.drawPath(
      Path()
        ..moveTo(left.dx, left.dy)
        ..quadraticBezierTo(
          size.width / 2,
          size.height * .05,
          right.dx,
          right.dy,
        ),
      paint,
    );
    canvas.drawCircle(left, 2.3, paint..style = PaintingStyle.fill);
    canvas.drawCircle(right, 2.3, paint);
  }

  @override
  bool shouldRepaint(covariant _BidirectionalRoutePainter oldDelegate) =>
      oldDelegate.color != color;
}

class PersonalTravelDetailPage extends StatelessWidget {
  const PersonalTravelDetailPage({
    super.key,
    required this.summary,
    required this.kind,
    required this.flightBuilder,
  });
  final PersonalTravelSummary summary;
  final PersonalTravelKind kind;
  final Widget Function(BuildContext, Flight) flightBuilder;

  @override
  Widget build(BuildContext context) {
    final zh = context.strings.isZh;
    final route = summary.frequentRoute;
    final title = switch (kind) {
      PersonalTravelKind.newCities => zh ? '新抵达的城市' : 'New cities reached',
      PersonalTravelKind.frequentRoute => zh ? '最常飞的航线' : 'Most-flown route',
      PersonalTravelKind.newAircraft =>
        zh ? '首次记录的机型' : 'Aircraft first recorded',
    };
    final explanation = switch (kind) {
      PersonalTravelKind.newCities =>
        zh ? '以完整飞行记录中最早的出发或抵达为依据，列出这一年新抵达城市的首条航班。历史记录不完整时，不代表人生首次到访。' : 'First arrivals this year, checked against all saved departures and arrivals. Incomplete history may not reflect your first-ever visit.',
      PersonalTravelKind.frequentRoute =>
        zh ? '统计这一年的已完成航班，同一机场对的两个方向合并；段数不等于往返次数。' : 'Completed flights this year, grouped by airport pair in both directions. Flight count is not round-trip count.',
      PersonalTravelKind.newAircraft =>
        zh ? '按完整飞行记录中该机型最早的一次乘坐计算，未填写的机型不作推测。' : 'The earliest flight for each aircraft type in your saved history. Missing types are not inferred.',
    };
    final flights = switch (kind) {
      PersonalTravelKind.newCities =>
        summary.newCities.map((item) => item.firstFlight).toList(),
      PersonalTravelKind.newAircraft =>
        summary.newAircraft.map((item) => item.firstFlight).toList(),
      PersonalTravelKind.frequentRoute => route?.flights ?? <Flight>[],
    };
    return AppPageBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text('${summary.year} · $title'),
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
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                itemCount: flights.length + 1,
                separatorBuilder: (_, _) => const SizedBox(height: 20),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Text(
                      explanation,
                      style: AppTextStyles.bodySecondary.copyWith(
                        color: context.appColors.textSecondary,
                      ),
                    );
                  }
                  final itemIndex = index - 1;
                  final flight = flights[itemIndex];
                  final label = switch (kind) {
                    PersonalTravelKind.newCities =>
                      summary.newCities[itemIndex].name,
                    PersonalTravelKind.newAircraft =>
                      summary.newAircraft[itemIndex].type,
                    PersonalTravelKind.frequentRoute =>
                      '${flight.departureIata} → ${flight.arrivalIata}',
                  };
                  final date = kind == PersonalTravelKind.newCities
                      ? summary.newCities[itemIndex].arrivedAt
                      : flight.departedAt;
                  return Column(
                    key: ValueKey(
                      'personal-travel-record-${kind.name}-${flight.id}-$itemIndex',
                    ),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        label,
                        style: AppTextStyles.sectionTitle.copyWith(
                          color: context.appColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        DateFormat.yMMMd(zh ? 'zh' : 'en')
                            .format(date.toLocal()),
                        style: AppTextStyles.label.copyWith(
                          color: context.appColors.textSecondary,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      const SizedBox(height: 10),
                      flightBuilder(context, flight),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
