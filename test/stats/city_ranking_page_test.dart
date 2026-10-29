import 'package:flight_footprint/core/localization/app_strings.dart';
import 'package:flight_footprint/domain/flight.dart';
import 'package:flight_footprint/features/stats/airline_ranking_row.dart';
import 'package:flight_footprint/features/stats/city_ranking.dart';
import 'package:flight_footprint/features/stats/city_ranking_page.dart';
import 'package:flight_footprint/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  CityRankingEntry city(String key, String name, String country, int count) =>
      CityRankingEntry(
        key: key,
        name: name,
        countryName: country,
        countryCode: 'CN',
        count: count,
        flights: const <Flight>[],
      );

  Widget host(
    Widget child, {
    double width = 360,
    double textScale = 1,
    bool isLight = true,
    TextDirection direction = TextDirection.ltr,
  }) => MaterialApp(
    theme: isLight ? AppTheme.light() : AppTheme.dark(),
    locale: const Locale('zh'),
    supportedLocales: AppStrings.supportedLocales,
    localizationsDelegates: const [
      AppStringsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: Directionality(
        textDirection: direction,
        child: Center(
          widthFactor: 1,
          child: SizedBox(width: width, child: child),
        ),
      ),
    ),
  );

  void expectRowTextInsideFill(WidgetTester tester, Finder row) {
    final fill = tester.getRect(
      find.descendant(of: row, matching: find.byType(FractionallySizedBox)),
    );
    for (final text
        in find.descendant(of: row, matching: find.byType(Text)).evaluate()) {
      final bounds = tester.getRect(find.byWidget(text.widget));
      expect(bounds.left, greaterThanOrEqualTo(fill.left - .01));
      expect(bounds.right, lessThanOrEqualTo(fill.right + .01));
      expect(bounds.top, greaterThanOrEqualTo(fill.top - .01));
      expect(bounds.bottom, lessThanOrEqualTo(fill.bottom + .01));
    }
  }

  testWidgets('equal city counts keep equal widths despite different names', (
    tester,
  ) async {
    for (final scale in [1.0, 2.0]) {
      await tester.pumpWidget(
        host(
          CityRankingPage(
            items: [
              city('CN:max', '上海', '中国', 100),
              city('CN:more', '京', '中国', 8),
              city('CN:short', '北京', '中国', 3),
              city('ZA:long', '约翰内斯堡', '南非', 3),
            ],
            onCitySelected: (_) {},
          ),
          textScale: scale,
        ),
      );
      await tester.pumpAndSettle();
      double width(String key) => tester
          .getSize(
            find.descendant(
              of: find.byKey(ValueKey(key)),
              matching: find.byType(FractionallySizedBox),
            ),
          )
          .width;
      expect(width('CN:short'), closeTo(width('ZA:long'), .01));
      expect(width('ZA:long'), lessThan(width('CN:more')));
      expect(width('CN:more'), lessThan(width('CN:max')));
      for (final key in ['CN:max', 'CN:more', 'CN:short', 'ZA:long']) {
        expectRowTextInsideFill(tester, find.byKey(ValueKey(key)));
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'rank 34 Johannesburg keeps its city, country and count inside fill',
    (tester) async {
      final items = [
        for (var index = 0; index < 33; index++)
          city('CN:city-$index', '城市 $index', '中国', 100 - index),
        city('ZA:johannesburg', '约翰内斯堡', '南非', 3),
      ];
      await tester.pumpWidget(
        host(CityRankingPage(items: items, onCitySelected: (_) {})),
      );
      await tester.scrollUntilVisible(
        find.text('约翰内斯堡'),
        400,
        scrollable: find.byType(Scrollable),
      );
      final row = find.byKey(const ValueKey('ZA:johannesburg'));
      expectRowTextInsideFill(tester, row);
      expect(
        find.descendant(of: row, matching: find.text('34')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.text('3 次')),
        findsOneWidget,
      );
      expect(
        tester.widget<AirlineRankingRow>(row).containContentInFill,
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'small-count cities stay contained at 2x in either direction and theme',
    (tester) async {
      for (final isLight in [true, false]) {
        for (final direction in TextDirection.values) {
          await tester.pumpWidget(
            host(
              CityRankingPage(
                items: [
                  city('CN:beijing', '北京', '中国', 100),
                  city('ZA:johannesburg', '约翰内斯堡', '南非', 3),
                ],
                onCitySelected: (_) {},
              ),
              width: 280,
              textScale: 2,
              isLight: isLight,
              direction: direction,
            ),
          );
          for (final key in ['CN:beijing', 'ZA:johannesburg']) {
            expectRowTextInsideFill(tester, find.byKey(ValueKey(key)));
          }
          expect(tester.takeException(), isNull);
        }
      }
    },
  );

  testWidgets('shows scope, calls selection, and uses native back navigation', (
    tester,
  ) async {
    final selected = <CityRankingEntry>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('zh'),
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: const [
          AppStringsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => CityRankingPage(
                    items: [city('CN:shanghai', '上海', '中国', 4)],
                    onCitySelected: selected.add,
                  ),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('到访 1 座城市'), findsOneWidget);
    expect(find.text('次数含完成航班的起飞与抵达端点，以及已保存足迹。'), findsOneWidget);
    expect(find.text('4 次'), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    await tester.tap(find.text('上海'));
    expect(selected.single.key, 'CN:shanghai');
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('count and fill update from current entries', (tester) async {
    final selected = <CityRankingEntry>[];
    Widget page(int count) => host(
      CityRankingPage(
        items: [city('CN:beijing', '北京', '中国', count)],
        onCitySelected: selected.add,
      ),
    );

    await tester.pumpWidget(page(2));
    expect(find.text('2 次'), findsOneWidget);
    expect(
      tester
          .widget<FractionallySizedBox>(find.byType(FractionallySizedBox))
          .widthFactor,
      1,
    );
    await tester.pumpWidget(
      host(
        CityRankingPage(
          items: [city('CN:beijing', '北京', '中国', 7)],
          onCitySelected: selected.add,
        ),
      ),
    );
    expect(find.text('7 次'), findsOneWidget);
    expect(selected, isEmpty);
  });

  testWidgets('empty list is safe and still explains the metric', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(CityRankingPage(items: const [], onCitySelected: (_) {})),
    );
    expect(find.text('到访 0 座城市'), findsOneWidget);
    expect(find.text('暂无数据'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long city and country fit narrow large text and wide themes', (
    tester,
  ) async {
    const longName = 'Very Long International City Name With Multiple Words';
    const longCountry = 'A Long Country Or Region Name That Must Ellipsize';
    final entry = city('US:long-city', longName, longCountry, 125);

    for (final isLight in [true, false]) {
      await tester.pumpWidget(
        host(
          CityRankingPage(items: [entry], onCitySelected: (_) {}),
          width: 320,
          textScale: 1.8,
          isLight: isLight,
        ),
      );
      final bounds = tester.getRect(find.byType(AirlineRankingRow));
      final countBounds = tester.getRect(find.text('125 次'));
      final subtitleBounds = tester.getRect(find.text(longCountry));
      expect(countBounds.right, lessThanOrEqualTo(bounds.right));
      expect(subtitleBounds.left, greaterThanOrEqualTo(bounds.left));
      expect(subtitleBounds.right, lessThan(countBounds.left));
      expectRowTextInsideFill(tester, find.byType(AirlineRankingRow));
      expect(tester.takeException(), isNull);
    }

    for (final isLight in [true, false]) {
      await tester.pumpWidget(
        host(
          CityRankingPage(items: [entry], onCitySelected: (_) {}),
          width: 900,
          isLight: isLight,
        ),
      );
      expect(
        tester.getRect(find.byType(AirlineRankingRow)).width,
        lessThanOrEqualTo(700),
      );
      expect(tester.takeException(), isNull);
    }
  });
}
