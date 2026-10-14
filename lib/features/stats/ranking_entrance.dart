import 'package:flutter/material.dart';

/// One bounded entrance clock, started after the visible route transition.
class RankingEntrance extends StatefulWidget {
  const RankingEntrance({
    super.key,
    required this.enabled,
    required this.empty,
    required this.builder,
  });

  final bool enabled;
  final bool empty;
  final Widget Function(BuildContext, Animation<double>, bool animated) builder;

  @override
  State<RankingEntrance> createState() => _RankingEntranceState();
}

class _RankingEntranceState extends State<RankingEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progress;
  Animation<double>? _routeAnimation;
  ModalRoute<dynamic>? _route;
  bool _started = false;

  bool get _animated {
    final media = MediaQuery.of(context);
    return widget.enabled &&
        !media.disableAnimations &&
        !media.accessibleNavigation;
  }

  @override
  void initState() {
    super.initState();
    _progress = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
      value: widget.enabled ? 0 : 1,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    final animation = _route?.animation;
    if (animation != _routeAnimation) {
      _routeAnimation?.removeStatusListener(_routeStatus);
      _routeAnimation = animation;
      animation?.addStatusListener(_routeStatus);
    }
    if (!_animated || widget.empty) {
      _started = true;
      _progress.stop();
      _progress.value = 1;
    } else if (animation == null ||
        animation.status == AnimationStatus.completed) {
      _start();
    }
  }

  void _routeStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) _start();
  }

  void _start() {
    // Offstage layout uses a completed proxy before the visible route opens.
    if (!mounted || _started || (_route?.offstage ?? false)) return;
    _started = true;
    if (!_animated || widget.empty) {
      _progress.value = 1;
    } else {
      _progress.forward();
    }
  }

  @override
  void dispose() {
    _routeAnimation?.removeStatusListener(_routeStatus);
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _progress, _animated);
}
