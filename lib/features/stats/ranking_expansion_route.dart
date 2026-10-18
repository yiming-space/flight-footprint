import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../ui/navigation/card_flip_route.dart';
import '../../ui/theme/app_theme.dart';

/// An anchored container expansion. Layout remains full-sized during flight;
/// only the outer surface, clipping and opacity change.
Route<T> rankingExpansionRoute<T>({
  required BuildContext context,
  required Rect sourceRect,
  required WidgetBuilder builder,
  Widget? flipFront,
  double flipSourceRadius = 28,
}) {
  if (flipFront != null) {
    return cardFlipRoute<T>(
      context: context,
      sourceRect: sourceRect,
      front: flipFront,
      builder: builder,
      sourceRadius: flipSourceRadius,
      keyPrefix: 'ranking-flip',
    );
  }
  final media = MediaQuery.maybeOf(context);
  final reduced =
      (media?.disableAnimations ?? false) ||
      (media?.accessibleNavigation ?? false);
  if (Theme.of(context).platform == TargetPlatform.iOS && !reduced) {
    return CupertinoPageRoute<T>(builder: builder);
  }
  if (!sourceRect.isFinite || sourceRect.isEmpty) {
    return MaterialPageRoute<T>(builder: builder);
  }
  return PageRouteBuilder<T>(
    opaque: false,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: .08),
    transitionDuration: Duration(milliseconds: reduced ? 120 : 360),
    reverseTransitionDuration: Duration(milliseconds: reduced ? 120 : 300),
    pageBuilder: (context, _, _) => builder(context),
    transitionsBuilder: (context, animation, _, child) {
      if (reduced) return FadeTransition(opacity: animation, child: child);
      final colors = context.appColors;
      final surface = Theme.of(context).brightness == Brightness.light
          ? colors.surface
          : Color.alphaBlend(
              colors.purple.withValues(alpha: .055),
              colors.surfaceElevated,
            );
      return LayoutBuilder(
        builder: (context, constraints) {
          final viewport = constraints.biggest;
          final page = ClipRect(
            child: OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: viewport.width,
              maxWidth: viewport.width,
              minHeight: viewport.height,
              maxHeight: viewport.height,
              child: SizedBox.fromSize(size: viewport, child: child),
            ),
          );
          return AnimatedBuilder(
            animation: animation,
            builder: (context, _) {
              final progress = animation.value.clamp(0.0, 1.0);
              final expansion = Curves.easeInOutCubic.transform(progress);
              final rect = Rect.lerp(
                sourceRect,
                Offset.zero & viewport,
                expansion,
              )!;
              return Stack(
                children: [
                  Positioned.fromRect(
                    key: const ValueKey('ranking-expansion-surface'),
                    rect: rect,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(28 * (1 - expansion)),
                      child: ColoredBox(
                        color: Color.lerp(
                          surface,
                          colors.background,
                          expansion,
                        )!,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            IgnorePointer(
                              ignoring:
                                  animation.status != AnimationStatus.completed,
                              child: ExcludeSemantics(
                                excluding:
                                    animation.status !=
                                    AnimationStatus.completed,
                                child: page,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      );
    },
  );
}
