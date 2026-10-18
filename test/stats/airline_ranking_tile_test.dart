import 'package:flight_footprint/features/stats/airline_ranking_row.dart';
import 'package:flight_footprint/features/stats/airline_ranking_tile.dart';
import 'package:flight_footprint/ui/theme/app_theme.dart';
import 'package:flight_footprint/ui/widgets/airline_logo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host({
    String code = 'ZZ',
    VoidCallback? onTap,
    String name = 'Test Airline',
    int count = 5,
    int maxCount = 10,
    double width = 340,
    double textScale = 1,
    bool isLight = true,
    TextDirection direction = TextDirection.ltr,
    double fillReveal = 1,
    bool animated = false,
  }) => MaterialApp(
    theme: isLight ? AppTheme.light() : AppTheme.dark(),
    home: Scaffold(
      body: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Directionality(
          textDirection: direction,
          child: Center(
            child: SizedBox(
              width: width,
              child: AirlineRankingTile(
                name: name,
                iataCode: code,
                count: count,
                maxCount: maxCount,
                rank: 1,
                countLabel: '$count 次',
                fillReveal: fillReveal,
                animatedCountLabel: animated ? (value) => '$value 次' : null,
                onTap: onTap ?? () {},
              ),
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('resolved logo color updates only its own ranking row', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(host(onTap: () => taps++));
    expect(
      tester
          .widget<AirlineRankingRow>(find.byType(AirlineRankingRow))
          .accentColor,
      isNull,
    );
    tester.widget<AirlineLogo>(find.byType(AirlineLogo)).onColorResolved!(
      Colors.red,
    );
    await tester.pump();
    expect(
      tester
          .widget<AirlineRankingRow>(find.byType(AirlineRankingRow))
          .accentColor,
      Colors.red,
    );
    await tester.tap(find.text('5 次'));
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('new airline identity clears the previous logo tint', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    tester.widget<AirlineLogo>(find.byType(AirlineLogo)).onColorResolved!(
      Colors.red,
    );
    await tester.pump();
    await tester.pumpWidget(host(code: 'YY'));
    expect(
      tester
          .widget<AirlineRankingRow>(find.byType(AirlineRankingRow))
          .accentColor,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'one and two flights retain ordered capsules and contained labels on narrow screens',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      const longName = 'A Very Long International Airline Name';
      for (final light in [true, false]) {
        for (final direction in TextDirection.values) {
          for (final scale in [1.0, 2.0]) {
            final widths = <int, double>{};
            for (final sample in [
              (1, longName),
              (2, 'ANA'),
              (1, 'ANA'),
              (2, longName),
              (10, longName),
            ]) {
              await tester.pumpWidget(
                host(
                  name: sample.$2,
                  count: sample.$1,
                  width: 280,
                  textScale: scale,
                  direction: direction,
                  isLight: light,
                ),
              );
              final fill = tester.getRect(find.byType(FractionallySizedBox));
              final oldWidth = widths[sample.$1];
              if (oldWidth != null) {
                expect(fill.width, closeTo(oldWidth, .01));
              }
              widths[sample.$1] = fill.width;
              for (final finder in [
                find.text(sample.$2),
                find.text('${sample.$1} 次'),
                find.byType(AirlineLogo),
              ]) {
                final bounds = tester.getRect(finder);
                expect(bounds.left, greaterThanOrEqualTo(fill.left - .01));
                expect(bounds.right, lessThanOrEqualTo(fill.right + .01));
                expect(bounds.top, greaterThanOrEqualTo(fill.top - .01));
                expect(bounds.bottom, lessThanOrEqualTo(fill.bottom + .01));
              }
              final name = tester.widget<Text>(find.text(sample.$2));
              expect(name.overflow, TextOverflow.ellipsis);
              expect(tester.takeException(), isNull);
            }
            expect(widths[1]!, lessThan(widths[2]!));
            expect(widths[2]!, lessThan(widths[10]!));
            expect(widths[2]!, lessThan(280));
            expect(widths[10]!, closeTo(280, .01));
          }
        }
      }
    },
  );

  testWidgets('small-count entrance keeps a moving count and a stable name', (
    tester,
  ) async {
    for (final count in [1, 2]) {
      for (final direction in TextDirection.values) {
        final positions = <double>[];
        Rect? originalName;
        for (final reveal in [0.0, .5, .75, 1.0]) {
          await tester.pumpWidget(
            host(
              name: 'A Very Long Airline Name',
              count: count,
              width: 280,
              textScale: 2,
              direction: direction,
              fillReveal: reveal,
              animated: true,
            ),
          );
          final name = tester.getRect(find.text('A Very Long Airline Name'));
          originalName ??= name;
          expect(name, originalName);
          final number = tester.getRect(
            find.byKey(const ValueKey('airline-ranking-count-1')),
          );
          positions.add(number.left);
          if (direction == TextDirection.ltr) {
            expect(number.left, greaterThanOrEqualTo(name.right + 12 - .01));
          } else {
            expect(number.right, lessThanOrEqualTo(name.left - 12 + .01));
          }
          if (reveal == 1) {
            final fill = tester.getRect(find.byType(FractionallySizedBox));
            expect(
              direction == TextDirection.ltr ? number.right : number.left,
              closeTo(
                direction == TextDirection.ltr
                    ? fill.right - 12
                    : fill.left + 12,
                .01,
              ),
            );
          }
          expect(tester.takeException(), isNull);
        }
        expect((positions.last - positions.first).abs(), greaterThan(1));
        for (var index = 1; index < positions.length; index++) {
          if (direction == TextDirection.ltr) {
            expect(
              positions[index],
              greaterThanOrEqualTo(positions[index - 1]),
            );
          } else {
            expect(positions[index], lessThanOrEqualTo(positions[index - 1]));
          }
        }
      }
    }
  });
}
