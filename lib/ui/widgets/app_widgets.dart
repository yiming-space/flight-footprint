import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.onBack,
    this.trailing,
  });
  final String title;
  final VoidCallback? onBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        20,
        AppSpacing.page,
        18,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
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
                Text(
                  title,
                  style: AppTextStyles.pageTitle.copyWith(
                    color: context.appColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
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
        decoration: ShapeDecoration(
          color: context.appColors.surface.withValues(alpha: .96),
          shape: RoundedSuperellipseBorder(
            borderRadius: AppRadii.large,
            side: BorderSide(color: context.appColors.border),
          ),
        ),
        child: Row(
          children: [
            Expanded(child: _destination(context, _items[0])),
            Expanded(child: _destination(context, _items[1])),
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
                      backgroundColor: context.appColors.purple,
                      foregroundColor: context.appColors.cardText,
                    ),
                    icon: const Icon(Icons.add),
                  ),
                ),
              ),
            ),
            Expanded(child: _destination(context, _items[2])),
            Expanded(child: _destination(context, _items[3])),
          ],
        ),
      ),
    );
  }

  Widget _destination(
    BuildContext context,
    (AppNavDestination, IconData, IconData, String) item,
  ) {
    final selected = current == item.$1;
    return Semantics(
      button: true,
      selected: selected,
      label: item.$4,
      child: InkWell(
        onTap: () => onDestinationSelected(item.$1),
        customBorder: AppShapes.small,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56, minWidth: 44),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                selected ? item.$3 : item.$2,
                color: selected
                    ? context.appColors.lime
                    : context.appColors.textSecondary,
                size: 26,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                item.$4,
                style: TextStyle(
                  fontSize: 12,
                  color: selected
                      ? context.appColors.lime
                      : context.appColors.textSecondary,
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
    this.pill = false,
    this.height = 56,
  });
  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  final bool pill;
  final double height;
  @override
  Widget build(BuildContext context) {
    if (labels.isEmpty) return const SizedBox.shrink();
    final safeIndex = selectedIndex.clamp(0, labels.length - 1);
    final controlRadius = pill ? AppRadii.pill : AppRadii.medium;
    final itemRadius = pill ? AppRadii.pill : AppRadii.small;
    final colors = context.appColors;
    final controlShape = RoundedSuperellipseBorder(
      borderRadius: controlRadius,
      side: pill ? BorderSide.none : BorderSide(color: colors.border),
    );
    final itemShape = RoundedSuperellipseBorder(borderRadius: itemRadius);
    return Semantics(
      container: true,
      label: '筛选选项',
      child: Container(
        height: height,
        padding: const EdgeInsets.all(AppSpacing.xs),
        decoration: ShapeDecoration(
          color: pill ? colors.surfaceElevated : colors.surface,
          shape: controlShape,
        ),
        child: ClipPath(
          clipper: ShapeBorderClipper(shape: itemShape),
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
                        builder: (context, offset, child) =>
                            Transform.translate(
                              offset: Offset(offset, 0),
                              child: child,
                            ),
                        child: SizedBox.expand(
                          child: DecoratedBox(
                            decoration: ShapeDecoration(
                              color: colors.lime,
                              shape: itemShape,
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
                              customBorder: itemShape,
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
                                        ? colors.cardText
                                        : colors.textSecondary,
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
    this.color,
    this.borderRadius = AppRadii.medium,
    this.showBorder = false,
    this.boxShadow,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? margin;
  final Color? color;
  final BorderRadius borderRadius;
  final bool showBorder;
  final List<BoxShadow>? boxShadow;
  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final content = Padding(padding: padding, child: child);
    final cardShape = RoundedSuperellipseBorder(
      borderRadius: borderRadius,
      side: showBorder ? BorderSide(color: colors.border) : BorderSide.none,
    );
    return Container(
      margin: margin,
      decoration: ShapeDecoration(
        color: color ?? colors.surface,
        shape: cardShape,
        shadows: boxShadow,
      ),
      child: onTap == null
          ? content
          : Semantics(
              button: true,
              child: InkWell(
                onTap: onTap,
                customBorder: cardShape,
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
    this.color,
  });
  final String value;
  final String? unit;
  final String? label;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Semantics(
      label: [?label, value, ?unit].join(' '),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label != null)
            Text(
              label!,
              style: AppTextStyles.bodySecondary.copyWith(
                color: colors.textSecondary,
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: AppTextStyles.metric.copyWith(
                  color: color ?? colors.textPrimary,
                ),
              ),
              if (unit != null) ...[
                const SizedBox(width: AppSpacing.sm),
                Text(
                  unit!,
                  style: AppTextStyles.sectionTitle.copyWith(
                    color: colors.lime,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
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
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48, color: colors.textTertiary),
              const SizedBox(height: AppSpacing.md),
              Text(
                title,
                style: AppTextStyles.sectionTitle.copyWith(
                  color: colors.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              if (message != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  message!,
                  style: AppTextStyles.bodySecondary.copyWith(
                    color: colors.textSecondary,
                  ),
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
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Semantics(
      button: onTap != null,
      label: [title, ?subtitle, ?value].join(' '),
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 68),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
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
                      Text(
                        title,
                        style: AppTextStyles.body.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: AppTextStyles.bodySecondary.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
                if (value != null)
                  Text(
                    value!,
                    style: AppTextStyles.bodySecondary.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                if (showChevron)
                  const Padding(
                    padding: EdgeInsets.only(left: AppSpacing.sm),
                    child: Icon(Icons.chevron_right),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
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
    final colors = context.appColors;
    final button = FilledButton.icon(
      onPressed: onPressed,
      icon: icon == null ? const SizedBox.shrink() : Icon(icon),
      label: Text(label),
      style: FilledButton.styleFrom(
        minimumSize: const Size(44, 56),
        backgroundColor: colors.lime,
        foregroundColor: colors.cardText,
        shape: AppShapes.large,
        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      ),
    );
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}
