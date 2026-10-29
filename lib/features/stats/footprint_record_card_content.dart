import 'package:flutter/material.dart';

import '../../core/localization/app_strings.dart';
import '../../domain/visited_place.dart';
import '../../ui/theme/app_theme.dart';

class FootprintRecordCardContent extends StatelessWidget {
  const FootprintRecordCardContent({super.key, required this.place});

  final VisitedPlace place;

  String _sourceLabel(bool isZh) => switch (place.source) {
    FootprintRecordSource.manual => isZh ? '手动添加' : 'Manually added',
    FootprintRecordSource.photo => isZh ? '照片导入' : 'Imported from photos',
    FootprintRecordSource.unknown => isZh ? '来源未知' : 'Source unknown',
  };

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(Icons.place_rounded, color: context.appColors.lime),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              place.name,
              style: AppTextStyles.body.copyWith(
                color: context.appColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${context.strings.isZh ? '足迹' : 'Footprint'} · ${MaterialLocalizations.of(context).formatMediumDate(place.visitedAt.toLocal())} · ${_sourceLabel(context.strings.isZh)}',
              style: AppTextStyles.bodySecondary.copyWith(
                color: context.appColors.textSecondary,
              ),
            ),
            if (place.note?.trim().isNotEmpty ?? false) ...[
              const SizedBox(height: 8),
              Text(
                place.note!,
                style: AppTextStyles.bodySecondary.copyWith(
                  color: context.appColors.textSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
    ],
  );
}
