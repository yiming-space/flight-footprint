import 'package:flutter/material.dart';

import '../../core/localization/app_strings.dart';
import 'ranking_expansion_card.dart';

class AircraftCollectionOverviewCard extends StatelessWidget {
  const AircraftCollectionOverviewCard({
    super.key,
    required this.aircraftCount,
    this.onTap,
    this.pageBuilder,
  }) : assert(onTap != null || pageBuilder != null);

  final int aircraftCount;
  final VoidCallback? onTap;
  final WidgetBuilder? pageBuilder;

  @override
  Widget build(BuildContext context) {
    final isZh = context.strings.isZh;
    return RankingExpansionCard(
      title: isZh ? '机型图鉴' : 'Aircraft collection',
      subtitle: isZh
          ? '已搭乘 $aircraftCount 种机型'
          : '$aircraftCount aircraft ${aircraftCount == 1 ? 'type' : 'types'} flown',
      icon: Icons.airplanemode_active_rounded,
      keyPrefix: 'aircraft-collection',
      onTap: onTap,
      pageBuilder: pageBuilder,
    );
  }
}
