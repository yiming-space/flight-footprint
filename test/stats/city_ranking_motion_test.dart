import 'package:flight_footprint/core/localization/app_strings.dart';
import 'package:flight_footprint/features/stats/airline_ranking_count.dart';
import 'package:flight_footprint/features/stats/airline_ranking_row.dart';
import 'package:flight_footprint/features/stats/city_ranking.dart';
import 'package:flight_footprint/features/stats/city_ranking_page.dart';
import 'package:flight_footprint/features/stats/ranking_expansion_card.dart';
import 'package:flight_footprint/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

final _items = [
  for (final item in [
    ('Shanghai', '上海', 100),
    ('Beijing', '北京', 10),
    ('Johannesburg', '约翰内斯堡', 3),
  ])
    CityRankingEntry(
      key: item.$1,
      name: item.$2,
      countryName: '国家/地区',
      countryCode: 'CN',
      count: item.$3,
      flights: const [],
    ),
];

Widget _host({
  bool reduced = false,
  bool accessible = false,
  double scale = 1,
  bool light = false,
  TextDirection direction = TextDirection.ltr,
}) => MaterialApp(
  theme: (light ? AppTheme.light() : AppTheme.dark()).copyWith(
    platform: TargetPlatform.android,
  ),
  locale: const Locale('zh'),
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
      textScaler: TextScaler.linear(scale),
    ),
    child: Directionality(textDirection: direction, child: child!),
  ),
  home: Scaffold(
    body: Padding(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: RankingExpansionCard(
          title: '城市统计',
          subtitle: '3 个城市',
          icon: Icons.location_city_rounded,
          keyPrefix: 'city-ranking',
          pageBuilder: (context) => CityRankingPage(
            items: _items,
            animateEntrance: true,
            onCitySelected: (entry) => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => Scaffold(
                  appBar: AppBar(title: Text(entry.name)),
                  body: const Text('Selected records'),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  ),
);

Finder _row(String key) => find.byKey(ValueKey(key));
Finder _number(String key) => find.byKey(ValueKey('city-ranking-count-$key'));

void main() {
  testWidgets(
    'city fill and moving count wait for expansion, then never replay on detail return',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_host());
      await tester.tap(find.byType(RankingExpansionCard));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 180));
      expect(tester.widget<AirlineRankingRow>(_row('Shanghai')).fillReveal, 0);
      expect(tester.widget<AirlineRankingCount>(_number('Shanghai')).reveal, 0);
      final title = find.text('城市排行');
      expect(
        find.ancestor(of: title, matching: find.byType(FadeTransition)),
        findsNothing,
      );
      await tester.pump(const Duration(milliseconds: 190));
      // Compare within the full page, not its moving expansion-origin frame.
      final initial = tester.getRect(_number('Shanghai'));
      final name = tester.getRect(find.text('上海'));
      await tester.pump(const Duration(milliseconds: 120));
      final progress = tester
          .widget<AirlineRankingRow>(_row('Shanghai'))
          .fillReveal;
      expect(progress, greaterThan(0));
      expect(progress, lessThan(1));
      expect(
        tester.widget<AirlineRankingCount>(_number('Shanghai')).reveal,
        progress,
      );
      expect(
        tester.getRect(_number('Shanghai')).left,
        greaterThan(initial.left),
      );
      expect(tester.getRect(find.text('上海')), name);
      await tester.pumpAndSettle();
      final finalRow = tester.widget<AirlineRankingRow>(_row('Shanghai'));
      expect(finalRow.count, 100);
      expect(finalRow.fillReveal, 1);
      final fill = tester.getRect(
        find.descendant(
          of: _row('Shanghai'),
          matching: find.byType(FractionallySizedBox),
        ),
      );
      expect(
        tester.getRect(_number('Shanghai')).right,
        closeTo(fill.right - 12, .01),
      );
      await tester.tap(_row('Shanghai'));
      await tester.pumpAndSettle();
      expect(find.text('Selected records'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(tester.widget<AirlineRankingRow>(_row('Shanghai')).fillReveal, 1);
      expect(find.text('100 次'), findsOneWidget);
      expect(tester.hasRunningAnimations, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'both reduced-motion flags show final city counts and ratios immediately',
    (tester) async {
      for (final accessible in [false, true]) {
        await tester.pumpWidget(
          _host(reduced: !accessible, accessible: accessible),
        );
        await tester.tap(find.byType(RankingExpansionCard));
        await tester.pumpAndSettle();
        expect(find.byType(AirlineRankingCount), findsNothing);
        expect(
          tester.widget<AirlineRankingRow>(_row('Shanghai')).fillReveal,
          1,
        );
        expect(find.text('100 次'), findsOneWidget);
        expect(tester.hasRunningAnimations, isFalse);
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox.shrink());
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'large city labels retain space while counts follow in either direction and theme',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 1000);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      for (final light in [false, true]) {
        for (final direction in TextDirection.values) {
          await tester.pumpWidget(
            _host(scale: 2, light: light, direction: direction),
          );
          await tester.tap(find.byType(RankingExpansionCard));
          await tester.pumpAndSettle();
          for (final key in ['Shanghai', 'Johannesburg']) {
            final row = _row(key);
            final number = tester.getRect(_number(key));
            final name = tester.getRect(
              find.descendant(
                of: row,
                matching: find.text(key == 'Shanghai' ? '上海' : '约翰内斯堡'),
              ),
            );
            if (direction == TextDirection.ltr) {
              expect(number.left, greaterThanOrEqualTo(name.right + 12 - .01));
            } else {
              expect(number.right, lessThanOrEqualTo(name.left - 12 + .01));
            }
          }
          expect(tester.takeException(), isNull);
          await tester.tap(find.byType(BackButton));
          await tester.pumpAndSettle();
          await tester.pumpWidget(const SizedBox.shrink());
        }
      }
    },
  );
}
