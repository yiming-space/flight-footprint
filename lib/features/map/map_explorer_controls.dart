import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/localization/app_strings.dart';

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

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final zh = strings.isZh;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Align(
        alignment: Alignment.bottomCenter,
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IgnorePointer(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    zh
                        ? '${globeMode ? '拖动旋转' : '拖动平移'} · 双指缩放'
                        : '${globeMode ? 'Drag to rotate' : 'Drag to pan'} · Pinch to zoom',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xffd8e0e8),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      shadows: [Shadow(blurRadius: 8, color: Colors.black)],
                    ),
                  ),
                ),
              ),
              MapExplorerGlass(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final modes = _modePicker(context, zh);
                          final actions = Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
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
                              MapExplorerButton(
                                label: strings.t(
                                  landscape
                                      ? 'exitLandscape'
                                      : 'landscapeFullscreen',
                                ),
                                icon: landscape
                                    ? Icons.stay_current_portrait_rounded
                                    : Icons.screen_rotation_alt_rounded,
                                onPressed: onOrientation,
                              ),
                            ],
                          );
                          // Preserve readable labels and touch areas at large
                          // text sizes instead of shrinking the controls.
                          final scaled = MediaQuery.textScalerOf(context)
                              .scale(14);
                          if (constraints.maxWidth < 350 || scaled > 20) {
                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                modes,
                                const SizedBox(height: 6),
                                actions,
                              ],
                            );
                          }
                          return Row(
                            children: [
                              Expanded(child: modes),
                              const SizedBox(width: 8),
                              actions,
                            ],
                          );
                        },
                      ),
                      if (routeCaption != null && progress != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                routeCaption!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xffe0e6ed),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 7),
                              LinearProgressIndicator(
                                value: progress!.clamp(0, 1),
                                minHeight: 2,
                                borderRadius: BorderRadius.circular(2),
                                color: const Color(0xffd5e5f4),
                                backgroundColor: Colors.white12,
                                semanticsLabel: zh
                                    ? '航线播放进度'
                                    : 'Route progress',
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _modePicker(BuildContext context, bool zh) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .06),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Padding(
      padding: const EdgeInsets.all(3),
      child: Row(
        children: [
          for (final globe in [false, true])
            Expanded(
              child: Semantics(
                selected: globeMode == globe,
                child: TextButton(
                  onPressed: () => onModeChanged(globe),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: globeMode == globe
                        ? Colors.white.withValues(alpha: .19)
                        : Colors.transparent,
                    minimumSize: const Size(44, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    animationDuration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 150),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                  ),
                  child: Text(
                    globe ? (zh ? '地球' : 'Globe') : (zh ? '平面' : 'Flat'),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class MapExplorerGlass extends StatelessWidget {
  const MapExplorerGlass({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final highContrast = MediaQuery.highContrastOf(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        enabled: !highContrast,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: highContrast
                  ? const [Color(0xff18212c), Color(0xff18212c)]
                  : [
                      const Color(0xffdbe9f6).withValues(alpha: .17),
                      const Color(0xff6d88a4).withValues(alpha: .11),
                      const Color(0xff101a26).withValues(alpha: .66),
                    ],
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: highContrast
                ? const []
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: .28),
                      blurRadius: 28,
                      offset: const Offset(0, 14),
                    ),
                  ],
          ),
          child: Stack(
            children: [
              if (!highContrast)
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
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool emphasized;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: label,
    onPressed: onPressed,
    icon: Icon(icon, size: 22),
    style: IconButton.styleFrom(
      foregroundColor: emphasized ? const Color(0xff17212b) : Colors.white,
      disabledForegroundColor: Colors.white38,
      backgroundColor: emphasized
          ? const Color(0xffe5edf5)
          : Colors.transparent,
      minimumSize: const Size(48, 48),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
  );
}
