import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

typedef PerspectiveCardBuilder = Widget Function(
  BuildContext context,
  int index,
  double relativePosition,
  bool isActive,
);

/// A small, virtualized deck: only the front card is interactive/accessible.
///
/// Dragging changes the presentation directly; releasing it hands that position
/// and velocity to a spring. A new drag can interrupt the spring at any time.
class PerspectiveCardDeck extends StatefulWidget {
  const PerspectiveCardDeck({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    required this.cardHeight,
    this.initialIndex = 0,
    this.onIndexChanged,
    this.reduceMotion = false,
    this.loop = false,
    this.animateEntrance = false,
    this.recycleArc = true,
    this.flipInPlace = false,
    this.cycleDepth = false,
    this.showControls = true,
  }) : assert(itemCount >= 0),
       assert(cardHeight > 0);

  final int itemCount;
  final PerspectiveCardBuilder itemBuilder;
  final double cardHeight;
  final int initialIndex;
  final ValueChanged<int>? onIndexChanged;
  final bool reduceMotion;

  /// Wrap through virtual slots, without jumping the presentation at the seam.
  /// Empty and single-item decks never loop.
  final bool loop;

  /// Open the visible stack once, ending immediately when interaction begins.
  final bool animateEntrance;

  /// Fold looping cards through the back of the stack. Disable for a subtle
  /// perspective slide that leaves larger rotations to the card's tap action.
  final bool recycleArc;

  /// Turn the whole front card around its center, handing off at its edge.
  /// Takes precedence over [recycleArc] and follows the drag in either direction.
  final bool flipInPlace;

  /// Slide up out of the deck, then tuck into its back without turning edge-on.
  /// Takes precedence over the older arc and flip styles for looping decks.
  final bool cycleDepth;
  final bool showControls;

  @override
  State<PerspectiveCardDeck> createState() => _PerspectiveCardDeckState();
}

class _PerspectiveCardDeckState extends State<PerspectiveCardDeck>
    with TickerProviderStateMixin {
  late final AnimationController _position;
  late final AnimationController _entrance;
  late final Listenable _animations;
  bool _entranceStarted = false;
  int _dragOrigin = 0;
  int? _reportedIndex;
  bool _dragging = false;
  bool? _motionReduced;
  bool _acceptInput = true;

  int get _lastIndex => math.max(0, widget.itemCount - 1);
  bool get _loops => widget.loop && widget.itemCount > 1;
  int get _currentSlot => _loops
      ? _position.value.round()
      : _position.value.round().clamp(0, _lastIndex);
  int _indexForSlot(int slot) =>
      _loops ? slot % widget.itemCount : slot.clamp(0, _lastIndex);
  int get _currentIndex => _indexForSlot(_currentSlot);
  bool get _canPrevious => _loops || _currentIndex > 0;
  bool get _canNext => _loops || _currentIndex < _lastIndex;
  double get _stride => (widget.cardHeight * .52).clamp(170.0, 260.0);
  bool get _reduced {
    final media = MediaQuery.maybeOf(context);
    return widget.reduceMotion ||
        (media?.disableAnimations ?? false) ||
        (media?.accessibleNavigation ?? false);
  }

  @override
  void initState() {
    super.initState();
    _position = AnimationController.unbounded(
      vsync: this,
      value: widget.initialIndex.clamp(0, _lastIndex).toDouble(),
    );
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
      value: widget.animateEntrance && widget.itemCount > 1 ? 0 : 1,
    );
    _animations = Listenable.merge([_position, _entrance]);
    _reportedIndex = _currentIndex;
  }

  @override
  void didUpdateWidget(covariant PerspectiveCardDeck oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialIndex != widget.initialIndex ||
        oldWidget.itemCount != widget.itemCount ||
        oldWidget.loop != widget.loop) {
      _finishEntrance();
      _position.stop();
      _position.value = widget.initialIndex.clamp(0, _lastIndex).toDouble();
      _reportedIndex = _currentIndex;
    } else if (!oldWidget.reduceMotion && widget.reduceMotion) {
      _snapForReducedMotion();
    }
    if (!widget.animateEntrance) _finishEntrance();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = _reduced;
    if (!_entranceStarted) {
      _entranceStarted = true;
      if (widget.animateEntrance && widget.itemCount > 1 && !reduced) {
        _entrance.forward();
      } else {
        _finishEntrance();
      }
    }
    if (reduced && _motionReduced == false) _snapForReducedMotion();
    _motionReduced = reduced;
  }

  void _snapForReducedMotion() {
    _finishEntrance();
    final slot = _currentSlot;
    final index = _currentIndex;
    _position.stop();
    _position.value = slot.toDouble();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _report(index);
    });
  }

  void _finishEntrance() {
    if (!_acceptInput || !mounted) return;
    _entrance.stop();
    if (_entrance.value != 1) _entrance.value = 1;
  }

  @override
  void deactivate() {
    // Gesture cancellation can run while descendants are being unmounted,
    // before this State is disposed but after ancestor lookups become unsafe.
    _acceptInput = false;
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _acceptInput = true;
  }

  @override
  void dispose() {
    _acceptInput = false;
    _entrance.dispose();
    _position.dispose();
    super.dispose();
  }

  void _report(int index) {
    if (!_acceptInput || !mounted) return;
    if (_reportedIndex == index) return;
    _reportedIndex = index;
    widget.onIndexChanged?.call(index);
  }

  Future<void> _settle(int target, {double? velocity}) async {
    if (!_acceptInput || !mounted) return;
    if (!_loops) target = target.clamp(0, _lastIndex);
    final startVelocity = velocity ?? _position.velocity;
    _position.stop();
    if (_reduced) {
      _position.value = target.toDouble();
      _report(_indexForSlot(target));
      return;
    }
    try {
      await _position
          .animateWith(
            SpringSimulation(
              const SpringDescription(mass: 1, stiffness: 260, damping: 31),
              _position.value,
              target.toDouble(),
              startVelocity.clamp(-12.0, 12.0),
              tolerance: const Tolerance(distance: .001, velocity: .001),
            ),
          )
          .orCancel;
      if (!mounted) return;
      _position.value = target.toDouble();
      _report(_indexForSlot(target));
    } on TickerCanceled {
      // A new gesture owns the still-visible presentation position.
    }
  }

  void _step(int direction) {
    _finishEntrance();
    if (widget.itemCount < 2) return;
    _settle(_currentSlot + direction);
  }

  void _dragStart(DragStartDetails details) {
    if (!_acceptInput || !mounted) return;
    _finishEntrance();
    _dragging = true;
    _position.stop();
    _dragOrigin = _currentSlot;
  }

  void _dragUpdate(DragUpdateDetails details) {
    if (!_acceptInput || !mounted) return;
    var next = _position.value - details.delta.dy / _stride;
    // Keep long flicks bounded, without locking a user out of a reverse drag.
    next = next.clamp(
      _loops ? _dragOrigin - 3.0 : math.max(-.18, _dragOrigin - 3.0),
      _loops
          ? _dragOrigin + 3.0
          : math.min(_lastIndex + .18, _dragOrigin + 3.0),
    );
    if (!_loops) {
      if (next < 0) next *= .35;
      if (next > _lastIndex) next = _lastIndex + (next - _lastIndex) * .35;
    }
    _position.value = next;
  }

  void _dragEnd(DragEndDetails details) {
    if (!_acceptInput || !mounted) return;
    _dragging = false;
    final velocity = -details.velocity.pixelsPerSecond.dy / _stride;
    final projected = _position.value + velocity * .18;
    final target = projected
        .round()
        .clamp(
          _loops ? _dragOrigin - 3 : math.max(0, _dragOrigin - 3),
          _loops ? _dragOrigin + 3 : math.min(_lastIndex, _dragOrigin + 3),
        )
        .toInt();
    _settle(target, velocity: velocity);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.itemCount == 0) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: _animations,
      builder: (context, _) {
        final index = _currentIndex;
        final isChinese = Localizations.localeOf(context).languageCode == 'zh';
        final colors = context.appColors;
        return Column(
          key: const ValueKey('perspective-deck'),
          children: [
            Expanded(
              child: Semantics(
                container: true,
                explicitChildNodes: true,
                onIncrease: _canNext ? () => _step(1) : null,
                onDecrease: _canPrevious ? () => _step(-1) : null,
                child: Focus(
                  onKeyEvent: (node, event) {
                    if (event is! KeyDownEvent) return KeyEventResult.ignored;
                    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                      _step(1);
                      return KeyEventResult.handled;
                    }
                    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                      _step(-1);
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: Listener(
                    // A tap during settling must open the visible aircraft,
                    // not let the old spring select another behind the route.
                    onPointerDown: (_) {
                      _finishEntrance();
                      _position.stop();
                    },
                    onPointerUp: (_) {
                      if (!_dragging) _settle(_currentSlot);
                    },
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onVerticalDragStart: _dragStart,
                      onVerticalDragUpdate: _dragUpdate,
                      onVerticalDragEnd: _dragEnd,
                      onVerticalDragCancel: () {
                        _dragging = false;
                        _settle(_currentSlot);
                      },
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final top = _reduced
                              ? 0.0
                              : (constraints.maxHeight - widget.cardHeight)
                                    .clamp(0.0, 156.0);
                          final base = _position.value.floor();
                          final indices = _reduced
                              ? <int>[_currentSlot]
                              : _loops
                              ? [
                                  for (
                                    var slot = base - 1;
                                    slot <= base + math.min(4, _lastIndex);
                                    slot++
                                  )
                                    if (slot - _position.value > -1) slot,
                                ]
                              : [
                                  for (
                                    var i = math.max(
                                      0,
                                      _position.value.floor() - 1,
                                    );
                                    i <=
                                        math.min(
                                          _lastIndex,
                                          _position.value.floor() + 3,
                                        );
                                    i++
                                  )
                                    i,
                                ];
                          // Paint by physical depth, not the rounded selection.
                          // The depth cycle blends its returning face at the
                          // crossover, so reordering cannot expose a hard cut.
                          indices.sort((a, b) {
                            if (!_loops ||
                                _reduced ||
                                (!widget.cycleDepth &&
                                    (!widget.recycleArc ||
                                        widget.flipInPlace))) {
                              return b.compareTo(a);
                            }
                            final depthOrder = _pose(b - _position.value).depth
                                .compareTo(_pose(a - _position.value).depth);
                            return depthOrder == 0
                                ? b.compareTo(a)
                                : depthOrder;
                          });
                          return Stack(
                            key: const ValueKey('deck-card-stack'),
                            clipBehavior: Clip.hardEdge,
                            children: [
                              for (final itemIndex in indices)
                                _card(context, itemIndex, top),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (widget.showControls)
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      key: const ValueKey('deck-previous'),
                      constraints: const BoxConstraints.tightFor(
                        width: 48,
                        height: 48,
                      ),
                      tooltip: isChinese ? '上一机型' : 'Previous aircraft',
                      onPressed: _canPrevious ? () => _step(-1) : null,
                      icon: const Icon(Icons.keyboard_arrow_up_rounded),
                      color: colors.textPrimary,
                    ),
                    SizedBox(
                      width: 84,
                      child: Text(
                        '${index + 1} / ${widget.itemCount}',
                        key: const ValueKey('deck-position'),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: colors.textSecondary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('deck-next'),
                      constraints: const BoxConstraints.tightFor(
                        width: 48,
                        height: 48,
                      ),
                      tooltip: isChinese ? '下一机型' : 'Next aircraft',
                      onPressed: _canNext ? () => _step(1) : null,
                      icon: const Icon(Icons.keyboard_arrow_down_rounded),
                      color: colors.textPrimary,
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  ({
    double x,
    double y,
    double scale,
    double angle,
    double opacity,
    double depth,
  })
  _pose(double relative) {
    final behind = math.max(0.0, relative);
    final outgoing = math.max(0.0, -relative);
    final entrance = Curves.easeOutCubic.transform(_entrance.value);
    final opening = 1 - entrance;
    final frontWeight = (1 - behind).clamp(0.0, 1.0);
    var scale =
        (1 - (behind * .085).clamp(0.0, .30) - outgoing * .045) *
        (1 - .02 * opening * frontWeight);
    var y =
        -behind * (22 + 24 * entrance) -
        outgoing * widget.cardHeight * (widget.recycleArc ? .58 : .24) +
        10 * opening * frontWeight;
    var angle =
        (behind * (.26 + .04 * opening)).clamp(0.0, .72 + .06 * opening) -
        outgoing * (widget.recycleArc ? .12 : .08);
    var opacity = outgoing > 0
        ? (1 - outgoing).clamp(0.0, 1.0)
        : (1 - behind * .10).clamp(.65, 1.0);
    var x = 0.0;
    var depth = behind;
    if (_loops && !_reduced) {
      if (outgoing > 0 && widget.recycleArc && !widget.flipInPlace) {
        final progress = outgoing.clamp(0.0, 1.0);
        final returnProgress = progress * progress * (3 - 2 * progress);
        final arc = math.sin(math.pi * progress);
        final back = math.min(3, _lastIndex).toDouble();
        final backScale = 1 - .085 * back;
        final backAngle = (.26 * back).clamp(0.0, .72);
        // Recede immediately instead of swelling toward the viewer. Ease in
        // the return arc after the initial fold, without a separate lift beat.
        // Position alone owns the path, so reverse drags remain symmetric.
        scale = 1 + (backScale - 1) * returnProgress;
        final arcStart = (progress / .30).clamp(0.0, 1.0);
        final arcWeight = arcStart * arcStart * (3 - 2 * arcStart);
        y =
            -back * 46 * returnProgress -
            widget.cardHeight * .20 * arc * arcWeight;
        x = 22 * arc;
        // Hold the returning face nearly edge-on until its upper edge has
        // passed behind the far strip, then unfold while occluded. This makes
        // depth crossings a physical handoff rather than a visible layer swap.
        final fold = (progress / .45).clamp(0.0, 1.0);
        final tuck = ((progress - .90) / .10).clamp(0.0, 1.0);
        final tucked = tuck * tuck * (3 - 2 * tuck);
        angle = progress <= .90
            ? 1.5 * math.sin(math.pi * .5 * fold)
            : 1.5 + (backAngle - 1.5) * tucked;
        opacity = 1 - .10 * back * returnProgress;
        depth = (back + .5) * returnProgress * returnProgress - .25 * arc;
      } else if (outgoing == 0) {
        // Preload one far strip and reveal it gradually as it advances;
        // this hides the virtual-slot seam without a materializing card.
        opacity *= (4 - behind).clamp(0.0, 1.0);
      }
    }
    if (widget.flipInPlace && !widget.cycleDepth && !_reduced) {
      if (relative <= 0) {
        // Keep the old face centered and stop at its edge; never expose a
        // mirrored back while the incoming card completes the turn.
        scale = 1;
        y = 0;
        angle = math.pi * outgoing.clamp(0.0, .5);
        opacity = outgoing <= .5 ? 1 : 0;
      } else if (relative < 1) {
        // First bring the next preview to the center, then unfold its face.
        final approach = ((1 - relative) * 2).clamp(0.0, 1.0);
        scale = .915 + .085 * approach;
        y = -46 * (1 - approach);
        angle = relative > .5
            ? .26 + (-math.pi / 2 - .26) * approach
            : -math.pi * relative;
        opacity = .9 + .1 * approach;
      }
    }
    if (widget.cycleDepth && _loops && !_reduced) {
      final back = math.min(4, _lastIndex).toDouble();
      final progress = outgoing.clamp(0.0, 1.0);
      depth = behind;
      final weight = (1 - depth).clamp(0.0, 1.0);
      scale =
          (1 - (depth * .085).clamp(0.0, .30)) * (1 - .02 * opening * weight);
      y = -depth * (22 + 24 * entrance) + 10 * opening * weight;
      angle = (depth * .18).clamp(0.0, .55);
      x = 0;
      opacity = (1 - depth * .08).clamp(.68, 1.0) * (4 - depth).clamp(0.0, 1.0);
      if (outgoing > 0) {
        final departure = (progress / .56).clamp(0.0, 1.0);
        final flight =
            .18 * departure + .82 * departure * departure * departure;
        final distance = widget.cardHeight * 1.15 + 156;
        final tuck = ((progress - .56) / .10).clamp(0.0, 1.0);
        final tucked = tuck * tuck * (3 - 2 * tuck);
        final landing = ((progress - .66) / .34).clamp(0.0, 1.0);
        final landed = landing * landing * (3 - 2 * landing);
        // The face follows the upward pull first. Change its paint depth only
        // while it is completely outside the clipped deck, then let the back
        // preview return underneath the incoming face. No edge-on flip or
        // crossover fade; reverse input follows exactly this same path.
        depth = -.05 * (1 - tucked) + back * tucked;
        final backScale = 1 - (back * .085).clamp(0.0, .30);
        scale = 1 - .08 * departure + (backScale - .92) * landed;
        y = -distance * flight + (distance - back * 46) * landed;
        angle = .12 * departure + ((back * .18).clamp(0.0, .55) - .12) * landed;
        opacity =
            1 + ((1 - back * .08) * (4 - back).clamp(0.0, 1.0) - 1) * landed;
      }
    }
    return (
      x: x,
      y: y,
      scale: scale,
      angle: angle,
      opacity: opacity,
      depth: depth,
    );
  }

  Widget _card(BuildContext context, int slot, double top) {
    final index = _indexForSlot(slot);
    final relative = _reduced ? 0.0 : slot - _position.value;
    final active = slot == _currentSlot;
    final pose = _pose(relative);
    return Positioned(
      key: ValueKey('deck-slot-$slot'),
      top: top + pose.y,
      left: 0,
      right: 0,
      height: widget.cardHeight,
      child: IgnorePointer(
        ignoring: !active,
        child: ExcludeSemantics(
          excluding: !active,
          child: Opacity(
            opacity: pose.opacity,
            child: Transform(
              key: ValueKey('deck-card-transform-$slot'),
              alignment: widget.flipInPlace && !widget.cycleDepth && !_reduced
                  ? Alignment(0, -((relative - .5) * 2).clamp(0.0, 1.0))
                  : Alignment.topCenter,
              transform: Matrix4.identity()
                ..setEntry(3, 2, .0012)
                ..translateByDouble(pose.x, 0, 0, 1)
                ..rotateX(pose.angle)
                ..scaleByDouble(pose.scale, pose.scale, 1, 1),
              child: RepaintBoundary(
                child: widget.itemBuilder(context, index, relative, active),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
