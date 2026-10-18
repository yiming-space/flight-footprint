import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Turns a source card into a full page without relaying out either face.
///
/// [sourceRect] must be in the destination Navigator's overlay coordinates.
/// iOS uses its native page transition to preserve interactive edge back,
/// unless accessibility settings request reduced motion.
Route<T> cardFlipRoute<T>({
  required BuildContext context,
  required Rect sourceRect,
  Size? frontSize,
  required Widget front,
  required WidgetBuilder builder,
  Axis flipAxis = Axis.horizontal,
  double sourceRadius = 28,
  String keyPrefix = 'card-flip',
}) {
  Widget buildPage(BuildContext pageContext) =>
      HeroMode(enabled: false, child: builder(pageContext));

  final mediaQuery = MediaQuery.maybeOf(context);
  final reduceMotion =
      (mediaQuery?.disableAnimations ?? false) ||
      (mediaQuery?.accessibleNavigation ?? false);

  if (Theme.of(context).platform == TargetPlatform.iOS && !reduceMotion) {
    return CupertinoPageRoute<T>(builder: buildPage);
  }

  if (!_isUsableRect(sourceRect)) {
    return MaterialPageRoute<T>(builder: buildPage);
  }

  return PageRouteBuilder<T>(
    opaque: false,
    barrierColor: Colors.transparent,
    barrierDismissible: false,
    transitionDuration: Duration(milliseconds: reduceMotion ? 120 : 460),
    reverseTransitionDuration: Duration(milliseconds: reduceMotion ? 120 : 420),
    pageBuilder: (pageContext, animation, secondaryAnimation) =>
        buildPage(pageContext),
    transitionsBuilder: (routeContext, animation, secondaryAnimation, child) {
      if (reduceMotion) {
        return FadeTransition(
          opacity: animation,
          child: _DetailInteractionGate(animation: animation, child: child),
        );
      }
      return _CardFlipTransition(
        animation: animation,
        sourceRect: sourceRect,
        frontSize: frontSize,
        front: front,
        flipAxis: flipAxis,
        sourceRadius: sourceRadius,
        keyPrefix: keyPrefix,
        child: child,
      );
    },
  );
}

bool _isUsableRect(Rect rect) =>
    rect.left.isFinite &&
    rect.top.isFinite &&
    rect.right.isFinite &&
    rect.bottom.isFinite &&
    rect.width.isFinite &&
    rect.height.isFinite &&
    rect.width > 0 &&
    rect.height > 0;

/// Keeps the real page mounted but inert until the route finishes opening.
/// Navigator still handles system back, including during either transition.
class _DetailInteractionGate extends StatelessWidget {
  const _DetailInteractionGate({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: animation,
    child: child,
    builder: (context, child) {
      final ready = animation.status == AnimationStatus.completed;
      return IgnorePointer(
        ignoring: !ready,
        child: ExcludeSemantics(excluding: !ready, child: child!),
      );
    },
  );
}

class _CardFlipTransition extends StatelessWidget {
  const _CardFlipTransition({
    required this.animation,
    required this.sourceRect,
    this.frontSize,
    required this.front,
    required this.flipAxis,
    required this.sourceRadius,
    required this.keyPrefix,
    required this.child,
  });

  final Animation<double> animation;
  final Rect sourceRect;
  final Size? frontSize;
  final Widget front;
  final Axis flipAxis;
  final double sourceRadius;
  final String keyPrefix;
  final Widget child;

  static const _handoff = 0.42;
  static const _growthStart = 0.28;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final viewport = constraints.biggest;
      final destinationRect = Offset.zero & viewport;
      final background = context.appColors.background;

      // Both faces stay mounted so the detail page retains its state on pop.
      // Their own layouts are stable even while the enclosing rect changes.
      final frontFace = HeroMode(
        enabled: false,
        child: IgnorePointer(
          child: ExcludeSemantics(
            child: FittedBox(
              fit: BoxFit.fill,
              child: SizedBox.fromSize(
                size: frontSize ?? sourceRect.size,
                child: Material(type: MaterialType.transparency, child: front),
              ),
            ),
          ),
        ),
      );
      final detailFace = _DetailInteractionGate(
        animation: animation,
        child: ClipRect(
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: viewport.width,
            maxWidth: viewport.width,
            minHeight: viewport.height,
            maxHeight: viewport.height,
            child: SizedBox.fromSize(size: viewport, child: child),
          ),
        ),
      );

      return AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          final progress = animation.value.clamp(0.0, 1.0);
          final showingFront = progress < _handoff;
          final growthProgress = Curves.easeInOutCubic.transform(
            ((progress - _growthStart) / (1 - _growthStart)).clamp(0.0, 1.0),
          );
          final rect = Rect.lerp(sourceRect, destinationRect, growthProgress)!;
          final radius = sourceRadius * (1 - growthProgress);

          // Switch faces only at the edge-on position. Neither face rotates
          // beyond 90 degrees, so text is never mirrored or upside down.
          final angle = showingFront
              ? math.pi / 2 * Curves.easeInCubic.transform(progress / _handoff)
              : -math.pi /
                    2 *
                    (1 -
                        Curves.easeOutCubic.transform(
                          (progress - _handoff) / (1 - _handoff),
                        ));

          final transform = Matrix4.identity()..setEntry(3, 2, .001);
          if (flipAxis == Axis.horizontal) {
            transform.rotateY(angle);
          } else {
            transform.rotateX(angle);
          }

          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fromRect(
                key: ValueKey('$keyPrefix-surface'),
                rect: rect,
                child: Transform(
                  key: ValueKey('$keyPrefix-transform'),
                  alignment: Alignment.center,
                  transform: transform,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(radius),
                    child: ColoredBox(
                      color: background,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Offstage(
                            key: ValueKey('$keyPrefix-front'),
                            offstage: !showingFront,
                            child: frontFace,
                          ),
                          Offstage(
                            key: ValueKey('$keyPrefix-detail'),
                            offstage: showingFront,
                            child: detailFace,
                          ),
                        ],
                      ),
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
}
