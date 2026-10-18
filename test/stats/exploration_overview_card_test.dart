import 'dart:ui' show SemanticsAction;

import 'package:flight_footprint/core/localization/app_strings.dart';
import 'package:flight_footprint/features/stats/exploration_overview_card.dart';
import 'package:flight_footprint/features/stats/ranking_expansion_card.dart';
import 'package:flight_footprint/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host({
  bool light = false,
  double scale = 1,
  Locale locale = const Locale('zh'),
  int world = 22,
  int china = 5,
}) => MaterialApp(
  theme: (light ? AppTheme.light() : AppTheme.dark()).copyWith(
    platform: TargetPlatform.android,
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
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: Scaffold(
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: ExplorationOverviewCard(
        worldCount: world,
        chinaCount: china,
        pageBuilder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Destination')),
          body: const Text('Real exploration detail'),
        ),
      ),
    ),
  ),
);

void _surface(WidgetTester tester, double width) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 1100);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Finder _key(String key) => find.byKey(ValueKey(key));

double _baseline(WidgetTester tester, Finder finder) {
  final box = tester.element(finder).findRenderObject()! as RenderBox;
  return tester.getTopLeft(finder).dy +
      box.getDryBaseline(box.constraints, TextBaseline.alphabetic)!;
}

void main() {
  testWidgets(
    'balanced hierarchy retains exact counts, colors and pill fills',
    (tester) async {
      _surface(tester, 390);
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();
      expect(find.text('探索详情'), findsOneWidget);
      expect(find.text('查看探索详情'), findsNothing);
      expect(find.text('11%', findRichText: true), findsOneWidget);
      expect(find.text('15%', findRichText: true), findsOneWidget);
      expect(
        tester.getSize(_key('world-exploration-source')).height,
        lessThan(250),
      );
      expect(_key('exploration-inline-details'), findsNothing);
      expect(
        tester.getTopLeft(_key('exploration-details-footer')).dy -
            tester.getBottomLeft(_key('exploration-china-count')).dy,
        closeTo(AppSpacing.xs, .01),
      );
      for (final section in ['world', 'china']) {
        final prefix = 'exploration-$section';
        final percent = tester.widget<Text>(_key('$prefix-percent'));
        expect(percent.style!.fontSize, 30);
        expect(
          ((percent.textSpan! as TextSpan).children!.single as TextSpan)
              .style!
              .fontSize,
          20,
        );
        expect(
          _baseline(tester, _key('$prefix-title')),
          closeTo(_baseline(tester, _key('$prefix-percent')), .01),
        );
        final count = tester.widget<Text>(_key('$prefix-count'));
        final spans = (count.textSpan! as TextSpan).children!;
        expect(
          (spans.first as TextSpan).style!.color,
          AppThemeColors.dark.textPrimary,
        );
        expect((spans.first as TextSpan).style!.fontWeight, FontWeight.w600);
        expect(count.style!.color, AppThemeColors.dark.textSecondary);
        final progress = tester.widget<LinearProgressIndicator>(
          _key('$prefix-progress'),
        );
        expect(progress.borderRadius, AppRadii.pill);
        expect(tester.getSize(_key('$prefix-progress')).height, 8);
        expect(progress.value, section == 'world' ? 22 / 195 : 5 / 34);
        expect(
          progress.valueColor!.value,
          section == 'world'
              ? AppThemeColors.dark.lime
              : AppThemeColors.dark.purple,
        );
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('the single button reads both scopes, ratios and percentages', (
    tester,
  ) async {
    _surface(tester, 390);
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();
      final data = tester
          .getSemantics(find.byType(RankingExpansionCard))
          .getSemanticsData();
      for (final text in [
        '探索世界',
        '11%',
        '22 / 195',
        '探索中国',
        '15%',
        '5 / 34',
        '探索详情',
      ]) {
        expect(data.label, contains(text));
      }
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      expect(find.bySemanticsLabel(data.label), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('small and complete progress preserve the existing formatting', (
    tester,
  ) async {
    _surface(tester, 390);
    for (final counts in [(0, 0), (1, 1), (195, 34)]) {
      await tester.pumpWidget(_host(world: counts.$1, china: counts.$2));
      await tester.pumpAndSettle();
      final worldText = tester.widget<Text>(_key('exploration-world-percent'));
      expect(
        worldText.textSpan!.toPlainText(),
        counts.$1 == 0
            ? '0.0%'
            : counts.$1 == 1
            ? '0.5%'
            : '100%',
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'narrow/wide, large type and both locales/themes do not overflow',
    (tester) async {
      _surface(tester, 320);
      for (final width in [320.0, 390.0, 900.0]) {
        tester.view.physicalSize = Size(width, 1100);
        for (final scale in [1.0, 2.0, 3.0]) {
          for (final light in [false, true]) {
            for (final locale in [const Locale('zh'), const Locale('en')]) {
              await tester.pumpWidget(
                _host(light: light, locale: locale, scale: scale),
              );
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
              if (width == 320 && scale >= 2) {
                expect(
                  _key('exploration-world-stacked-header'),
                  findsOneWidget,
                );
              }
            }
          }
        }
      }
    },
  );
}
