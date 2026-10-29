import 'package:flight_footprint/app/app_controller.dart';
import 'package:flight_footprint/core/localization/app_strings.dart';
import 'package:flight_footprint/domain/flight.dart';
import 'package:flight_footprint/domain/airport.dart';
import 'package:flight_footprint/domain/visited_place.dart';
import 'package:flight_footprint/features/home/home_page.dart';
import 'package:flight_footprint/features/map/detail_map.dart';
import 'package:flight_footprint/features/map/map_explorer_controls.dart';
import 'package:flight_footprint/features/map/globe_map.dart';
import 'package:flight_footprint/features/map/offline_map.dart';
import 'package:flight_footprint/features/stats/world_exploration.dart';
import 'package:flight_footprint/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class _Controller extends ChangeNotifier implements AppController {
  _Controller({this.records = const [], this.airportsByCode = const {}});
  final List<Flight> records;
  final Map<String, Airport> airportsByCode;
  @override
  List<Flight> get flights => records;
  @override
  Airport? airportFor(String code) => airportsByCode[code];
  @override
  List<VisitedPlace> get visitedPlaces => const [];
  @override
  bool get countTransitArrivals => true;
  @override
  List<Never> get transferDecisions => const [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app(Widget child) => MaterialApp(
  theme: AppTheme.dark(),
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

void main() {
  testWidgets('map and exploration retain a known endpoint independently', (
    tester,
  ) async {
    const known = Airport(
      iataCode: 'HKG',
      latitude: 22.3,
      longitude: 113.9,
      name: 'Hong Kong',
      city: 'Hong Kong',
      countryCode: 'HK',
    );
    final date = DateTime(2025);
    final flight = Flight(
      id: 'partial',
      departureIata: '???',
      arrivalIata: 'HKG',
      departedAt: date,
      createdAt: date,
      updatedAt: date,
    );
    final outbound = flight.copyWith(departureIata: 'HKG', arrivalIata: '???');
    for (final record in [flight, outbound]) {
      final controller = _Controller(
        records: [record],
        airportsByCode: {'HKG': known},
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(_app(HomePage(controller: controller)));
      await tester.pump();
      final map = tester.widget<DetailMap>(find.byType(DetailMap));
      final exploration = buildExplorationPlaces(
        flights: [record],
        visitedPlaces: [],
        airportFor: controller.airportFor,
        isZh: false,
      );
      expect(map.places, hasLength(1));
      expect(map.places.single.countryCode, exploration.single.countryCode);
      expect(map.places.single.latitude, exploration.single.latitude);
      expect(map.places.single.longitude, exploration.single.longitude);
      expect(map.routes, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('home defaults to detailed flat map without a basemap toggle', (
    tester,
  ) async {
    final controller = _Controller();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(HomePage(controller: controller)));
    await tester.pump();
    expect(find.byType(DetailMap), findsOneWidget);
    expect(find.byIcon(Icons.layers_outlined), findsNothing);
    expect(find.byIcon(Icons.layers_rounded), findsNothing);
    expect(find.byIcon(Icons.flight_rounded), findsWidgets);
    expect(find.byIcon(Icons.map_outlined), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('home fullscreen retains route arrows across map projections', (
    tester,
  ) async {
    final controller = _Controller();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(HomePage(controller: controller)));
    await tester.tap(find.byTooltip('横向全屏地图'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    final fullscreen = find.byType(MapFullscreenPage);
    expect(fullscreen, findsOneWidget);
    final detail = tester.widget<DetailMap>(
      find.descendant(of: fullscreen, matching: find.byType(DetailMap)),
    );
    expect(detail.showRouteArrows, isTrue);
    expect((detail.fallback as OfflineMap).showRouteArrows, isTrue);

    await tester.tap(
      find.descendant(
        of: fullscreen,
        matching: find.byIcon(Icons.public_rounded),
      ),
    );
    await tester.pump();
    final globe = tester.widget<GlobeMap>(
      find.descendant(of: fullscreen, matching: find.byType(GlobeMap)),
    );
    expect(globe.active, isTrue);
    expect(globe.showRouteArrows, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final globe in [false, true]) {
    testWidgets(
      'fullscreen controls keep projection, reset and add place in globe=$globe',
      (tester) async {
        bool? chosen;
        var resets = 0;
        await tester.pumpWidget(
          _app(
            MapExplorerControls(
              globeMode: globe,
              landscape: false,
              onModeChanged: (value) => chosen = value,
              onOrientation: null,
              onReset: () => resets++,
              onAddPlace: () {},
            ),
          ),
        );
        expect(find.byIcon(Icons.layers_outlined), findsNothing);
        expect(find.text('离线底图'), findsNothing);
        expect(find.byIcon(Icons.add_location_alt_outlined), findsOneWidget);
        await tester.tap(find.byIcon(Icons.public_rounded));
        expect(chosen, isTrue);
        await tester.tap(find.byIcon(Icons.map_outlined));
        expect(chosen, isFalse);
        await tester.tap(find.byIcon(Icons.center_focus_strong_rounded));
        expect(resets, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
