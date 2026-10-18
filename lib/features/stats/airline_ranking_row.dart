import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../ui/theme/app_theme.dart';

/// A comparative ranking bar with its count following the fill's trailing edge.
///
/// [countLabel] is localized by the caller. [leading] can carry an airline logo
/// or an offline fallback; the row itself does not fetch remote assets.
class AirlineRankingRow extends StatelessWidget {
  const AirlineRankingRow({
    required this.name,
    required this.count,
    required this.maxCount,
    required this.rank,
    required this.countLabel,
    this.subtitle,
    this.leading,
    this.accentColor,
    this.onTap,
    this.containContentInFill = false,
    this.minimumFillFraction = .64,
    this.countTravelSpace = 0,
    this.leadingWidth = 36,
    this.fillReveal = 1,
    this.countBuilder,
    this.followFill = false,
    super.key,
  });

  final String name;
  final int count;
  final int maxCount;
  final int rank;
  final String countLabel;
  final String? subtitle;
  final Widget? leading;

  /// The detected logo hue, when available; text stays theme-neutral.
  final Color? accentColor;
  final VoidCallback? onTap;

  /// Uses one readable baseline at the same width/text scale, then grows with
  /// the count. Per-row label lengths cannot change comparative bar lengths.
  final bool containContentInFill;
  final double minimumFillFraction;

  /// A small, stable gap lets an entrance count follow the fill even when a
  /// long airline name would otherwise consume every available pixel.
  final double countTravelSpace;
  final double leadingWidth;

  /// Decorative entrance only; labels and counts use their final layout.
  final double fillReveal;

  /// Optional decorative count presentation; final label still owns layout
  /// and accessibility so changing digits cannot shift the row or its name.
  final Widget Function(TextStyle style)? countBuilder;

  /// Attach the count to the painted fill during a ranking entrance, while
  /// retaining a readable lower bound after the logo and name.
  final bool followFill;

  static const _pastels = [
    Color(0xFFE7EFF9),
    Color(0xFFEEE8F8),
    Color(0xFFE5F1EB),
  ];

  static const _darkHues = [
    Color(0xFF6C91BF),
    Color(0xFF9A7BC5),
    Color(0xFF6AA68F),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final progress = maxCount <= 0 ? 0.0 : (count / maxCount).clamp(0.0, 1.0);
    final paletteIndex = rank <= 1 ? 0 : (rank - 1) % _pastels.length;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final fallbackFill = isLight
        ? _pastels[paletteIndex]
        : Color.alphaBlend(
            _darkHues[paletteIndex].withValues(alpha: .26),
            colors.surfaceElevated,
          );
    final brandHue = accentColor;
    final fill = brandHue == null
        ? fallbackFill
        : Color.alphaBlend(
            brandHue.withValues(alpha: isLight ? .17 : .30),
            isLight ? colors.surface : colors.surfaceElevated,
          );
    final labelStyle =
        (Theme.of(context).textTheme.bodyLarge ?? const TextStyle(fontSize: 16))
            .copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w600,
              height: 1.3,
            );
    final subtitleStyle =
        (Theme.of(context).textTheme.bodyMedium ??
                const TextStyle(fontSize: 14))
            .copyWith(
              color: Color.lerp(colors.textPrimary, colors.textSecondary, .45),
              fontSize: 12,
              height: 1.25,
            );

    return Semantics(
      container: true,
      label: [
        name,
        if (subtitle != null && subtitle!.isNotEmpty) subtitle,
        countLabel,
      ].join(', '),
      button: onTap != null,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        // Keep the whole row tappable without painting an unfilled track.
        type: MaterialType.transparency,
        borderRadius: AppRadii.pill,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          excludeFromSemantics: true,
          borderRadius: AppRadii.pill,
          highlightColor: colors.textPrimary.withValues(alpha: .06),
          focusColor: colors.textPrimary.withValues(alpha: .08),
          hoverColor: colors.textPrimary.withValues(alpha: .04),
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth <= 0) return const SizedBox.shrink();
              final contained = containContentInFill
                  ? _containedLayout(
                      context,
                      width: constraints.maxWidth,
                      progress: progress,
                      labelStyle: labelStyle,
                      subtitleStyle: subtitleStyle,
                    )
                  : null;
              return SizedBox(
                width: constraints.maxWidth,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: FractionallySizedBox(
                          widthFactor:
                              (contained == null
                                  ? progress
                                  : contained.fillWidth /
                                        constraints.maxWidth) *
                              fillReveal.clamp(0.0, 1.0),
                          heightFactor: 1,
                          child: Ink(
                            decoration: BoxDecoration(
                              color: fill,
                              borderRadius: AppRadii.pill,
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: contained?.fillWidth,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 64),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: contained == null
                              ? _contentRow(
                                  context,
                                  width: constraints.maxWidth,
                                  progress: progress,
                                  labelStyle: labelStyle,
                                  subtitleStyle: subtitleStyle,
                                )
                              : _containedContent(
                                  context,
                                  contained,
                                  labelStyle: labelStyle,
                                  subtitleStyle: subtitleStyle,
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _contentRow(
    BuildContext context, {
    required double width,
    required double progress,
    required TextStyle labelStyle,
    required TextStyle subtitleStyle,
  }) {
    const inset = 12.0;
    const gap = 12.0;
    final leadingSlot = leading == null ? 0.0 : leadingWidth + AppSpacing.sm;
    final contentWidth = math.max(0.0, width - inset * 2);
    final countStyle = labelStyle.copyWith(
      fontWeight: FontWeight.w700,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final countWidth = _measureText(
      context,
      countLabel,
      countStyle,
      maxWidth: math.min(
        (width * .28).clamp(56.0, 112.0),
        math.max(0.0, contentWidth - leadingSlot - gap),
      ),
    );
    final availableNameWidth = math.max(
      0.0,
      contentWidth - leadingSlot - gap - countWidth,
    );
    final nameWidth = _measureText(
      context,
      name,
      labelStyle,
      maxWidth: availableNameWidth,
      maxLines: 2,
    );
    final subtitleWidth = subtitle == null || subtitle!.isEmpty
        ? 0.0
        : _measureText(
            context,
            subtitle!,
            subtitleStyle,
            maxWidth: availableNameWidth,
            maxLines: 1,
          );
    final nameColumnWidth = math.max(nameWidth, subtitleWidth);
    final nameEnd = inset + leadingSlot + nameColumnWidth;
    final latestCountStart = width - inset - countWidth;
    final earliestCountStart = math.min(nameEnd + gap, latestCountStart);
    // Only the text is clamped. A tiny fill must not imply more flights just
    // to accommodate its logo, airline name or count.
    final countStart = (width * progress - inset - countWidth).clamp(
      earliestCountStart,
      latestCountStart,
    );
    final media = MediaQuery.maybeOf(context);
    final reduced =
        (media?.disableAnimations ?? false) ||
        (media?.accessibleNavigation ?? false);
    final reveal = reduced ? 1.0 : fillReveal.clamp(0.0, 1.0);
    final paintedCountStart = (width * progress * reveal - inset - countWidth)
        .clamp(earliestCountStart, latestCountStart);
    final direction = Directionality.of(context) == TextDirection.rtl ? -1 : 1;
    return Row(
      children: [
        if (leading != null) ...[
          SizedBox(
            width: leadingWidth,
            height: 36,
            child: Center(child: leading),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
        SizedBox(
          width: nameColumnWidth,
          child: subtitle == null || subtitle!.isEmpty
              ? Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: labelStyle,
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: labelStyle,
                    ),
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: subtitleStyle,
                    ),
                  ],
                ),
        ),
        SizedBox(width: math.max(0.0, countStart - nameEnd)),
        SizedBox(
          width: countWidth,
          child: Transform.translate(
            key: const ValueKey('ranking-count-position'),
            offset: Offset(
              followFill ? (paintedCountStart - countStart) * direction : 0,
              0,
            ),
            child:
                countBuilder?.call(countStyle) ??
                Text(countLabel, textAlign: TextAlign.end, style: countStyle),
          ),
        ),
        const Spacer(),
      ],
    );
  }

  _ContainedRankingLayout _containedLayout(
    BuildContext context, {
    required double width,
    required double progress,
    required TextStyle labelStyle,
    required TextStyle subtitleStyle,
  }) {
    const inset = 12.0;
    const gap = 12.0;
    // Determine the bar before measuring any labels. A per-row text minimum
    // made equally frequent cities differ in length and could reverse ranks.
    final textScale = MediaQuery.textScalerOf(context).scale(16) / 16;
    final minimum = minimumFillFraction.clamp(0.0, .90);
    final baseline = (minimum + .18 * (textScale - 1)).clamp(minimum, .90);
    final fillWidth = width * (baseline + (1 - baseline) * progress);
    final leadingSlot = leading == null ? 0.0 : leadingWidth + AppSpacing.sm;
    final available = math.max(0.0, fillWidth - inset * 2 - leadingSlot - gap);
    final countStyle = _countStyle(labelStyle);
    // Keep the complete count, allowing its localized unit to wrap when large
    // text would otherwise leave no useful space for the city name.
    final countWidth = _measureText(
      context,
      countLabel,
      countStyle,
      maxWidth: available / 2,
    );
    final remainingNameWidth = math.max(0.0, available - countWidth);
    final travelSpace = math.min(
      countTravelSpace.clamp(0.0, double.infinity),
      remainingNameWidth * .25,
    );
    final availableNameWidth = remainingNameWidth - travelSpace;
    final nameWidth = _measureText(
      context,
      name,
      labelStyle,
      maxWidth: availableNameWidth,
      maxLines: 2,
    );
    final subtitleWidth = subtitle == null || subtitle!.isEmpty
        ? 0.0
        : _measureText(
            context,
            subtitle!,
            subtitleStyle,
            maxWidth: availableNameWidth,
            maxLines: 1,
          );
    final nameColumnWidth = math.max(nameWidth, subtitleWidth);
    return _ContainedRankingLayout(
      fillWidth: fillWidth,
      nameWidth: nameColumnWidth,
      countWidth: countWidth,
    );
  }

  TextStyle _countStyle(TextStyle labelStyle) => labelStyle.copyWith(
    fontWeight: FontWeight.w700,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  Widget _containedContent(
    BuildContext context,
    _ContainedRankingLayout layout, {
    required TextStyle labelStyle,
    required TextStyle subtitleStyle,
  }) {
    final media = MediaQuery.maybeOf(context);
    final reduced =
        (media?.disableAnimations ?? false) ||
        (media?.accessibleNavigation ?? false);
    final reveal = reduced ? 1.0 : fillReveal.clamp(0.0, 1.0);
    final leadingSlot = leading == null ? 0.0 : leadingWidth + AppSpacing.sm;
    final latest = layout.fillWidth - 12 - layout.countWidth;
    final earliest = math.min(12 + leadingSlot + layout.nameWidth + 12, latest);
    final painted = (layout.fillWidth * reveal - 12 - layout.countWidth).clamp(
      earliest,
      latest,
    );
    final direction = Directionality.of(context) == TextDirection.rtl ? -1 : 1;
    final style = _countStyle(labelStyle);
    return Row(
      children: [
        if (leading != null) ...[
          SizedBox(
            width: leadingWidth,
            child: Center(child: leading),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
        SizedBox(
          width: layout.nameWidth,
          child: Tooltip(
            message: [
              name,
              if (subtitle != null && subtitle!.isNotEmpty) subtitle,
            ].join(', '),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: labelStyle,
                ),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: subtitleStyle,
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        const Spacer(),
        SizedBox(
          width: layout.countWidth,
          child: Transform.translate(
            key: const ValueKey('ranking-count-position'),
            offset: Offset(followFill ? (painted - latest) * direction : 0, 0),
            child:
                countBuilder?.call(style) ??
                Text(countLabel, textAlign: TextAlign.end, style: style),
          ),
        ),
      ],
    );
  }

  double _measureText(
    BuildContext context,
    String text,
    TextStyle style, {
    required double maxWidth,
    int? maxLines,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
      maxLines: maxLines,
      ellipsis: maxLines == null ? null : '…',
    )..layout(maxWidth: maxWidth);
    final measured = painter.width;
    painter.dispose();
    return measured;
  }
}

class _ContainedRankingLayout {
  const _ContainedRankingLayout({
    required this.fillWidth,
    required this.nameWidth,
    required this.countWidth,
  });

  final double fillWidth;
  final double nameWidth;
  final double countWidth;
}
