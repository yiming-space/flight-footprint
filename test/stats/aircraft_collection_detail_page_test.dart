import 'package:flight_footprint/core/localization/app_strings.dart';
import 'package:flight_footprint/domain/flight.dart';
import 'package:flight_footprint/features/stats/aircraft_artwork.dart';
import 'package:flight_footprint/features/stats/aircraft_collection.dart';
import 'package:flight_footprint/features/stats/aircraft_collection_detail_page.dart';
import 'package:flight_footprint/features/stats/aircraft_collection_page.dart';
import 'package:flight_footprint/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

const _a350Asset = 'assets/images/aircraft/a350-900-side-right-v3.png';

Flight _flight(
  String id,
  DateTime date, {
  double? distance = 1200,
  String type = 'A350-900',
}) => Flight(
  id: id,
  departureIata: id == 'oldest' ? 'PVG' : 'PEK',
  arrivalIata: id == 'oldest' ? 'HKG' : 'CAN',
  departedAt: date,
  createdAt: date,
  updatedAt: date,
  flightNumber: 'MU-$id',
  aircraftType: type,
  distanceKm: distance,
);

AircraftCollectionEntry _entry({
  String type = 'A350-900',
  AircraftManufacturer manufacturer = AircraftManufacturer.airbus,
  List<Flight>? flights,
}) => AircraftCollectionEntry(
  key: type,
  type: type,
  manufacturer: manufacturer,
  flights: flights ?? [_flight('only', DateTime(2026, 3, 4))],
);

Widget _host(
  Widget home, {
  bool isLight = true,
  Locale locale = const Locale('en'),
  double textScale = 1,
  AssetBundle? bundle,
  bool disableAnimations = false,
  bool accessibleNavigation = false,
}) => MaterialApp(
  theme: isLight ? AppTheme.light() : AppTheme.dark(),
  locale: locale,
  supportedLocales: AppStrings.supportedLocales,
  localizationsDelegates: const [
    AppStringsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  builder: (context, child) {
    final scaled = MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
        disableAnimations: disableAnimations,
        accessibleNavigation: accessibleNavigation,
      ),
      child: child!,
    );
    return bundle == null
        ? scaled
        : DefaultAssetBundle(bundle: bundle, child: scaled);
  },
  home: home,
);

class _MissingAircraftBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) {
    if (key == _a350Asset) {
      return Future<ByteData>.error(FlutterError('Aircraft art unavailable'));
    }
    return rootBundle.load(key);
  }
}

void _setSurface(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Finder _art(String key) => find.byKey(ValueKey('aircraft-art-$key'));
Finder _flightRow(String id) =>
    find.byKey(ValueKey('aircraft-detail-flight-$id'));
Finder get _verticalScrollable => find.byWidgetPredicate(
  (widget) =>
      widget is Scrollable && widget.axisDirection == AxisDirection.down,
);

String _textAt(Finder finder) => [
  ...finder.evaluate().map((element) => element.widget).whereType<Text>(),
  ...find
      .descendant(of: finder, matching: find.byType(Text))
      .evaluate()
      .map((element) => element.widget)
      .whereType<Text>(),
].map((text) => text.data ?? text.textSpan?.toPlainText() ?? '').join(' ');

void _expectDate(String key, DateTime date, String locale) {
  final finder = find.byKey(ValueKey(key));
  expect(finder, findsOneWidget);
  expect(
    _textAt(finder),
    anyOf(
      contains(DateFormat('yyyy-MM-dd').format(date.toLocal())),
      contains(DateFormat.yMMMd(locale).format(date.toLocal())),
    ),
  );
}

Widget _buildFlight(BuildContext context, Flight flight) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 12),
  child: Text(
    '${flight.flightNumber}: ${flight.departureIata} → ${flight.arrivalIata}',
  ),
);

void main() {
  testWidgets(
    'detail summary shares two column anchors and preserves complete artwork',
    (tester) async {
      _setSurface(tester, const Size(400, 1000));
      await tester.pumpWidget(
        _host(
          AircraftCollectionDetailPage(
            entry: _entry(),
            flightBuilder: _buildFlight,
          ),
          locale: const Locale('zh'),
        ),
      );
      await tester.pumpAndSettle();
      Rect bounds(String key) => tester.getRect(find.byKey(ValueKey(key)));
      final count = bounds('aircraft-detail-count');
      final distance = bounds('aircraft-detail-distance');
      final first = bounds('aircraft-detail-first-flight');
      final latest = bounds('aircraft-detail-latest-flight');
      expect(count.top, distance.top);
      expect(first.top, latest.top);
      expect(first.left, count.left);
      expect(latest.left, distance.left);
      expect(count.width, distance.width);
      expect(first.top, greaterThan(count.bottom));
      final artwork = tester.widget<AircraftExhibitArtwork>(
        find.byKey(const ValueKey('aircraft-detail-exhibit')),
      );
      expect(artwork.aspectRatio, 2.6);
      expect(find.text('A350'), findsOneWidget);
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('aircraft-detail-family-label')),
            )
            .style
            ?.color,
        AppThemeColors.light.displaySecondary.withValues(alpha: .11),
      );
      expect(tester.widget<Image>(_art('A350-900')).fit, BoxFit.contain);
      final image = tester.getRect(_art('A350-900'));
      expect(image.height, closeTo(image.width / 2.6, .01));
      expect(find.text('机型风格示意'), findsNothing);
      await tester.scrollUntilVisible(
        _flightRow('only'),
        200,
        scrollable: _verticalScrollable,
      );
      expect(find.text('MU-only: PEK → CAN'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('detail aircraft family text uses a restrained dark accent', (
    tester,
  ) async {
    _setSurface(tester, const Size(400, 1000));
    await tester.pumpWidget(
      _host(
        AircraftCollectionDetailPage(
          entry: _entry(),
          flightBuilder: _buildFlight,
        ),
        isLight: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('aircraft-detail-family-label')),
          )
          .style
          ?.color,
      AppThemeColors.dark.lime.withValues(alpha: .09),
    );
    expect(tester.widget<Image>(_art('A350-900')).fit, BoxFit.contain);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'detail summary stacks at large text without squeezing dates or values',
    (tester) async {
      _setSurface(tester, const Size(360, 1500));
      await tester.pumpWidget(
        _host(
          AircraftCollectionDetailPage(
            entry: _entry(),
            flightBuilder: _buildFlight,
          ),
          textScale: 2,
        ),
      );
      await tester.pumpAndSettle();
      final count = tester.getRect(
        find.byKey(const ValueKey('aircraft-detail-count')),
      );
      final distance = tester.getRect(
        find.byKey(const ValueKey('aircraft-detail-distance')),
      );
      final first = tester.getRect(
        find.byKey(const ValueKey('aircraft-detail-first-flight')),
      );
      expect(distance.left, count.left);
      expect(distance.top, greaterThan(count.bottom));
      expect(first.top, greaterThan(distance.bottom));
      expect(find.text('1 flight'), findsOneWidget);
      expect(find.text('1,200 km'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('detail artwork has no visible style caption in either locale', (
    tester,
  ) async {
    for (final locale in [const Locale('zh'), const Locale('en')]) {
      await tester.pumpWidget(
        _host(
          AircraftCollectionDetailPage(
            entry: _entry(),
            flightBuilder: _buildFlight,
          ),
          locale: locale,
        ),
      );
      await tester.pumpAndSettle();
      expect(_art('A350-900'), findsOneWidget);
      expect(find.text('机型风格示意'), findsNothing);
      expect(find.text('Aircraft style illustration'), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'collection opens a real detail page with the same artwork and native back',
    (tester) async {
      _setSurface(tester, const Size(700, 1400));
      final entry = _entry();
      var selections = 0;
      Flight? selectedFlight;
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (collectionContext) => AircraftCollectionPage(
                      items: [entry],
                      onAircraftSelected: (selected) {
                        selections++;
                        Navigator.of(collectionContext).push<void>(
                          MaterialPageRoute<void>(
                            builder: (_) => AircraftCollectionDetailPage(
                              entry: selected,
                              flightBuilder: (context, flight) => ListTile(
                                title: Text(flight.flightNumber!),
                                onTap: () => selectedFlight = flight,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                child: const Text('Open collection'),
              ),
            ),
          ),
          locale: const Locale('zh'),
        ),
      );
      await tester.tap(find.text('Open collection'));
      await tester.pumpAndSettle();
      final sourceHero = tester
          .widget<Hero>(
            find.ancestor(of: _art(entry.key), matching: find.byType(Hero)),
          )
          .tag;
      await tester.tap(find.byKey(ValueKey('aircraft-card-${entry.key}')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('aircraft-detail-page-${entry.key}')),
        findsOneWidget,
      );
      expect(find.byType(BottomSheet), findsNothing);
      expect(selections, 1);
      final destinationHero = tester.widget<Hero>(
        find.ancestor(of: _art(entry.key), matching: find.byType(Hero)),
      );
      expect(destinationHero.tag, sourceHero);
      expect(destinationHero.tag, aircraftArtworkHeroTag(entry.key));
      expect(
        tester.widget<Image>(_art(entry.key)).image,
        isA<AssetImage>().having(
          (image) => image.assetName,
          'assetName',
          _a350Asset,
        ),
      );
      await tester.tap(find.text(entry.flights.single.flightNumber!));
      expect(selectedFlight, same(entry.flights.single));
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(AircraftCollectionPage), findsOneWidget);
      expect(find.byType(AircraftCollectionDetailPage), findsNothing);
      expect(_art(entry.key), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Open collection'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('uses min/max dates and renders unique real flights newest first', (
    tester,
  ) async {
    _setSurface(tester, const Size(700, 1800));
    final oldest = _flight('oldest', DateTime(2024, 6, 12));
    final middle = _flight('middle', DateTime(2025, 7, 18));
    final latest = _flight('latest', DateTime(2026, 9, 23));
    final source = [middle, oldest, latest, middle];
    final entry = _entry(flights: source);
    final built = <Flight>[];
    await tester.pumpWidget(
      _host(
        AircraftCollectionDetailPage(
          entry: entry,
          flightBuilder: (context, flight) {
            built.add(flight);
            return _buildFlight(context, flight);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    _expectDate('aircraft-detail-first-flight', oldest.departedAt, 'en');
    _expectDate('aircraft-detail-latest-flight', latest.departedAt, 'en');
    expect(find.text('3 flights'), findsOneWidget);
    expect(find.text('3,600 km'), findsOneWidget);
    for (final flight in [oldest, middle, latest]) {
      expect(_flightRow(flight.id), findsOneWidget);
      expect(
        find.text(
          '${flight.flightNumber}: ${flight.departureIata} → ${flight.arrivalIata}',
        ),
        findsOneWidget,
      );
      expect(built.where((item) => identical(item, flight)), isNotEmpty);
    }
    expect(built.map((flight) => flight.id).toSet(), {
      'latest',
      'middle',
      'oldest',
    });
    expect(
      tester.getTopLeft(_flightRow('latest')).dy,
      lessThan(tester.getTopLeft(_flightRow('middle')).dy),
    );
    expect(
      tester.getTopLeft(_flightRow('middle')).dy,
      lessThan(tester.getTopLeft(_flightRow('oldest')).dy),
    );
    expect(entry.flights, orderedEquals(source));
    expect(source, [middle, oldest, latest, middle]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('supports narrow/wide layouts and both themes at 2x text', (
    tester,
  ) async {
    _setSurface(tester, const Size(360, 1600));
    const type = 'B777-300ER Long Range International Aircraft Edition';
    final entry = _entry(
      type: type,
      manufacturer: AircraftManufacturer.boeing,
      flights: [_flight('only', DateTime(2026, 3, 4), type: type)],
    );
    for (final width in [360.0, 700.0]) {
      tester.view.physicalSize = Size(width, 1600);
      for (final isLight in [true, false]) {
        await tester.pumpWidget(
          _host(
            AircraftCollectionDetailPage(
              entry: entry,
              flightBuilder: _buildFlight,
            ),
            isLight: isLight,
            textScale: 2,
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(ValueKey('aircraft-detail-page-$type')),
          findsOneWidget,
        );
        expect(find.text('Aircraft illustration coming soon'), findsOneWidget);
        expect(find.byType(Image), findsNothing);
        await tester.scrollUntilVisible(
          _flightRow('only'),
          200,
          scrollable: _verticalScrollable,
        );
        expect(find.text('MU-only: PEK → CAN'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets('keeps partial and unrecorded mileage honest', (tester) async {
    _setSurface(tester, const Size(700, 1400));
    await tester.pumpWidget(
      _host(
        AircraftCollectionDetailPage(
          entry: _entry(
            flights: [
              _flight('recorded', DateTime(2026, 1, 1), distance: 1800),
              _flight('missing', DateTime(2026, 2, 1), distance: null),
            ],
          ),
          flightBuilder: _buildFlight,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1,800 km'), findsOneWidget);
    expect(find.text('Recorded distance'), findsOneWidget);
    expect(find.text('1,800 km total'), findsNothing);
    await tester.pumpWidget(
      _host(
        AircraftCollectionDetailPage(
          entry: _entry(
            type: 'UNKNOWN A350-1000',
            flights: [
              _flight(
                'missing',
                DateTime(2026, 2, 1),
                distance: null,
                type: 'UNKNOWN A350-1000',
              ),
            ],
          ),
          flightBuilder: _buildFlight,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Distance not recorded'), findsOneWidget);
    expect(find.text('0 km total'), findsNothing);
    expect(find.text('Aircraft illustration coming soon'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'an empty flight list is safe and does not invent dates or rows',
    (tester) async {
      var builderCalls = 0;
      await tester.pumpWidget(
        _host(
          AircraftCollectionDetailPage(
            entry: _entry(flights: const []),
            flightBuilder: (context, flight) {
              builderCalls++;
              return _buildFlight(context, flight);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AircraftCollectionDetailPage), findsOneWidget);
      expect(builderCalls, 0);
      await tester.scrollUntilVisible(
        find.text('No flights recorded for this aircraft yet'),
        260,
        scrollable: _verticalScrollable,
      );
      expect(
        find.text('No flights recorded for this aircraft yet'),
        findsOneWidget,
      );
      for (final key in [
        'aircraft-detail-first-flight',
        'aircraft-detail-latest-flight',
      ]) {
        expect(find.byKey(ValueKey(key)), findsNothing);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a failed specific asset shows an unavailable fallback in detail',
    (tester) async {
      await tester.pumpWidget(
        _host(
          AircraftCollectionDetailPage(
            entry: _entry(),
            flightBuilder: _buildFlight,
          ),
          bundle: _MissingAircraftBundle(),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('aircraft-art-fallback-A350-900')),
        findsOneWidget,
      );
      expect(find.text('Aircraft illustration unavailable'), findsOneWidget);
      expect(find.text('Aircraft illustration coming soon'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final accessibleNavigation in [false, true]) {
    testWidgets(
      'detail respects ${accessibleNavigation ? 'accessibleNavigation' : 'disableAnimations'} for Hero',
      (tester) async {
        await tester.pumpWidget(
          _host(
            AircraftCollectionDetailPage(
              entry: _entry(),
              flightBuilder: _buildFlight,
            ),
            disableAnimations: !accessibleNavigation,
            accessibleNavigation: accessibleNavigation,
          ),
        );
        final artwork = _art('A350-900');
        final position = tester.getTopLeft(artwork);
        for (final hero
            in find
                .ancestor(of: artwork, matching: find.byType(Hero))
                .evaluate()) {
          var disabled = false;
          hero.visitAncestorElements((element) {
            final widget = element.widget;
            if (widget is HeroMode && !widget.enabled) disabled = true;
            return true;
          });
          expect(disabled, isTrue);
        }
        await tester.pump(const Duration(milliseconds: 520));
        expect(tester.getTopLeft(artwork), position);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
