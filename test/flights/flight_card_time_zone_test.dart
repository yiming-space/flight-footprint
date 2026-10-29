import 'package:flight_footprint/app/app_controller.dart';
import 'package:flight_footprint/core/localization/app_strings.dart';
import 'package:flight_footprint/data/airport_catalog.dart';
import 'package:flight_footprint/domain/airport.dart';
import 'package:flight_footprint/domain/flight.dart';
import 'package:flight_footprint/domain/transfer_decision.dart';
import 'package:flight_footprint/domain/visited_place.dart';
import 'package:flight_footprint/features/flights/flight_card.dart';
import 'package:flight_footprint/features/flights/flights_page.dart';
import 'package:flight_footprint/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class _Controller extends ChangeNotifier implements AppController {
  _Controller(this.flights)
    : airports = AirportCatalog(
        const {},
        timeZoneIds: const {'JFK': 'America/New_York', 'LHR': 'Europe/London'},
      );

  @override
  final List<Flight> flights;

  @override
  List<TransferDecision> get transferDecisions => const [];

  @override
  final List<VisitedPlace> visitedPlaces = const [];

  @override
  final AirportCatalog airports;

  @override
  Airport? airportFor(String iata) => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Flight _flight({required String departure, required String arrival}) => Flight(
  id: 'timezone-flight',
  departureIata: departure,
  arrivalIata: arrival,
  departedAt: DateTime.utc(2026, 1, 1, 0, 30),
  arrivedAt: DateTime.utc(2026, 1, 1, 8, 30),
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  flightNumber: 'TZ101',
  durationMinutes: 480,
  status: FlightStatus.completed,
);

Widget _host(Widget child) => MaterialApp(
  theme: AppTheme.light(),
  locale: const Locale('zh'),
  supportedLocales: AppStrings.supportedLocales,
  localizationsDelegates: const [
    AppStringsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: Scaffold(body: child),
);

void _setSurface(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(430, 1200);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets(
    'FlightsPage shows JFK and LHR wall times and filters by JFK year',
    (tester) async {
      _setSurface(tester);
      final controller = _Controller([
        _flight(departure: 'JFK', arrival: 'LHR'),
      ]);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _host(FlightsPage(controller: controller, onAdd: () {})),
      );
      await tester.pumpAndSettle();

      expect(find.byType(FlightCard), findsOneWidget);
      expect(find.text('19:30'), findsOneWidget);
      expect(find.text('2025.12.31'), findsOneWidget);
      expect(find.text('08:30'), findsOneWidget);
      expect(find.text('2026.1.1'), findsOneWidget);
      expect(find.text('次日'), findsOneWidget);
      expect(find.text('2025'), findsOneWidget);

      await tester.tap(find.text('2025').first);
      await tester.pumpAndSettle();
      expect(find.byType(FlightCard), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('arrival badge can show a previous airport-local day', (
    tester,
  ) async {
    _setSurface(tester);
    final flight = Flight(
      id: 'westbound',
      departureIata: 'LHR',
      arrivalIata: 'JFK',
      departedAt: DateTime.utc(2026, 1, 1, 0, 30),
      arrivedAt: DateTime.utc(2026, 1, 1, 4, 30),
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      flightNumber: 'TZ102',
      durationMinutes: 240,
      status: FlightStatus.completed,
    );
    final controller = _Controller([flight]);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _host(FlightCard(flight: flight, controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(find.text('00:30'), findsOneWidget);
    expect(find.text('23:30'), findsOneWidget);
    expect(find.text('-1天'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
