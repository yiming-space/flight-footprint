import 'package:flight_footprint/features/stats/airline_ranking_row.dart';
import 'package:flight_footprint/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(
    Widget child, {
    double width = 340,
    double textScale = 1,
    bool isLight = true,
    TextDirection direction = TextDirection.ltr,
  }) => MaterialApp(
    theme: isLight ? AppTheme.light() : AppTheme.dark(),
    home: Scaffold(
      body: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Directionality(
          textDirection: direction,
          child: Center(
            child: SizedBox(width: width, child: child),
          ),
        ),
      ),
    ),
  );

  AirlineRankingRow row({
    int count = 5,
    int maxCount = 10,
    int rank = 1,
    String name = '中国国际航空',
    String countLabel = '5 次',
    VoidCallback? onTap,
    Widget? leading,
    Color? accentColor,
    String? subtitle,
    bool containContentInFill = false,
    double fillReveal = 1,
    bool followFill = false,
  }) => AirlineRankingRow(
    name: name,
    count: count,
    maxCount: maxCount,
    rank: rank,
    countLabel: countLabel,
    onTap: onTap,
    leading: leading,
    accentColor: accentColor,
    subtitle: subtitle,
    containContentInFill: containContentInFill,
    fillReveal: fillReveal,
    followFill: followFill,
  );

  double fillRatio(WidgetTester tester) => tester
      .widget<FractionallySizedBox>(find.byType(FractionallySizedBox))
      .widthFactor!;

  testWidgets(
    'entrance grows only paint while preserving final count position',
    (tester) async {
      await tester.pumpWidget(host(row(fillReveal: 1)));
      final countRect = tester.getRect(find.text('5 次'));
      final nameRect = tester.getRect(find.text('中国国际航空'));
      for (final reveal in [0.0, .25, .75, 1.0]) {
        await tester.pumpWidget(host(row(fillReveal: reveal)));
        expect(fillRatio(tester), closeTo(.5 * reveal, 1e-10));
        expect(tester.getRect(find.text('5 次')), countRect);
        expect(tester.getRect(find.text('中国国际航空')), nameRect);
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'airline count follows the painted endpoint without crossing its name',
    (tester) async {
      for (final direction in TextDirection.values) {
        for (final scale in [1.0, 2.0]) {
          Rect? previous;
          Rect? nameBounds;
          for (final reveal in [0.0, .25, .5, .75, 1.0]) {
            await tester.pumpWidget(
              host(
                row(
                  name: 'KLM',
                  count: 10,
                  countLabel: '10 次',
                  followFill: true,
                  fillReveal: reveal,
                ),
                direction: direction,
                textScale: scale,
              ),
            );
            final number = tester.getRect(find.text('10 次'));
            final name = tester.getRect(find.text('KLM'));
            nameBounds ??= name;
            expect(name, nameBounds);
            if (direction == TextDirection.ltr) {
              expect(number.left, greaterThanOrEqualTo(name.right + 12 - .01));
              if (previous != null) {
                expect(number.left, greaterThanOrEqualTo(previous.left));
              }
            } else {
              expect(number.right, lessThanOrEqualTo(name.left - 12 + .01));
              if (previous != null) {
                expect(number.right, lessThanOrEqualTo(previous.right));
              }
            }
            if (reveal == .75) {
              final fill = tester.getRect(find.byType(FractionallySizedBox));
              if (direction == TextDirection.ltr) {
                expect(number.right, closeTo(fill.right - 12, .01));
              } else {
                expect(number.left, closeTo(fill.left + 12, .01));
              }
            }
            if (reveal == 1) {
              final transform = tester.widget<Transform>(
                find.byKey(const ValueKey('ranking-count-position')),
              );
              expect(transform.transform.storage[12], 0);
            }
            previous = number;
            expect(tester.takeException(), isNull);
          }
        }
      }
    },
  );

  void expectTextInsideFill(WidgetTester tester, String text) {
    final fill = tester.getRect(find.byType(FractionallySizedBox));
    final bounds = tester.getRect(find.text(text));
    expect(bounds.left, greaterThanOrEqualTo(fill.left - .01));
    expect(bounds.right, lessThanOrEqualTo(fill.right + .01));
    expect(bounds.top, greaterThanOrEqualTo(fill.top - .01));
    expect(bounds.bottom, lessThanOrEqualTo(fill.bottom + .01));
  }

  testWidgets('city widths depend on counts, never labels or rank widths', (
    tester,
  ) async {
    const samples = [
      ('北京', '中国', 3, 1, 36.0),
      ('A Very Long International City Name', 'South Africa', 3, 1000, 70.0),
      ('沪', '中国', 8, 2, 36.0),
      ('广州', '中国', 100, 3, 36.0),
    ];
    for (final width in [240.0, 340.0]) {
      for (final scale in [1.0, 2.0]) {
        for (final direction in TextDirection.values) {
          final widths = <double>[];
          for (final sample in samples) {
            await tester.pumpWidget(
              host(
                AirlineRankingRow(
                  name: sample.$1,
                  subtitle: sample.$2,
                  count: sample.$3,
                  maxCount: 100,
                  rank: sample.$4,
                  countLabel: '${sample.$3} 次',
                  leading: Text('${sample.$4}'),
                  leadingWidth: sample.$5,
                  containContentInFill: true,
                ),
                width: width,
                textScale: scale,
                direction: direction,
              ),
            );
            await tester.pumpAndSettle();
            widths.add(tester.getSize(find.byType(FractionallySizedBox)).width);
            for (final text in [
              sample.$1,
              sample.$2,
              '${sample.$4}',
              '${sample.$3} 次',
            ]) {
              expectTextInsideFill(tester, text);
            }
            expect(tester.takeException(), isNull);
          }
          expect(widths[0], closeTo(widths[1], .01));
          expect(widths[1], lessThan(widths[2]));
          expect(widths[2], lessThan(widths[3]));
          expect(widths[3], closeTo(width, .01));
        }
      }
    }
  });

  testWidgets(
    'contained city capsule reserves text space and still compares counts',
    (tester) async {
      final widths = <double>[];
      for (final count in [3, 30, 100]) {
        await tester.pumpWidget(
          host(
            row(
              name: '约翰内斯堡',
              subtitle: '南非',
              rank: 34,
              count: count,
              maxCount: 100,
              countLabel: '$count 次',
              leading: const Text('34'),
              containContentInFill: true,
            ),
          ),
        );
        widths.add(tester.getSize(find.byType(FractionallySizedBox)).width);
        for (final text in ['34', '约翰内斯堡', '南非', '$count 次']) {
          expectTextInsideFill(tester, text);
        }
        expect(tester.takeException(), isNull);
      }
      expect(widths[0], greaterThan(340 * .03));
      expect(widths[0], lessThan(widths[1]));
      expect(widths[1], lessThan(widths[2]));
      expect(widths[2], 340);
    },
  );

  testWidgets('contained labels fit both themes, directions, and large text', (
    tester,
  ) async {
    const longName = 'A Very Long International City Name With Multiple Words';
    const longCountry = 'A Long Country Or Region Name';
    for (final isLight in [true, false]) {
      for (final direction in TextDirection.values) {
        for (final scale in [1.0, 2.0]) {
          for (final name in ['北京', '约翰内斯堡', longName]) {
            final semantics = tester.ensureSemantics();
            try {
              await tester.pumpWidget(
                host(
                  row(
                    name: name,
                    subtitle: longCountry,
                    rank: 34,
                    count: 3,
                    maxCount: 100,
                    countLabel: '3 次',
                    leading: const Text('34'),
                    containContentInFill: true,
                  ),
                  width: 240,
                  textScale: scale,
                  direction: direction,
                  isLight: isLight,
                ),
              );
              for (final text in ['34', name, longCountry, '3 次']) {
                expectTextInsideFill(tester, text);
              }
              expect(
                tester.getSemantics(find.byType(AirlineRankingRow)),
                matchesSemantics(label: '$name, $longCountry, 3 次'),
              );
              expect(
                tester.widget<Tooltip>(find.byType(Tooltip)).message,
                '$name, $longCountry',
              );
              expect(tester.widget<Text>(find.text(name)).maxLines, 2);
              expect(tester.widget<Text>(find.text('3 次')).maxLines, isNull);
              expect(tester.takeException(), isNull);
            } finally {
              semantics.dispose();
            }
          }
        }
      }
    }
  });

  testWidgets('contained localized count wraps completely at large text', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        row(
          name: 'Johannesburg',
          subtitle: 'South Africa',
          count: 125,
          maxCount: 1000,
          countLabel: '125 movements',
          leading: const Text('34'),
          containContentInFill: true,
        ),
        width: 240,
        textScale: 2,
      ),
    );
    for (final text in [
      '34',
      'Johannesburg',
      'South Africa',
      '125 movements',
    ]) {
      expectTextInsideFill(tester, text);
    }
    final countText = tester.widget<Text>(find.text('125 movements'));
    expect(countText.maxLines, isNull);
    expect(countText.overflow, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bar compares exactly with first place and clamps invalid data', (
    tester,
  ) async {
    for (final contained in [false, true]) {
      for (final data in [
        (5, 10, .5),
        (10, 10, 1.0),
        (15, 10, 1.0),
        (-5, 10, 0.0),
        (5, 0, 0.0),
        (5, -10, 0.0),
      ]) {
        await tester.pumpWidget(
          host(
            row(
              count: data.$1,
              maxCount: data.$2,
              containContentInFill: contained,
            ),
          ),
        );
        final expected = contained ? .64 + .36 * data.$3 : data.$3;
        expect(fillRatio(tester), closeTo(expected, .000001));
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets('zero-width constraint does not create an invalid fill', (
    tester,
  ) async {
    await tester.pumpWidget(host(row(containContentInFill: true), width: 0));
    expect(find.byType(FractionallySizedBox), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('count follows fill endpoint and short fills avoid the name', (
    tester,
  ) async {
    Widget sample(int count) => host(
      row(
        name: 'ANA',
        count: count,
        maxCount: 10,
        countLabel: '$count 次',
        leading: const Icon(Icons.flight),
      ),
    );
    await tester.pumpWidget(sample(10));
    final fullNameRect = tester.getRect(find.text('ANA'));
    final fullCountRect = tester.getRect(find.text('10 次'));
    final bounds = tester.getRect(find.byType(AirlineRankingRow));
    expect(fullCountRect.right, closeTo(bounds.right - 12, .01));

    await tester.pumpWidget(sample(7));
    final movingCount = tester.getRect(find.text('7 次'));
    expect(
      movingCount.right,
      closeTo(bounds.left + bounds.width * .7 - 12, .01),
    );
    expect(movingCount.right, lessThan(fullCountRect.right));
    expect(tester.getRect(find.text('ANA')), fullNameRect);

    await tester.pumpWidget(sample(1));
    expect(fillRatio(tester), .1);
    final shortCount = tester.getRect(find.text('1 次'));
    expect(tester.getRect(find.text('ANA')), fullNameRect);
    expect(shortCount.left, greaterThanOrEqualTo(fullNameRect.right + 12));
    expect(shortCount.right, lessThan(movingCount.right));
    expect(shortCount.right, lessThanOrEqualTo(bounds.right - 12));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'different count lengths preserve fill measurement and alignment',
    (tester) async {
      await tester.pumpWidget(
        host(row(name: 'ANA', count: 9, maxCount: 18, countLabel: '9 次')),
      );
      final shortFillWidth = tester
          .getSize(find.byType(FractionallySizedBox))
          .width;
      final shortCountRect = tester.getRect(find.text('9 次'));
      final rowRect = tester.getRect(find.byType(AirlineRankingRow));
      expect(shortFillWidth, rowRect.width / 2);
      expect(
        shortCountRect.right,
        closeTo(rowRect.left + rowRect.width / 2 - 12, .01),
      );

      await tester.pumpWidget(
        host(row(name: 'ANA', count: 125, maxCount: 250, countLabel: '125 次')),
      );
      final longFillWidth = tester
          .getSize(find.byType(FractionallySizedBox))
          .width;
      final longCountRect = tester.getRect(find.text('125 次'));
      expect(longFillWidth, shortFillWidth);
      expect(longCountRect.right, closeTo(shortCountRect.right, .01));
      expect(longCountRect.left, lessThan(shortCountRect.left));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('count follows the logical fill endpoint in RTL', (tester) async {
    await tester.pumpWidget(
      host(
        row(name: 'ANA', count: 7, maxCount: 10, countLabel: '7 flights'),
        direction: TextDirection.rtl,
      ),
    );
    final bounds = tester.getRect(find.byType(AirlineRankingRow));
    final count = tester.getRect(find.text('7 flights'));
    final name = tester.getRect(find.text('ANA'));
    expect(count.left, closeTo(bounds.right - bounds.width * .7 + 12, .01));
    expect(count.right, lessThan(name.left));
    expect(tester.takeException(), isNull);
  });

  testWidgets('light and dark use distinct subdued palettes and neutral text', (
    tester,
  ) async {
    final fills = <Color>[];
    for (final isLight in [true, false]) {
      for (var rank = 1; rank <= 3; rank++) {
        await tester.pumpWidget(host(row(rank: rank), isLight: isLight));
        await tester.pumpAndSettle();
        final decoration =
            tester.widget<Ink>(find.byType(Ink)).decoration as BoxDecoration;
        fills.add(decoration.color!);
        expect(decoration.border, isNull);
        final text = tester.widget<Text>(find.text('中国国际航空'));
        expect(
          text.style!.color,
          isLight
              ? AppThemeColors.light.textPrimary
              : AppThemeColors.dark.textPrimary,
        );
        final foregroundLuminance = text.style!.color!.computeLuminance();
        final fillLuminance = decoration.color!.computeLuminance();
        final lighter = foregroundLuminance > fillLuminance
            ? foregroundLuminance
            : fillLuminance;
        final darker = foregroundLuminance < fillLuminance
            ? foregroundLuminance
            : fillLuminance;
        expect((lighter + .05) / (darker + .05), greaterThanOrEqualTo(4.5));
      }
    }
    expect(fills.toSet(), hasLength(6));
    for (var index = 0; index < 3; index++) {
      // Light fills must remain visible against the white card canvas.
      expect(
        1.05 / (fills[index].computeLuminance() + .05),
        greaterThanOrEqualTo(1.3),
      );
      expect(fills[index + 3].computeLuminance(), lessThan(.15));
    }
    final darkBlue = HSVColor.fromColor(fills[3]);
    final darkLavender = HSVColor.fromColor(fills[4]);
    final darkMint = HSVColor.fromColor(fills[5]);
    expect(darkBlue.hue, inInclusiveRange(200, 240));
    expect(darkLavender.hue, inInclusiveRange(240, 290));
    expect(darkMint.hue, inInclusiveRange(140, 190));
    for (final color in [darkBlue, darkLavender, darkMint]) {
      expect(color.saturation, greaterThan(.2));
    }
  });

  testWidgets('entire row is tappable with one meaningful semantic label', (
    tester,
  ) async {
    var taps = 0;
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(host(row(onTap: () => taps++)));

      expect(
        tester.getSize(find.byType(AirlineRankingRow)).height,
        greaterThanOrEqualTo(48),
      );
      expect(
        tester.getSemantics(find.byType(AirlineRankingRow)),
        matchesSemantics(
          label: '中国国际航空, 5 次',
          isButton: true,
          hasTapAction: true,
        ),
      );
      await tester.tap(find.text('5 次'));
      expect(taps, 1);
      await tester.tap(find.text('中国国际航空'));
      expect(taps, 2);
      final bounds = tester.getRect(find.byType(AirlineRankingRow));
      await tester.tapAt(bounds.centerRight - const Offset(12, 0));
      expect(taps, 3, reason: 'The transparent remainder stays tappable.');
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('only the filled capsule is painted with the logo hue', (
    tester,
  ) async {
    for (final isLight in [true, false]) {
      await tester.pumpWidget(
        host(row(accentColor: const Color(0xFFD62F42)), isLight: isLight),
      );
      await tester.pumpAndSettle();
      final fill =
          (tester.widget<Ink>(find.byType(Ink)).decoration as BoxDecoration)
              .color!;
      final material = tester.widget<Material>(
        find.descendant(
          of: find.byType(AirlineRankingRow),
          matching: find.byType(Material),
        ),
      );
      expect(fill.r, greaterThan(fill.b));
      expect(material.type, MaterialType.transparency);
      expect(material.color, isNull);
      final foreground = isLight
          ? AppThemeColors.light.textPrimary
          : AppThemeColors.dark.textPrimary;
      for (final text in ['中国国际航空', '5 次']) {
        expect(tester.widget<Text>(find.text(text)).style!.color, foreground);
      }
      final palette = isLight ? AppThemeColors.light : AppThemeColors.dark;
      for (final background in [
        fill,
        palette.background,
        palette.surface,
        palette.surfaceElevated,
      ]) {
        final luminance = background.computeLuminance();
        final inkLuminance = foreground.computeLuminance();
        final contrast = isLight
            ? (luminance + .05) / (inkLuminance + .05)
            : (inkLuminance + .05) / (luminance + .05);
        expect(contrast, greaterThanOrEqualTo(4.5));
      }
    }
  });

  testWidgets('narrow large-text row keeps long name and count within bounds', (
    tester,
  ) async {
    const longName = 'Very Long International Airline Name';
    await tester.pumpWidget(
      host(
        row(
          name: longName,
          countLabel: '125 flights',
          leading: const Icon(Icons.flight),
        ),
        width: 240,
        textScale: 2,
      ),
    );

    final bounds = tester.getRect(find.byType(AirlineRankingRow));
    final countBounds = tester.getRect(find.text('125 flights'));
    final nameBounds = tester.getRect(find.text(longName));
    expect(countBounds.right, lessThanOrEqualTo(bounds.right));
    expect(nameBounds.left, greaterThanOrEqualTo(bounds.left));
    expect(nameBounds.right, lessThan(countBounds.left));
    expect(tester.takeException(), isNull);
  });

  testWidgets('read-only row does not announce a disabled button', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(host(row()));
      expect(
        tester.getSemantics(find.byType(AirlineRankingRow)),
        matchesSemantics(label: '中国国际航空, 5 次'),
      );
      expect(tester.binding.transientCallbackCount, 0);
    } finally {
      semantics.dispose();
    }
  });
}
