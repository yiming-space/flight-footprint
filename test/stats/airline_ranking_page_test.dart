import 'package:flight_footprint/core/localization/app_strings.dart';
import 'package:flight_footprint/domain/flight.dart';
import 'package:flight_footprint/features/stats/airline_ranking.dart';
import 'package:flight_footprint/features/stats/airline_ranking_count.dart';
import 'package:flight_footprint/features/stats/airline_ranking_overview_card.dart';
import 'package:flight_footprint/features/stats/airline_ranking_page.dart';
import 'package:flight_footprint/features/stats/airline_ranking_tile.dart';
import 'package:flight_footprint/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageRoute;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

List<AirlineRankingEntry> entries() => List.generate(
  5,
  (index) => AirlineRankingEntry(
    name: 'Airline ${index + 1}',
    iataCode: null,
    flights: List.generate(
      5 - index,
      (flightIndex) => Flight(
        id: '$index-$flightIndex',
        departureIata: 'PVG',
        arrivalIata: 'PEK',
        departedAt: DateTime(2026, 1, 1),
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ),
    ),
  ),
);

Widget host(
  Widget home, {
  bool isLight = true,
  Locale locale = const Locale('zh'),
  double textScale = 1,
  bool disableAnimations = false,
  bool accessibleNavigation = false,
  TargetPlatform? platform,
}) => MaterialApp(
  theme: (isLight ? AppTheme.light() : AppTheme.dark()).copyWith(
    platform: platform,
  ),
  locale: locale,
  supportedLocales: AppStrings.supportedLocales,
  localizationsDelegates: const [
    AppStringsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      textScaler: TextScaler.linear(textScale),
      disableAnimations: disableAnimations,
      accessibleNavigation: accessibleNavigation,
    ),
    child: child!,
  ),
  home: home,
);

void main() {
  Widget expansionHost({
    VoidCallback? onBuild,
    bool reduced = false,
    bool accessible = false,
    TargetPlatform? platform,
    double textScale = 1,
    bool isLight = true,
  }) => host(
    Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: AirlineRankingOverviewCard(
            airlineCount: 5,
            pageBuilder: (context) {
              onBuild?.call();
              return AirlineRankingPage(
                items: entries(),
                animateEntrance: true,
                onAirlineSelected: (entry) => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => Scaffold(
                      appBar: AppBar(title: Text(entry.name)),
                      body: const Text('Selected flights'),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    ),
    disableAnimations: reduced,
    accessibleNavigation: accessible,
    platform: platform,
    textScale: textScale,
    isLight: isLight,
  );

  double sourceOpacity(WidgetTester tester) => tester
      .widget<Opacity>(
        find.byKey(
          const ValueKey('airline-ranking-source'),
          skipOffstage: false,
        ),
      )
      .opacity;

  testWidgets(
    'card flips once, then fills capsules with stable title and labels',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      var builds = 0;
      await tester.pumpWidget(expansionHost(onBuild: () => builds++));
      await tester.pumpAndSettle();
      final card = find.byType(AirlineRankingOverviewCard);
      final original = tester.getRect(card);
      final pointer = await tester.startGesture(tester.getCenter(card));
      await tester.pump(const Duration(milliseconds: 40));
      expect(
        tester
            .widget<AnimatedScale>(
              find.byKey(const ValueKey('airline-ranking-press')),
            )
            .scale,
        .985,
      );
      await pointer.up();
      await tester.tap(card, warnIfMissed: false);
      await tester.pump();
      expect(sourceOpacity(tester), 1);
      await tester.pump();
      expect(sourceOpacity(tester), 0);
      final surface = tester.widget<Positioned>(
        find.byKey(const ValueKey('ranking-flip-surface')),
      );
      expect(surface.left, closeTo(original.left, .01));
      expect(surface.top, closeTo(original.top, .01));
      final width = tester
          .getSize(find.byType(AirlineRankingTile, skipOffstage: false).first)
          .width;
      await tester.pump(const Duration(milliseconds: 240));
      expect(
        tester
            .widget<AirlineRankingTile>(find.byType(AirlineRankingTile).first)
            .fillReveal,
        0,
      );
      final title = find.descendant(
        of: find.byType(AirlineRankingPage),
        matching: find.text('航司排行'),
      );
      expect(title, findsOneWidget);
      expect(
        find.ancestor(of: title, matching: find.byType(FadeTransition)),
        findsNothing,
      );
      expect(find.byType(Hero), findsNothing);
      expect(find.text('累计 · 已完成航班'), findsNothing);
      expect(
        tester
            .widget<AirlineRankingCount>(find.byType(AirlineRankingCount).first)
            .reveal,
        0,
      );
      expect(
        find.descendant(
          of: find.byType(AirlineRankingCount).first,
          matching: find.text('0 次'),
        ),
        findsOneWidget,
      );
      await tester.pump(const Duration(milliseconds: 230));
      await tester.pump(const Duration(milliseconds: 120));
      final first = tester
          .widget<AirlineRankingTile>(find.byType(AirlineRankingTile).first)
          .fillReveal;
      final fourth = tester
          .widget<AirlineRankingTile>(find.byType(AirlineRankingTile).at(3))
          .fillReveal;
      expect(first, greaterThan(fourth));
      expect(first, greaterThan(0));
      expect(first, lessThan(1));
      expect(
        tester
            .widget<AirlineRankingCount>(find.byType(AirlineRankingCount).first)
            .reveal,
        first,
      );
      expect(
        tester.getSize(find.byType(AirlineRankingTile).first).width,
        width,
      );
      await tester.pumpAndSettle();
      expect(builds, 1);
      expect(find.text('5 次'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('airline-count-outgoing')),
        findsNothing,
      );
      await tester.tap(find.text('Airline 1'));
      await tester.pumpAndSettle();
      expect(find.text('Selected flights'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AirlineRankingTile>(find.byType(AirlineRankingTile).first)
            .fillReveal,
        1,
      );
      await tester.tap(find.byType(BackButton));
      await tester.pump();
      expect(sourceOpacity(tester), 0);
      await tester.pump(const Duration(milliseconds: 380));
      expect(sourceOpacity(tester), 1);
      await tester.pumpAndSettle();
      expect(find.byType(AirlineRankingPage), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('expansion can be dismissed while opening', (tester) async {
    await tester.pumpWidget(expansionHost());
    await tester.tap(find.byType(AirlineRankingOverviewCard));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    Navigator.of(
      tester.element(find.byType(AirlineRankingPage, skipOffstage: false)),
    ).pop();
    await tester.pumpAndSettle();
    expect(sourceOpacity(tester), 1);
    expect(find.byType(AirlineRankingPage), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('both reduced-motion flags skip expansion and fill loading', (
    tester,
  ) async {
    for (final accessible in [false, true]) {
      await tester.pumpWidget(
        expansionHost(reduced: !accessible, accessible: accessible),
      );
      await tester.tap(find.byType(AirlineRankingOverviewCard));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ranking-flip-surface')), findsNothing);
      expect(
        find.byKey(const ValueKey('airline-ranking-fill-0')),
        findsNothing,
      );
      expect(sourceOpacity(tester), 1);
      expect(find.byType(Hero), findsNothing);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('iOS retains native route and visible source for edge back', (
    tester,
  ) async {
    await tester.pumpWidget(expansionHost(platform: TargetPlatform.iOS));
    await tester.tap(find.byType(AirlineRankingOverviewCard));
    await tester.pumpAndSettle();
    expect(
      ModalRoute.of(tester.element(find.byType(AirlineRankingPage))),
      isA<CupertinoPageRoute<void>>(),
    );
    expect(sourceOpacity(tester), 1);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('expansion preserves full layout in both themes at large text', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    for (final width in [320.0, 900.0]) {
      tester.view.physicalSize = Size(width, 900);
      for (final light in [true, false]) {
        await tester.pumpWidget(expansionHost(textScale: 2, isLight: light));
        await tester.tap(find.byType(AirlineRankingOverviewCard));
        await tester.pumpAndSettle();
        expect(find.byType(AirlineRankingPage), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets('overview has no preview rows and opens a full page with back', (
    tester,
  ) async {
    final items = entries();
    AirlineRankingEntry? selected;
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => Scaffold(
            body: AirlineRankingOverviewCard(
              airlineCount: items.length,
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (context) => AirlineRankingPage(
                    items: items,
                    onAirlineSelected: (entry) {
                      selected = entry;
                      Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                          builder: (_) => Scaffold(
                            appBar: AppBar(title: Text(entry.name)),
                            body: const Text('Selected flights'),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('已搭乘 5 家航司'), findsOneWidget);
    expect(find.byType(AirlineRankingTile), findsNothing);
    expect(find.text('查看全部'), findsNothing);
    await tester.tap(find.byType(AirlineRankingOverviewCard));
    await tester.pumpAndSettle();
    expect(find.byType(AirlineRankingPage), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(BackButton), findsOneWidget);
    expect(find.text('Airline 1'), findsOneWidget);
    expect(find.text('累计 · 已完成航班'), findsNothing);
    await tester.scrollUntilVisible(find.text('Airline 5'), 150);
    expect(find.text('Airline 5'), findsOneWidget);
    await tester.tap(find.text('Airline 5'));
    await tester.pumpAndSettle();
    expect(selected, same(items.last));
    expect(find.text('Selected flights'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(AirlineRankingPage), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(AirlineRankingOverviewCard), findsOneWidget);
    expect(find.byType(AirlineRankingTile), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'ranking page supports narrow/wide and both themes at large text',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.devicePixelRatio = 1;
      for (final width in [320.0, 900.0]) {
        tester.view.physicalSize = Size(width, 900);
        for (final isLight in [true, false]) {
          await tester.pumpWidget(
            host(
              AirlineRankingPage(items: entries(), onAirlineSelected: (_) {}),
              isLight: isLight,
              locale: const Locale('en'),
              textScale: 2,
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('Airline Ranking'), findsOneWidget);
          expect(find.text('All time · Completed flights'), findsNothing);
          expect(find.text('5 flights'), findsOneWidget);
          final rowWidth = tester
              .getSize(find.byType(AirlineRankingTile).first)
              .width;
          expect(rowWidth, lessThanOrEqualTo(660));
          expect(tester.takeException(), isNull);
        }
      }
    },
  );

  testWidgets('empty ranking page has a stable empty state', (tester) async {
    await tester.pumpWidget(
      host(AirlineRankingPage(items: const [], onAirlineSelected: (_) {})),
    );
    expect(
      find.text(const AppStrings(Locale('zh')).t('rankingEmpty')),
      findsOneWidget,
    );
    expect(find.byType(AirlineRankingTile), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('overview remains readable and announces its whole-card action', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 900);
    var taps = 0;
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        host(
          Scaffold(
            body: AirlineRankingOverviewCard(
              airlineCount: 1,
              onTap: () => taps++,
            ),
          ),
          locale: const Locale('en'),
          textScale: 2,
        ),
      );
      expect(find.text('Flown with 1 airline'), findsOneWidget);
      expect(
        tester.getSemantics(find.byType(AirlineRankingOverviewCard)),
        matchesSemantics(
          label: 'Airline Ranking, Flown with 1 airline',
          isButton: true,
          hasTapAction: true,
        ),
      );
      await tester.tap(find.byIcon(Icons.flight_takeoff_rounded));
      expect(taps, 1);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });
}
