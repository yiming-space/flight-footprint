import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../core/localization/app_strings.dart';
import '../features/add_flight/add_flight_page.dart';
import '../features/flights/flights_page.dart';
import '../features/home/home_page.dart';
import '../features/profile/profile_page.dart';
import '../features/stats/stats_page.dart';
import '../ui/theme/app_theme.dart';
import 'app_controller.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.controller});
  final AppController controller;
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  int _index = 0;
  late final AnimationController _addAnimation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 360),
    lowerBound: .88,
    upperBound: 1.08,
    value: 1,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeMetrics() {
    // A fold/unfold can interrupt the add-button spring while Android is
    // resizing the window. Reset it before the next frame so the fixed
    // circular button is never left in a stale transform state.
    if (_addAnimation.isAnimating || (_addAnimation.value - 1).abs() > .001) {
      _addAnimation
        ..stop()
        ..value = 1;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _addAnimation.dispose();
    super.dispose();
  }

  void _openAdd() {
    unawaited(_playAddAnimation());
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      // The form should only open the IME after the user taps a field. This
      // avoids competing with the bottom-sheet entrance animation.
      requestFocus: false,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: .68),
      builder: (_) => FractionallySizedBox(
        heightFactor: .94,
        child: ClipPath(
          clipper: ShapeBorderClipper(shape: AppShapes.sheet),
          child: RepaintBoundary(
            child: AddFlightPage(controller: widget.controller),
          ),
        ),
      ),
    );
  }

  Future<void> _playAddAnimation() async {
    if (!mounted) return;
    try {
      await _addAnimation.animateTo(
        .9,
        duration: const Duration(milliseconds: 70),
        curve: Curves.easeOut,
      );
      await _addAnimation.animateTo(
        1.08,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutBack,
      );
      await _addAnimation.animateTo(
        1,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
      );
    } on TickerCanceled {
      // The shell can be disposed while a route transition is in progress.
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    // Do not subscribe the whole app shell to viewInsets. Android reports
    // the IME animation as a stream of inset changes; using MediaQuery.of
    // here would rebuild the IndexedStack on every keyboard frame. The
    // bottom bar only needs real window changes, and viewPadding deliberately
    // excludes the keyboard inset while retaining system-bar safe areas.
    final size = MediaQuery.sizeOf(context);
    final viewPadding = MediaQuery.viewPaddingOf(context);
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    final bottomBarKey = ValueKey(
      '${size.width}:${size.height}:'
      '${viewPadding.left}:${viewPadding.right}:'
      '${viewPadding.top}:${viewPadding.bottom}:'
      '$devicePixelRatio',
    );
    final pages = [
      HomePage(
        controller: widget.controller,
        onShowFlights: () => setState(() => _index = 1),
        onAdd: _openAdd,
      ),
      FlightsPage(controller: widget.controller, onAdd: _openAdd),
      StatsPage(controller: widget.controller),
      ProfilePage(controller: widget.controller, isActive: _index == 3),
    ];
    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _index != 0) setState(() => _index = 0);
      },
      child: Scaffold(
        // The modal sheet owns IME avoidance through its viewInsets-aware
        // padding. Keeping the underlying shell fixed prevents the entire
        // page stack and its map from relayouting during the keyboard slide.
        resizeToAvoidBottomInset: false,
        // The navigation material floats in the same stack as the pages.
        // Using Scaffold.bottomNavigationBar would still create a rectangular
        // footer region around the rounded glass, preventing page content from
        // showing through its outer margins.
        body: Stack(
          fit: StackFit.expand,
          children: [
            SafeArea(
              top: true,
              bottom: false,
              left: false,
              right: false,
              child: IndexedStack(index: _index, children: pages),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: RepaintBoundary(
                child: _BottomBar(
                  key: bottomBarKey,
                  index: _index,
                  labels: [
                    strings.t('home'),
                    strings.t('flights'),
                    strings.t('stats'),
                    strings.t('profile'),
                  ],
                  addAnimation: _addAnimation,
                  onChanged: (value) => setState(() => _index = value),
                  onAdd: _openAdd,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomBar extends StatefulWidget {
  const _BottomBar({
    super.key,
    required this.index,
    required this.labels,
    required this.addAnimation,
    required this.onChanged,
    required this.onAdd,
  });
  final int index;
  final List<String> labels;
  final Animation<double> addAnimation;
  final ValueChanged<int> onChanged;
  final VoidCallback onAdd;

  @override
  State<_BottomBar> createState() => _BottomBarState();
}

class _BottomBarState extends State<_BottomBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _selectionAnimation;
  var _selectionStart = 0.0;
  var _selectionTarget = 0.0;

  @override
  void initState() {
    super.initState();
    final initialSlot = _slotForIndex(widget.index).toDouble();
    _selectionStart = initialSlot;
    _selectionTarget = initialSlot;
    _selectionAnimation = AnimationController.unbounded(
      vsync: this,
      value: initialSlot,
    );
  }

  @override
  void didUpdateWidget(covariant _BottomBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index == widget.index) return;

    final target = _slotForIndex(widget.index).toDouble();
    _selectionStart = _selectionAnimation.value;
    _selectionTarget = target;
    if (MediaQuery.disableAnimationsOf(context)) {
      _selectionAnimation.value = target;
      return;
    }

    final spring = SpringDescription.withDurationAndBounce(
      duration: const Duration(milliseconds: 400),
      bounce: 0,
    );
    unawaited(
      _selectionAnimation.animateWith(
        SpringSimulation(
          spring,
          _selectionAnimation.value,
          target,
          _selectionAnimation.velocity,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _selectionAnimation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final glassBorder = isLight
        ? colors.border.withValues(alpha: .58)
        : Colors.white.withValues(alpha: .16);
    final glassColor = isLight
        ? Colors.white.withValues(alpha: .66)
        : colors.surface.withValues(alpha: .46);
    final glassShadow = Colors.black.withValues(alpha: isLight ? .12 : .28);
    const icons = [
      Icons.home_rounded,
      Icons.flight_rounded,
      Icons.bar_chart_rounded,
      Icons.person_rounded,
    ];
    final glassShape = RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(44),
      side: BorderSide(color: glassBorder, width: .8),
    );
    return SafeArea(
      top: false,
      left: false,
      right: false,
      maintainBottomViewPadding: true,
      minimum: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.sm,
        AppSpacing.page,
        AppSpacing.bottomBarBottomMinimum,
      ),
      child: SizedBox(
        height: AppSpacing.bottomBarHeight,
        child: ClipPath(
          clipper: ShapeBorderClipper(shape: glassShape),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(
              sigmaX: isLight ? 24 : 20,
              sigmaY: isLight ? 24 : 20,
            ),
            child: DecoratedBox(
              decoration: ShapeDecoration(
                // A translucent material lets the page remain present beneath
                // the bar while the blur keeps labels readable over maps/cards.
                color: glassColor,
                shape: glassShape,
                shadows: [
                  BoxShadow(
                    color: glassShadow,
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: ShapeDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.white.withValues(
                                alpha: isLight ? .28 : .10,
                              ),
                              Colors.white.withValues(
                                alpha: isLight ? .07 : .025,
                              ),
                              Colors.transparent,
                            ],
                            stops: const [0, .24, 1],
                          ),
                          shape: glassShape,
                        ),
                      ),
                    ),
                  ),
                  _liquidSelection(),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: [
                        _item(0, icons[0]),
                        _item(1, icons[1]),
                        Expanded(
                          child: Center(
                            child: ScaleTransition(
                              scale: widget.addAnimation,
                              child: SizedBox.square(
                                dimension: 64,
                                child: Semantics(
                                  button: true,
                                  label: context.strings.t('addFlight'),
                                  child: Material(
                                    color: colors.purple,
                                    shape: const CircleBorder(),
                                    clipBehavior: Clip.antiAlias,
                                    child: InkWell(
                                      onTap: widget.onAdd,
                                      customBorder: const CircleBorder(),
                                      child: Center(
                                        child: Icon(
                                          Icons.add_rounded,
                                          size: 34,
                                          color: colors.cardText,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        _item(2, icons[2]),
                        _item(3, icons[3]),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _liquidSelection() {
    final colors = context.appColors;
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Positioned.fill(
      child: IgnorePointer(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final slotWidth = (constraints.maxWidth - 16) / 5;
              final baseWidth = math.max(0.0, slotWidth - 6);
              final shape = RoundedSuperellipseBorder(
                borderRadius: BorderRadius.circular(26),
                side: BorderSide(
                  color: isLight
                      ? Colors.white.withValues(alpha: .18)
                      : colors.lime.withValues(alpha: .08),
                  width: .6,
                ),
              );

              return AnimatedBuilder(
                animation: _selectionAnimation,
                builder: (context, child) {
                  final travel = _selectionTarget - _selectionStart;
                  final progress = travel.abs() < .001
                      ? 1.0
                      : ((_selectionAnimation.value - _selectionStart) / travel)
                            .clamp(0.0, 1.0)
                            .toDouble();
                  // Stretch from the middle of the route, not from the raw
                  // spring velocity. This keeps the blob's edge motion
                  // continuous when the user quickly changes destinations.
                  final stretch = math.sin(progress * math.pi) * 10;
                  final scaleX = baseWidth <= 0 ? 1.0 : 1 + stretch / baseWidth;
                  final left =
                      8 +
                      _selectionAnimation.value * slotWidth +
                      3 -
                      stretch / 2;
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: Transform.translate(
                      offset: Offset(left, 0),
                      child: Transform.scale(
                        alignment: Alignment.center,
                        scaleX: scaleX,
                        child: SizedBox(
                          width: baseWidth,
                          height: constraints.maxHeight,
                          child: child,
                        ),
                      ),
                    ),
                  );
                },
                child: DecoratedBox(
                  decoration: ShapeDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        colors.lime.withValues(alpha: isLight ? .25 : .22),
                        colors.lime.withValues(alpha: isLight ? .10 : .11),
                        colors.lime.withValues(alpha: isLight ? .18 : .16),
                      ],
                    ),
                    shape: shape,
                    shadows: [
                      BoxShadow(
                        color: colors.lime.withValues(
                          alpha: isLight ? .10 : .08,
                        ),
                        blurRadius: 18,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _item(int value, IconData icon) {
    final colors = context.appColors;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final selected = value == widget.index;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final inactiveColor = isLight
        ? colors.textSecondary.withValues(alpha: .82)
        : colors.textTertiary;
    final selectedColor = isLight
        ? Color.lerp(colors.lime, colors.textPrimary, .12)!
        : colors.lime;
    final style = TextStyle(
      fontSize: 11,
      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      color: selected ? selectedColor : inactiveColor,
    );
    return Expanded(
      child: InkWell(
        onTap: () => widget.onChanged(value),
        customBorder: AppShapes.medium,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedSwitcher(
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 180),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(
                      scale: Tween<double>(
                        begin: .82,
                        end: 1,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: SizedBox.square(
                    key: ValueKey('$value-$selected'),
                    dimension: 25,
                    child: Icon(
                      icon,
                      color: selected ? selectedColor : inactiveColor,
                      size: 25,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                AnimatedDefaultTextStyle(
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  style: style,
                  child: Text(widget.labels[value]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static int _slotForIndex(int value) => value < 2 ? value : value + 1;
}
