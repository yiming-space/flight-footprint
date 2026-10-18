import 'package:flutter/material.dart';

import '../../core/localization/app_strings.dart';
import 'ranking_expansion_card.dart';

/// A single entry point; ranking details are deliberately kept off the overview.
class AirlineRankingOverviewCard extends StatelessWidget {
  const AirlineRankingOverviewCard({
    super.key,
    required this.airlineCount,
    this.onTap,
    this.pageBuilder,
  }) : assert(onTap != null || pageBuilder != null);

  final int airlineCount;
  final VoidCallback? onTap;
  final WidgetBuilder? pageBuilder;

  @override
  Widget build(BuildContext context) => RankingExpansionCard(
    title: context.strings.t('airlineRanking'),
    subtitle: context.strings.isZh
        ? '已搭乘 $airlineCount 家航司'
        : 'Flown with $airlineCount ${airlineCount == 1 ? 'airline' : 'airlines'}',
    icon: Icons.flight_takeoff_rounded,
    keyPrefix: 'airline-ranking',
    flipOnOpen: true,
    onTap: onTap,
    pageBuilder: pageBuilder,
  );
}
