import 'package:flutter/material.dart';

import '../../ui/theme/app_theme.dart';
import '../../ui/widgets/widgets.dart';

/// The shared summary entry point for statistics with a separate detail page.
class RankingOverviewCard extends StatelessWidget {
  const RankingOverviewCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final accent = isLight ? colors.lime : colors.purple;
    return Semantics(
      button: true,
      label: '$title, $subtitle',
      onTap: onTap,
      excludeSemantics: true,
      child: SurfaceCard(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
        color: isLight
            ? colors.surface
            : Color.alphaBlend(
                colors.purple.withValues(alpha: .055),
                colors.surfaceElevated,
              ),
        showBorder: false,
        boxShadow: AppShadows.card(context),
        onTap: onTap,
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTextStyles.sectionTitle.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    style: AppTextStyles.bodySecondary.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: .14),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: accent, size: 25),
            ),
          ],
        ),
      ),
    );
  }
}
