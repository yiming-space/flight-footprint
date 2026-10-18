import 'package:flight_footprint/features/stats/exploration_overview_card.dart';
import 'package:flight_footprint/ui/theme/app_theme.dart';
import 'package:flight_footprint/core/localization/app_strings.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _source = ValueKey('world-exploration-source');
const _transform = ValueKey('ranking-flip-transform');
const _surface = ValueKey('ranking-flip-surface');
const _detail = ValueKey('exploration-detail');

class _Fixture {
  final navigator = GlobalKey<NavigatorState>();
  int builds = 0;
  int detailTaps = 0;

  Future<void> mount(
    WidgetTester tester, {
    bool reduced = false,
    bool accessible = false,
    bool light = false,
    double textScale = 1,
    Size size = const Size(390, 900),
    TargetPlatform platform = TargetPlatform.android,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        locale: const Locale('en'),
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: const [
          AppStringsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: (light ? AppTheme.light() : AppTheme.dark()).copyWith(
          platform: platform,
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: reduced,
            accessibleNavigation: accessible,
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Center(
              child: ExplorationOverviewCard(
                worldCount: 22,
                chinaCount: 5,
                pageBuilder: (_) {
                  builds++;
                  return Scaffold(
                    key: _detail,
                    appBar: AppBar(title: const Text('Exploration details')),
                    body: Center(
                      child: FilledButton(
                        key: const ValueKey('detail-action'),
                        onPressed: () => detailTaps++,
                        child: const Text('Destination'),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.byKey(_source));
    await tester.pump();
    await tester.pump();
  }
}

double _sourceOpacity(WidgetTester tester) =>
    tester.widget<Opacity>(find.byKey(_source, skipOffstage: false)).opacity;

Matrix4 _matrix(WidgetTester tester) =>
    tester.widget<Transform>(find.byKey(_transform)).transform;

Rect _rect(WidgetTester tester) {
  final surface = tester.widget<Positioned>(find.byKey(_surface));
  return Rect.fromLTWH(
    surface.left!,
    surface.top!,
    surface.width!,
    surface.height!,
  );
}

void main() {
  testWidgets('exploration turns sideways from the exact source then opens', (
    tester,
  ) async {
    final fixture = _Fixture();
    await fixture.mount(tester);
    final original = tester.getRect(find.byKey(_source));
    await fixture.open(tester);
    expect(_rect(tester), original);
    expect(
      tester
          .widget<ClipRRect>(
            find
                .ancestor(
                  of: find.byKey(const ValueKey('ranking-flip-front')),
                  matching: find.byType(ClipRRect),
                )
                .first,
          )
          .borderRadius,
      AppRadii.large,
    );
    expect(_sourceOpacity(tester), 0);
    expect(_matrix(tester).entry(0, 0), closeTo(1, 1e-8));
    expect(
      find.byKey(const ValueKey('detail-action')).hitTestable(),
      findsNothing,
    );
    await tester.pump(const Duration(milliseconds: 160));
    expect(_matrix(tester).entry(2, 0), lessThan(0));
    expect(_matrix(tester).entry(1, 1), 1);
    expect(
      tester
          .widget<Offstage>(find.byKey(const ValueKey('ranking-flip-front')))
          .offstage,
      isFalse,
    );
    await tester.pump(const Duration(milliseconds: 60));
    expect(_matrix(tester).entry(2, 0), greaterThan(0));
    expect(
      tester
          .widget<Offstage>(
            find.byKey(
              const ValueKey('ranking-flip-front'),
              skipOffstage: false,
            ),
          )
          .offstage,
      isTrue,
    );
    expect(tester.getSize(find.byKey(_detail)), const Size(390, 900));
    await tester.pumpAndSettle();
    expect(_rect(tester), const Rect.fromLTWH(0, 0, 390, 900));
    expect(fixture.builds, 1);
    await tester.tap(find.byKey(const ValueKey('detail-action')));
    expect(fixture.detailTaps, 1);
    await tester.tap(find.byType(BackButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(_sourceOpacity(tester), 0);
    await tester.pumpAndSettle();
    expect(_sourceOpacity(tester), 1);
    expect(find.byKey(_detail), findsNothing);
    expect(tester.takeException(), isNull);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets(
    'sampled frames never mirror text; early back and reopening work',
    (tester) async {
      final fixture = _Fixture();
      await fixture.mount(tester);
      await fixture.open(tester);
      await tester.tap(find.byKey(_source), warnIfMissed: false);
      for (var frame = 0; frame < 35; frame++) {
        final matrix = _matrix(tester);
        expect(matrix.storage.every((value) => value.isFinite), isTrue);
        expect(matrix.entry(0, 0), greaterThanOrEqualTo(-1e-8));
        if (frame == 20) fixture.navigator.currentState!.pop();
        await tester.pump(const Duration(milliseconds: 10));
      }
      await tester.pumpAndSettle();
      expect(fixture.builds, 1);
      expect(_sourceOpacity(tester), 1);
      await fixture.open(tester);
      await tester.pumpAndSettle();
      expect(fixture.builds, 2);
      fixture.navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  for (final flag in ['reduced', 'accessible']) {
    testWidgets('$flag replaces the flip with a short fade', (tester) async {
      final fixture = _Fixture();
      await fixture.mount(
        tester,
        reduced: flag == 'reduced',
        accessible: flag == 'accessible',
      );
      await fixture.open(tester);
      expect(find.byKey(_transform), findsNothing);
      final route = ModalRoute.of(tester.element(find.byKey(_detail)))!;
      expect(route.transitionDuration, const Duration(milliseconds: 120));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('detail-action')).hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('detail-action')));
      expect(fixture.detailTaps, 1);
      fixture.navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(_sourceOpacity(tester), 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'narrow/wide and 2x text retain full page layout in both themes',
    (tester) async {
      for (final width in [320.0, 900.0]) {
        for (final light in [true, false]) {
          final fixture = _Fixture();
          await fixture.mount(
            tester,
            size: Size(width, 1000),
            textScale: 2,
            light: light,
          );
          await fixture.open(tester);
          await tester.pump(const Duration(milliseconds: 230));
          expect(tester.getSize(find.byKey(_detail)), Size(width, 1000));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          fixture.navigator.currentState!.pop();
          await tester.pumpAndSettle();
          await tester.pumpWidget(const SizedBox.shrink());
        }
      }
    },
  );

  testWidgets('iOS retains native interactive edge back', (tester) async {
    final fixture = _Fixture();
    await fixture.mount(tester, platform: TargetPlatform.iOS);
    await fixture.open(tester);
    await tester.pumpAndSettle();
    final route = ModalRoute.of(tester.element(find.byKey(_detail)))!;
    expect(route, isA<CupertinoPageRoute<void>>());
    expect(find.byKey(_transform), findsNothing);
    await tester.dragFrom(const Offset(1, 450), const Offset(360, 0));
    await tester.pumpAndSettle();
    expect(fixture.navigator.currentState!.canPop(), isFalse);
    expect(_sourceOpacity(tester), 1);
    expect(tester.takeException(), isNull);
  });
}
