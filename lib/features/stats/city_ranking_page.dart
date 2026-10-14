import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/localization/app_strings.dart';
import '../../ui/theme/app_theme.dart';
import 'airline_ranking_row.dart';
import 'airline_ranking_count.dart';
import 'city_ranking.dart';
import 'ranking_entrance.dart';

class CityRankingPage extends StatelessWidget {
  const CityRankingPage({
    super.key,
    required this.items,
    required this.onCitySelected,
    this.animateEntrance = false,
  });

  final List<CityRankingEntry> items;
  final ValueChanged<CityRankingEntry> onCitySelected;
  final bool animateEntrance;

  @override
  Widget build(BuildContext context) => RankingEntrance(
    enabled: animateEntrance,
    empty: items.isEmpty,
    builder: _buildPage,
  );

  Widget _buildPage(
    BuildContext context,
    Animation<double> entrance,
    bool animated,
  ) {
    final strings = context.strings;
    final colors = context.appColors;
    final maxCount = items.isEmpty ? 0 : items.first.count;

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.isZh ? '城市排行' : 'City ranking'),
        backgroundColor: colors.background,
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
              key: const PageStorageKey('city-ranking-list'),
              primary: false,
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  sliver: SliverToBoxAdapter(
                    child: Text(
                      strings.isZh
                          ? '累计 · 起降次数'
                          : 'All time · Takeoffs and landings',
                      style: AppTextStyles.bodySecondary.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                ),
                if (items.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Text(
                        strings.t('rankingEmpty'),
                        style: TextStyle(color: colors.textSecondary),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    sliver: SliverList.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final entry = items[index];
                        final rankStyle =
                            (Theme.of(context).textTheme.bodyMedium ??
                                    const TextStyle())
                                .copyWith(
                                  color: colors.textSecondary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                );
                        final rankPainter = TextPainter(
                          text: TextSpan(
                            text: '${index + 1}',
                            style: rankStyle,
                          ),
                          textDirection: Directionality.of(context),
                          textScaler: MediaQuery.textScalerOf(context),
                          locale: Localizations.maybeLocaleOf(context),
                        )..layout();
                        final rankWidth = math.max(36.0, rankPainter.width);
                        rankPainter.dispose();
                        Widget row(double reveal) => AirlineRankingRow(
                          key: ValueKey(entry.key),
                          name: entry.name,
                          subtitle: entry.countryName,
                          count: entry.count,
                          maxCount: maxCount,
                          rank: index + 1,
                          containContentInFill: true,
                          leadingWidth: rankWidth,
                          countLabel: strings.isZh
                              ? '${entry.count} 次'
                              : '${entry.count} movements',
                          fillReveal: reveal,
                          followFill: animated,
                          countBuilder: animated
                              ? (style) => AirlineRankingCount(
                                  key: ValueKey(
                                    'city-ranking-count-${entry.key}',
                                  ),
                                  count: entry.count,
                                  reveal: reveal,
                                  labelForCount: (value) => strings.isZh
                                      ? '$value 次'
                                      : '$value movements',
                                  style: style,
                                )
                              : null,
                          leading: Text(
                            '${index + 1}',
                            textAlign: TextAlign.center,
                            style: rankStyle,
                          ),
                          onTap: () => onCitySelected(entry),
                        );
                        if (!animated) return row(1);
                        final delay = index.clamp(0, 3) * .04;
                        return AnimatedBuilder(
                          key: ValueKey('city-ranking-fill-${entry.key}'),
                          animation: entrance,
                          builder: (context, _) => row(
                            Interval(
                              delay,
                              .76 + delay,
                              curve: Curves.easeOutCubic,
                            ).transform(entrance.value),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
