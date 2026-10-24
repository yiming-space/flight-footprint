import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/localization/app_strings.dart';
import '../../domain/flight.dart';
import '../../data/airport_localization.dart';
import '../../ui/widgets/country_flag.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/widgets/app_page_background.dart';
import '../../ui/widgets/frosted_glass_surface.dart';
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
        return FrostedGlassSurface(
          shape: RoundedSuperellipseBorder(borderRadius: AppRadii.medium),
          refractionRadius: AppRadii.medium.topLeft.x,
          edgeThickness: 2,
          useLocalRefraction: true,
          adaptiveContrast: true,
          highlightStrength: Theme.of(context).brightness == Brightness.light
              ? 1.5
              : 1.35,
          tintOpacity: Theme.of(context).brightness == Brightness.light
              ? .055
              : .035,
          child: SurfaceCard(
            key: ValueKey('personal-travel-${kind.name}'),
            onTap: available ? onOpen : null,
            padding: ExplorationMemoryLayout.padding,
            color: Colors.transparent,
            borderRadius: AppRadii.medium,
            child: constraints.hasBoundedHeight
                ? SingleChildScrollView(child: content)
                : content,
          ),
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
              ),
              PersonalTravelKind.frequentRoute => _FrequentRouteMomentHero(
                route: route!,
                colors: colors,
              ),
              PersonalTravelKind.newAircraft => _AircraftMomentHero(
                type: aircraft!.type,
                entry: aircraftEntry,
                date: date,
                colors: colors,
              ),
            },
      footer: !available
          ? null
          : kind == PersonalTravelKind.frequentRoute
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _MomentDate(date: date, label: zh ? '首次搭乘' : 'First flown'),
                const SizedBox(height: 10),
                Text(
                  zh ? '往返方向合并统计' : 'Both directions combined',
                  style: AppTextStyles.label.copyWith(
                    color: colors.textTertiary,
                    fontSize: 11,
                  ),
                ),
              ],
            )
          : _AnnualCollectionSummary(count: count, kind: kind),
    );
  }
}

class _NewCityMomentHero extends StatelessWidget {
  const _NewCityMomentHero({
    required this.city,
    required this.colors,
    required this.isZh,
  });

  final NewCityMoment city;
  final AppThemeColors colors;
  final bool isZh;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final fontSize = math.min(
        56.0,
        math.max(36.0, constraints.maxWidth * .18),
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 9,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              CountryFlag(code: city.countryCode, size: 21, showBorder: false),
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
          const SizedBox(height: 12),
          Text(
            city.name,
            key: const ValueKey('personal-travel-city-name'),
            softWrap: true,
            style: AppTextStyles.sectionTitle.copyWith(
              color: colors.textPrimary,
              fontSize: fontSize,
              height: 1.12,
              fontWeight: FontWeight.w600,
              letterSpacing: -.8,
            ),
          ),
          const SizedBox(height: 28),
          _MomentDate(
            date: city.arrivedAt,
            label: isZh ? '首次抵达' : 'First arrival',
            labelKey: const ValueKey('personal-travel-city-date-label'),
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
      final zh = context.strings.isZh;
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
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            zh ? '本年搭乘' : 'Flights this year',
            textAlign: TextAlign.center,
            style: AppTextStyles.label.copyWith(
              color: colors.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 6),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '${route.flights.length}',
                  style: TextStyle(
                    color: colors.displayPrimary,
                    fontSize: 52,
                    height: 1.05,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -1,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                TextSpan(
                  text: zh
                      ? ' 次'
                      : (route.flights.length == 1 ? ' flight' : ' flights'),
                  style: TextStyle(color: colors.textSecondary, fontSize: 15),
                ),
              ],
            ),
            key: const ValueKey('personal-travel-count'),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          routePair,
        ],
      );
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
  const _AircraftMomentHero({
    required this.type,
    required this.entry,
    required this.date,
    required this.colors,
  });

  final String type;
  final AircraftCollectionEntry? entry;
  final DateTime? date;
  final AppThemeColors colors;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final model = Text(
        type,
        key: const ValueKey('personal-travel-aircraft-model'),
        softWrap: true,
        style: AppTextStyles.sectionTitle.copyWith(
          color: colors.textPrimary,
          fontSize: 29,
          height: 1.12,
          fontWeight: FontWeight.w600,
          letterSpacing: -.6,
        ),
      );
      final firstRecorded = context.strings.isZh ? '首次记录' : 'First recorded';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (entry != null) ...[
            SizedBox(
              key: const ValueKey('personal-travel-aircraft-artwork'),
              width: double.infinity,
              child: AircraftExhibitArtwork(
                entry: entry!,
                aspectRatio: 2.35,
                useHero: false,
              ),
            ),
            const SizedBox(height: 18),
          ],
          _MomentDate(date: date, label: firstRecorded, leading: model),
        ],
      );
    },
  );
}

/// An annual collection is supporting context, distinct from the featured visit
/// or aircraft. Its count shares a text line rather than competing as a metric.
class _AnnualCollectionSummary extends StatelessWidget {
  const _AnnualCollectionSummary({required this.count, required this.kind});
  final int count;
  final PersonalTravelKind kind;

  @override
  Widget build(BuildContext context) {
    final zh = context.strings.isZh;
    final colors = context.appColors;
    final city = kind == PersonalTravelKind.newCities;
    final title = city
        ? (zh ? '本年新增城市' : 'New cities this year')
        : (zh ? '本年新增机型' : 'New types this year');
    final unit = zh
        ? (city ? '座' : '种')
        : (city
              ? (count == 1 ? 'city' : 'cities')
              : (count == 1 ? 'type' : 'types'));
    final labelText = Text(
      title,
      key: city ? const ValueKey('personal-travel-city-count-label') : null,
      style: AppTextStyles.label.copyWith(
        color: colors.textSecondary,
        fontSize: 12,
        height: 1.35,
      ),
    );
    final countText = Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$count',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          TextSpan(
            text: ' $unit',
            style: TextStyle(color: colors.textSecondary),
          ),
        ],
      ),
      key: const ValueKey('personal-travel-count'),
      style: AppTextStyles.label.copyWith(fontSize: 14, height: 1.35),
    );
    return Row(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 240 ||
                  MediaQuery.textScalerOf(context).scale(14) > 18) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [labelText, const SizedBox(height: 6), countText],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Flexible(child: labelText),
                  const SizedBox(width: 8),
                  countText,
                ],
              );
            },
          ),
        ),
        const SizedBox(width: 12),
        Icon(Icons.chevron_right_rounded, size: 17, color: colors.textTertiary),
      ],
    );
  }
}

class _MomentDate extends StatelessWidget {
  const _MomentDate({
    required this.date,
    required this.label,
    this.labelKey,
    this.leading,
  });
  final DateTime? date;
  final String label;
  final Key? labelKey;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    if (date == null) return leading ?? const SizedBox.shrink();
    final colors = context.appColors;
    final labelText = Text(
      label,
      key: labelKey,
      textAlign: leading != null ? TextAlign.right : TextAlign.start,
      style: AppTextStyles.label.copyWith(
        color: colors.textSecondary,
        fontSize: 12,
        height: 1.35,
      ),
    );
    final value = Text(
      DateFormat.yMMMd(context.strings.isZh ? 'zh' : 'en')
          .format(date!.toLocal()),
      key: const ValueKey('personal-travel-date'),
      textAlign: TextAlign.right,
      style: AppTextStyles.label.copyWith(
        color: colors.textPrimary,
        fontSize: 14,
        fontWeight: FontWeight.w500,
        height: 1.35,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            constraints.maxWidth < 300 ||
            MediaQuery.textScalerOf(context).scale(14) > 18;
        if (leading != null && !stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(child: SizedBox.shrink()),
                  const SizedBox(width: 16),
                  Expanded(child: labelText),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(child: leading!),
                  const SizedBox(width: 16),
                  Expanded(child: value),
                ],
              ),
            ],
          );
        }
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (leading != null) ...[leading!, const SizedBox(height: 16)],
              labelText,
              const SizedBox(height: 6),
              value,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(child: labelText),
            const SizedBox(width: 16),
            Expanded(flex: 2, child: value),
          ],
        );
      },
    );
  }
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
