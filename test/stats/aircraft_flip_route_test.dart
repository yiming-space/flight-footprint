import 'package:flight_footprint/features/stats/aircraft_flip_route.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _sourceRect = Rect.fromLTWH(36, 80, 220, 160);
const _pageSize = Size(800, 600);
const _transformKey = ValueKey('aircraft-flip-transform');
const _surfaceKey = ValueKey('aircraft-flip-surface');
const _frontButtonKey = ValueKey('front-button');
const _detailButtonKey = ValueKey('detail-button');

class _Fixture {
  final navigator = GlobalKey<NavigatorState>();
  Route<void>? route;
  int frontTaps = 0;
  int detailTaps = 0;

  Future<void> mount(
    WidgetTester tester, {
    Rect sourceRect = _sourceRect,
    Size? frontSize,
    Widget? front,
    TargetPlatform platform = TargetPlatform.android,
    bool disableAnimations = false,
    bool accessibleNavigation = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = _pageSize;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        theme: ThemeData(platform: platform),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: disableAnimations,
            accessibleNavigation: accessibleNavigation,
          ),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Stack(
              children: [
                Positioned.fromRect(
                  rect: _sourceRect,
                  child: FilledButton(
                    key: const ValueKey('open-detail'),
                    onPressed: () {
                      route = aircraftFlipRoute<void>(
                        context: context,
                        sourceRect: sourceRect,
                        frontSize: frontSize,
                        front:
                            front ??
                            Material(
                              color: Colors.blue,
                              child: TextButton(
                                key: _frontButtonKey,
                                onPressed: () => frontTaps++,
                                child: const Text('Aircraft front'),
                              ),
                            ),
                        builder: (_) => Scaffold(
                          appBar: AppBar(
                            leading: const BackButton(),
                            title: const Text('Aircraft detail'),
                          ),
                          body: Center(
                            child: FilledButton(
                              key: _detailButtonKey,
                              onPressed: () => detailTaps++,
                              child: const Text('Real detail content'),
                            ),
                          ),
                        ),
                      );
                      navigator.currentState!.push<void>(route!);
                    },
                    child: const Text('Open aircraft'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open-detail')));
    await tester.pump();
    // The first route frame measures its offstage page. A second frame exposes
    // the transition at the same timestamp, before its animation advances.
    await tester.pump();
  }
}

Transform _transform(WidgetTester tester) =>
    tester.widget<Transform>(find.byKey(_transformKey));

TransitionRoute<void> _transition(_Fixture fixture) =>
    fixture.route! as TransitionRoute<void>;

Rect _surface(WidgetTester tester) {
  final positioned = tester.widget<Positioned>(find.byKey(_surfaceKey));
  return Rect.fromLTWH(
    positioned.left!,
    positioned.top!,
    positioned.width!,
    positioned.height!,
  );
}

void _expectFiniteFrontFacing(WidgetTester tester) {
  final matrix = _transform(tester).transform;
  expect(matrix.storage.every((value) => value.isFinite), isTrue);
  expect(
    matrix.entry(1, 1),
    greaterThanOrEqualTo(-1e-8),
    reason: 'Neither face may rotate through its mirrored back side',
  );
}

void _expectHeroDisabled(Finder face) {
  final modes = [
    ...find.ancestor(of: face, matching: find.byType(HeroMode)).evaluate(),
    ...find.descendant(of: face, matching: find.byType(HeroMode)).evaluate(),
  ].map((element) => element.widget as HeroMode);
  expect(modes.any((mode) => !mode.enabled), isTrue);
}

void main() {
  testWidgets('compressed source bounds do not relayout the front card', (
    tester,
  ) async {
    final fixture = _Fixture();
    await fixture.mount(
      tester,
      sourceRect: const Rect.fromLTWH(36, 80, 200, 70),
      frontSize: const Size(220, 320),
      front: const Column(
        children: [
          SizedBox(key: ValueKey('logical-front-content'), height: 320),
        ],
      ),
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('logical-front-content')))
          .height,
      320,
    );
    await tester.pump(const Duration(milliseconds: 160));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    fixture.navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('starts at the source and hands off between front-facing faces', (
    tester,
  ) async {
    final fixture = _Fixture();
    await fixture.mount(tester);
    expect(
      _transition(fixture).transitionDuration,
      const Duration(milliseconds: 460),
    );
    expect(
      _transition(fixture).reverseTransitionDuration,
      const Duration(milliseconds: 420),
    );
    expect(_surface(tester), _sourceRect);
    expect(_transform(tester).transform.entry(1, 1), closeTo(1, 1e-8));
    _expectHeroDisabled(find.byKey(const ValueKey('aircraft-flip-front')));

    await tester.pump(const Duration(milliseconds: 180));
    _expectFiniteFrontFacing(tester);
    expect(_transform(tester).transform.entry(2, 1), greaterThan(0));
    expect(
      tester
          .widget<Offstage>(
            find.byKey(
              const ValueKey('aircraft-flip-front'),
              skipOffstage: false,
            ),
          )
          .offstage,
      isFalse,
    );
    await tester.pump(const Duration(milliseconds: 30));
    _expectFiniteFrontFacing(tester);
    expect(_transform(tester).transform.entry(2, 1), lessThan(0));
    expect(
      tester
          .widget<Offstage>(
            find.byKey(
              const ValueKey('aircraft-flip-front'),
              skipOffstage: false,
            ),
          )
          .offstage,
      isTrue,
    );
    _expectHeroDisabled(find.byKey(const ValueKey('aircraft-flip-detail')));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
  });

  testWidgets('finishes as a full page whose real back button returns', (
    tester,
  ) async {
    final fixture = _Fixture();
    await fixture.mount(tester);
    await tester.pumpAndSettle();
    expect(_surface(tester), Offset.zero & _pageSize);
    expect(_transform(tester).transform.entry(1, 1), closeTo(1, 1e-8));
    expect(find.text('Real detail content'), findsOneWidget);
    expect(tester.getSize(find.byType(Scaffold).last), _pageSize);
    await tester.tap(find.byKey(_detailButtonKey));
    expect(fixture.detailTaps, 1);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('open-detail')), findsOneWidget);
    expect(find.byKey(_detailButtonKey), findsNothing);
    expect(fixture.navigator.currentState!.canPop(), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('all sampled forward frames stay finite and never mirror', (
    tester,
  ) async {
    final fixture = _Fixture();
    await fixture.mount(tester);
    for (var frame = 0; frame < 45; frame++) {
      _expectFiniteFrontFacing(tester);
      await tester.pump(const Duration(milliseconds: 10));
    }
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('an early pop reverses safely back to the source', (
    tester,
  ) async {
    final fixture = _Fixture();
    await fixture.mount(tester);
    await tester.pump(const Duration(milliseconds: 100));
    fixture.navigator.currentState!.pop();
    await tester.pump();
    _expectFiniteFrontFacing(tester);
    for (var frame = 0; frame < 8; frame++) {
      await tester.pump(const Duration(milliseconds: 10));
      if (find.byKey(_transformKey).evaluate().isNotEmpty) {
        _expectFiniteFrontFacing(tester);
      }
    }
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('open-detail')), findsOneWidget);
    expect(find.byKey(_detailButtonKey), findsNothing);
    expect(tester.takeException(), isNull);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('the hidden face cannot receive taps', (tester) async {
    final fixture = _Fixture();
    await fixture.mount(tester);
    expect(find.byKey(_detailButtonKey).hitTestable(), findsNothing);
    await tester.tapAt(_pageSize.center(Offset.zero));
    expect(fixture.detailTaps, 0);
    await tester.pump(const Duration(milliseconds: 280));
    expect(find.byKey(_frontButtonKey).hitTestable(), findsNothing);
    await tester.tapAt(_sourceRect.center);
    expect(fixture.frontTaps, 0);
    await tester.pumpAndSettle();
  });

  for (final flag in ['disableAnimations', 'accessibleNavigation']) {
    testWidgets('$flag uses a short fade with no flip transform', (
      tester,
    ) async {
      final fixture = _Fixture();
      await fixture.mount(
        tester,
        disableAnimations: flag == 'disableAnimations',
        accessibleNavigation: flag == 'accessibleNavigation',
      );
      expect(
        _transition(fixture).transitionDuration,
        const Duration(milliseconds: 120),
      );
      expect(
        _transition(fixture).reverseTransitionDuration,
        const Duration(milliseconds: 120),
      );
      expect(find.byKey(_transformKey), findsNothing);
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.byKey(_transformKey), findsNothing);
      await tester.pumpAndSettle();
      expect(find.byKey(_detailButtonKey).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('invalid source rectangles fall back without nonfinite layout', (
    tester,
  ) async {
    for (final rect in [
      Rect.zero,
      const Rect.fromLTWH(20, 20, -10, 80),
      const Rect.fromLTWH(double.nan, 20, 100, 80),
      const Rect.fromLTWH(20, 20, double.infinity, 80),
    ]) {
      final fixture = _Fixture();
      await fixture.mount(tester, sourceRect: rect);
      if (find.byKey(_transformKey).evaluate().isNotEmpty) {
        _expectFiniteFrontFacing(tester);
      }
      if (find.byKey(_surfaceKey).evaluate().isNotEmpty) {
        final surface = _surface(tester);
        expect(
          [
            surface.left,
            surface.top,
            surface.width,
            surface.height,
          ].every((value) => value.isFinite),
          isTrue,
        );
        expect(surface.width, greaterThan(0));
        expect(surface.height, greaterThan(0));
      }
      await tester.pumpAndSettle();
      expect(find.byKey(_detailButtonKey), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });

  testWidgets('iOS keeps CupertinoPageRoute and native back behavior', (
    tester,
  ) async {
    final fixture = _Fixture();
    await fixture.mount(tester, platform: TargetPlatform.iOS);
    expect(fixture.route, isA<CupertinoPageRoute<void>>());
    expect(find.byKey(_transformKey), findsNothing);
    await tester.pumpAndSettle();
    expect(
      (fixture.route! as CupertinoPageRoute<void>).popGestureEnabled,
      isTrue,
    );
    await tester.dragFrom(const Offset(1, 300), const Offset(650, 0));
    await tester.pumpAndSettle();
    expect(fixture.navigator.currentState!.canPop(), isFalse);
    expect(find.byKey(const ValueKey('open-detail')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
