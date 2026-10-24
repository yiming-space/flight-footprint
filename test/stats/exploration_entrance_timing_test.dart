import 'package:flight_footprint/core/localization/app_strings.dart';
import 'package:flight_footprint/features/stats/exploration_map_artwork.dart';
import 'package:flight_footprint/features/stats/exploration_overview_card.dart';
import 'package:flight_footprint/features/stats/exploration_passport.dart';
import 'package:flight_footprint/features/stats/world_exploration.dart';
import 'package:flight_footprint/features/map/passport_map_palette.dart';
import 'package:flight_footprint/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _source = ValueKey('world-exploration-source');
const _places = [
  ExplorationPlace(
    name: 'Singapore',
    countryCode: 'SG',
    latitude: 1.35,
    longitude: 103.82,
  ),
  ExplorationPlace(
    name: 'London',
    countryCode: 'GB',
    latitude: 51.5,
    longitude: -.12,
  ),
];

class _Fixture {
  Future<void> mount(
    WidgetTester tester, {
    bool reduced = false,
    bool accessible = false,
    bool light = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 1100);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: (light ? AppTheme.light() : AppTheme.dark()).copyWith(
          platform: TargetPlatform.android,
        ),
        locale: const Locale('en'),
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: const [
          AppStringsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: reduced,
            accessibleNavigation: accessible,
          ),
          child: child!,
        ),
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: ExplorationOverviewCard(
                worldCount: 2,
                chinaCount: 0,
                pageBuilder: (_) => Scaffold(
                  appBar: AppBar(title: const Text('Exploration details')),
                  body: ExplorationPassport(
                    places: _places,
                    worldCount: 2,
                    home: null,
                    homeLoaded: true,
                    onChooseHome: () {},
                  ),
                ),
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

Color _coast(WidgetTester tester, TravelContinent continent) => tester
    .widget<ExplorationMapArtwork>(
      find.byWidgetPredicate(
        (widget) =>
            widget is ExplorationMapArtwork && widget.continent == continent,
        skipOffstage: false,
      ),
    )
    .color!;

ModalRoute<dynamic> _route(WidgetTester tester) => ModalRoute.of(
  tester.element(find.byType(ExplorationPassport, skipOffstage: false)),
)!;

void main() {
  setUpAll(() async => ExplorationMapArtwork.preload());

  testWidgets('real passport illuminates once after the flip has completed', (
    tester,
  ) async {
    final fixture = _Fixture();
    await fixture.mount(tester);
    expect(find.byType(ExplorationPassport), findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
    await fixture.open(tester);
    final route = _route(tester);
    expect(route.animation!.status, AnimationStatus.forward);
    final muted = _coast(tester, TravelContinent.asia);
    final locked = _coast(tester, TravelContinent.africa);
    // Sample both the source-facing and destination-facing portions. Detail
    // geometry is already mounted, but its entrance must not compete with flip.
    for (final step in [160, 140, 140]) {
      await tester.pump(Duration(milliseconds: step));
      expect(route.animation!.status, AnimationStatus.forward);
      expect(_coast(tester, TravelContinent.asia), muted);
    }
    await tester.pump(const Duration(milliseconds: 30));
    expect(route.animation!.status, AnimationStatus.completed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    final revealing = _coast(tester, TravelContinent.asia);
    expect(revealing, isNot(muted));
    await tester.pumpAndSettle();
    final lit = _coast(tester, TravelContinent.asia);
    expect(lit, AppThemeColors.dark.lime);
    expect(lit, isNot(revealing));
    expect(_coast(tester, TravelContinent.africa), locked);
    expect(tester.binding.transientCallbackCount, 0);
    // Selecting a continent rebuilds the real passport and opens its detail;
    // that rebuild must not replay the entrance animation.
    await tester.tap(find.byKey(const ValueKey('exploration-continent-asia')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_coast(tester, TravelContinent.asia), lit);
    await tester.pumpAndSettle();
    expect(find.text('Singapore'), findsWidgets);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(ExplorationPassport), findsNothing);
    expect(tester.widget<Opacity>(find.byKey(_source)).opacity, 1);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('light passport continents use the passport map land color', (
    tester,
  ) async {
    final fixture = _Fixture();
    await fixture.mount(tester, light: true);
    await fixture.open(tester);
    await tester.pumpAndSettle();
    expect(
      _coast(tester, TravelContinent.asia),
      passportMapLandFill(light: true),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'system back during flip disposes waiting entrance without a ticker',
    (tester) async {
      final fixture = _Fixture();
      await fixture.mount(tester);
      await fixture.open(tester);
      final muted = _coast(tester, TravelContinent.asia);
      await tester.pump(const Duration(milliseconds: 120));
      expect(_coast(tester, TravelContinent.asia), muted);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(ExplorationPassport), findsNothing);
      expect(tester.widget<Opacity>(find.byKey(_source)).opacity, 1);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    },
  );

  for (final flag in ['reduced', 'accessible']) {
    testWidgets('$flag settles real passport without entrance tickers', (
      tester,
    ) async {
      final fixture = _Fixture();
      await fixture.mount(
        tester,
        reduced: flag == 'reduced',
        accessible: flag == 'accessible',
      );
      await fixture.open(tester);
      expect(
        _route(tester).transitionDuration,
        const Duration(milliseconds: 120),
      );
      await tester.pumpAndSettle();
      final lit = _coast(tester, TravelContinent.asia);
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pump(const Duration(seconds: 1));
      expect(_coast(tester, TravelContinent.asia), lit);
      expect(tester.binding.transientCallbackCount, 0);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(ExplorationPassport), findsNothing);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    });
  }
}
