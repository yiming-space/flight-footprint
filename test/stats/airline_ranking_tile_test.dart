import 'package:flight_footprint/features/stats/airline_ranking_row.dart';
import 'package:flight_footprint/features/stats/airline_ranking_tile.dart';
import 'package:flight_footprint/ui/theme/app_theme.dart';
import 'package:flight_footprint/ui/widgets/airline_logo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host({String code = 'ZZ', VoidCallback? onTap}) => MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(
      body: AirlineRankingTile(
        name: 'Test Airline',
        iataCode: code,
        count: 5,
        maxCount: 10,
        rank: 1,
        countLabel: '5 次',
        onTap: onTap ?? () {},
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
}
