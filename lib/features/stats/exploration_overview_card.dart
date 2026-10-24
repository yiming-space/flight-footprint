import 'package:flutter/material.dart';

import '../../core/localization/app_strings.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/widgets/surface_card.dart';
import 'ranking_expansion_card.dart';

/// Presentation only: the stats page still owns the visited-place calculation.
class ExplorationOverviewCard extends StatelessWidget {
  const ExplorationOverviewCard({
    super.key,
    required this.worldCount,
    required this.chinaCount,
    required this.pageBuilder,
    this.boxShadow,
  });

  final int worldCount;
  final int chinaCount;
  final WidgetBuilder pageBuilder;
  final List<BoxShadow>? boxShadow;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final colors = context.appColors;
    final worldProgress = (worldCount / 195).clamp(0.0, 1.0).toDouble();
    final chinaProgress = (chinaCount / 34).clamp(0.0, 1.0).toDouble();
    return RankingExpansionCard(
      title: strings.t('worldExplorer'),
      subtitle:
          '$worldCount / 195 · ${strings.t('visitedCountriesAndRegions')}',
      semanticsLabel:
          '${strings.t('worldExplorer')}, ${_percent(worldProgress)}%, '
          '$worldCount / 195 · ${strings.t('visitedCountriesAndRegions')}; '
          '${strings.t('chinaExplorer')}, ${_percent(chinaProgress)}%, '
          '$chinaCount / 34 · ${strings.t('visitedRegions')}; '
          '${strings.t('explorationDetails')}',
      icon: Icons.public_rounded,
      keyPrefix: 'world-exploration',
      flipOnOpen: true,
      flipSourceRadius: AppRadii.large.topLeft.x,
      pageBuilder: pageBuilder,
      overviewBuilder: (context, onTap) => SurfaceCard(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 12),
        color: colors.cardSurface,
        borderRadius: AppRadii.large,
        boxShadow: boxShadow,
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ProgressSection(
              section: 'exploration-world',
              title: strings.t('worldExplorer'),
              count: worldCount,
              total: 195,
              progress: worldProgress,
              color: colors.lime,
              fillColor: colors.actionFill,
              detail: strings.t('visitedCountriesAndRegions'),
            ),
            const SizedBox(height: AppSpacing.lg),
            _ProgressSection(
              section: 'exploration-china',
              title: strings.t('chinaExplorer'),
              count: chinaCount,
              total: 34,
              progress: chinaProgress,
              color: colors.displaySecondary,
              detail: strings.t('visitedRegions'),
            ),
            const SizedBox(height: AppSpacing.xs),
            Align(
              key: const ValueKey('exploration-details-footer'),
              alignment: AlignmentDirectional.centerEnd,
              child: _DetailsHint(
                label: strings.t('explorationDetails'),
                style: AppTextStyles.label.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _percent(double progress) =>
    (progress * 100).toStringAsFixed(progress * 100 < 10 ? 1 : 0);

class _ProgressSection extends StatelessWidget {
  const _ProgressSection({
    required this.section,
    required this.title,
    required this.count,
    required this.total,
    required this.progress,
    required this.color,
    this.fillColor,
    required this.detail,
  });

  final String section;
  final String title;
  final int count;
  final int total;
  final double progress;
  final Color color;
  final Color? fillColor;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final titleStyle = AppTextStyles.sectionTitle.copyWith(
      color: colors.textPrimary,
    );
    final percentStyle = TextStyle(
      color: color,
      fontSize: 30,
      height: 1.1,
      fontWeight: FontWeight.w700,
      letterSpacing: -.8,
    );
    final percentSpan = TextSpan(
      text: _percent(progress),
      children: const [
        TextSpan(text: '%', style: TextStyle(fontSize: 20, letterSpacing: 0)),
      ],
    );
    final titleWidget = Text(
      title,
      key: ValueKey('$section-title'),
      style: titleStyle,
    );
    final percentWidget = Text.rich(
      percentSpan,
      key: ValueKey('$section-percent'),
      style: percentStyle,
    );
    final countStyle = AppTextStyles.bodySecondary.copyWith(
      color: colors.textSecondary,
    );
    final countSpan = TextSpan(
      style: countStyle,
      children: [
        TextSpan(
          text: '$count',
          style: TextStyle(
            color: colors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        TextSpan(text: ' / $total · $detail'),
      ],
    );
    final countWidget = Text.rich(
      countSpan,
      key: ValueKey('$section-count'),
      style: countStyle,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final requiredWidth =
                _textWidth(context, TextSpan(text: title, style: titleStyle)) +
                12 +
                _textWidth(
                  context,
                  TextSpan(style: percentStyle, children: [percentSpan]),
                );
            if (requiredWidth > constraints.maxWidth) {
              // Large type and long translations reflow, never shrink or clip.
              return Column(
                key: ValueKey('$section-stacked-header'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  titleWidget,
                  const SizedBox(height: AppSpacing.xs),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: percentWidget,
                  ),
                ],
              );
            }
            return Row(
              key: ValueKey('$section-header-row'),
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(child: titleWidget),
                const SizedBox(width: 12),
                percentWidget,
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        ClipRRect(
          borderRadius: AppRadii.pill,
          child: SizedBox(
            height: AppSpacing.sm,
            child: LinearProgressIndicator(
              key: ValueKey('$section-progress'),
              value: progress,
              borderRadius: AppRadii.pill,
              backgroundColor: Theme.of(context).brightness == Brightness.light
                  ? Color.lerp(colors.border, colors.cardSurface, .28)
                  : colors.background.withValues(alpha: .72),
              valueColor: AlwaysStoppedAnimation<Color>(fillColor ?? color),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        countWidget,
      ],
    );
  }
}

class _DetailsHint extends StatelessWidget {
  const _DetailsHint({required this.label, required this.style});

  final String label;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.baseline,
    textBaseline: TextBaseline.alphabetic,
    children: [
      Flexible(
        child: Text(label, textAlign: TextAlign.end, style: style),
      ),
      const SizedBox(width: AppSpacing.xs),
      Icon(Icons.arrow_forward_rounded, size: 16, color: style.color),
    ],
  );
}

double _textWidth(BuildContext context, TextSpan span) {
  final painter = TextPainter(
    text: TextSpan(style: DefaultTextStyle.of(context).style, children: [span]),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    locale: Localizations.maybeLocaleOf(context),
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}
