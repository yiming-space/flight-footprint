import 'package:flight_footprint/app/app_controller.dart';
import 'package:flight_footprint/core/localization/app_strings.dart';
import 'package:flight_footprint/data/airport_catalog.dart';
import 'package:flight_footprint/domain/airport.dart';
import 'package:flight_footprint/domain/flight.dart';
import 'package:flight_footprint/features/add_flight/flight_entry_sheet.dart';
import 'package:flight_footprint/features/flights/flight_card.dart';
import 'package:flight_footprint/features/flights/flights_page.dart';
import 'package:flight_footprint/ui/theme/app_theme.dart';
import 'package:flight_footprint/ui/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class _Controller extends ChangeNotifier implements AppController {
  @override
  List<Flight> flights = [];
  @override
  final airports = AirportCatalog({});
  @override
  Airport? airportFor(String iata) => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Flight _past() => Flight(
  id: 'past',
  departureIata: 'PEK',
  arrivalIata: 'SHA',
  departedAt: DateTime.utc(2025),
  createdAt: DateTime.utc(2025),
  updatedAt: DateTime.utc(2025),
  flightNumber: 'CA123',
);

Widget _host(
  _Controller controller,
  ValueChanged<FlightEntryMethod> onRecord,
) => MaterialApp(
  theme: AppTheme.dark(),
  locale: const Locale('zh'),
  supportedLocales: AppStrings.supportedLocales,
  localizationsDelegates: const [
    AppStringsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: Scaffold(
    body: FlightsPage(controller: controller, onAdd: () {}, onRecord: onRecord),
  ),
);

void main() {
  testWidgets('first-record choices differ from search with no matches', (
    tester,
  ) async {
    final controller = _Controller();
    addTearDown(controller.dispose);
    final selections = <FlightEntryMethod>[];
    await tester.pumpWidget(_host(controller, selections.add));
    await tester.pumpAndSettle();
    expect(find.byType(FlightFirstRecord), findsOneWidget);
    for (final method in FlightEntryMethod.values) {
      await tester.ensureVisible(
        find.byKey(ValueKey('flight-entry-${method.name}')),
      );
      await tester.tap(find.byKey(ValueKey('flight-entry-${method.name}')));
    }
    expect(selections, FlightEntryMethod.values);
    await tester.ensureVisible(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'unmatched');
    await tester.pumpAndSettle();
    expect(find.text('没有匹配的航班'), findsOneWidget);
    expect(find.byType(FlightFirstRecord), findsNothing);
    final clear = find.widgetWithText(PrimaryButton, '清除');
    await tester.ensureVisible(clear);
    await tester.tap(clear);
    await tester.pumpAndSettle();
    expect(find.byType(FlightFirstRecord), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'history-only records open completed tab including after first import',
    (tester) async {
      final controller = _Controller();
      addTearDown(controller.dispose);
      await tester.pumpWidget(_host(controller, (_) {}));
      await tester.pumpAndSettle();
      controller.flights = [_past()];
      await tester.pumpWidget(_host(controller, (_) {}));
      await tester.pumpAndSettle();
      expect(find.byType(FlightFirstRecord), findsNothing);
      expect(find.byType(FlightCard), findsOneWidget);
      expect(
        tester
            .widget<AppSegmentedControl>(find.byType(AppSegmentedControl))
            .selectedIndex,
        1,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(_host(controller, (_) {}));
      await tester.pumpAndSettle();
      expect(find.byType(FlightCard), findsOneWidget);
      expect(
        tester
            .widget<AppSegmentedControl>(find.byType(AppSegmentedControl))
            .selectedIndex,
        1,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
