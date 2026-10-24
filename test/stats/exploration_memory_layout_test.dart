import 'package:flight_footprint/core/localization/app_strings.dart';
import 'package:flight_footprint/domain/airport.dart';
import 'package:flight_footprint/domain/flight.dart';
import 'package:flight_footprint/features/stats/aircraft_artwork.dart';
import 'package:flight_footprint/features/stats/exploration_memory_carousel.dart';
import 'package:flight_footprint/features/stats/farthest_footprint_card.dart';
import 'package:flight_footprint/features/stats/personal_travel_card.dart';
import 'package:flight_footprint/features/stats/personal_travel_summary.dart';
import 'package:flight_footprint/features/stats/world_exploration.dart';
import 'package:flight_footprint/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _home = Airport(
  iataCode: 'PVG',
  latitude: 31.1443,
  longitude: 121.8083,
  name: 'Shanghai Pudong',
  city: 'Shanghai',
  countryCode: 'CN',
);

final _firstFlight = Flight(
  id: 'memory-layout-first',
  departureIata: 'PVG',
  arrivalIata: 'NRT',
  departedAt: DateTime(2026, 8, 11, 8),
  arrivedAt: DateTime(2026, 8, 11, 12),
  createdAt: DateTime(2026, 8, 11, 8),
  updatedAt: DateTime(2026, 8, 11, 12),
  aircraftType: 'A350-900',
  distanceKm: 1800,
);

final _summary = PersonalTravelSummary(
  year: 2026,
  newCities: [
    NewCityMoment(
      key: 'JP|TOKYO',
      name: 'Tokyo',
      countryCode: 'JP',
      firstFlight: _firstFlight,
      arrivedAt: _firstFlight.arrivedAt!,
    ),
  ],
  newAircraft: [NewAircraftMoment(type: 'A350-900', firstFlight: _firstFlight)],
  frequentRoute: FrequentRouteMoment(
    departureIata: 'PVG',
    arrivalIata: 'NRT',
    fromCity: 'Shanghai',
    toCity: 'Tokyo',
    flights: [_firstFlight, _firstFlight],
  ),
);

Widget _host({required Locale locale, required bool light}) => MaterialApp(
  theme: light ? AppTheme.light() : AppTheme.dark(),
  locale: locale,
  supportedLocales: AppStrings.supportedLocales,
  localizationsDelegates: const [
    AppStringsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(2)),
    child: child!,
  ),
  home: Scaffold(
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: ExplorationMemoryCarousel(
          cards: [
            FarthestFootprintCard(
              home: _home,
              farthest: FarthestFootprint(
                place: ExplorationPlace(
                  name: 'Singapore',
                  countryCode: 'SG',
                  latitude: 1.35,
                  longitude: 103.82,
                  visitedAt: DateTime(2026, 9, 10),
                ),
                distanceKm: 3800,
              ),
              homeLoaded: true,
              onChooseHome: _chooseHome,
            ),
            PersonalTravelMomentCard(
              summary: _summary,
              kind: PersonalTravelKind.newCities,
              onOpen: () => _openedMemory = PersonalTravelKind.newCities,
            ),
            PersonalTravelMomentCard(
              summary: _summary,
              kind: PersonalTravelKind.frequentRoute,
              onOpen: () => _openedMemory = PersonalTravelKind.frequentRoute,
            ),
            PersonalTravelMomentCard(
              summary: _summary,
              kind: PersonalTravelKind.newAircraft,
              onOpen: () => _openedMemory = PersonalTravelKind.newAircraft,
            ),
          ],
          labels: const [
            'Farthest footprint',
            'New cities',
            'Most-flown route',
            'New aircraft types',
          ],
        ),
      ),
    ),
  ),
);

int _homeChoices = 0;
PersonalTravelKind? _openedMemory;
void _chooseHome() => _homeChoices++;

void _setSurface(WidgetTester tester, double width) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 1200);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

Finder get _deck => find.byKey(const ValueKey('exploration-memory-deck'));
Finder get _deckSemantics =>
    find.byKey(const ValueKey('exploration-memory-deck-semantics'));

Future<void> _advance(WidgetTester tester, double width, int index) async {
  await tester.drag(_deck, Offset(-width * .38, 0));
  await tester.pumpAndSettle();
  expect(
    tester.widget<Semantics>(_deckSemantics).properties.value,
    '${index + 1} / 4',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'four memory cards fit large text across widths, locales and themes',
    (tester) async {
      for (final width in [320.0, 411.0, 720.0]) {
        _setSurface(tester, width);
        for (final locale in [const Locale('zh'), const Locale('en')]) {
          for (final light in [false, true]) {
            _homeChoices = 0;
            _openedMemory = null;
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpWidget(_host(locale: locale, light: light));
            await tester.pumpAndSettle();

            expect(
              tester.widget<Semantics>(_deckSemantics).properties.value,
              '1 / 4',
            );
            final edit = find.descendant(
              of: find.byType(FarthestFootprintCard),
              matching: find.byType(IconButton),
            );
            await tester.tap(edit);
            expect(_homeChoices, 1);

            await _advance(tester, width, 1);
            await tester.tap(
              find.byKey(const ValueKey('personal-travel-newCities')),
            );
            expect(_openedMemory, PersonalTravelKind.newCities);

            await _advance(tester, width, 2);
            await tester.tap(
              find.byKey(const ValueKey('personal-travel-frequentRoute')),
            );
            expect(_openedMemory, PersonalTravelKind.frequentRoute);

            await _advance(tester, width, 3);
            await tester.tap(
              find.byKey(const ValueKey('personal-travel-newAircraft')),
            );
            expect(_openedMemory, PersonalTravelKind.newAircraft);

            final asset = aircraftArtworkAssetFor('A350-900');
            expect(asset, isNotNull);
            final image = find.byKey(const ValueKey('aircraft-art-A350-900'));
            expect(image, findsOneWidget);
            final imageWidget = tester.widget<Image>(image);
            expect(imageWidget.image, isA<AssetImage>());
            expect((imageWidget.image as AssetImage).assetName, asset);
            await tester.runAsync(
              () => precacheImage(imageWidget.image, tester.element(image)),
            );
            await tester.pumpAndSettle();
            expect(
              tester
                  .widgetList<RawImage>(find.byType(RawImage))
                  .any((raw) => raw.image != null),
              isTrue,
            );
            expect(
              find.byKey(const ValueKey('aircraft-art-fallback-A350-900')),
              findsNothing,
            );
            expect(tester.takeException(), isNull);
          }
        }
      }
    },
  );
}
