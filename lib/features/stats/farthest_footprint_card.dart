import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/localization/app_strings.dart';
import '../../data/airport_localization.dart';
import '../../domain/airport.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/widgets/country_flag.dart';
import '../../ui/widgets/widgets.dart';
import 'world_exploration.dart';

/// A memento of the farthest recorded place from the selected home city.
class FarthestFootprintCard extends StatefulWidget {
  const FarthestFootprintCard({
    super.key,
    required this.home,
    required this.farthest,
    required this.homeLoaded,
    required this.onChooseHome,
  });

  final Airport? home;
  final FarthestFootprint? farthest;
  final bool homeLoaded;
  final VoidCallback onChooseHome;

  @override
  State<FarthestFootprintCard> createState() => _FarthestFootprintCardState();
}

class _FarthestFootprintCardState extends State<FarthestFootprintCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _routeController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
    value: 1,
  );
  bool _motionAllowed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final media = MediaQuery.of(context);
    _motionAllowed =
        !media.disableAnimations &&
        !media.accessibleNavigation &&
        TickerMode.valuesOf(context).enabled;
    if (!_motionAllowed) _showCompletedRoute();
  }

  @override
  void didUpdateWidget(covariant FarthestFootprintCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final homeChanged =
        oldWidget.home?.iataCode != widget.home?.iataCode ||
        oldWidget.home?.latitude != widget.home?.latitude ||
        oldWidget.home?.longitude != widget.home?.longitude;
    if (homeChanged &&
        oldWidget.homeLoaded &&
        widget.homeLoaded &&
        _usableFarthest != null &&
        _motionAllowed) {
      // Restoring a saved home does not replay the memento. Only a new city
      // choice earns the brief distance reveal.
      _routeController.forward(from: 0);
    } else if (homeChanged || _usableFarthest == null || !_motionAllowed) {
      _showCompletedRoute();
    }
  }

  FarthestFootprint? get _usableFarthest {
    final home = widget.home;
    final farthest = widget.farthest;
    if (!widget.homeLoaded ||
        home == null ||
        farthest == null ||
        !_validCoordinate(home.latitude, home.longitude) ||
        !_validCoordinate(farthest.place.latitude, farthest.place.longitude) ||
        !farthest.distanceKm.isFinite ||
        farthest.distanceKm <= 0) {
      return null;
    }
    return farthest;
  }

  void _showCompletedRoute() {
    _routeController.stop();
    _routeController.value = 1;
  }

  @override
  void dispose() {
    _routeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final strings = context.strings;
    final home = widget.homeLoaded ? widget.home : null;
    final farthest = _usableFarthest;

    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        12,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      color: Theme.of(context).brightness == Brightness.light
          ? colors.surface
          : colors.surfaceElevated,
      borderRadius: AppRadii.medium,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHeading(
            showEdit: home != null,
            onChooseHome: widget.onChooseHome,
            coordinateNote: home == null
                ? null
                : '${strings.t('homeDistanceNote')}\n${_coordinateNote(home, strings.isZh, strings.t('homeAirportCoordinate'))}',
          ),
          if (home != null && farthest != null) ...[
            const SizedBox(height: AppSpacing.xs),
            _PlaceConnection(
              home: home,
              destination: farthest.place,
              metric: AnimatedBuilder(
                animation: _routeController,
                builder: (context, _) => _DistanceMetric(
                  distanceKm: farthest.distanceKm,
                  progress: Curves.easeOutCubic.transform(
                    _routeController.value,
                  ),
                ),
              ),
            ),
          ] else ...[
            const SizedBox(height: 8),
            if (!widget.homeLoaded)
              Text(
                strings.t('homeCityLoading'),
                style: AppTextStyles.bodySecondary.copyWith(
                  color: colors.textSecondary,
                ),
              )
            else if (home == null) ...[
              Text(
                strings.t('homeCityHint'),
                style: AppTextStyles.bodySecondary.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 14),
              FilledButton.tonalIcon(
                onPressed: widget.onChooseHome,
                icon: const Icon(Icons.home_outlined, size: 20),
                label: Text(strings.t('setHomeCity')),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 48),
                  foregroundColor: colors.textPrimary,
                  backgroundColor: colors.lime.withValues(alpha: .13),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              ),
            ] else ...[
              Text(
                strings.t('noExplorationPlaces'),
                style: AppTextStyles.bodySecondary.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              _CoordinateNote(home: home),
            ],
          ],
        ],
      ),
    );
  }
}

class _CardHeading extends StatelessWidget {
  const _CardHeading({
    required this.showEdit,
    required this.onChooseHome,
    this.coordinateNote,
  });

  final bool showEdit;
  final VoidCallback onChooseHome;
  final String? coordinateNote;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final title = Text(
      context.strings.t('farthestFootprint'),
      key: const ValueKey('farthest-footprint-heading'),
      style: AppTextStyles.sectionTitle.copyWith(
        color: colors.textPrimary,
        fontSize: 18,
      ),
    );
    if (!showEdit) return title;

    final edit = IconButton(
      onPressed: onChooseHome,
      tooltip: context.strings.t('setHomeCity'),
      style: IconButton.styleFrom(
        foregroundColor: colors.textSecondary,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.all(12),
      ),
      icon: const Icon(Icons.edit_outlined, size: 22),
    );
    final heading = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: title),
        if (coordinateNote != null) ...[
          const SizedBox(width: AppSpacing.sm),
          Tooltip(
            message: coordinateNote!,
            triggerMode: TooltipTriggerMode.tap,
            child: SizedBox(
              width: 48,
              height: 48,
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                // CJK ink sits below the line-box center. Move only the
                // visible mark; the full touch target stays centered.
                child: Transform.translate(
                  offset: Offset(
                    0,
                    context.strings.isZh
                        ? MediaQuery.textScalerOf(context).scale(1.5)
                        : 0,
                  ),
                  child: Icon(
                    Icons.info_outline_rounded,
                    size: 18,
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (MediaQuery.textScalerOf(context).scale(16) > 22.4) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              heading,
              Align(alignment: Alignment.centerRight, child: edit),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: heading),
            const SizedBox(width: 8),
            edit,
          ],
        );
      },
    );
  }
}

class _DistanceMetric extends StatelessWidget {
  const _DistanceMetric({required this.distanceKm, required this.progress});

  final double distanceKm;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final distance = (distanceKm * progress).round();
    final finalDistance = _formatKilometers(distanceKm.round());
    final textScaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final accent = Theme.of(context).brightness == Brightness.light
        ? Color.lerp(colors.lime, colors.textPrimary, .18)!
        : colors.lime;

    TextSpan metric(String value, double scale) => TextSpan(
      style: AppTextStyles.metric.copyWith(
        color: accent,
        fontSize: 28 * scale,
        fontWeight: FontWeight.w600,
        letterSpacing: -.6 * scale,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      children: [
        TextSpan(
          text: '≈ ',
          style: TextStyle(
            fontSize: 16 * scale,
            fontWeight: FontWeight.w400,
            color: colors.textSecondary,
            letterSpacing: 0,
          ),
        ),
        TextSpan(text: value),
        TextSpan(
          text: ' km',
          style: AppTextStyles.label.copyWith(
            fontSize: 14 * scale,
            color: colors.textSecondary,
            letterSpacing: 0,
          ),
        ),
      ],
    );

    return Semantics(
      key: const ValueKey('farthest-footprint-distance'),
      label: '≈ $finalDistance km',
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Measure the final value so counting digits cannot resize the
            // card, while large accessibility text still fits compact phones.
            final painter = TextPainter(
              text: metric(finalDistance, 1),
              textDirection: direction,
              textScaler: textScaler,
            )..layout();
            final scale = painter.width > constraints.maxWidth
                ? constraints.maxWidth / painter.width
                : 1.0;
            painter.dispose();
            return SizedBox(
              width: double.infinity,
              child: Text.rich(
                metric(_formatKilometers(distance), scale),
                key: const ValueKey('farthest-footprint-distance-value'),
                textScaler: textScaler,
                textAlign: TextAlign.start,
                softWrap: false,
                maxLines: 1,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PlaceConnection extends StatelessWidget {
  const _PlaceConnection({
    required this.home,
    required this.destination,
    required this.metric,
  });

  final Airport home;
  final ExplorationPlace destination;
  final Widget metric;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final lineColor = Color.lerp(colors.purple, colors.textSecondary, .28)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DestinationSummary(destination: destination),
        const SizedBox(height: AppSpacing.sm),
        LayoutBuilder(
          builder: (context, constraints) {
            final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
            final homeSummary = _HomeSummary(home: home);
            final date = _VisitDate(destination: destination);
            if (scale > 1.35 || constraints.maxWidth < 230) {
              // Large type keeps full-width readable content rather than
              // squeezing the accepted diagonal composition into tiny text.
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ConnectionArtwork(
                    width: constraints.maxWidth,
                    height: 32,
                    color: lineColor,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Align(alignment: Alignment.centerRight, child: homeSummary),
                  const SizedBox(height: AppSpacing.md),
                  metric,
                  const SizedBox(height: AppSpacing.sm),
                  date,
                ],
              );
            }
            final homeSize = _measureText(
              context,
              _cityName(home, context.strings.isZh),
              _HomeSummary.titleStyle(context),
              constraints.maxWidth * .36,
            );
            final labelLeadingWidth = _HomeSummary.labelLeadingWidth(home);
            final labelSize = _measureText(
              context,
              context.strings.t('homeCity'),
              _HomeSummary.labelStyle(context),
              constraints.maxWidth * .36 - labelLeadingWidth,
            );
            final homeWidth = math.max(
              homeSize.width,
              labelSize.width + labelLeadingWidth,
            );
            const homeTop = AppSpacing.lg;
            final endY = homeTop + homeSize.height / 2;
            final clearance = math.max(48.0, endY + 12);
            final lineWidth = constraints.maxWidth - homeWidth - AppSpacing.sm;
            // Measured home content determines the line endpoint and free
            // metric width, including the flag beside the label.
            return Stack(
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  child: _ConnectionArtwork(
                    width: lineWidth,
                    height: endY + 4,
                    color: lineColor,
                  ),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(height: clearance),
                          metric,
                          const SizedBox(height: AppSpacing.sm),
                          date,
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    SizedBox(
                      width: homeWidth,
                      child: Padding(
                        padding: const EdgeInsets.only(top: homeTop),
                        child: homeSummary,
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _DestinationSummary extends StatelessWidget {
  const _DestinationSummary({required this.destination});

  final ExplorationPlace destination;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final colors = context.appColors;
    final country = strings.isZh
        ? localizedCountryName(destination.countryCode)
        : localizedCountryEnglishName(destination.countryCode);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          destination.name.trim().isEmpty
              ? strings.t('unknown')
              : destination.name,
          key: const ValueKey('farthest-footprint-destination'),
          style: AppTextStyles.sectionTitle.copyWith(
            color: colors.textPrimary,
            fontSize: 34,
            height: 1.12,
            fontWeight: FontWeight.w700,
            letterSpacing: -.7,
          ),
        ),
        if (country.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ExcludeSemantics(
                child: CountryFlag(
                  code: destination.countryCode,
                  size: 24,
                  showBorder: false,
                ),
              ),
              Text(
                country,
                key: const ValueKey('farthest-footprint-country'),
                style: AppTextStyles.label.copyWith(
                  color: colors.textSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _HomeSummary extends StatelessWidget {
  const _HomeSummary({required this.home});

  final Airport home;

  static bool hasFlag(Airport home) =>
      RegExp(r'^[a-zA-Z]{2}$').hasMatch(home.countryCode.trim());

  static double labelLeadingWidth(Airport home) => hasFlag(home) ? 22 : 0;

  static TextStyle titleStyle(BuildContext context) =>
      AppTextStyles.sectionTitle.copyWith(
        color: context.appColors.textPrimary,
        fontSize: 22,
        fontWeight: FontWeight.w600,
      );

  static TextStyle labelStyle(BuildContext context) =>
      AppTextStyles.label.copyWith(
        color: context.appColors.textSecondary,
        fontSize: 14,
        fontWeight: FontWeight.w400,
      );

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        _cityName(home, context.strings.isZh),
        key: const ValueKey('farthest-footprint-home'),
        style: titleStyle(context),
      ),
      const SizedBox(height: AppSpacing.xs),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasFlag(home)) ...[
            CountryFlag(
              key: const ValueKey('farthest-footprint-home-flag'),
              code: home.countryCode,
              size: 16,
              showBorder: false,
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              context.strings.t('homeCity'),
              key: const ValueKey('farthest-footprint-home-label'),
              style: labelStyle(context),
            ),
          ),
        ],
      ),
    ],
  );
}

class _ConnectionArtwork extends StatelessWidget {
  const _ConnectionArtwork({
    required this.width,
    required this.height,
    required this.color,
  });

  final double width;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: IgnorePointer(
      child: RepaintBoundary(
        child: SizedBox(
          width: width,
          height: height,
          child: CustomPaint(
            key: const ValueKey('farthest-footprint-connection'),
            painter: _PlaceConnectionPainter(color: color),
          ),
        ),
      ),
    ),
  );
}

class _PlaceConnectionPainter extends CustomPainter {
  const _PlaceConnectionPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 16 || size.height < 16) return;
    final start = const Offset(12, 4);
    final end = Offset(size.width - 4, size.height - 4);
    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..cubicTo(
        size.width * .36,
        end.dy,
        size.width * .72,
        end.dy,
        end.dx,
        end.dy,
      );
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: .8)
        ..strokeWidth = 1.25
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );
    final dotPaint = Paint()..color = color;
    canvas.drawCircle(start, 2.5, dotPaint);
    canvas.drawCircle(end, 2.5, dotPaint);
  }

  @override
  bool shouldRepaint(_PlaceConnectionPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _VisitDate extends StatelessWidget {
  const _VisitDate({required this.destination});

  final ExplorationPlace destination;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final colors = context.appColors;
    final visitedAt = destination.visitedAt;
    return SizedBox(
      width: double.infinity,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Icon(
              Icons.calendar_today_outlined,
              size: 14,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (visitedAt != null)
                  Text(
                    strings.t('visitedOn'),
                    style: AppTextStyles.label.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: colors.textSecondary,
                    ),
                  ),
                Text(
                  visitedAt == null
                      ? strings.t('photoFootprintDateUnknown')
                      : DateFormat.yMMMd(strings.isZh ? 'zh' : 'en')
                            .format(visitedAt.toLocal()),
                  key: const ValueKey('farthest-footprint-date'),
                  style: AppTextStyles.label.copyWith(
                    color: colors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CoordinateNote extends StatelessWidget {
  const _CoordinateNote({required this.home});

  final Airport home;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final strings = context.strings;
    return Text(
      strings
          .t('homeAirportCoordinate')
          .replaceFirst(
            '{airport}',
            strings.isZh ? localizedAirportName(home) : home.name,
          ),
      style: AppTextStyles.label.copyWith(
        color: colors.textSecondary,
        fontWeight: FontWeight.w400,
      ),
    );
  }
}

Size _measureText(
  BuildContext context,
  String text,
  TextStyle style,
  double width,
) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: DefaultTextStyle.of(context).style.merge(style),
    ),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  )..layout(maxWidth: width);
  final size = painter.size;
  painter.dispose();
  return size;
}

bool _validCoordinate(double latitude, double longitude) =>
    latitude.isFinite &&
    longitude.isFinite &&
    latitude.abs() <= 90 &&
    longitude.abs() <= 180;

String _coordinateNote(Airport home, bool isZh, String template) => template
    .replaceFirst('{airport}', isZh ? localizedAirportName(home) : home.name);

String _cityName(Airport airport, bool isZh) {
  final localized = localizedAirportCity(airport);
  if (isZh && localized.isNotEmpty) return localized;
  final city = airport.city.trim();
  if (city.isNotEmpty) return city;
  if (localized.isNotEmpty) return localized;
  return airport.iataCode;
}

String _formatKilometers(int value) => value.toString().replaceAllMapped(
  RegExp(r'\B(?=(\d{3})+(?!\d))'),
  (_) => ',',
);
