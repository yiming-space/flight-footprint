import 'package:flight_footprint/core/localization/app_strings.dart';
import 'package:flight_footprint/features/stats/exploration_memory_carousel.dart';
import 'package:flight_footprint/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Finder get _deck => find.byKey(const ValueKey('exploration-memory-deck'));
Finder get _semantics =>
    find.byKey(const ValueKey('exploration-memory-deck-semantics'));

Color _dotColor(WidgetTester tester, int index) =>
    (tester
                .widget<AnimatedContainer>(
                  find.byKey(ValueKey('memory-carousel-dot-$index')),
                )
                .decoration!
            as BoxDecoration)
        .color!;

Widget _host({double scale = 1}) => MaterialApp(
  theme: AppTheme.light(),
  locale: const Locale('en'),
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
      child: Column(
        children: [
          ExplorationMemoryCarousel(
            cards: [
              for (var i = 0; i < 4; i++)
                SizedBox(
                  height: 180 + i * 40,
                  child: Center(child: Text('Memory ${i + 1}')),
                ),
            ],
            labels: [for (var i = 0; i < 4; i++) 'Memory ${i + 1}'],
          ),
          const SizedBox(height: 1000, child: Text('Below the deck')),
        ],
      ),
    ),
  ),
);

void _surface(WidgetTester tester, {double width = 390, double height = 900}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

void main() {
  testWidgets('uses ordinary finite horizontal pages and preserves semantics', (
    tester,
  ) async {
    _surface(tester);
    await tester.pumpWidget(_host());
    expect(find.byType(PageView), findsOneWidget);
    for (var i = 0; i < 4; i++) {
      expect(find.byKey(ValueKey('memory-carousel-dot-$i')), findsOneWidget);
    }
    expect(
      tester.getSize(find.byKey(const ValueKey('memory-page-card-0'))).width,
      tester.getSize(_deck).width - 12,
    );
    final active = tester.element(_deck).appColors.lime;
    final muted = tester.element(_deck).appColors.textTertiary;
    expect(_dotColor(tester, 0), active);
    expect(_dotColor(tester, 1), muted);
    expect(tester.widget<Semantics>(_semantics).properties.value, '1 / 4');
    expect(
      tester.widget<Semantics>(_semantics).properties.decreasedValue,
      isNull,
    );
    await tester.drag(_deck, const Offset(-220, 0));
    await tester.pumpAndSettle();
    expect(find.text('Memory 2'), findsOneWidget);
    expect(_dotColor(tester, 0), muted);
    expect(_dotColor(tester, 1), active);
    expect(tester.widget<Semantics>(_semantics).properties.value, '2 / 4');
    await tester.drag(_deck, const Offset(0, -80));
    await tester.pumpAndSettle();
    expect(find.text('Memory 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
    for (var i = 0; i < 2; i++) {
      await tester.drag(_deck, const Offset(-220, 0));
      await tester.pumpAndSettle();
    }
    final endSemantics = tester.widget<Semantics>(_semantics).properties;
    expect(endSemantics.value, '4 / 4');
    expect(endSemantics.increasedValue, isNull);
  });

  testWidgets(
    'scales page height and lets large text scroll without overflow',
    (tester) async {
      _surface(tester, width: 320);
      await tester.pumpWidget(_host(scale: 2));
      expect(tester.getSize(_deck).height, 600);
      await tester.drag(_deck, const Offset(-220, 0));
      await tester.pumpAndSettle();
      expect(find.text('Memory 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
