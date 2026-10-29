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
import 'package:flight_footprint/ui/widgets/surface_card.dart';
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
      name: 'San Carlos de Bariloche',
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

Widget _host({required Locale locale, required bool light, double scale = 2}) =>
    MaterialApp(
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
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
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
                  onOpen: () =>
                      _openedMemory = PersonalTravelKind.frequentRoute,
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

void _expectSurfaceSize(WidgetTester tester, Finder finder, Size size) {
  final surface = tester.widget<SurfaceCard>(finder);
  expect(tester.getSize(finder), size);
  expect(surface.borderRadius, AppRadii.medium);
  final card = tester.getRect(finder);
  final header = tester.getRect(
    find.descendant(
      of: finder,
      matching: find.byKey(const ValueKey('exploration-memory-header')),
    ),
  );
  final footer = tester.getRect(
    find.descendant(
      of: finder,
      matching: find.byKey(const ValueKey('exploration-memory-footer')),
    ),
  );
  final left = tester.getRect(
    find.descendant(
      of: finder,
      matching: find.byKey(const ValueKey('exploration-memory-footer-left')),
    ),
  );
  final right = tester.getRect(
    find.descendant(
      of: finder,
      matching: find.byKey(const ValueKey('exploration-memory-footer-right')),
    ),
  );
  expect(header.top - card.top, 12);
  expect(card.bottom - footer.bottom, 20);
  expect(left.width, closeTo(right.width, .1));
}

Future<void> _advance(WidgetTester tester, double width, int index) async {
  await tester.drag(_deck, Offset(-width * .7, 0));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull, reason: 'layout after page $index');
  expect(
    tester.widget<Semantics>(_deckSemantics).properties.value,
    '${index + 1} / 4',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('new city card balances wrapped city and yearly count', (
    tester,
  ) async {
    for (final width in [320.0, 411.0]) {
      _setSurface(tester, width);
      for (final locale in [const Locale('zh'), const Locale('en')]) {
        for (final scale in [1.0, 2.0]) {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpWidget(
            _host(locale: locale, light: true, scale: scale),
          );
          await tester.pumpAndSettle();
          await _advance(tester, width, 1);

          final city = find.byKey(const ValueKey('personal-travel-city-name'));
          final country = find.byKey(
            const ValueKey('personal-travel-city-country'),
          );
          final count = find.byKey(
            const ValueKey('personal-travel-new-city-count'),
          );
          expect(city, findsOneWidget);
          expect(country, findsOneWidget);
          expect(count, findsOneWidget);
          expect(
            tester.getRect(country).top,
            greaterThan(tester.getRect(city).top),
          );
          expect(
            tester.getRect(count).right,
            lessThanOrEqualTo(
              tester
                      .getRect(
                        find.byKey(const ValueKey('personal-travel-newCities')),
                      )
                      .right -
                  16,
            ),
          );
          expect(
            tester.widget<Text>(count).style!.color,
            AppTheme.light().extension<AppThemeColors>()!.displayPrimary,
          );
          expect(
            find.text(locale.languageCode == 'zh' ? '首次抵达' : 'First arrival'),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('personal-travel-date')),
            findsOneWidget,
          );
          expect(
            tester.takeException(),
            isNull,
            reason: 'width=$width scale=$scale locale=$locale',
          );
        }
      }
    }
  });

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
              tester.takeException(),
              isNull,
              reason: 'initial layout at $width, $locale, light=$light',
            );

            expect(
              tester.widget<Semantics>(_deckSemantics).properties.value,
              '1 / 4',
            );
            final edit = find.descendant(
              of: find.byType(FarthestFootprintCard),
              matching: find.byType(IconButton),
            );
            final farthestSurface = find.descendant(
              of: find.byType(FarthestFootprintCard),
              matching: find.byType(SurfaceCard),
            );
            final sharedCardSize = tester.getSize(farthestSurface);
            _expectSurfaceSize(tester, farthestSurface, sharedCardSize);
            await tester.tap(edit);
            expect(_homeChoices, 1);

            await _advance(tester, width, 1);
            _expectSurfaceSize(
              tester,
              find.byKey(const ValueKey('personal-travel-newCities')),
              sharedCardSize,
            );
            await tester.tap(
              find.byKey(const ValueKey('personal-travel-newCities')),
            );
            expect(_openedMemory, PersonalTravelKind.newCities);

            await _advance(tester, width, 2);
            _expectSurfaceSize(
              tester,
              find.byKey(const ValueKey('personal-travel-frequentRoute')),
              sharedCardSize,
            );
            await tester.tap(
              find.byKey(const ValueKey('personal-travel-frequentRoute')),
            );
            expect(_openedMemory, PersonalTravelKind.frequentRoute);

            await _advance(tester, width, 3);
            _expectSurfaceSize(
              tester,
              find.byKey(const ValueKey('personal-travel-newAircraft')),
              sharedCardSize,
            );
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
            final layoutError = tester.takeException();
            expect(layoutError, isNull, reason: '$layoutError');
          }
        }
      }
    },
  );
}
