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
    final strings = context.strings;
    return RankingExpansionCard(
      title: strings.t('aircraftCollection'),
      subtitle: strings
          .t('aircraftTypesCount')
          .replaceAll('{count}', '$aircraftCount'),
      icon: Icons.airplanemode_active_rounded,
      keyPrefix: 'aircraft-collection',
      flipOnOpen: true,
      onTap: onTap,
      pageBuilder: pageBuilder,
    );
  }
}
