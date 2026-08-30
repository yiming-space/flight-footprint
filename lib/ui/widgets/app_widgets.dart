import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.onBack,
    this.trailing,
  });
  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (onBack != null) ...[
            Semantics(
              button: true,
              label: '返回',
              child: IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: '返回',
                onPressed: onBack,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.pageTitle),
                if (subtitle != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(subtitle!, style: AppTextStyles.bodySecondary),
                ],
              ],
            ),
          ),
          if (trailing != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: trailing!,
            ),
        ],
      ),
    ),
  );
}

enum AppNavDestination { home, flights, stats, profile }

class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    super.key,
    required this.current,
    required this.onDestinationSelected,
    this.onAdd,
  });
  final AppNavDestination current;
  final ValueChanged<AppNavDestination> onDestinationSelected;
  final VoidCallback? onAdd;

  static const _items = [
    (AppNavDestination.home, Icons.home_outlined, Icons.home, '首页'),
    (AppNavDestination.flights, Icons.public_outlined, Icons.public, '航迹'),
    (AppNavDestination.stats, Icons.bar_chart_outlined, Icons.bar_chart, '统计'),
    (AppNavDestination.profile, Icons.person_outline, Icons.person, '我的'),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        constraints: const BoxConstraints(minHeight: 80),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.sm,
          AppSpacing.sm,
          AppSpacing.sm,
          AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: .96),
          border: const Border(top: BorderSide(color: AppColors.border)),
          borderRadius: AppRadii.large,
        ),
        child: Row(
          children: [
            Expanded(child: _destination(_items[0])),
            Expanded(child: _destination(_items[1])),
            SizedBox(
              width: 72,
              child: Center(
                child: Semantics(
                  button: true,
                  label: '记录飞行',
                  child: IconButton(
                    onPressed: onAdd,
                    iconSize: 34,
                    style: IconButton.styleFrom(
                      minimumSize: const Size(56, 56),
                      backgroundColor: AppColors.purple,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.add),
                  ),
                ),
              ),
            ),
            Expanded(child: _destination(_items[2])),
            Expanded(child: _destination(_items[3])),
          ],
        ),
      ),
    );
  }

  Widget _destination((AppNavDestination, IconData, IconData, String) item) {
    final selected = current == item.$1;
    return Semantics(
      button: true,
      selected: selected,
      label: item.$4,
      child: InkWell(
        onTap: () => onDestinationSelected(item.$1),
        borderRadius: AppRadii.small,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56, minWidth: 44),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                selected ? item.$3 : item.$2,
                color: selected ? AppColors.lime : AppColors.textSecondary,
                size: 26,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                item.$4,
                style: TextStyle(
                  fontSize: 12,
                  color: selected ? AppColors.lime : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AppSegmentedControl extends StatelessWidget {
  const AppSegmentedControl({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onChanged,
  });
  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) {
    if (labels.isEmpty) return const SizedBox.shrink();
    final safeIndex = selectedIndex.clamp(0, labels.length - 1);
    return Semantics(
      container: true,
      label: '筛选选项',
      child: Container(
        height: 56,
        padding: const EdgeInsets.all(AppSpacing.xs),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
          borderRadius: AppRadii.medium,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final itemWidth = constraints.maxWidth / labels.length;
            return Stack(
              fit: StackFit.expand,
              clipBehavior: Clip.hardEdge,
              children: [
                // Translate the highlight on the compositor instead of
                // relaying out the whole control every frame. This keeps the
                // green pill fluid while the map below remains untouched.
                Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: itemWidth,
                    height: constraints.maxHeight,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween<double>(end: itemWidth * safeIndex),
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOutCubic,
                      builder: (context, offset, child) => Transform.translate(
                        offset: Offset(offset, 0),
                        child: child,
                      ),
                      child: const SizedBox.expand(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: AppColors.lime,
                            borderRadius: AppRadii.small,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Row(
                  children: [
                    for (var i = 0; i < labels.length; i++)
                      Expanded(
                        child: Semantics(
                          button: true,
                          selected: i == safeIndex,
                          label: labels[i],
                          child: InkWell(
                            onTap: () => onChanged(i),
                            borderRadius: AppRadii.small,
                            child: Center(
                              child: AnimatedDefaultTextStyle(
                                duration: const Duration(milliseconds: 180),
                                curve: Curves.easeOut,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: i == safeIndex
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: i == safeIndex
                                      ? Colors.black
                                      : AppColors.textSecondary,
                                ),
                                child: Text(labels[i]),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.onTap,
    this.margin,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? margin;
  @override
  Widget build(BuildContext context) {
    final content = Padding(padding: padding, child: child);
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: AppRadii.medium,
      ),
      child: onTap == null
          ? content
          : Semantics(
              button: true,
              child: InkWell(
                onTap: onTap,
                borderRadius: AppRadii.medium,
                child: content,
              ),
            ),
    );
  }
}

class MetricText extends StatelessWidget {
  const MetricText({
    super.key,
    required this.value,
    this.unit,
    this.label,
    this.color = AppColors.textPrimary,
  });
  final String value;
  final String? unit;
  final String? label;
  final Color color;
  @override
  Widget build(BuildContext context) => Semantics(
    label: [?label, value, ?unit].join(' '),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) Text(label!, style: AppTextStyles.bodySecondary),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(value, style: AppTextStyles.metric.copyWith(color: color)),
            if (unit != null) ...[
              const SizedBox(width: AppSpacing.sm),
              Text(
                unit!,
                style: AppTextStyles.sectionTitle.copyWith(
                  color: AppColors.lime,
                ),
              ),
            ],
          ],
        ),
      ],
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    this.message,
    this.icon = Icons.flight_takeoff,
    this.action,
  });
  final String title;
  final String? message;
  final IconData icon;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    container: true,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: AppColors.textTertiary),
            const SizedBox(height: AppSpacing.md),
            Text(
              title,
              style: AppTextStyles.sectionTitle,
              textAlign: TextAlign.center,
            ),
            if (message != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                message!,
                style: AppTextStyles.bodySecondary,
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: AppSpacing.lg),
              action!,
            ],
          ],
        ),
      ),
    ),
  );
}

class DisclosureRow extends StatelessWidget {
  const DisclosureRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.value,
    this.onTap,
    this.showChevron = true,
  });
  final String title;
  final String? subtitle;
  final Widget? leading;
  final String? value;
  final VoidCallback? onTap;
  final bool showChevron;
  @override
  Widget build(BuildContext context) => Semantics(
    button: onTap != null,
    label: [title, ?subtitle, ?value].join(' '),
    child: InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              if (leading != null) ...[
                leading!,
                const SizedBox(width: AppSpacing.md),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(title, style: AppTextStyles.body),
                    if (subtitle != null)
                      Text(subtitle!, style: AppTextStyles.bodySecondary),
                  ],
                ),
              ),
              if (value != null)
                Text(value!, style: AppTextStyles.bodySecondary),
              if (showChevron)
                const Padding(
                  padding: EdgeInsets.only(left: AppSpacing.sm),
                  child: Icon(
                    Icons.chevron_right,
                    color: AppColors.textSecondary,
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.expand = true,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;
  @override
  Widget build(BuildContext context) {
    final button = FilledButton.icon(
      onPressed: onPressed,
      icon: icon == null ? const SizedBox.shrink() : Icon(icon),
      label: Text(label),
      style: FilledButton.styleFrom(
        minimumSize: const Size(44, 52),
        backgroundColor: AppColors.lime,
        foregroundColor: Colors.black,
        shape: const RoundedRectangleBorder(borderRadius: AppRadii.large),
        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      ),
    );
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}
