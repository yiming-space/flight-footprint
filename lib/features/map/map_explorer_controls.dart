import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/localization/app_strings.dart';
import '../../ui/theme/app_theme.dart';

/// Floating fullscreen chrome; the map keeps the entire gesture surface.
class MapExplorerControls extends StatelessWidget {
  const MapExplorerControls({
    super.key,
    required this.globeMode,
    required this.landscape,
    required this.onModeChanged,
    required this.onOrientation,
    required this.onReset,
    this.onPlayback,
    this.playbackLabel,
    this.playbackIcon = Icons.play_arrow_rounded,
    this.progress,
    this.routeCaption,
    this.onAddPlace,
    this.mapInteracting = false,
  });

  final bool globeMode;
  final bool landscape;
  final ValueChanged<bool> onModeChanged;
  final VoidCallback? onOrientation;
  final VoidCallback onReset;
  final VoidCallback? onPlayback;
  final String? playbackLabel;
  final IconData playbackIcon;
  final double? progress;
  final String? routeCaption;
  final VoidCallback? onAddPlace;

  /// Disables live backdrop blur while the map is moving. The solid fallback
  /// keeps the controls readable without forcing the map below to be sampled
  /// and blurred for every gesture frame.
  final bool mapInteracting;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final zh = strings.isZh;
    final colors = context.appColors;
    final size = MediaQuery.sizeOf(context);
    final isWide = size.width > size.height;
    final lightTheme = Theme.of(context).brightness == Brightness.light;
    final progressColor = lightTheme
        ? AppColors.routePurpleDeep
        : AppColors.routePurple;
    final progressTrack = lightTheme
        ? colors.border.withValues(alpha: .82)
        : colors.border.withValues(alpha: .88);
    final progressText = colors.textPrimary;
    final actions = <Widget>[
      MapExplorerButton(
        label: zh ? '平面地图' : 'Flat map',
        icon: Icons.map_outlined,
        selected: !globeMode,
        onPressed: () => onModeChanged(false),
      ),
      MapExplorerButton(
        label: zh ? '地球模式' : 'Globe mode',
        icon: Icons.public_rounded,
        selected: globeMode,
        onPressed: () => onModeChanged(true),
      ),
      if (onPlayback != null)
        MapExplorerButton(
          label: playbackLabel!,
          icon: playbackIcon,
          onPressed: onPlayback,
          emphasized: true,
        ),
      if (onAddPlace != null)
        MapExplorerButton(
          label: strings.t('addPlace'),
          icon: Icons.add_location_alt_outlined,
          onPressed: onAddPlace,
        ),
      MapExplorerButton(
        label: zh ? '重置视角' : 'Reset view',
        icon: Icons.center_focus_strong_rounded,
        onPressed: onReset,
      ),
      if (onOrientation != null)
        MapExplorerButton(
          label: strings.t(landscape ? 'exitLandscape' : 'landscapeFullscreen'),
          icon: landscape
              ? Icons.stay_current_portrait_rounded
              : Icons.screen_rotation_alt_rounded,
          onPressed: onOrientation,
        ),
    ];
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(12, 12, 14, 14),
      child: Align(
        alignment: Alignment.bottomRight,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: size.width - 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (routeCaption != null && progress != null) ...[
                MapExplorerGlass(
                  blurEnabled: !mapInteracting,
                  child: Semantics(
                    container: true,
                    label: zh ? '航线播放进度' : 'Route progress',
                    value: '${(progress!.clamp(0, 1) * 100).round()}%',
                    child: SizedBox(
                      width: isWide ? 240 : 190,
                      height: 42,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ColoredBox(color: progressTrack),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: FractionallySizedBox(
                                widthFactor: progress!.clamp(0, 1),
                                heightFactor: 1,
                                child: ColoredBox(color: progressColor),
                              ),
                            ),
                            Center(
                              child: Text(
                                routeCaption!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: progressText,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: true,
                clipBehavior: Clip.none,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var index = 0; index < actions.length; index++) ...[
                      if (index > 0) const SizedBox(width: 6),
                      actions[index],
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MapExplorerGlass extends StatelessWidget {
  const MapExplorerGlass({
    super.key,
    required this.child,
    this.blurEnabled = true,
  });

  final Widget child;
  final bool blurEnabled;

  @override
  Widget build(BuildContext context) {
    final highContrast = MediaQuery.highContrastOf(context);
    final colors = context.appColors;
    final lightTheme = Theme.of(context).brightness == Brightness.light;
    final useBlur = blurEnabled && !highContrast;
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        enabled: useBlur,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: highContrast
                  ? [colors.surfaceDeep, colors.surfaceDeep]
                  : lightTheme
                  ? [
                      colors.surface.withValues(alpha: .90),
                      colors.iceTint.withValues(alpha: .78),
                      colors.surface.withValues(alpha: .94),
                    ]
                  : [
                      colors.surfaceElevated.withValues(alpha: .96),
                      colors.surface.withValues(alpha: .90),
                      colors.background.withValues(alpha: .94),
                    ],
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: highContrast
                ? const []
                : [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: lightTheme ? .12 : .28,
                      ),
                      blurRadius: 28,
                      offset: const Offset(0, 14),
                    ),
                  ],
          ),
          child: Stack(
            children: [
              if (!highContrast && useBlur)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.center,
                          colors: [
                            Colors.white.withValues(alpha: .12),
                            Colors.white.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class MapExplorerButton extends StatelessWidget {
  const MapExplorerButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.emphasized = false,
    this.selected = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool emphasized;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final lightTheme = Theme.of(context).brightness == Brightness.light;
    return IconButton(
      tooltip: label,
      onPressed: onPressed,
      icon: Icon(icon, size: 22),
      style: IconButton.styleFrom(
        foregroundColor: emphasized ? colors.onPrimary : colors.textPrimary,
        disabledForegroundColor: colors.textTertiary,
        backgroundColor: emphasized
            ? colors.lime
            : selected
            ? colors.iceTint
            : lightTheme
            ? colors.surface
            : colors.surfaceElevated,
        shape: const CircleBorder(),
        minimumSize: const Size(48, 48),
        fixedSize: const Size(48, 48),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}
