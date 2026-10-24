import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/localization/app_strings.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/widgets/app_page_background.dart';
import '../../ui/widgets/country_flag.dart';

class CountryStatsPage extends StatelessWidget {
  const CountryStatsPage({
    super.key,
    required this.items,
    required this.countryCodes,
    required this.onCountrySelected,
  });

  final List<(String, int)> items;
  final Map<String, String> countryCodes;
  final ValueChanged<String> onCountrySelected;

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    final colors = context.appColors;
    return AppPageBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(s.t('countries')),
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
                key: const PageStorageKey('country-statistics-grid'),
                primary: false,
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                    sliver: SliverToBoxAdapter(
                      child: Text(
                        s.isZh
                            ? '到访 ${items.length} 个国家／地区'
                            : '${items.length} ${items.length == 1 ? 'country/region' : 'countries/regions'} visited',
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
                          s.t('rankingEmpty'),
                          style: TextStyle(color: colors.textSecondary),
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                      sliver: SliverLayoutBuilder(
                        builder: (context, constraints) {
                          const gap = 8.0;
                          final cellWidth =
                              (constraints.crossAxisExtent - gap * 4) / 5;
                          final flagSize = math.min(
                            48.0,
                            math.max(28.0, cellWidth - 12),
                          );
                          final labelHeight =
                              MediaQuery.textScalerOf(context).scale(12) *
                              1.25 *
                              2;
                          final cellHeight =
                              8 + flagSize + 6 + 8 + labelHeight + 8;
                          return SliverGrid.builder(
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 5,
                                  crossAxisSpacing: gap,
                                  mainAxisSpacing: 16,
                                  mainAxisExtent: cellHeight,
                                ),
                            itemCount: items.length,
                            itemBuilder: (context, index) {
                              final item = items[index];
                              return CountryStatsTile(
                                key: ValueKey(item.$1),
                                name: item.$1,
                                countryCode: countryCodes[item.$1] ?? '',
                                count: item.$2,
                                flagSize: flagSize,
                                onTap: () => onCountrySelected(item.$1),
                              );
                            },
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

class CountryStatsTile extends StatelessWidget {
  const CountryStatsTile({
    super.key,
    required this.name,
    required this.countryCode,
    required this.count,
    required this.flagSize,
    required this.onTap,
  });

  final String name;
  final String countryCode;
  final int count;
  final double flagSize;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final label = context.strings.isZh
        ? '$name，$count 次到访'
        : '$name, $count ${count == 1 ? 'visit' : 'visits'}';
    return Semantics(
      button: true,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: flagSize + 6,
                    child: LayoutBuilder(
                      builder: (context, constraints) => Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Align(
                            alignment: Alignment.bottomCenter,
                            child: CountryFlag(
                              code: countryCode,
                              size: flagSize,
                              showBorder: false,
                            ),
                          ),
                          PositionedDirectional(
                            top: 0,
                            end: math.max(
                              0.0,
                              (constraints.maxWidth - flagSize) / 2 - 4,
                            ),
                            child: Container(
                              constraints: BoxConstraints(
                                minWidth: 18,
                                minHeight: 18,
                                maxWidth: constraints.maxWidth * .7,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: colors.actionFill,
                                borderRadius: AppRadii.pill,
                              ),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  '$count',
                                  style: TextStyle(
                                    color: colors.onPrimary,
                                    fontSize: 10,
                                    height: 1.2,
                                    fontWeight: FontWeight.w700,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    name,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 12,
                      height: 1.25,
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
