import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../ui/theme/app_theme.dart';
import '../../ui/widgets/frosted_glass_surface.dart';

/// The backs add a faint cool highlight only in the exposed stack slivers.
Color explorationMemoryCardColor(BuildContext context, int index) {
  if (Theme.of(context).brightness == Brightness.light) {
    return const Color(0xFFA9DBF7).withValues(alpha: .12);
  }
  return Colors.white.withValues(alpha: .045);
}

/// A four-card memory deck. Card widgets keep their absolute identity; motion
/// updates only the deck's paint phase, so card content is not rebuilt per tick.
class ExplorationMemoryCarousel extends StatefulWidget {
  const ExplorationMemoryCarousel({
    super.key,
    required this.cards,
    required this.labels,
    @visibleForTesting this.onPaintSnapshot,
  }) : assert(cards.length == labels.length);

  final List<Widget> cards;
  final List<String> labels;
  @visibleForTesting
  final void Function(
    int frontIndex,
    double progress,
    List<ExplorationMemoryPose> poses,
  )?
  onPaintSnapshot;

  @override
  State<ExplorationMemoryCarousel> createState() =>
      _ExplorationMemoryCarouselState();
}

class _ExplorationMemoryCarouselState extends State<ExplorationMemoryCarousel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController.unbounded(
    vsync: this,
    value: 0,
  )..addStatusListener(_motionStatusChanged);
  int _index = 0;
  double _width = 0;
  int? _targetIndex;
  int? _pendingTarget;
  bool _reducedMotion = false;
  double _reducedDrag = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reducedMotion =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    if (_reducedMotion && _motion.isAnimating) _settleImmediately();
  }

  @override
  void didUpdateWidget(covariant ExplorationMemoryCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cards.length != widget.cards.length) {
      _index = widget.cards.isEmpty
          ? 0
          : _index.clamp(0, widget.cards.length - 1);
      _settleImmediately();
    }
  }

  void _motionStatusChanged(AnimationStatus status) {
    if (status != AnimationStatus.completed &&
        status != AnimationStatus.dismissed) {
      return;
    }
    final target = _targetIndex;
    _targetIndex = null;
    if (target != null && widget.cards.isNotEmpty) {
      setState(() {
        _index = target;
        _motion.value = 0;
      });
      final pending = _pendingTarget;
      if (pending != null && pending != _index) {
        final forward =
            (pending - _index + widget.cards.length) % widget.cards.length;
        final direction = forward <= widget.cards.length / 2 ? 1 : -1;
        _pendingTarget = pending;
        _animateTo(direction.toDouble(), 0);
      } else {
        _pendingTarget = null;
      }
    }
  }

  void _settleImmediately() {
    _targetIndex = null;
    _motion.stop();
    _motion.value = 0;
  }

  @override
  void dispose() {
    _motion.removeStatusListener(_motionStatusChanged);
    _motion.dispose();
    super.dispose();
  }

  void _onDragStart(DragStartDetails details) {
    _targetIndex = null;
    _pendingTarget = null;
    _reducedDrag = 0;
    _motion.stop();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_width <= 0) return;
    if (_reducedMotion) {
      _reducedDrag += details.delta.dx;
      return;
    }
    // Positive progress cuts the next card; negative progress cuts backward.
    _motion.value = (_motion.value - details.delta.dx / _width).clamp(
      -1.0,
      1.0,
    );
  }

  void _onDragEnd(DragEndDetails details) {
    if (_reducedMotion) {
      final delta = _reducedDrag;
      _reducedDrag = 0;
      if (delta.abs() > _width * .22 && widget.cards.length > 1) {
        _commit(delta < 0 ? 1 : -1);
      }
      return;
    }
    final p = _motion.value;
    final velocity = details.velocity.pixelsPerSecond.dx;
    final projected = p - velocity / _width * .16;
    final shouldCut =
        p.abs() > .24 ||
        (p.abs() > .08 &&
            velocity.abs() > 650 &&
            projected.abs() > .22 &&
            projected.sign == p.sign);
    if (shouldCut && widget.cards.length > 1) {
      _animateTo(projected < 0 ? -1 : 1, velocity);
    } else {
      _animateTo(0, velocity);
    }
  }

  void _onDragCancel() => _animateTo(0, 0);

  void _animateTo(double target, double velocity) {
    if (_reducedMotion) {
      if (target != 0) {
        _commit(target.sign.toInt());
      } else {
        _settleImmediately();
      }
      return;
    }
    _targetIndex = target == 0
        ? null
        : (_index + target.sign.toInt() + widget.cards.length) %
              widget.cards.length;
    _motion.animateWith(
      SpringSimulation(
        const SpringDescription(mass: 1, stiffness: 370, damping: 34),
        _motion.value,
        target,
        (-velocity / _width).clamp(-5.5, 5.5),
      ),
    );
  }

  void _commit(int direction) {
    if (widget.cards.length < 2) return;
    _targetIndex =
        (_index + direction + widget.cards.length) % widget.cards.length;
    _motion.value = direction.toDouble();
    if (_reducedMotion) {
      _motion.value = 0;
      setState(() => _index = _targetIndex!);
      _targetIndex = null;
    } else {
      _motionStatusChanged(AnimationStatus.completed);
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
        event.logicalKey == LogicalKeyboardKey.pageDown) {
      _selectRelative(1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
        event.logicalKey == LogicalKeyboardKey.pageUp) {
      _selectRelative(-1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.home) {
      _select(0);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.end) {
      _select(widget.cards.length - 1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _selectRelative(int direction) {
    if (widget.cards.length < 2) return;
    _motion.stop();
    _pendingTarget = null;
    _targetIndex =
        (_index + direction + widget.cards.length) % widget.cards.length;
    _animateTo(_targetIndex == (_index + 1) % widget.cards.length ? 1 : -1, 0);
  }

  void _select(int index) {
    if (index == _index || widget.cards.length < 2) return;
    // Repeatedly cut the shortest circular direction, preserving the same
    // continuous card path for keyboard and assistive-technology actions.
    final forward =
        (index - _index + widget.cards.length) % widget.cards.length;
    _motion.stop();
    _targetIndex = index;
    final direction = forward <= widget.cards.length / 2 ? 1 : -1;
    if (_reducedMotion) {
      _motion.value = 0;
      setState(() => _index = index);
      _targetIndex = null;
    } else {
      _pendingTarget = index;
      _animateTo(direction.toDouble(), 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.cards.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        _width = math.max(1, constraints.maxWidth - 16);
        final deckWidth = _width;
        return Semantics(
          key: const ValueKey('exploration-memory-deck-semantics'),
          container: true,
          label: widget.labels[_index],
          value: '${_index + 1} / ${widget.cards.length}',
          increasedValue: widget.labels[(_index + 1) % widget.cards.length],
          decreasedValue: widget
              .labels[(_index - 1 + widget.cards.length) % widget.cards.length],
          onIncrease: () => _selectRelative(1),
          onDecrease: () => _selectRelative(-1),
          child: Focus(
            onKeyEvent: _onKey,
            child: GestureDetector(
              key: const ValueKey('exploration-memory-deck'),
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: widget.cards.length > 1
                  ? _onDragStart
                  : null,
              onHorizontalDragUpdate: widget.cards.length > 1
                  ? _onDragUpdate
                  : null,
              onHorizontalDragEnd: widget.cards.length > 1 ? _onDragEnd : null,
              onHorizontalDragCancel: widget.cards.length > 1
                  ? _onDragCancel
                  : null,
              child: SizedBox(
                width: constraints.maxWidth,
                child: _NaturalCardDeck(
                  width: deckWidth,
                  index: _index,
                  progress: _motion,
                  light: Theme.of(context).brightness == Brightness.light,
                  highContrast: MediaQuery.highContrastOf(context),
                  onPaintSnapshot: widget.onPaintSnapshot,
                  cardBacks: [
                    for (var i = 0; i < widget.cards.length; i++)
                      explorationMemoryCardColor(context, i),
                  ],
                  children: [
                    for (var i = 0; i < widget.cards.length; i++)
                      KeyedSubtree(
                        key: ValueKey('memory-card-$i'),
                        child: RepaintBoundary(child: widget.cards[i]),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

@visibleForTesting
class ExplorationMemoryPose {
  const ExplorationMemoryPose(this.translation, this.rotation, this.scale);
  final Offset translation;
  final double rotation;
  final double scale;
}

class _NaturalCardDeck extends MultiChildRenderObjectWidget {
  const _NaturalCardDeck({
    required this.width,
    required this.index,
    required this.progress,
    required this.light,
    required this.highContrast,
    required this.onPaintSnapshot,
    required this.cardBacks,
    required super.children,
  });
  final double width;
  final int index;
  final Animation<double> progress;
  final bool light;
  final bool highContrast;
  final void Function(
    int frontIndex,
    double progress,
    List<ExplorationMemoryPose> poses,
  )?
  onPaintSnapshot;
  final List<Color> cardBacks;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderNaturalCardDeck(
        width,
        index,
        progress,
        cardBacks,
        onPaintSnapshot,
        light,
        highContrast,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderNaturalCardDeck renderObject,
  ) {
    renderObject
      ..width = width
      ..index = index
      ..progress = progress
      ..light = light
      ..highContrast = highContrast
      ..cardBacks = cardBacks
      ..onPaintSnapshot = onPaintSnapshot;
  }
}

class _DeckParentData extends ContainerBoxParentData<RenderBox> {}

/// Natural-size measurement happens during layout only. Motion is a repaint
/// listenable: it never calls setState, rebuilds the card widgets, or relayouts.
class _RenderNaturalCardDeck extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _DeckParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _DeckParentData> {
  static const _frontSwapProgress = .86;
  _RenderNaturalCardDeck(
    this._width,
    this._index,
    this._progress,
    this._cardBacks,
    this._onPaintSnapshot,
    this._light,
    this._highContrast,
  ) {
    if (attached) _progress.addListener(_progressChanged);
  }
  double _width;
  int _index;
  Animation<double> _progress;
  List<Color> _cardBacks;
  bool _light;
  bool _highContrast;
  static final _lightBlur = ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14);
  static final _darkBlur = ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12);
  final _backdropKey = BackdropKey();

  @override
  bool get alwaysNeedsCompositing => true;

  set light(bool value) {
    if (_light == value) return;
    _light = value;
    markNeedsPaint();
  }

  set highContrast(bool value) {
    if (_highContrast == value) return;
    _highContrast = value;
    markNeedsPaint();
  }

  void Function(int, double, List<ExplorationMemoryPose>)? _onPaintSnapshot;

  set width(double value) {
    if (value != _width) {
      _width = value;
      markNeedsLayout();
    }
  }

  set index(int value) {
    if (value != _index) {
      _index = value;
      // The incoming face was previously sampled through an exposed sliver.
      // Re-record its glass against the full pane when it becomes the front.
      childAt(_index)?.markNeedsPaint();
      markNeedsPaint();
      markNeedsSemanticsUpdate();
    }
  }

  set cardBacks(List<Color> value) {
    _cardBacks = value;
    markNeedsPaint();
  }

  set onPaintSnapshot(
    void Function(int, double, List<ExplorationMemoryPose>)? value,
  ) {
    _onPaintSnapshot = value;
  }

  set progress(Animation<double> value) {
    if (identical(value, _progress)) return;
    if (attached) _progress.removeListener(_progressChanged);
    _progress = value;
    if (attached) _progress.addListener(_progressChanged);
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _progress.addListener(_progressChanged);
  }

  @override
  void detach() {
    _progress.removeListener(_progressChanged);
    super.detach();
  }

  void _progressChanged() {
    markNeedsPaint();
    if (childCount == 0) return;
    final p = _progress.value.clamp(-1.0, 1.0);
    final direction = p == 0 ? 1.0 : p.sign;
    final target = (_index + direction.toInt() + childCount) % childCount;
    childAt(_index)?.markNeedsPaint();
    if (p.abs() > .38 && target != _index) childAt(target)?.markNeedsPaint();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _DeckParentData) {
      child.parentData = _DeckParentData();
    }
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    var maxHeight = 0.0;
    var child = firstChild;
    while (child != null) {
      maxHeight = math.max(
        maxHeight,
        child.getDryLayout(BoxConstraints.tightFor(width: _width)).height,
      );
      child = (child.parentData! as _DeckParentData).nextSibling;
    }
    return constraints.constrain(Size(_width + 16, maxHeight + 26));
  }

  @override
  void performLayout() {
    var maxHeight = 0.0;
    var child = firstChild;
    while (child != null) {
      child.layout(
        BoxConstraints.tightFor(width: _width),
        parentUsesSize: true,
      );
      maxHeight = math.max(maxHeight, child.size.height);
      child = (child.parentData! as _DeckParentData).nextSibling;
    }
    child = firstChild;
    var finalHeight = maxHeight;
    while (child != null) {
      // Stretch the glass shell to the deck height without imposing a maximum
      // on its contents. A tight height can make the inner responsive layout
      // overflow; leaving every shell at its own height exposes a large blank
      // card back whenever a shorter memory comes to the front.
      child.layout(
        BoxConstraints(
          minWidth: _width,
          maxWidth: _width,
          minHeight: maxHeight,
        ),
        parentUsesSize: true,
      );
      finalHeight = math.max(finalHeight, child.size.height);
      final data = child.parentData! as _DeckParentData;
      data.offset = const Offset(8, 0);
      child = data.nextSibling;
    }
    size = constraints.constrain(Size(_width + 16, finalHeight + 26));
  }

  double _depth(int card, int front) =>
      (card - front + childCount) % childCount.toDouble();

  @override
  void paint(PaintingContext context, Offset offset) {
    if (childCount == 0) return;
    final p = _progress.value.clamp(-1.0, 1.0);
    final direction = p == 0 ? 1.0 : p.sign;
    final t = p.abs();
    final target = (_index + direction.toInt() + childCount) % childCount;
    final snapshot = _onPaintSnapshot;
    if (snapshot != null) {
      final bounds = boundsForSize();
      final poses = <ExplorationMemoryPose>[];
      for (var card = 0; card < childCount; card++) {
        if (card == _index) {
          final pose = t < _frontSwapProgress
              ? _frontPose(bounds, t, direction)
              : _outgoingBackPose(bounds, t, direction, _depth(_index, target));
          poses.add(
            ExplorationMemoryPose(
              Offset(pose.dx, pose.dy),
              pose.rotation,
              pose.scale,
            ),
          );
        } else {
          final oldDepth = _depth(card, _index);
          final newDepth = _depth(card, target);
          final depth = card == target
              ? oldDepth * (1 - t)
              : oldDepth + (newDepth - oldDepth) * t;
          final pose = _backPose(bounds, depth, card);
          poses.add(
            ExplorationMemoryPose(
              Offset(pose.dx, pose.dy),
              pose.rotation,
              pose.scale,
            ),
          );
        }
      }
      snapshot(_index, p, poses);
    }
    final bounds = Rect.fromLTWH(8, 0, _width, size.height - 26);
    var availableBack = _visibleBackClipPath(t, direction, target);
    final backs = <({int card, double depth})>[];
    for (var i = 0; i < childCount; i++) {
      if (i == _index && t < _frontSwapProgress) continue;
      if (i == target && t >= _frontSwapProgress) continue;
      final oldDepth = _depth(i, _index);
      final newDepth = _depth(i, target);
      final depth = i == _index && t >= _frontSwapProgress
          ? _depth(_index, target) *
                ((t - _frontSwapProgress) / (1 - _frontSwapProgress))
          : oldDepth + (newDepth - oldDepth) * t;
      backs.add((card: i, depth: depth));
    }
    // Assign each exposed pixel to its nearest pane. Re-filtering overlapping
    // translucent backs otherwise accumulates a dull gray/white patch.
    backs.sort((a, b) => a.depth.compareTo(b.depth));
    const shape = RoundedSuperellipseBorder(borderRadius: AppRadii.medium);
    for (final back in backs) {
      final pane = childAt(back.card)!;
      final pose = back.card == _index && t >= _frontSwapProgress
          ? _outgoingBackPose(bounds, t, direction, _depth(_index, target))
          : _backPose(bounds, back.depth, back.card);
      final outline = shape
          .getOuterPath(Offset.zero & pane.size)
          .transform(_childTransform(pane, pose).storage);
      final exposed = Path.combine(
        PathOperation.intersect,
        availableBack,
        outline,
      );
      if (!exposed.getBounds().isEmpty) {
        _paintGlassBack(
          context,
          offset,
          pane,
          pose,
          exposed,
          _cardBacks[back.card % _cardBacks.length],
        );
      }
      availableBack = Path.combine(
        PathOperation.difference,
        availableBack,
        outline,
      );
    }
    final front = childAt(_index);
    final incoming = childAt(target);
    if (!_highContrast && target != _index && t < _frontSwapProgress) {
      // Glass must have a real pane behind its face, not just the page wash.
      // Only the nearest card contributes a subdued silhouette; the front
      // surface's native blur/refraction then diffuses it into the material.
      final frontOutline = shape
          .getOuterPath(Offset.zero & front!.size)
          .transform(
            _childTransform(front, _frontPose(bounds, t, direction)).storage,
          );
      final incomingPose = _backPose(
        bounds,
        _depth(target, _index) * (1 - t),
        target,
      );
      final overlap = Path.combine(
        PathOperation.intersect,
        frontOutline,
        shape
            .getOuterPath(Offset.zero & incoming!.size)
            .transform(_childTransform(incoming, incomingPose).storage),
      );
      context.pushClipPath(
        true,
        offset,
        Offset.zero & size,
        overlap,
        (underContext, underOffset) => _paintChild(
          underContext,
          underOffset,
          incoming,
          incomingPose,
          opacity: .24,
        ),
      );
    }
    if (target != _index && t > .38 && t < _frontSwapProgress) {
      // Reveal only the exposed part of the next pane. Filtering the same
      // pixels twice made the overlapping glass pulse during a cut.
      final frontOutline =
          RoundedSuperellipseBorder(borderRadius: AppRadii.medium)
              .getOuterPath(Offset.zero & front!.size)
              .transform(_childTransform(front, _poseForChild(front)).storage);
      final exposed = Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        frontOutline,
      );
      context.pushClipPath(
        true,
        offset,
        Offset.zero & size,
        exposed,
        (clippedContext, clippedOffset) => _paintChild(
          clippedContext,
          clippedOffset,
          incoming!,
          _backPose(bounds, _depth(target, _index) * (1 - t), target),
        ),
      );
    }
    if (t < _frontSwapProgress || target == _index) {
      _paintChild(context, offset, front!, _frontPose(bounds, t, direction));
    }
    if (target != _index && t >= _frontSwapProgress) {
      _paintChild(
        context,
        offset,
        incoming!,
        _backPose(bounds, _depth(target, _index) * (1 - t), target),
      );
    }
  }

  void _paintGlassBack(
    PaintingContext context,
    Offset offset,
    RenderBox pane,
    _DeckPose pose,
    Path exposed,
    Color tint,
  ) {
    const shape = RoundedSuperellipseBorder(borderRadius: AppRadii.medium);
    final rect = Offset.zero & pane.size;
    final path = shape.getOuterPath(rect);
    void paintPane(PaintingContext paneContext, Offset paneOffset) {
      final canvas = paneContext.canvas;
      canvas.save();
      canvas.translate(paneOffset.dx, paneOffset.dy);
      canvas.drawPath(
        path,
        Paint()
          ..color = _highContrast
              ? (_light ? Colors.white : AppThemeColors.dark.surface)
              : tint.withValues(alpha: _light ? .045 : .028),
      );
      if (!_highContrast) {
        canvas.drawPath(
          path,
          Paint()
            ..shader = ui.Gradient.linear(
              rect.topLeft,
              rect.bottomRight,
              [
                Colors.white.withValues(alpha: _light ? .09 : .045),
                Colors.transparent,
                Colors.white.withValues(alpha: _light ? .035 : .02),
              ],
              const [0, .48, 1],
            ),
        );
        paintFrostedGlassRim(
          canvas,
          pane.size,
          shape: shape,
          light: _light,
          highlightStrength: _light ? 1.1 : .85,
        );
      }
      canvas.restore();
    }

    context.pushClipPath(
      true,
      offset,
      Offset.zero & size,
      exposed,
      (clipContext, clipOffset) => clipContext.pushTransform(
        true,
        clipOffset,
        _childTransform(pane, pose),
        (paneContext, paneOffset) {
          if (_highContrast) {
            paintPane(paneContext, paneOffset);
          } else {
            paneContext.pushLayer(
              BackdropFilterLayer(filter: _light ? _lightBlur : _darkBlur)
                ..backdropKey = _backdropKey,
              paintPane,
              paneOffset,
            );
          }
        },
      ),
    );
  }

  Rect boundsForSize() => Rect.fromLTWH(0, 0, _width, size.height - 26);

  _DeckPose _frontPose(Rect bounds, double progress, double direction) {
    final dx = direction * 6 * progress;
    final scale = 1 - .018 * progress;
    return _DeckPose(
      dx,
      -math.sin(progress * math.pi) * 14,
      _fitRotation(bounds, direction * .04 * progress, scale, dx),
      scale,
    );
  }

  _DeckPose _backPose(Rect bounds, double depth, int card) {
    final dx = depth * 2;
    final scale = 1 - depth * .012;
    final rotation = (card.isEven ? 1 : -1) * depth * .009;
    return _DeckPose(
      dx,
      depth * 6.5,
      _fitRotation(bounds, rotation, scale, dx),
      scale,
    );
  }

  double _fitRotation(Rect bounds, double rotation, double scale, double dx) {
    final available = (8 - dx.abs()).clamp(0.0, 8.0);
    final angle = rotation.abs();
    double extra(double radians) =>
        (scale *
                (bounds.width * math.cos(radians) +
                    bounds.height * math.sin(radians)) -
            bounds.width) /
        2;
    if (extra(angle) <= available) return rotation;
    var low = 0.0;
    var high = angle;
    for (var i = 0; i < 16; i++) {
      final middle = (low + high) / 2;
      if (extra(middle) <= available) {
        low = middle;
      } else {
        high = middle;
      }
    }
    return rotation.sign * low;
  }

  Path _visibleBackClipPath(double progress, double direction, int target) {
    var visible = Path()..addRect(Offset.zero & size);
    final t = progress;
    final front = childAt(_index);
    final incoming = childAt(target);

    void subtractFace(RenderBox? face, _DeckPose pose) {
      if (face == null) return;
      final outline = RoundedSuperellipseBorder(borderRadius: AppRadii.medium)
          .getOuterPath(Offset.zero & face.size)
          .transform(_childTransform(face, pose).storage);
      visible = Path.combine(PathOperation.difference, visible, outline);
    }

    if (target != _index && t >= _frontSwapProgress) {
      subtractFace(
        incoming,
        _backPose(boundsForSize(), _depth(target, _index) * (1 - t), target),
      );
    } else {
      subtractFace(front, _frontPose(boundsForSize(), t, direction));
      if (target != _index && t > .38) {
        subtractFace(
          incoming,
          _backPose(boundsForSize(), _depth(target, _index) * (1 - t), target),
        );
      }
    }
    return visible;
  }

  _DeckPose _outgoingBackPose(
    Rect bounds,
    double progress,
    double direction,
    double endDepth,
  ) {
    final t = ((progress - _frontSwapProgress) / (1 - _frontSwapProgress))
        .clamp(0.0, 1.0);
    final end = _backPose(bounds, endDepth, _index);
    final startY = -math.sin(_frontSwapProgress * math.pi) * 14;
    final dx =
        (1 - t) * _frontPose(bounds, _frontSwapProgress, direction).dx +
        t * end.dx;
    final scale =
        (1 - t) * _frontPose(bounds, _frontSwapProgress, direction).scale +
        t * end.scale;
    final rotation =
        (1 - t) * _frontPose(bounds, _frontSwapProgress, direction).rotation +
        t * end.rotation;
    return _DeckPose(
      dx,
      (1 - t) * startY + t * end.dy,
      _fitRotation(bounds, rotation, scale, dx),
      scale,
    );
  }

  void _paintChild(
    PaintingContext context,
    Offset offset,
    RenderBox child,
    _DeckPose pose, {
    double opacity = 1,
  }) {
    final transform = _childTransform(child, pose);
    context.pushClipRect(
      true,
      offset,
      Rect.fromLTWH(0, 0, size.width, size.height),
      (clipContext, clippedOffset) {
        if (opacity < .999) {
          clipContext.pushOpacity(clippedOffset, (opacity * 255).round(), (
            context,
            childOffset,
          ) {
            context.pushTransform(true, childOffset, transform, (
              context,
              transformed,
            ) {
              context.paintChild(child, transformed);
            });
          });
        } else {
          clipContext.pushTransform(true, clippedOffset, transform, (
            context,
            transformed,
          ) {
            context.paintChild(child, transformed);
          });
        }
      },
    );
  }

  RenderBox? childAt(int index) {
    var child = firstChild;
    for (var i = 0; i < index && child != null; i++) {
      child = (child.parentData! as _DeckParentData).nextSibling;
    }
    return child;
  }

  Matrix4 _childTransform(RenderBox child, _DeckPose pose) => Matrix4.identity()
    ..translateByDouble(pose.dx + 8, pose.dy, 0, 1)
    ..translateByDouble(8 + _width / 2, child.size.height / 2, 0, 1)
    ..rotateZ(pose.rotation)
    ..scaleByDouble(pose.scale, pose.scale, 1, 1)
    ..translateByDouble(-(8 + _width / 2), -child.size.height / 2, 0, 1);

  _DeckPose _poseForChild(RenderBox child) {
    final p = _progress.value.clamp(-1.0, 1.0);
    final direction = p == 0 ? 1.0 : p.sign;
    final t = p.abs();
    final target = (_index + direction.toInt() + childCount) % childCount;
    final current = childAt(_index);
    final bounds = boundsForSize();
    if (identical(child, current)) {
      if (t < _frontSwapProgress) {
        return _frontPose(bounds, t, direction);
      }
      return _outgoingBackPose(bounds, t, direction, _depth(_index, target));
    }
    final incoming = childAt(target);
    if (identical(child, incoming) && target != _index) {
      final oldDepth = _depth(target, _index);
      return _backPose(bounds, oldDepth * (1 - t), target);
    }
    for (var i = 0; i < childCount; i++) {
      if (identical(child, childAt(i))) {
        return _backPose(bounds, _depth(i, _index), i);
      }
    }
    return const _DeckPose(0, 0, 0, 1);
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.multiply(_childTransform(child, _poseForChild(child)));
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    final front = childAt(_index);
    if (front != null) visitor(front);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final front = childAt(_index);
    if (front == null) return false;
    return result.addWithPaintTransform(
      transform: _childTransform(front, _poseForChild(front)),
      position: position,
      hitTest: (result, transformed) =>
          front.hitTest(result, position: transformed),
    );
  }
}

class _DeckPose {
  const _DeckPose(this.dx, this.dy, this.rotation, this.scale);
  final double dx, dy, rotation, scale;
}
