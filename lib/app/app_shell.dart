import 'dart:async';

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
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
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
      ProfilePage(controller: widget.controller),
    ];
    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _index != 0) setState(() => _index = 0);
      },
      child: Scaffold(
        // Keep the scrollable viewport above the floating navigation bar. This
        // prevents a large artificial blank area at the end of every page.
        // Extending the body lets the page show through the navigation bar's
        // outer margins, so the bar reads as a floating control rather than a
        // full-width black footer.
        extendBody: true,
        body: SafeArea(
          top: true,
          bottom: false,
          child: IndexedStack(index: _index, children: pages),
        ),
        bottomNavigationBar: _BottomBar(
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
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: Container(
        height: 84,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          // A lower alpha is intentional: .94 reads as a solid panel on the
          // dark canvas, while .72 lets the page remain visible beneath the
          // floating menu without sacrificing label contrast.
          color: AppColors.surface.withValues(alpha: .72),
          border: Border.all(color: AppColors.border.withValues(alpha: .86)),
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .24),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
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
    );
  }

  Widget _item(int value, IconData icon) {
    final selected = value == index;
    return Expanded(
      child: InkWell(
        onTap: () => onChanged(value),
        borderRadius: BorderRadius.circular(20),
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
    );
  }
}
