import 'package:flight_footprint/core/localization/app_strings.dart';
import 'package:flight_footprint/domain/flight.dart';
import 'package:flight_footprint/features/stats/aircraft_collection_page.dart'
    show AircraftExhibitArtwork;
import 'package:flight_footprint/features/stats/personal_travel_card.dart';
import 'package:flight_footprint/features/stats/personal_travel_summary.dart';
import 'package:flight_footprint/ui/theme/app_theme.dart';
import 'package:flight_footprint/ui/widgets/country_flag.dart';
import 'package:flight_footprint/ui/widgets/surface_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

final _momentDate = DateTime(2026, 8, 11, 12);

Flight _flight({String? aircraftType, String id = 'memory-flight'}) => Flight(
  id: id,
  departureIata: 'PVG',
  arrivalIata: 'NRT',
  departedAt: _momentDate,
  arrivedAt: _momentDate.add(const Duration(hours: 3)),
  createdAt: _momentDate,
  updatedAt: _momentDate,
  aircraftType: aircraftType,
  distanceKm: 1800,
);

PersonalTravelSummary _summary() {
  final flight = _flight(aircraftType: 'A350-900');
  final secondFlight = _flight(aircraftType: 'A350-900', id: 'memory-flight-2');
  return PersonalTravelSummary(
    year: 2026,
    newCities: [
      NewCityMoment(
        key: 'JP|TOKYO',
        name: 'Tokyo',
        countryCode: 'JP',
        firstFlight: flight,
        arrivedAt: flight.arrivedAt!,
      ),
    ],
    newAircraft: [NewAircraftMoment(type: 'A350-900', firstFlight: flight)],
    frequentRoute: FrequentRouteMoment(
      departureIata: 'PVG',
      arrivalIata: 'NRT',
      fromCity: 'Shanghai',
      toCity: 'Tokyo',
      flights: [flight, secondFlight],
    ),
  );
}

Widget _host(
  Widget child, {
  Locale locale = const Locale('en'),
  bool light = false,
  double textScale = 1,
}) => MaterialApp(
  theme: light ? AppTheme.light() : AppTheme.dark(),
  locale: locale,
  supportedLocales: AppStrings.supportedLocales,
  localizationsDelegates: const [
    AppStringsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  builder: (context, content) => MediaQuery(
    data: MediaQuery.of(context)
        .copyWith(textScaler: TextScaler.linear(textScale)),
    child: content!,
  ),
  home: Scaffold(
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: child,
          ),
        ),
      ),
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'new city groups its visit and keeps the annual collection secondary',
    (tester) async {
      final summary = _summary();
      var opened = 0;
      await tester.pumpWidget(
        _host(
          PersonalTravelMomentCard(
            summary: summary,
            kind: PersonalTravelKind.newCities,
            onOpen: () => opened++,
          ),
          locale: const Locale('zh'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('新抵达的城市'), findsOneWidget);
      expect(find.text('2026'), findsOneWidget);
      expect(find.text('Tokyo'), findsOneWidget);
      expect(find.text('日本'), findsOneWidget);
      expect(find.byType(CountryFlag), findsOneWidget);
      expect(
        find.byKey(const ValueKey('personal-travel-city-art')),
        findsNothing,
      );
      final count = tester.widget<Text>(
        find.byKey(const ValueKey('personal-travel-new-city-count')),
      );
      expect(count.data, '1');
      expect(find.text('座'), findsOneWidget);
      expect(find.text('本年新增'), findsOneWidget);
      expect(find.text('首次抵达'), findsOneWidget);
      expect(find.text('2026年8月11日'), findsOneWidget);
      expect(
        tester
            .getTopLeft(find.byKey(const ValueKey('personal-travel-date')))
            .dy,
        greaterThan(
          tester
              .getBottomLeft(
                find.byKey(const ValueKey('personal-travel-new-city-count')),
              )
              .dy,
        ),
      );
      await tester.tap(find.byType(SurfaceCard));
      expect(opened, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('frequent route uses airport codes and a two-way connector', (
    tester,
  ) async {
    final summary = _summary();
    var opened = 0;
    await tester.pumpWidget(
      _host(
        PersonalTravelMomentCard(
          summary: summary,
          kind: PersonalTravelKind.frequentRoute,
          onOpen: () => opened++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('PVG'), findsOneWidget);
    expect(find.text('NRT'), findsOneWidget);
    expect(find.text('Shanghai'), findsOneWidget);
    expect(find.text('Tokyo'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('personal-travel-route-connector')),
      findsOneWidget,
    );
    expect(find.text('Shanghai ↔ Tokyo'), findsNothing);
    final count = tester.widget<Text>(
      find.byKey(const ValueKey('personal-travel-count')),
    );
    expect(count.data, contains('2'));
    expect(find.text('Aug 11, 2026'), findsOneWidget);
    expect(
      tester
          .getBottomLeft(find.byKey(const ValueKey('personal-travel-count')))
          .dy,
      greaterThan(tester.getBottomLeft(find.text('PVG')).dy),
    );
    final connector = tester.getRect(
      find.byKey(const ValueKey('personal-travel-route-connector')),
    );
    expect(connector.left, greaterThan(tester.getRect(find.text('PVG')).right));
    expect(connector.right, lessThan(tester.getRect(find.text('NRT')).left));
    await tester.tap(find.byType(SurfaceCard));
    expect(opened, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('new aircraft uses the shared model-matched exhibit artwork', (
    tester,
  ) async {
    final summary = _summary();
    var opened = 0;
    await tester.pumpWidget(
      _host(
        PersonalTravelMomentCard(
          summary: summary,
          kind: PersonalTravelKind.newAircraft,
          onOpen: () => opened++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('A350-900'), findsOneWidget);
    expect(find.byType(AircraftExhibitArtwork), findsOneWidget);
    expect(
      find.byKey(const ValueKey('personal-travel-aircraft-artwork')),
      findsOneWidget,
    );
    final count = tester.widget<Text>(
      find.byKey(const ValueKey('personal-travel-count')),
    );
    expect(count.data, 'A350-900');
    expect(find.text('Aircraft'), findsOneWidget);
    expect(find.text('First recorded'), findsOneWidget);
    expect(find.text('Aug 11, 2026'), findsOneWidget);
    await tester.tap(find.byType(SurfaceCard));
    expect(opened, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty cards do not fabricate airport, aircraft or city data', (
    tester,
  ) async {
    final empty = PersonalTravelSummary(
      year: 2026,
      newCities: const [],
      newAircraft: const [],
      frequentRoute: null,
    );
    for (final kind in PersonalTravelKind.values) {
      await tester.pumpWidget(
        _host(
          PersonalTravelMomentCard(summary: empty, kind: kind, onOpen: () {}),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('personal-travel-empty-message')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('personal-travel-date')), findsNothing);
      expect(find.byKey(const ValueKey('personal-travel-count')), findsNothing);
      expect(find.byType(AircraftExhibitArtwork), findsNothing);
      expect(
        find.byKey(const ValueKey('personal-travel-route-connector')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('large type reflows the city hero without overflow', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 720);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final summary = _summary();
    await tester.pumpWidget(
      _host(
        PersonalTravelMomentCard(
          summary: summary,
          kind: PersonalTravelKind.newCities,
          onOpen: () {},
        ),
        locale: const Locale('zh'),
        light: true,
        textScale: 1.8,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Tokyo'), findsOneWidget);
    expect(find.text('2026年8月11日'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
