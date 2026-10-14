import 'package:flight_footprint/core/localization/app_strings.dart';
import 'package:flight_footprint/features/stats/country_stats_page.dart';
import 'package:flight_footprint/features/stats/ranking_overview_card.dart';
import 'package:flight_footprint/ui/theme/app_theme.dart';
import 'package:flight_footprint/ui/widgets/country_flag.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const items = [
  ('China', 101),
  ('United States', 22),
  ('United Kingdom', 13),
  ('France', 8),
  ('Japan', 7),
  ('Canada', 5),
  ('Unknown region', 3),
];
const codes = {
  'China': 'cn',
  'United States': 'us',
  'United Kingdom': 'gb',
  'France': 'fr',
  'Japan': 'jp',
  'Canada': 'ca',
};

Widget host(
  Widget home, {
  bool isLight = false,
  double textScale = 1,
  GlobalKey<NavigatorState>? navigatorKey,
}) => MaterialApp(
  navigatorKey: navigatorKey,
  theme: isLight ? AppTheme.light() : AppTheme.dark(),
  locale: const Locale('en'),
  supportedLocales: AppStrings.supportedLocales,
  localizationsDelegates: const [
    AppStringsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context)
        .copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: home,
);

CountryStatsPage page({ValueChanged<String>? onCountrySelected}) =>
    CountryStatsPage(
      items: items,
      countryCodes: codes,
      onCountrySelected: onCountrySelected ?? (_) {},
    );

void main() {
  testWidgets('countries form five circular flags per row with count badges', (
    tester,
  ) async {
    await tester.pumpWidget(host(page()));
    await tester.pumpAndSettle();
    final grid = tester.widget<SliverGrid>(find.byType(SliverGrid));
    expect(
      (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
          .crossAxisCount,
      5,
    );
    final tiles = find.byType(CountryStatsTile);
    final first = tester.getRect(tiles.at(0));
    for (var index = 1; index < 5; index++) {
      expect(tester.getRect(tiles.at(index)).top, first.top);
    }
    expect(tester.getRect(tiles.at(5)).top, greaterThan(first.top));
    for (final flag in tester.widgetList<CountryFlag>(
      find.byType(CountryFlag),
    )) {
      expect(flag.showBorder, isFalse);
    }
    expect(find.text('101'), findsOneWidget);
    expect(find.text('All time · Takeoffs and landings'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'country tile exposes full name/count and selects related flights',
    (tester) async {
      String? selected;
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          host(page(onCountrySelected: (name) => selected = name)),
        );
        await tester.pumpAndSettle();
        expect(
          tester.getSemantics(find.byKey(const ValueKey('China'))),
          matchesSemantics(
            label: 'China, 101 takeoffs and landings',
            isButton: true,
            hasTapAction: true,
          ),
        );
        await tester.tap(find.text('101'));
        expect(selected, 'China');
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'five columns work in both themes and large text on narrow/wide screens',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.devicePixelRatio = 1;
      for (final width in [320.0, 900.0]) {
        tester.view.physicalSize = Size(width, 1000);
        for (final isLight in [true, false]) {
          await tester.pumpWidget(host(page(), isLight: isLight, textScale: 2));
          await tester.pumpAndSettle();
          final tiles = find.byType(CountryStatsTile);
          final first = tester.getRect(tiles.first);
          expect(first.width, greaterThanOrEqualTo(48));
          expect(first.height, greaterThanOrEqualTo(48));
          expect(tester.getRect(tiles.at(4)).top, first.top);
          expect(tester.getRect(tiles.at(5)).top, greaterThan(first.top));
          final badge = tester.widget<Container>(
            find
                .ancestor(
                  of: find.text('101'),
                  matching: find.byType(Container),
                )
                .first,
          );
          expect(badge.constraints!.maxWidth, lessThanOrEqualTo(first.width));
          expect(tester.takeException(), isNull);
        }
      }
    },
  );

  testWidgets('overview opens a separate country page and returns normally', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      host(
        Scaffold(
          body: RankingOverviewCard(
            title: 'Country statistics',
            subtitle: '7 countries / regions recorded',
            icon: Icons.public_rounded,
            onTap: () => navigator.currentState!.push<void>(
              MaterialPageRoute<void>(builder: (_) => page()),
            ),
          ),
        ),
        navigatorKey: navigator,
      ),
    );
    expect(find.byType(CountryStatsTile), findsNothing);
    await tester.tap(find.byType(RankingOverviewCard));
    await tester.pumpAndSettle();
    expect(find.byType(CountryStatsPage), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(RankingOverviewCard), findsOneWidget);
    expect(find.byType(CountryStatsPage), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty data and missing flags have safe fallbacks', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        CountryStatsPage(
          items: const [],
          countryCodes: const {},
          onCountrySelected: (_) {},
        ),
      ),
    );
    expect(
      find.text(const AppStrings(Locale('en')).t('rankingEmpty')),
      findsOneWidget,
    );
    expect(find.byType(CountryStatsTile), findsNothing);
    await tester.pumpWidget(
      host(
        CountryStatsPage(
          items: const [('Unknown region', 99999)],
          countryCodes: const {},
          onCountrySelected: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.public_rounded), findsOneWidget);
    expect(find.text('99999'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
