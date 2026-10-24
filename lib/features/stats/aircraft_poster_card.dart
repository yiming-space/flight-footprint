import 'package:flutter/material.dart';

import '../../ui/theme/app_theme.dart';
import '../../ui/widgets/widgets.dart';

/// The collection's poster face; the caller owns press motion and semantics.
///
/// Compact height is `(width - 40) / 2.35 + 180 * textScale`, matching the
/// collection deck. The list face grows naturally for long names and large text.
class AircraftPosterCard extends StatelessWidget {
  const AircraftPosterCard({
    super.key,
    required this.model,
    required this.manufacturer,
    required this.countLabel,
    required this.distanceLabel,
    required this.artwork,
    required this.onTap,
    this.compact = false,
    this.depth = 0,
  });

  final String model;
  final String manufacturer;
  final String countLabel;
  final String distanceLabel;
  final Widget artwork;
  final VoidCallback onTap;
  final bool compact;
  final double depth;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final textScale = MediaQuery.textScalerOf(context).scale(16) / 16;
    final rearDepth = depth.isFinite ? depth.clamp(0.0, 3.0) : 0.0;
    final isZh = Localizations.localeOf(context).languageCode == 'zh';
    final family = _modelFamily(model);
    final modelStyle =
        (Theme.of(context).textTheme.headlineLarge ?? AppTextStyles.pageTitle)
            .copyWith(
              color: colors.textPrimary,
              fontSize: compact ? 40 - rearDepth.clamp(0.0, 1.0) * 12 : 36,
              height: 1,
              letterSpacing: -1,
              fontWeight: FontWeight.w600,
            );
    final manufacturerStyle = AppTextStyles.label.copyWith(
      color: colors.textSecondary,
      fontWeight: FontWeight.w400,
    );

    final title = Tooltip(
      message: model,
      child: compact
          ? FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(model, maxLines: 1, style: modelStyle),
            )
          : Text(model, style: modelStyle),
    );
    final maker = compact
        ? FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(manufacturer, maxLines: 1, style: manufacturerStyle),
          )
        : Text(manufacturer, style: manufacturerStyle);

    return SurfaceCard(
      padding: EdgeInsets.symmetric(
        horizontal: 20,
        vertical: compact ? 20 * textScale : 24,
      ),
      borderRadius: compact ? AppRadii.medium : AppRadii.small,
      color: colors.cardSurface,
      showBorder: false,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (compact)
            SizedBox(
              height: 62 * textScale,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Align(alignment: Alignment.centerLeft, child: title),
                  ),
                  SizedBox(height: 4 * textScale),
                  maker,
                ],
              ),
            )
          else ...[
            title,
            const SizedBox(height: 8),
            maker,
          ],
          SizedBox(height: compact ? 14 * textScale : 24),
          LayoutBuilder(
            builder: (context, constraints) {
              final artworkHeight = constraints.maxWidth / 2.35;
              final poster = Stack(
                alignment: Alignment.center,
                fit: compact ? StackFit.expand : StackFit.loose,
                children: [
                  if (family != model.trim().toUpperCase())
                    Positioned.fill(
                      child: ExcludeSemantics(
                        child: IgnorePointer(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: FittedBox(
                              fit: BoxFit.contain,
                              child: Text(
                                family,
                                textScaler: TextScaler.noScaling,
                                style: TextStyle(
                                  color: colors.textPrimary.withValues(
                                    alpha: .07,
                                  ),
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
                    ),
                  artwork,
                ],
              );
              if (compact) {
                return SizedBox(height: artworkHeight, child: poster);
              }
              // Missing-artwork labels may need several lines at large text
              // sizes; only the deck face has a fixed artwork-height envelope.
              return ConstrainedBox(
                constraints: BoxConstraints(minHeight: artworkHeight),
                child: poster,
              );
            },
          ),
          SizedBox(height: compact ? 12 * textScale : 24),
          if (compact)
            SizedBox(
              height: 52 * textScale,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _PosterMetric(
                      label: isZh ? '搭乘次数' : 'Flights flown',
                      value: countLabel,
                      color: colors.lime,
                      compact: true,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: _PosterMetric(
                      label: isZh ? '累计里程' : 'Distance flown',
                      value: distanceLabel,
                      color: colors.textPrimary,
                      compact: true,
                    ),
                  ),
                ],
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final count = _PosterMetric(
                  label: isZh ? '搭乘次数' : 'Flights flown',
                  value: countLabel,
                  color: colors.lime,
                );
                final distance = _PosterMetric(
                  label: isZh ? '累计里程' : 'Distance flown',
                  value: distanceLabel,
                  color: colors.textPrimary,
                );
                if (constraints.maxWidth < 280 || textScale >= 1.4) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [count, const SizedBox(height: 20), distance],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: count),
                    const SizedBox(width: 20),
                    Expanded(flex: 2, child: distance),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

class _PosterMetric extends StatelessWidget {
  const _PosterMetric({
    required this.label,
    required this.value,
    required this.color,
    this.compact = false,
  });

  final String label;
  final String value;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final caption = Text(
      label,
      maxLines: compact ? 1 : null,
      style: AppTextStyles.label.copyWith(
        color: context.appColors.textSecondary,
        fontSize: 12,
        fontWeight: FontWeight.w400,
      ),
    );
    final metric = Text(
      value,
      maxLines: compact ? 1 : null,
      style: AppTextStyles.body.copyWith(
        color: color,
        fontWeight: FontWeight.w600,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
    Widget fit(Widget child) => FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: child,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        compact ? fit(caption) : caption,
        const SizedBox(height: 4),
        compact ? fit(metric) : metric,
      ],
    );
  }
}

String _modelFamily(String model) {
  final match = RegExp(
    r'\b((?:A|B|E|C|CRJ|ERJ|ARJ)?\d{3})(?=$|[\s-]|NEO|CEO|XLR|LR|MAX)',
    caseSensitive: false,
  ).firstMatch(model);
  // Unknown model names remain factual instead of borrowing a known family.
  return match?.group(1)?.toUpperCase() ?? model.trim().toUpperCase();
}
