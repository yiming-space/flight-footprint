import 'package:flight_footprint/core/localization/app_strings.dart';
import 'package:flight_footprint/domain/flight.dart';
import 'package:flight_footprint/features/stats/aircraft_collection.dart';
import 'package:flight_footprint/features/stats/aircraft_collection_detail_page.dart';
import 'package:flight_footprint/features/stats/aircraft_collection_overview_card.dart';
import 'package:flight_footprint/features/stats/aircraft_collection_page.dart';
import 'package:flight_footprint/features/stats/airline_ranking.dart';
import 'package:flight_footprint/features/stats/airline_ranking_overview_card.dart';
import 'package:flight_footprint/features/stats/airline_ranking_page.dart';
import 'package:flight_footprint/features/stats/city_ranking.dart';
import 'package:flight_footprint/features/stats/city_ranking_page.dart';
import 'package:flight_footprint/features/stats/country_stats_page.dart';
import 'package:flight_footprint/features/stats/ranking_expansion_card.dart';
import 'package:flight_footprint/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

enum _Entry { aircraft, airlines, cities, countries }

String _prefix(_Entry entry) => switch (entry) {
  _Entry.aircraft => 'aircraft-collection',
  _Entry.airlines => 'airline-ranking',
  _Entry.cities => 'city-ranking',
  _Entry.countries => 'country-stats',
};

Flight _flight() => Flight(
  id: 'record-1',
  departureIata: 'PVG',
  arrivalIata: 'PEK',
  departedAt: DateTime(2026, 1, 1),
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
  aircraftType: 'A350-900',
  distanceKm: 1200,
);

Widget _host(
  _Entry entry, {
  VoidCallback? onBuild,
  bool isLight = true,
  double textScale = 1,
  bool reduced = false,
  bool accessible = false,
}) => MaterialApp(
  theme: (isLight ? AppTheme.light() : AppTheme.dark()).copyWith(
    platform: TargetPlatform.android,
  ),
  locale: const Locale('en'),
  supportedLocales: AppStrings.supportedLocales,
  localizationsDelegates: const [
    AppStringsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      textScaler: TextScaler.linear(textScale),
      disableAnimations: reduced,
      accessibleNavigation: accessible,
    ),
    child: child!,
  ),
  home: Scaffold(
    body: Padding(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: Builder(
          builder: (context) {
            Widget selectedPage(String label) => Scaffold(
              appBar: AppBar(title: const Text('Selected records')),
              body: Text(label),
            );
            Widget pageBuilder(BuildContext pageContext) {
              onBuild?.call();
              return switch (entry) {
                _Entry.aircraft => AircraftCollectionPage(
                  items: [
                    AircraftCollectionEntry(
                      key: 'A350-900',
                      type: 'A350-900',
                      manufacturer: AircraftManufacturer.airbus,
                      flights: [_flight()],
                    ),
                  ],
                  detailBuilder: (context, aircraft) =>
                      AircraftCollectionDetailPage(
                        entry: aircraft,
                        flightBuilder: (_, flight) => Text(flight.id),
                      ),
                ),
                _Entry.airlines => AirlineRankingPage(
                  items: [
                    AirlineRankingEntry(
                      name: 'Test airline',
                      iataCode: null,
                      flights: [_flight()],
                    ),
                  ],
                  animateEntrance: true,
                  onAirlineSelected: (airline) => Navigator.of(pageContext)
                      .push<void>(
                        MaterialPageRoute(
                          builder: (_) =>
                              selectedPage(airline.flights.single.id),
                        ),
                      ),
                ),
                _Entry.cities => CityRankingPage(
                  animateEntrance: true,
                  items: [
                    CityRankingEntry(
                      key: 'CN:Shanghai',
                      name: 'Shanghai',
                      countryName: 'China',
                      countryCode: 'CN',
                      count: 1,
                      flights: [_flight()],
                    ),
                  ],
                  onCitySelected: (city) => Navigator.of(pageContext)
                      .push<void>(
                        MaterialPageRoute(
                          builder: (_) => selectedPage(city.flights.single.id),
                        ),
                      ),
                ),
                _Entry.countries => CountryStatsPage(
                  items: const [('China', 1)],
                  countryCodes: const {'China': 'cn'},
                  onCountrySelected: (country) => Navigator.of(pageContext)
                      .push<void>(
                        MaterialPageRoute(
                          builder: (_) => selectedPage(country),
                        ),
                      ),
                ),
              };
            }

            return switch (entry) {
              _Entry.aircraft => AircraftCollectionOverviewCard(
                aircraftCount: 1,
                pageBuilder: pageBuilder,
              ),
              _Entry.airlines => AirlineRankingOverviewCard(
                airlineCount: 1,
                pageBuilder: pageBuilder,
              ),
              _ => RankingExpansionCard(
                keyPrefix: _prefix(entry),
                title: entry == _Entry.cities
                    ? 'City ranking'
                    : 'Country statistics',
                subtitle: entry == _Entry.cities
                    ? '1 city in your flights'
                    : '1 country / region recorded',
                icon: entry == _Entry.cities
                    ? Icons.location_city_rounded
                    : Icons.public_rounded,
                pageBuilder: pageBuilder,
                flipOnOpen: true,
              ),
            };
          },
        ),
      ),
    ),
  ),
);

Finder _source(_Entry entry) =>
    find.byKey(ValueKey('${_prefix(entry)}-source'), skipOffstage: false);

double _opacity(WidgetTester tester, _Entry entry) =>
    tester.widget<Opacity>(_source(entry)).opacity;

Finder _page(_Entry entry) => switch (entry) {
  _Entry.aircraft => find.byType(AircraftCollectionPage, skipOffstage: false),
  _Entry.airlines => find.byType(AirlineRankingPage, skipOffstage: false),
  _Entry.cities => find.byType(CityRankingPage, skipOffstage: false),
  _Entry.countries => find.byType(CountryStatsPage, skipOffstage: false),
};

void _surface(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

void main() {
  testWidgets(
    'all four entries turn sideways from the source and restore on return',
    (tester) async {
      _surface(tester, const Size(360, 900));
      for (final entry in _Entry.values) {
        var builds = 0;
        await tester.pumpWidget(_host(entry, onBuild: () => builds++));
        await tester.pumpAndSettle();
        final original = tester.getRect(_source(entry));
        await tester.tap(_source(entry));
        await tester.tap(_source(entry), warnIfMissed: false);
        await tester.pump();
        expect(_opacity(tester, entry), 1);
        await tester.pump();
        expect(_opacity(tester, entry), 0);
        final initial = tester.getRect(
          find.byKey(const ValueKey('ranking-flip-surface')),
        );
        expect(initial.left, closeTo(original.left, .01));
        expect(initial.top, closeTo(original.top, .01));
        expect(initial.width, closeTo(original.width, .01));
        expect(
          tester
              .widget<ClipRRect>(
                find
                    .ancestor(
                      of: find.byKey(const ValueKey('ranking-flip-front')),
                      matching: find.byType(ClipRRect),
                    )
                    .first,
              )
              .borderRadius,
          AppRadii.medium,
        );
        await tester.pump(const Duration(milliseconds: 180));
        final expanding = tester.getSize(
          find.byKey(const ValueKey('ranking-flip-surface')),
        );
        expect(expanding.width, greaterThan(original.width));
        expect(expanding.width, lessThan(360));
        final frontTransform = tester.widget<Transform>(
          find.byKey(const ValueKey('ranking-flip-transform')),
        );
        expect(frontTransform.transform.entry(2, 0), lessThan(0));
        expect(frontTransform.transform.entry(1, 1), 1);
        await tester.pump(const Duration(milliseconds: 60));
        expect(
          tester
              .widget<Transform>(
                find.byKey(const ValueKey('ranking-flip-transform')),
              )
              .transform
              .entry(2, 0),
          greaterThan(0),
        );
        await tester.pumpAndSettle();
        expect(builds, 1);
        expect(_page(entry), findsOneWidget);
        expect(find.byType(BottomSheet), findsNothing);
        await tester.tap(find.byType(BackButton));
        await tester.pump();
        expect(_opacity(tester, entry), 0);
        await tester.pumpAndSettle();
        expect(_opacity(tester, entry), 1);
        expect(_page(entry), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

  for (final flag in ['reduced', 'accessible']) {
    testWidgets('all four entries use a short fade for $flag motion', (
      tester,
    ) async {
      _surface(tester, const Size(360, 900));
      for (final entry in _Entry.values) {
        await tester.pumpWidget(
          _host(
            entry,
            reduced: flag == 'reduced',
            accessible: flag == 'accessible',
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(_source(entry));
        await tester.pump();
        await tester.pump();
        expect(
          find.byKey(const ValueKey('ranking-flip-transform')),
          findsNothing,
        );
        final route = ModalRoute.of(tester.element(_page(entry)))!;
        expect(route.transitionDuration, const Duration(milliseconds: 120));
        await tester.pumpAndSettle();
        expect(_page(entry), findsOneWidget);
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(_opacity(tester, entry), 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });
  }

  testWidgets('all four entries allow an early back and can be opened again', (
    tester,
  ) async {
    _surface(tester, const Size(360, 900));
    for (final entry in _Entry.values) {
      var builds = 0;
      await tester.pumpWidget(_host(entry, onBuild: () => builds++));
      await tester.pumpAndSettle();
      await tester.tap(_source(entry));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 260));
      Navigator.of(tester.element(_page(entry))).pop();
      await tester.pumpAndSettle();
      expect(builds, 1);
      expect(_opacity(tester, entry), 1);
      await tester.tap(_source(entry));
      await tester.pumpAndSettle();
      expect(builds, 2);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(_opacity(tester, entry), 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets(
    'expanded aircraft collection retains card detail and back path',
    (tester) async {
      _surface(tester, const Size(360, 900));
      await tester.pumpWidget(_host(_Entry.aircraft));
      await tester.tap(_source(_Entry.aircraft));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('aircraft-card-A350-900')));
      await tester.pumpAndSettle();
      final detail = tester.widget<AircraftCollectionDetailPage>(
        find.byType(AircraftCollectionDetailPage),
      );
      expect(detail.entry.type, 'A350-900');
      expect(detail.entry.flights.single.id, 'record-1');
      await tester.tap(
        find.descendant(
          of: find.byType(AircraftCollectionDetailPage),
          matching: find.byType(BackButton),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AircraftCollectionPage), findsOneWidget);
      expect(_opacity(tester, _Entry.aircraft), 0);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(_opacity(tester, _Entry.aircraft), 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('expanded city and country pages retain record selection', (
    tester,
  ) async {
    _surface(tester, const Size(360, 900));
    for (final entry in [_Entry.cities, _Entry.countries]) {
      await tester.pumpWidget(_host(entry));
      await tester.tap(_source(entry));
      await tester.pumpAndSettle();
      expect(
        find.text(
          entry == _Entry.cities
              ? '1 city visited'
              : '1 country/region visited',
        ),
        findsOneWidget,
      );
      await tester.tap(
        entry == _Entry.cities
            ? find.byKey(const ValueKey('CN:Shanghai'))
            : find.byKey(const ValueKey('China')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Selected records'), findsOneWidget);
      expect(
        find.text(entry == _Entry.cities ? 'record-1' : 'China'),
        findsOneWidget,
      );
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(_page(entry), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(_opacity(tester, entry), 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets(
    'entry expansions remain full-layout at 2x on narrow and wide screens',
    (tester) async {
      _surface(tester, const Size(320, 1000));
      for (final width in [320.0, 900.0]) {
        tester.view.physicalSize = Size(width, 1000);
        for (final entry in _Entry.values) {
          for (final isLight in [true, false]) {
            await tester.pumpWidget(
              _host(entry, isLight: isLight, textScale: 2),
            );
            await tester.pumpAndSettle();
            await tester.tap(_source(entry));
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 180));
            expect(tester.getSize(_page(entry)).width, width);
            expect(tester.takeException(), isNull);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await tester.tap(find.byType(BackButton));
            await tester.pumpAndSettle();
            expect(_opacity(tester, entry), 1);
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
          }
        }
      }
    },
  );
}
