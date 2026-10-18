import 'package:flutter/material.dart';

import '../../core/localization/app_strings.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/widgets/surface_card.dart';
import 'exploration_map_artwork.dart';
import 'world_exploration.dart';

/// A continent's recorded visits, with one quiet illumination on entry.
class ContinentExplorationCard extends StatefulWidget {
  const ContinentExplorationCard({
    super.key,
    required this.visits,
    required this.selected,
    required this.onTap,
    this.entranceIndex = 0,
    this.wide = false,
  });

  final ContinentVisits visits;
  final bool selected;
  final VoidCallback onTap;
  final int entranceIndex;
  final bool wide;

  @override
  State<ContinentExplorationCard> createState() =>
      _ContinentExplorationCardState();
}

class _ContinentExplorationCardState extends State<ContinentExplorationCard>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );
  late final AnimationController _stamp = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
    value: 1,
  );
  ScrollPosition? _scrollPosition;
  bool _entranceStarted = false;
  bool _visible = false;
  bool _visibilityScheduled = false;
  bool _pressed = false;
  bool _appActive = true;
  bool _motionEnabled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final media = MediaQuery.maybeOf(context);
    _motionEnabled =
        !(media?.disableAnimations ?? false) &&
        !(media?.accessibleNavigation ?? false) &&
        TickerMode.valuesOf(context).enabled;
    final position = Scrollable.maybeOf(context)?.position;
    if (position != _scrollPosition) {
      _scrollPosition?.removeListener(_scheduleVisibilityCheck);
      _scrollPosition = position;
      position?.addListener(_scheduleVisibilityCheck);
    }
    if (!_motionEnabled) _settleAnimations();
    _scheduleVisibilityCheck();
  }

  @override
  void didUpdateWidget(covariant ContinentExplorationCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.visits.isUnlocked && widget.visits.isUnlocked) {
      // A new recorded visit earns a single stamp. Selecting an existing
      // continent never restarts this controller or the entrance sequence.
      if (_motionEnabled && _visible && _appActive) {
        _stamp.forward(from: 0);
      } else {
        _stamp.value = 1;
      }
    }
    _scheduleVisibilityCheck();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    if (!_appActive) _settleAnimations();
  }

  void _scheduleVisibilityCheck() {
    if (_visibilityScheduled) return;
    _visibilityScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _visibilityScheduled = false;
      if (!mounted) return;
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.hasSize || !box.attached) return;
      final topLeft = box.localToGlobal(Offset.zero);
      var visibleBounds = Offset.zero & MediaQuery.sizeOf(context);
      final scrollBox = _scrollPosition?.context.notificationContext
          ?.findRenderObject();
      if (scrollBox is RenderBox && scrollBox.hasSize && scrollBox.attached) {
        visibleBounds = visibleBounds.intersect(
          scrollBox.localToGlobal(Offset.zero) & scrollBox.size,
        );
      }
      final visible = visibleBounds.overlaps(topLeft & box.size);
      if (_visible != visible) setState(() => _visible = visible);
      if (!visible || !_motionEnabled || !_appActive) {
        if (_entranceStarted || !_motionEnabled) _settleAnimations();
      } else if (!_entranceStarted) {
        _entranceStarted = true;
        if (widget.visits.isUnlocked) {
          _entrance.forward();
        } else {
          _entrance.value = 1;
        }
      }
    });
  }

  void _settleAnimations() {
    if (_entrance.isAnimating || _entrance.value != 1) {
      _entrance.stop();
      _entrance.value = 1;
    }
    if (_stamp.isAnimating || _stamp.value != 1) {
      _stamp.stop();
      _stamp.value = 1;
    }
    _entranceStarted = true;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollPosition?.removeListener(_scheduleVisibilityCheck);
    _entrance.dispose();
    _stamp.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final colors = context.appColors;
    final visits = widget.visits;
    final title = strings.isZh
        ? visits.continent.nameZh
        : visits.continent.nameEn;
    final count = strings
        .t('continentCountries')
        .replaceFirst('{count}', '${visits.countryCount}');
    final status = visits.isUnlocked
        ? strings.t('continentUnlocked')
        : strings.t('noContinentLocations');
    final isLight = Theme.of(context).brightness == Brightness.light;
    final motion = _motionEnabled && _visible && _appActive;
    final baseColor = isLight ? colors.surface : colors.surfaceElevated;
    const shape = RoundedSuperellipseBorder(borderRadius: AppRadii.small);

    return Semantics(
      key: ValueKey('continent-card-${visits.continent.name}'),
      button: true,
      selected: widget.selected,
      label: '$title, $count, $status',
      onTap: widget.onTap,
      child: ExcludeSemantics(
        child: AnimatedScale(
          key: ValueKey('continent-press-${visits.continent.name}'),
          scale: _pressed && motion ? .985 : 1,
          duration: motion ? AppMotion.short : Duration.zero,
          curve: Curves.easeOutCubic,
          child: SurfaceCard(
            padding: EdgeInsets.zero,
            borderRadius: AppRadii.small,
            color: widget.selected
                ? Color.lerp(baseColor, colors.lime, isLight ? .10 : .08)
                : Colors.transparent,
            child: Material(
              color: Colors.transparent,
              shape: shape,
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                customBorder: shape,
                onTap: widget.onTap,
                onHighlightChanged: (value) {
                  if (_pressed != value) setState(() => _pressed = value);
                },
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: widget.wide ? 16 : 8,
                    vertical: widget.wide ? 10 : 12,
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final horizontal =
                          widget.wide && constraints.maxWidth >= 240;
                      final caption = Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight:
                                  MediaQuery.textScalerOf(context)
                                      .scale(widget.wide ? 16 : 14) *
                                  1.3 *
                                  (strings.isZh || widget.wide ? 1 : 2),
                            ),
                            child: Text(
                              title,
                              textAlign: widget.wide
                                  ? TextAlign.start
                                  : TextAlign.center,
                              style: AppTextStyles.body.copyWith(
                                color: colors.textPrimary,
                                fontSize: widget.wide ? 16 : 14,
                                height: 1.3,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight:
                                  MediaQuery.textScalerOf(context).scale(12) *
                                  1.35 *
                                  (strings.isZh || widget.wide ? 1 : 2),
                            ),
                            child: Text(
                              count,
                              textAlign: widget.wide
                                  ? TextAlign.start
                                  : TextAlign.center,
                              style: AppTextStyles.label.copyWith(
                                color: colors.textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w400,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      );
                      final artwork = AnimatedBuilder(
                        animation: Listenable.merge([_entrance, _stamp]),
                        builder: (context, _) {
                          final delay = widget.entranceIndex.clamp(0, 6) * .05;
                          final reveal = Curves.easeOutCubic.transform(
                            ((_entrance.value - delay) / (1 - delay)).clamp(
                              0.0,
                              1.0,
                            ),
                          );
                          final muted = colors.textTertiary.withValues(
                            alpha: isLight ? .35 : .32,
                          );
                          final lit =
                              (isLight
                                      ? Color.lerp(
                                          colors.lime,
                                          colors.textPrimary,
                                          .16,
                                        )!
                                      : colors.lime)
                                  .withValues(alpha: .76);
                          final stamp = _stamp.value < .65
                              ? .9 +
                                    .135 *
                                        Curves.easeOutCubic.transform(
                                          _stamp.value / .65,
                                        )
                              : 1.035 -
                                    .035 *
                                        Curves.easeOutCubic.transform(
                                          (_stamp.value - .65) / .35,
                                        );
                          return Transform.scale(
                            key: ValueKey(
                              'continent-unlock-${visits.continent.name}',
                            ),
                            scale: stamp,
                            child: ExplorationMapArtwork(
                              continent: visits.continent,
                              color: visits.isUnlocked
                                  ? Color.lerp(muted, lit, reveal)
                                  : muted,
                            ),
                          );
                        },
                      );
                      if (horizontal) {
                        return Row(
                          children: [
                            SizedBox(
                              width: constraints.maxWidth * .28,
                              height: 44,
                              child: artwork,
                            ),
                            const SizedBox(width: 16),
                            Expanded(child: caption),
                          ],
                        );
                      }
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            height: 56,
                            width: double.infinity,
                            child: artwork,
                          ),
                          const SizedBox(height: 8),
                          caption,
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
