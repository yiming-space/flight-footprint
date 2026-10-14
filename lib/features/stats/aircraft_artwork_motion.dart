import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

/// A small, interruptible translation that follows the aircraft deck position.
class AircraftArtworkMotion extends StatefulWidget {
  const AircraftArtworkMotion({
    super.key,
    required this.child,
    required this.relativePosition,
    this.enabled = true,
    this.builder,
  });

  final Widget child;
  final double relativePosition;
  final bool enabled;
  final Widget Function(BuildContext context, Offset offset, Widget child)?
  builder;

  @override
  State<AircraftArtworkMotion> createState() => _AircraftArtworkMotionState();
}

class _AircraftArtworkMotionState extends State<AircraftArtworkMotion>
    with SingleTickerProviderStateMixin {
  static const _spring = SpringDescription(
    mass: 1,
    stiffness: 170,
    damping: 27,
  );

  late final AnimationController _position;
  late double _target;
  bool _reducedMotion = false;

  double get _relativePosition => widget.relativePosition.isFinite
      ? widget.relativePosition.clamp(-1.0, 1.0).toDouble()
      : 0;

  @override
  void initState() {
    super.initState();
    _target = widget.enabled ? _relativePosition : 0;
    _position = AnimationController.unbounded(vsync: this, value: _target);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final mediaQuery = MediaQuery.maybeOf(context);
    _reducedMotion =
        (mediaQuery?.disableAnimations ?? false) ||
        (mediaQuery?.accessibleNavigation ?? false);
    _retarget();
  }

  @override
  void didUpdateWidget(covariant AircraftArtworkMotion oldWidget) {
    super.didUpdateWidget(oldWidget);
    _retarget();
  }

  void _retarget() {
    if (!widget.enabled || _reducedMotion) {
      _target = 0;
      _position.value = 0;
      return;
    }

    final target = _relativePosition;
    if (target == _target &&
        (_position.isAnimating || _position.value == target)) {
      return;
    }
    _target = target;
    // Read velocity before animateWith cancels the previous simulation.
    final velocity = _position.velocity;
    _position.animateWith(
      SpringSimulation(
        _spring,
        _position.value,
        target,
        velocity,
        snapToEnd: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _position,
    child: RepaintBoundary(child: widget.child),
    builder: (context, child) {
      final offset = Offset(_position.value * 10, _position.value * -5);
      return widget.builder?.call(context, offset, child!) ??
          Transform.translate(
            key: const ValueKey('aircraft-artwork-motion-transform'),
            offset: offset,
            child: child,
          );
    },
  );

  @override
  void dispose() {
    _position.dispose();
    super.dispose();
  }
}
