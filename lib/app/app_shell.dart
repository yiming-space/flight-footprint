import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/localization/app_strings.dart';
import '../data/app_update_service.dart';
import '../features/add_flight/add_flight_page.dart';
import '../features/add_flight/flight_entry_sheet.dart';
import '../features/add_flight/flight_import_actions.dart';
import '../features/flights/flights_page.dart';
import '../features/home/home_page.dart';
import '../features/map/add_visited_place_sheet.dart';
import '../features/map/map_models.dart';
import '../features/profile/profile_page.dart';
import '../features/stats/stats_page.dart';
import '../ui/theme/app_theme.dart';
import '../ui/widgets/app_page_background.dart';
import '../ui/widgets/frosted_glass_surface.dart';
import 'app_controller.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.controller, this.updateService});
  final AppController controller;
  final AppUpdateService? updateService;
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell>
    with
        SingleTickerProviderStateMixin,
        WidgetsBindingObserver,
        FlightImportActions<AppShell> {
  @override
  AppController get controller => widget.controller;
  int _index = 0;
  MapMode _homeMapMode = MapMode.flight;
  late final AnimationController _addAnimation = AnimationController(
    vsync: this,
    duration: AppMotion.short,
    lowerBound: .92,
    upperBound: 1,
    value: 1,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Let Android report the real posture window. A portrait lock makes an
    // unfolded Pixel Fold letterbox the entire Flutter view, so page-level
    // wide-layout breakpoints never receive the expanded width.
    if (Platform.isAndroid || Platform.isIOS) {
      unawaited(SystemChrome.setPreferredOrientations(const []));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_checkCalendarAutoImport());
    });
  }

  Future<void> _checkCalendarAutoImport() async {
    try {
      final outcome = await widget.controller
          .checkCalendarAutoImportOnStartup();
      if (!mounted || outcome == null) return;
      final strings = context.strings;
      switch (outcome.state) {
        case CalendarAutoImportState.completed:
          break;
        case CalendarAutoImportState.permissionRequired:
          _showCalendarAutoImportNotice(
            strings.t('calendarAutoImportPermissionNeeded'),
            strings.t('calendarAutoImportOpenImport'),
          );
          return;
        case CalendarAutoImportState.unsupported:
          _showCalendarAutoImportNotice(
            strings.t('calendarAutoImportUnsupported'),
            strings.t('calendarAutoImportOpenImport'),
          );
          return;
        case CalendarAutoImportState.failed:
          _showCalendarAutoImportNotice(
            strings.t('calendarAutoImportFailed'),
            strings.t('calendarAutoImportOpenImport'),
          );
          return;
      }
      if (outcome.candidates case final candidates?) {
        await reviewCalendarScan(context, candidates);
        return;
      }
      final summary = outcome.summary;
      if (summary.added == 0 && outcome.pendingConfirmationCount == 0) return;
      final message = strings
          .t('calendarAutoImportResult')
          .replaceFirst('{added}', '${summary.added}')
          .replaceFirst('{pending}', '${outcome.pendingConfirmationCount}');
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(message),
            action: outcome.pendingConfirmationCount == 0
                ? null
                : SnackBarAction(
                    label: strings.t('calendarAutoImportReview'),
                    onPressed: () => setState(() => _index = 3),
                  ),
          ),
        );
    } catch (_) {
      if (!mounted) return;
      _showCalendarAutoImportNotice(
        context.strings.t('calendarAutoImportFailed'),
        context.strings.t('calendarAutoImportOpenImport'),
      );
    }
  }

  void _showCalendarAutoImportNotice(String message, String actionLabel) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          action: SnackBarAction(
            label: actionLabel,
            onPressed: () => setState(() => _index = 3),
          ),
        ),
      );
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
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.controller.refreshFlights());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _addAnimation.dispose();
    super.dispose();
  }

  Future<void> _openAdd([FlightEntryMethod? method]) async {
    unawaited(_playAddAnimation());
    if (method == null &&
        _index == 0 &&
        _homeMapMode == MapMode.travelFootprint) {
      await _openAddPlace();
      return;
    }
    if (method == FlightEntryMethod.manual) {
      _openManualFlight();
      return;
    }
    final FlightEntryResult? result;
    if (_isDesktopWindow(context)) {
      result = await showDialog<FlightEntryResult>(
        context: context,
        barrierDismissible: false,
        builder: (_) => Dialog(
          backgroundColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: FlightEntrySheet(
              controller: widget.controller,
              initialMethod: method,
            ),
          ),
        ),
      );
    } else {
      result = await showModalBottomSheet<FlightEntryResult>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        requestFocus: false,
        isDismissible: false,
        enableDrag: false,
        backgroundColor: Colors.transparent,
        builder: (_) => FlightEntrySheet(
          controller: widget.controller,
          initialMethod: method,
        ),
      );
    }
    if (!mounted) return;
    if (result == FlightEntryResult.manual) {
      _openManualFlight();
    } else if (result == FlightEntryResult.imported) {
      setState(() => _index = 1);
    }
  }

  void _openManualFlight() {
    if (_isDesktopWindow(context)) {
      showDialog<void>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: .62),
        builder: (_) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 72,
            vertical: 32,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760, maxHeight: 820),
            child: ClipRRect(
              borderRadius: AppRadii.large,
              child: AddFlightPage(controller: widget.controller),
            ),
          ),
        ),
      );
      return;
    }
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

  Future<void> _openAddPlace() async {
    if (_isDesktopWindow(context)) {
      await showDialog<void>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: .62),
        builder: (_) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 72,
            vertical: 32,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760, maxHeight: 820),
            child: ClipRRect(
              borderRadius: AppRadii.large,
              child: AddVisitedPlaceSheet(controller: widget.controller),
            ),
          ),
        ),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      requestFocus: false,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: .68),
      builder: (_) => FractionallySizedBox(
        heightFactor: .9,
        child: ClipPath(
          clipper: const ShapeBorderClipper(shape: AppShapes.sheet),
          child: RepaintBoundary(
            child: AddVisitedPlaceSheet(controller: widget.controller),
          ),
        ),
      ),
    );
  }

  void _setHomeMapMode(MapMode mode) {
    if (_homeMapMode == mode) return;
    setState(() => _homeMapMode = mode);
  }

  Future<void> _playAddAnimation() async {
    if (!mounted) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _addAnimation.value = 1;
      return;
    }
    try {
      await _addAnimation.animateTo(
        .94,
        duration: const Duration(milliseconds: 70),
        curve: Curves.easeOut,
      );
      await _addAnimation.animateTo(
        1,
        duration: AppMotion.short,
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
    final isDesktop = _isDesktopWindow(context);
    final addLabel = _index == 0 && _homeMapMode == MapMode.travelFootprint
        ? strings.t('addPlace')
        : strings.t('addFlight');
    final pages = [
      HomePage(
        controller: widget.controller,
        isActive: _index == 0,
        onMapModeChanged: _setHomeMapMode,
        onRecord: _openAdd,
      ),
      FlightsPage(
        controller: widget.controller,
        onAdd: _openAdd,
        onRecord: _openAdd,
      ),
      StatsPage(controller: widget.controller),
      ProfilePage(
        controller: widget.controller,
        isActive: _index == 3,
        // Keep one update workflow for the home startup and About controls.
        isHomeActive: _index == 0,
        updateService: widget.updateService,
      ),
    ];
    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _index != 0) setState(() => _index = 0);
      },
      child: isDesktop
          ? _DesktopWorkspace(
              index: _index,
              pages: pages,
              labels: [
                strings.t('home'),
                strings.t('flights'),
                strings.t('stats'),
                strings.t('profile'),
              ],
              addAnimation: _addAnimation,
              onChanged: (value) => setState(() => _index = value),
              onAdd: _openAdd,
              addLabel: addLabel,
            )
          : Scaffold(
              backgroundColor: Colors.transparent,
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
                  const AppPageBackground(),
                  // Keep the IndexedStack viewport stable across tab
                  // changes. Applying the top inset to the whole stack made
                  // the home map change height when returning from another
                  // tab, which triggered its fit-to-data camera animation.
                  // The home surface remains edge-to-edge; only the other
                  // pages receive their existing status-bar inset.
                  IndexedStack(
                    index: _index,
                    children: [
                      pages[0],
                      SafeArea(
                        top: true,
                        bottom: false,
                        left: false,
                        right: false,
                        child: pages[1],
                      ),
                      SafeArea(
                        top: true,
                        bottom: false,
                        left: false,
                        right: false,
                        child: pages[2],
                      ),
                      SafeArea(
                        top: true,
                        bottom: false,
                        left: false,
                        right: false,
                        child: pages[3],
                      ),
                    ],
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
                        addLabel: addLabel,
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  bool _isDesktopWindow(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final wideWindow = size.width >= 840;
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      return wideWindow;
    }

    // An unfolded Android foldable is still an Android window, but its
    // landscape canvas is wide enough for the desktop shell. Keeping the
    // mobile floating bottom bar in that posture lets it cover the second
    // column and the lower part of the scroll view.
    return Platform.isAndroid && wideWindow && size.width > size.height;
  }
}

class _DesktopWorkspace extends StatelessWidget {
  const _DesktopWorkspace({
    required this.index,
    required this.pages,
    required this.labels,
    required this.addAnimation,
    required this.onChanged,
    required this.onAdd,
    required this.addLabel,
  });

  final int index;
  final List<Widget> pages;
  final List<String> labels;
  final Animation<double> addAnimation;
  final ValueChanged<int> onChanged;
  final VoidCallback onAdd;
  final String addLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: false,
      body: AppPageBackground(
        child: SafeArea(
          minimum: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DesktopSidebar(
                index: index,
                labels: labels,
                addAnimation: addAnimation,
                onChanged: onChanged,
                onAdd: onAdd,
                addLabel: addLabel,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: DecoratedBox(
                  decoration: ShapeDecoration(
                    color: Colors.transparent,
                    shape: RoundedSuperellipseBorder(
                      borderRadius: AppRadii.large,
                      side: BorderSide(
                        color: colors.border.withValues(alpha: .35),
                      ),
                    ),
                  ),
                  child: Column(
                    children: [
                      _DesktopHeader(title: labels[index]),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: AppRadii.large,
                          child: IndexedStack(index: index, children: pages),
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
}

class _DesktopSidebar extends StatelessWidget {
  const _DesktopSidebar({
    required this.index,
    required this.labels,
    required this.addAnimation,
    required this.onChanged,
    required this.onAdd,
    required this.addLabel,
  });

  final int index;
  final List<String> labels;
  final Animation<double> addAnimation;
  final ValueChanged<int> onChanged;
  final VoidCallback onAdd;
  final String addLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    const icons = [
      Icons.home_rounded,
      Icons.flight_rounded,
      Icons.bar_chart_rounded,
      Icons.person_rounded,
    ];
    return SizedBox(
      width: 224,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: colors.surface,
          shape: RoundedSuperellipseBorder(
            borderRadius: AppRadii.large,
            side: BorderSide(color: colors.border.withValues(alpha: .5)),
          ),
          shadows: [
            BoxShadow(
              color: Colors.black.withValues(
                alpha: Theme.of(context).brightness == Brightness.dark
                    ? .18
                    : .06,
              ),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 18, 14, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: colors.actionFill,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.flight_takeoff_rounded,
                        color: colors.onPrimary,
                        size: 21,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Flight Footprint',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              for (var i = 0; i < labels.length; i++) ...[
                _DesktopNavItem(
                  label: labels[i],
                  icon: icons[i],
                  selected: i == index,
                  onTap: () => onChanged(i),
                ),
                const SizedBox(height: 6),
              ],
              const Spacer(),
              _DesktopLocalStatus(),
              const SizedBox(height: 12),
              ScaleTransition(
                scale: addAnimation,
                child: _DesktopAddButton(label: addLabel, onTap: onAdd),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DesktopNavItem extends StatelessWidget {
  const _DesktopNavItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final foreground = selected
        ? colors.navigationSelected
        : colors.navigationUnselected;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : AppMotion.control,
          decoration: ShapeDecoration(
            color: Colors.transparent,
            shape: AppShapes.small,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              customBorder: AppShapes.small,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Icon(icon, color: foreground, size: 22),
                    const SizedBox(width: 12),
                    Text(
                      label,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 15,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopAddButton extends StatelessWidget {
  const _DesktopAddButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Material(
        color: colors.actionFill,
        shape: AppShapes.medium,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          customBorder: AppShapes.medium,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add_rounded, color: colors.onPrimary, size: 22),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: colors.onPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopLocalStatus extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: ShapeDecoration(
        color: colors.surfaceElevated,
        shape: AppShapes.small,
      ),
      child: Row(
        children: [
          Icon(Icons.shield_outlined, size: 18, color: colors.textTertiary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '本地优先',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopHeader extends StatelessWidget {
  const _DesktopHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 22, 28, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            title,
            style: AppTextStyles.sectionTitle.copyWith(
              color: colors.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
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
    required this.addLabel,
  });
  final int index;
  final List<String> labels;
  final Animation<double> addAnimation;
  final ValueChanged<int> onChanged;
  final VoidCallback onAdd;
  final String addLabel;

  @override
  State<_BottomBar> createState() => _BottomBarState();
}

class _BottomBarState extends State<_BottomBar> {
  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    const icons = [
      Icons.home_rounded,
      Icons.flight_rounded,
      Icons.bar_chart_rounded,
      Icons.person_rounded,
    ];
    final glassShape = RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(44),
      side: BorderSide.none,
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final barSize = Size(
            constraints.maxWidth,
            AppSpacing.bottomBarHeight,
          );
          return SizedBox(
            height: barSize.height,
            child: FrostedGlassSurface(
              shape: glassShape,
              edgeThickness: 2,
              adaptiveContrast: true,
              // Keep the interior more translucent while letting the existing
              // backdrop-responsive bevel give the capsule a little more depth.
              tintOpacity: Theme.of(context).brightness == Brightness.light
                  ? .11
                  : .07,
              highlightStrength: 1.18,
              liquidRefraction: true,
              environmentReflectionStrength: 1.45,
              backgroundResponsiveHighlights: true,
              child: Padding(
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
                              label: widget.addLabel,
                              child: Material(
                                color: colors.actionFill,
                                shape: const CircleBorder(),
                                clipBehavior: Clip.antiAlias,
                                child: InkWell(
                                  onTap: widget.onAdd,
                                  customBorder: const CircleBorder(),
                                  child: Center(
                                    child: Icon(
                                      Icons.add_rounded,
                                      size: 34,
                                      color: colors.onPrimary,
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
            ),
          );
        },
      ),
    );
  }

  Widget _item(int value, IconData icon) {
    final colors = context.appColors;
    final selected = value == widget.index;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final inactiveColor = colors.navigationUnselected;
    final selectedColor = colors.navigationSelected;
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
                Text(
                  widget.labels[value],
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: selected ? selectedColor : inactiveColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
