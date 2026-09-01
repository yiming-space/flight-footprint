import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

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
    with SingleTickerProviderStateMixin {
  int _index = 0;
  late final AnimationController _addAnimation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 360),
    lowerBound: .88,
    upperBound: 1.08,
    value: 1,
  );

  @override
  void dispose() {
    _addAnimation.dispose();
    super.dispose();
  }

  void _openAdd() {
    unawaited(_playAddAnimation());
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: .68),
      builder: (_) => FractionallySizedBox(
        heightFactor: .94,
        child: ClipPath(
          clipper: ShapeBorderClipper(shape: AppShapes.sheet),
          child: AddFlightPage(controller: widget.controller),
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
    final pages = [
      HomePage(
        controller: widget.controller,
        onShowFlights: () => setState(() => _index = 1),
        onAdd: _openAdd,
      ),
      FlightsPage(controller: widget.controller, onAdd: _openAdd),
      StatsPage(controller: widget.controller),
      ProfilePage(
        controller: widget.controller,
        isActive: _index == 3,
      ),
    ];
    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _index != 0) setState(() => _index = 0);
      },
      child: Scaffold(
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
              child: IndexedStack(index: _index, children: pages),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _BottomBar(
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
          ],
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
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
  Widget build(BuildContext context) {
    const icons = [
      Icons.home_rounded,
      Icons.flight_rounded,
      Icons.bar_chart_rounded,
      Icons.person_rounded,
    ];
    final glassShape = RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(44),
      side: BorderSide(color: Colors.white.withValues(alpha: .16), width: .8),
    );
    return SafeArea(
      top: false,
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
            filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: DecoratedBox(
              decoration: ShapeDecoration(
                // A translucent material lets the page remain present beneath
                // the bar while the blur keeps labels readable over maps/cards.
                color: AppColors.surface.withValues(alpha: .46),
                shape: glassShape,
                shadows: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: .28),
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
                              Colors.white.withValues(alpha: .10),
                              Colors.white.withValues(alpha: .025),
                              Colors.transparent,
                            ],
                            stops: const [0, .24, 1],
                          ),
                          shape: glassShape,
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: [
                        _item(0, icons[0]),
                        _item(1, icons[1]),
                        Expanded(
                          child: Center(
                            child: ScaleTransition(
                              scale: addAnimation,
                              child: Semantics(
                                button: true,
                                label: context.strings.t('addFlight'),
                                child: IconButton.filled(
                                  onPressed: onAdd,
                                  icon: const Icon(Icons.add_rounded, size: 34),
                                  style: IconButton.styleFrom(
                                    fixedSize: const Size(64, 64),
                                    backgroundColor: AppColors.purple,
                                    foregroundColor: Colors.black,
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

  Widget _item(int value, IconData icon) {
    final selected = value == index;
    return Expanded(
      child: InkWell(
        onTap: () => onChanged(value),
        customBorder: AppShapes.medium,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: ShapeDecoration(
            color: selected
                ? AppColors.lime.withValues(alpha: .14)
                : Colors.transparent,
            shape: AppShapes.medium,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: selected ? AppColors.lime : AppColors.textTertiary,
                size: 25,
              ),
              const SizedBox(height: 4),
              Text(
                labels[value],
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? AppColors.lime : AppColors.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
