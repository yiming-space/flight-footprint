import 'package:flight_footprint/app/app_controller.dart';
import 'package:flight_footprint/core/localization/app_strings.dart';
import 'package:flight_footprint/data/airport_catalog.dart';
import 'package:flight_footprint/domain/airport.dart';
import 'package:flight_footprint/domain/flight.dart';
import 'package:flight_footprint/domain/transfer_decision.dart';
import 'package:flight_footprint/domain/visited_place.dart';
import 'package:flight_footprint/features/flights/flights_page.dart';
import 'package:flight_footprint/features/flights/record_issues_sheet.dart';
import 'package:flight_footprint/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class _Controller extends ChangeNotifier implements AppController {
  _Controller({List<Flight>? initialFlights})
    : flights =
          initialFlights ??
          [
            Flight(
              id: 'unknown-airport-flight',
              departureIata: 'ZZZ',
              arrivalIata: 'AAA',
              departedAt: DateTime.utc(2025),
              createdAt: DateTime.utc(2025),
              updatedAt: DateTime.utc(2025),
              flightNumber: 'FF101',
            ),
          ];

  @override
  final List<Flight> flights;

  @override
  List<TransferDecision> get transferDecisions => const [];

  @override
  final visitedPlaces = <VisitedPlace>[];

  @override
  final airports = AirportCatalog(const {});

  @override
  Airport? airportFor(String iata) => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _host(_Controller controller) => MaterialApp(
  theme: AppTheme.light(),
  locale: const Locale('zh'),
  supportedLocales: AppStrings.supportedLocales,
  localizationsDelegates: const [
    AppStringsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: Scaffold(
    body: FlightsPage(controller: controller, onAdd: () {}),
  ),
);

void main() {
  testWidgets('flight list exposes an actionable record check', (tester) async {
    final controller = _Controller();
    addTearDown(controller.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 1000);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_host(controller));
    await tester.pumpAndSettle();

    expect(find.text('1 项需要查看或修正'), findsOneWidget);
    await tester.tap(find.text('1 项需要查看或修正'));
    await tester.pumpAndSettle();

    expect(find.byType(RecordIssuesSheet), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(RecordIssuesSheet),
        matching: find.textContaining('FF101'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('出发机场无法识别'), findsOneWidget);
    expect(find.text('修正航班'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('suspected duplicates appear as a review group', (tester) async {
    final instant = DateTime.utc(2025, 5, 6, 7, 8);
    final controller = _Controller(
      initialFlights: [
        Flight(
          id: 'duplicate-one',
          departureIata: 'AAA',
          arrivalIata: 'BBB',
          departedAt: instant,
          createdAt: instant,
          updatedAt: instant,
          flightNumber: 'CA123',
        ),
        Flight(
          id: 'duplicate-two',
          departureIata: 'aaa',
          arrivalIata: 'bbb',
          departedAt: instant,
          createdAt: instant,
          updatedAt: instant,
          flightNumber: 'ca123',
        ),
      ],
    );
    addTearDown(controller.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 1000);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_host(controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('3 项需要查看或修正'));
    await tester.pumpAndSettle();

    expect(find.text('疑似重复航班 · 1'), findsOneWidget);
    expect(find.textContaining('请逐条核对，记录不会自动合并。'), findsOneWidget);
    expect(find.text('查看'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}
