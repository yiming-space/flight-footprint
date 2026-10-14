import 'package:flight_footprint/features/stats/airline_ranking_count.dart';
import 'package:flight_footprint/features/stats/airline_ranking_row.dart';
import 'package:flight_footprint/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(
    double reveal, {
    bool reduced = false,
    bool accessible = false,
    double scale = 1,
    bool english = false,
    int count = 10,
    String name = 'International Airline',
  }) => MaterialApp(
    theme: AppTheme.dark(),
    home: Scaffold(
      body: MediaQuery(
        data: MediaQueryData(
          disableAnimations: reduced,
          accessibleNavigation: accessible,
          textScaler: TextScaler.linear(scale),
        ),
        child: Center(
          child: SizedBox(
            width: 280,
            child: AirlineRankingRow(
              name: name,
              count: count,
              maxCount: count,
              rank: 1,
              countLabel: english ? '$count flights' : '$count 次',
              fillReveal: reveal,
              followFill: true,
              countBuilder: (style) => AirlineRankingCount(
                key: const ValueKey('count-window'),
                count: count,
                reveal: reveal,
                labelForCount: (value) =>
                    english ? '$value flights' : '$value 次',
                style: style,
              ),
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('count shares fill progress with a continuous soft roll', (
    tester,
  ) async {
    await tester.pumpWidget(host(0, name: 'KLM'));
    expect(find.text('0 次'), findsOneWidget);
    final bounds = tester.getRect(find.byKey(const ValueKey('count-window')));
    final nameBounds = tester.getRect(find.text('KLM'));
    await tester.pumpWidget(host(.25, name: 'KLM'));
    final outgoing = find.byKey(const ValueKey('airline-count-outgoing'));
    final incoming = find.byKey(const ValueKey('airline-count-incoming'));
    expect(
      find.descendant(of: outgoing, matching: find.text('2 次')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: incoming, matching: find.text('3 次')),
      findsOneWidget,
    );
    expect(tester.widget<Opacity>(outgoing).opacity, .5);
    expect(tester.widget<Opacity>(incoming).opacity, .5);
    expect(
      tester
          .widget<Transform>(
            find.descendant(of: outgoing, matching: find.byType(Transform)),
          )
          .transform
          .storage[13],
      -2,
    );
    expect(
      tester.getRect(find.byKey(const ValueKey('count-window'))).size,
      bounds.size,
    );
    expect(tester.getRect(find.text('KLM')), nameBounds);
    await tester.pumpWidget(host(1, name: 'KLM'));
    expect(find.text('10 次'), findsOneWidget);
    expect(outgoing, findsNothing);
    expect(incoming, findsNothing);
    final settled = tester.getRect(find.byKey(const ValueKey('count-window')));
    expect(settled.size, bounds.size);
    expect(settled.left, greaterThan(bounds.left));
    expect(tester.hasRunningAnimations, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('both reduced-motion settings show the final count immediately', (
    tester,
  ) async {
    for (final accessible in [false, true]) {
      await tester.pumpWidget(
        host(.25, reduced: !accessible, accessible: accessible),
      );
      expect(find.text('10 次'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('airline-count-outgoing')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('airline-count-incoming')),
        findsNothing,
      );
      expect(tester.hasRunningAnimations, isFalse);
    }
  });

  testWidgets('large localized counts keep layout and final accessibility', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      for (final english in [false, true]) {
        await tester.pumpWidget(
          host(1, scale: 2, english: english, count: 125),
        );
        final bounds = tester.getRect(
          find.byKey(const ValueKey('count-window')),
        );
        for (final reveal in [0.0, .07, .79, 1.0]) {
          await tester.pumpWidget(
            host(reveal, scale: 2, english: english, count: 125),
          );
          expect(
            tester.getRect(find.byKey(const ValueKey('count-window'))).size,
            bounds.size,
          );
          expect(
            tester.getSemantics(find.byType(AirlineRankingRow)).label,
            english
                ? 'International Airline, 125 flights'
                : 'International Airline, 125 次',
          );
          expect(tester.takeException(), isNull);
        }
      }
    } finally {
      semantics.dispose();
    }
  });
}
