import 'package:flight_footprint/core/localization/app_strings.dart';
import 'package:flight_footprint/domain/flight.dart';
import 'package:flight_footprint/features/stats/aircraft_artwork.dart';
import 'package:flight_footprint/features/stats/aircraft_collection.dart';
import 'package:flight_footprint/features/stats/aircraft_collection_detail_page.dart';
import 'package:flight_footprint/features/stats/aircraft_collection_overview_card.dart';
import 'package:flight_footprint/features/stats/aircraft_collection_page.dart';
import 'package:flight_footprint/features/stats/aircraft_poster_card.dart';
import 'package:flight_footprint/ui/theme/app_theme.dart';
import 'package:flight_footprint/ui/widgets/perspective_card_deck.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _a350Asset = 'assets/images/aircraft/a350-900-side-right-v3.png';

AircraftCollectionEntry _aircraft(
  String type,
  AircraftManufacturer manufacturer,
  int count, {
  double? distance = 1200,
  String? idPrefix,
}) => AircraftCollectionEntry(
  key: type,
  type: type,
  manufacturer: manufacturer,
  flights: List.generate(
    count,
    (index) => Flight(
      id: '${idPrefix ?? type}-$index',
      departureIata: 'PVG',
      arrivalIata: 'PEK',
      departedAt: DateTime(2026, 1, index + 1),
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      aircraftType: type,
      distanceKm: distance,
    ),
  ),
);

List<AircraftCollectionEntry> _entries() => [
  _aircraft('B777-300ER', AircraftManufacturer.boeing, 2),
  _aircraft('A350-1000', AircraftManufacturer.airbus, 3),
  _aircraft('A350-900', AircraftManufacturer.airbus, 5),
  _aircraft('COMAC C919', AircraftManufacturer.other, 1, distance: null),
];

Widget _host(
  Widget home, {
  bool isLight = true,
  Locale locale = const Locale('zh'),
  double textScale = 1,
  AssetBundle? bundle,
  bool disableAnimations = false,
  bool accessibleNavigation = false,
  TargetPlatform? platform,
}) => MaterialApp(
  theme: (isLight ? AppTheme.light() : AppTheme.dark()).copyWith(
    platform: platform,
  ),
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

Finder _card(String key) => find.byKey(ValueKey('aircraft-card-$key'));
Finder _art(String key) => find.byKey(ValueKey('aircraft-art-$key'));
Finder _active(String key) => find.byKey(ValueKey('aircraft-active-$key'));

Future<void> _nextCard(WidgetTester tester) async {
  Focus.of(tester.element(find.byKey(const ValueKey('deck-card-stack'))))
      .requestFocus();
  await tester.pump();
  await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
  await tester.pumpAndSettle();
}

String _assetName(Image image) {
  final provider = image.image is ResizeImage
      ? (image.image as ResizeImage).imageProvider
      : image.image;
  expect(provider, isA<AssetImage>());
  return (provider as AssetImage).assetName;
}

void _expectHeroDisabled(Finder art) {
  for (final hero
      in find.ancestor(of: art, matching: find.byType(Hero)).evaluate()) {
    var disabled = false;
    hero.visitAncestorElements((element) {
      final widget = element.widget;
      if (widget is HeroMode && !widget.enabled) disabled = true;
      return true;
    });
    expect(disabled, isTrue, reason: 'Reduce Motion must disable the art Hero');
  }
}

void main() {
  testWidgets(
    'replacing a pressed card safely ignores its remaining pointer events',
    (tester) async {
      _setSurface(tester, const Size(360, 800));
      await tester.pumpWidget(
        _host(
          AircraftCollectionPage(items: _entries(), onAircraftSelected: (_) {}),
        ),
      );
      await tester.pumpAndSettle();
      final pointer = await tester.startGesture(
        tester.getCenter(_card('A350-900')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('aircraft-filter-boeing')));
      await tester.pumpAndSettle();
      expect(_card('A350-900'), findsNothing);
      await pointer.moveBy(const Offset(0, -110));
      await tester.pump();
      await pointer.up();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('compact poster metrics fit fractional widths and text scales', (
    tester,
  ) async {
    _setSurface(tester, const Size(411.428571, 900));
    for (final scale in [1.0, 1.015625, 1.125, 1.2]) {
      const width = 347.462857;
      await tester.pumpWidget(
        _host(
          Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                height: (width - 40) / 2.35 + 180 * scale,
                child: AircraftPosterCard(
                  model: 'B737 MAX 8',
                  manufacturer: '波音',
                  countLabel: '12 次',
                  distanceLabel: '累计 21,680 km',
                  compact: true,
                  depth: 1.47,
                  onTap: () {},
                  artwork: const AspectRatio(
                    aspectRatio: 2.35,
                    child: SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ),
          textScale: scale,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('12 次'), findsOneWidget);
      expect(find.text('累计 21,680 km'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('native iOS back keeps the original card visible', (
    tester,
  ) async {
    _setSurface(tester, const Size(360, 800));
    await tester.pumpWidget(
      _host(
        AircraftCollectionPage(
          items: _entries(),
          detailBuilder: (_, entry) => Scaffold(
            appBar: AppBar(title: Text(entry.type)),
            body: const Text('Native detail'),
          ),
        ),
        platform: TargetPlatform.iOS,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(_card('A350-900'));
    await tester.pumpAndSettle();
    final source = find.byKey(
      const ValueKey('aircraft-source-A350-900'),
      skipOffstage: false,
    );
    expect(tester.widget<Opacity>(source).opacity, 1);
    // The app uses a Material AppBar on this native Cupertino route.
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(_active('A350-900'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'tap flips into the real detail once and restores the selected card on back',
    (tester) async {
      _setSurface(tester, const Size(360, 800));
      var detailBuilds = 0;
      await tester.pumpWidget(
        _host(
          AircraftCollectionPage(
            items: _entries(),
            detailBuilder: (context, entry) {
              detailBuilds++;
              return AircraftCollectionDetailPage(
                entry: entry,
                flightBuilder: (context, flight) => Text(flight.id),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _nextCard(tester);
      final press = find.byKey(const ValueKey('aircraft-card-press-A350-1000'));
      final pointer = await tester.startGesture(
        tester.getCenter(_card('A350-1000')),
      );
      await tester.pump(const Duration(milliseconds: 40));
      expect(tester.widget<AnimatedScale>(press).scale, .985);
      await pointer.up();
      // A second tap before the route's first frame cannot push a duplicate.
      await tester.tap(_card('A350-1000'), warnIfMissed: false);
      await tester.pump();
      expect(
        tester
            .widget<Opacity>(
              find.byKey(const ValueKey('aircraft-source-A350-1000')),
            )
            .opacity,
        1,
        reason: 'The source covers the offstage measurement frame',
      );
      // The first route frame measures the offstage destination.
      await tester.pump();
      expect(
        find.byKey(const ValueKey('aircraft-flip-transform')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Opacity>(
              find.byKey(const ValueKey('aircraft-source-A350-1000')),
            )
            .opacity,
        0,
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('aircraft-detail-page-A350-1000')),
        findsOneWidget,
      );
      expect(detailBuilds, 1);
      await tester.tap(find.byType(BackButton));
      await tester.pump();
      expect(
        tester
            .widget<Opacity>(
              find.byKey(const ValueKey('aircraft-source-A350-1000')),
            )
            .opacity,
        0,
        reason: 'Source stays hidden during the reverse flip',
      );
      await tester.pump(const Duration(milliseconds: 380));
      expect(
        tester
            .widget<Opacity>(
              find.byKey(const ValueKey('aircraft-source-A350-1000')),
            )
            .opacity,
        1,
        reason: 'Source is painted before the reverse overlay is removed',
      );
      await tester.pumpAndSettle();
      expect(_active('A350-1000'), findsOneWidget);
      expect(
        tester
            .widget<Opacity>(
              find.byKey(const ValueKey('aircraft-source-A350-1000')),
            )
            .opacity,
        1,
      );
      await tester.tap(_card('A350-1000'));
      await tester.pumpAndSettle();
      expect(detailBuilds, 2);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('detail builder respects reduced motion from the collection', (
    tester,
  ) async {
    _setSurface(tester, const Size(360, 800));
    await tester.pumpWidget(
      _host(
        AircraftCollectionPage(
          items: _entries(),
          detailBuilder: (context, entry) =>
              Scaffold(appBar: AppBar(title: Text('Detail ${entry.type}'))),
        ),
        disableAnimations: true,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(_card('A350-900'));
    await tester.pump();
    expect(find.byKey(const ValueKey('aircraft-flip-transform')), findsNothing);
    await tester.pumpAndSettle();
    expect(find.text('Detail A350-900'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'aircraft lag survives becoming active and filters do not replay entrance',
    (tester) async {
      _setSurface(tester, const Size(360, 800));
      await tester.pumpWidget(
        _host(
          AircraftCollectionPage(items: _entries(), onAircraftSelected: (_) {}),
        ),
      );
      await tester.pumpAndSettle();
      final motion = find.byKey(const ValueKey('aircraft-motion-A350-1000'));
      final before = tester.state(motion);
      final start =
          tester.getTopLeft(find.byKey(const ValueKey('perspective-deck'))) +
          const Offset(160, 220);
      final gesture = await tester.startGesture(start);
      await gesture.moveBy(const Offset(0, -24));
      await tester.pump(const Duration(milliseconds: 20));
      await gesture.moveBy(const Offset(0, -110));
      await tester.pump(const Duration(milliseconds: 20));
      expect(_active('A350-1000'), findsOneWidget);
      expect(tester.state(motion), same(before));
      await tester.pump(const Duration(milliseconds: 400));
      await gesture.up();
      await tester.pumpAndSettle();
      final transform = tester.widget<Transform>(
        find.byKey(const ValueKey('aircraft-parallax-A350-1000')),
      );
      expect(transform.transform.storage, Matrix4.identity().storage);
      await tester.tap(find.byKey(const ValueKey('aircraft-filter-airbus')));
      await tester.pump();
      final deckTransform = tester.widget<Transform>(
        find.byKey(const ValueKey('deck-card-transform-0')),
      );
      expect(
        deckTransform.transform.storage[0],
        1,
        reason: 'Filters must not replay the opening scale',
      );
      expect(deckTransform.transform.storage[5], 1);
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'collection loops through all models without duplicating the active Hero',
    (tester) async {
      _setSurface(tester, const Size(360, 800));
      AircraftCollectionEntry? selected;
      await tester.pumpWidget(
        _host(
          AircraftCollectionPage(
            items: _entries(),
            onAircraftSelected: (entry) => selected = entry,
          ),
        ),
      );
      await tester.pumpAndSettle();
      Focus.of(tester.element(find.byKey(const ValueKey('deck-card-stack'))))
          .requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(_active('COMAC C919'), findsOneWidget);
      await _nextCard(tester);
      expect(_active('A350-900'), findsOneWidget);
      expect(find.byType(Hero), findsOneWidget);
      await tester.tap(_card('A350-900'));
      expect(selected?.type, 'A350-900');
      for (var i = 0; i < 4; i++) {
        await _nextCard(tester);
      }
      expect(_active('A350-900'), findsOneWidget);
      expect(find.byType(Hero), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('aircraft-filter-airbus')));
      await tester.pumpAndSettle();
      for (var i = 0; i < 3; i++) {
        await _nextCard(tester);
        expect(find.byType(Hero), findsOneWidget);
      }
      expect(_active('A350-1000'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('overview opens the collection, selects once, and goes back', (
    tester,
  ) async {
    _setSurface(tester, const Size(360, 900));
    final items = _entries();
    AircraftCollectionEntry? selected;
    var selections = 0;
    await tester.pumpWidget(
      _host(
        Builder(
          builder: (context) => Scaffold(
            body: AircraftCollectionOverviewCard(
              aircraftCount: items.length,
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => AircraftCollectionPage(
                    items: items,
                    onAircraftSelected: (entry) {
                      selected = entry;
                      selections++;
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('已搭乘 4 种机型'), findsOneWidget);
    await tester.tap(find.byType(AircraftCollectionOverviewCard));
    await tester.pumpAndSettle();
    expect(find.byType(AircraftCollectionPage), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(
      find.byKey(const ValueKey('aircraft-collection-summary')),
      findsOneWidget,
    );
    expect(find.text('通用客机示意'), findsNothing);
    await tester.tap(_card('A350-900'));
    expect(selected, same(items[2]));
    expect(selections, 1);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(AircraftCollectionOverviewCard), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'known models have distinct artwork and unknown models fall back',
    (tester) async {
      _setSurface(tester, const Size(700, 2400));
      final items = [
        ..._entries(),
        _aircraft('A320-200', AircraftManufacturer.airbus, 1),
        _aircraft('A321LR', AircraftManufacturer.airbus, 1),
        _aircraft('A321NEO', AircraftManufacturer.airbus, 1),
        _aircraft('A330-300', AircraftManufacturer.airbus, 1),
        _aircraft('A330-900NEO', AircraftManufacturer.airbus, 1),
        _aircraft('A380-800', AircraftManufacturer.airbus, 1),
        _aircraft('B737 MAX 8', AircraftManufacturer.boeing, 1),
        _aircraft('B737 MAX 9', AircraftManufacturer.boeing, 1),
        _aircraft('B737-800', AircraftManufacturer.boeing, 1),
        _aircraft('B787-10', AircraftManufacturer.boeing, 1),
        _aircraft('B787-8', AircraftManufacturer.boeing, 1),
        _aircraft('B787-9', AircraftManufacturer.boeing, 1),
        _aircraft('E190-E2', AircraftManufacturer.other, 1),
        _aircraft('UNKNOWN A350-900', AircraftManufacturer.other, 1),
      ];
      await tester.pumpWidget(
        _host(AircraftCollectionPage(items: items, onAircraftSelected: (_) {})),
      );
      await tester.pumpAndSettle();
      final artwork = _art('A350-900');
      expect(artwork, findsOneWidget);
      expect(_assetName(tester.widget<Image>(artwork)), _a350Asset);
      final hero = tester.widget<Hero>(
        find.ancestor(of: artwork, matching: find.byType(Hero)),
      );
      expect(hero.tag, aircraftArtworkHeroTag('A350-900'));
      for (final type in [
        'A350-1000',
        'B777-300ER',
        'A320-200',
        'A321LR',
        'A321NEO',
        'A330-300',
        'A330-900NEO',
        'A380-800',
        'B737 MAX 8',
        'B737 MAX 9',
        'B737-800',
        'B787-10',
        'B787-8',
        'B787-9',
        'COMAC C919',
        'E190-E2',
        'UNKNOWN A350-900',
      ]) {
        final card = _card(type);
        await _nextCard(tester);
        expect(card, findsOneWidget);
        final expectedAsset = aircraftArtworkAssetFor(type);
        if (expectedAsset == null) {
          expect(
            find.descendant(of: card, matching: find.byType(Image)),
            findsNothing,
          );
          expect(
            find.descendant(of: card, matching: find.text('外观图待补充')),
            findsOneWidget,
          );
          expect(
            find.descendant(of: card, matching: find.byType(Icon)),
            findsWidgets,
          );
          continue;
        }
        final art = _art(type);
        expect(art, findsOneWidget);
        expect(
          find.descendant(
            of: card,
            matching: find.byKey(ValueKey('aircraft-art-fallback-$type')),
          ),
          findsNothing,
        );
        expect(_assetName(tester.widget<Image>(art)), expectedAsset);
        expect(
          tester
              .widget<Hero>(find.ancestor(of: art, matching: find.byType(Hero)))
              .tag,
          aircraftArtworkHeroTag(type),
        );
      }
      expect(find.text('通用客机示意'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'orders the active exhibit and filters without changing the total',
    (tester) async {
      _setSurface(tester, const Size(700, 2000));
      await tester.pumpWidget(
        _host(
          AircraftCollectionPage(items: _entries(), onAircraftSelected: (_) {}),
        ),
      );
      await tester.pumpAndSettle();
      expect(_active('A350-900'), findsOneWidget);
      expect(_active('A350-1000'), findsNothing);
      expect(_active('B777-300ER'), findsNothing);
      await _nextCard(tester);
      expect(_active('A350-1000'), findsOneWidget);
      expect(_active('A350-900'), findsNothing);
      await _nextCard(tester);
      expect(_active('B777-300ER'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('aircraft-filter-boeing')));
      await tester.pumpAndSettle();
      expect(find.text('A350-900'), findsNothing);
      expect(find.text('A350-1000'), findsNothing);
      expect(find.text('B777-300ER'), findsOneWidget);
      expect(find.text('已搭乘 4 种机型'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('aircraft-filter-other')));
      await tester.pumpAndSettle();
      expect(find.text('COMAC C919'), findsOneWidget);
      expect(find.text('里程未记录'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('aircraft-filter-airbus')));
      await tester.pumpAndSettle();
      expect(find.text('A350-900'), findsOneWidget);
      expect(find.text('A350-1000'), findsOneWidget);
      expect(find.text('B777-300ER'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('aircraft-filter-all')));
      await tester.pumpAndSettle();
      expect(_active('B777-300ER'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('handles an empty collection and a filter with no results', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        AircraftCollectionPage(items: const [], onAircraftSelected: (_) {}),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('还没有机型记录'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    await tester.pumpWidget(
      _host(
        AircraftCollectionPage(
          items: [_aircraft('A350-900', AircraftManufacturer.airbus, 1)],
          onAircraftSelected: (_) {},
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('aircraft-filter-boeing')));
    await tester.pumpAndSettle();
    expect(find.text('还没有搭乘这一制造商的机型'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'narrow/wide layouts and both themes support long names at 2x text',
    (tester) async {
      _setSurface(tester, const Size(360, 1400));
      const longType = 'Airbus A321neo Long Range International Edition';
      for (final width in [360.0, 700.0, 960.0]) {
        tester.view.physicalSize = Size(width, 1400);
        for (final isLight in [true, false]) {
          await tester.pumpWidget(
            _host(
              AircraftCollectionPage(
                items: [
                  _aircraft(
                    longType,
                    AircraftManufacturer.airbus,
                    125,
                    distance: 8000,
                  ),
                ],
                onAircraftSelected: (_) {},
              ),
              textScale: 2,
              locale: const Locale('en'),
              isLight: isLight,
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text(longType), findsOneWidget);
          expect(
            find.text('Aircraft illustration coming soon'),
            findsOneWidget,
          );
          expect(find.text('Generic aircraft illustration'), findsNothing);
          final card = _card(longType);
          await tester.ensureVisible(card);
          await tester.pumpAndSettle();
          final bounds = tester.getRect(card);
          expect(bounds.width, lessThanOrEqualTo(700));
          for (final metric in ['125 flights', '1,000,000 km total']) {
            final metricBounds = tester.getRect(find.text(metric));
            expect(metricBounds.left, greaterThanOrEqualTo(bounds.left));
            expect(metricBounds.right, lessThanOrEqualTo(bounds.right));
            expect(metricBounds.bottom, lessThanOrEqualTo(bounds.bottom));
          }
          expect(tester.takeException(), isNull);
        }
      }
    },
  );

  testWidgets(
    'whole card announces the full model, manufacturer, and metrics',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          _host(
            AircraftCollectionPage(
              items: [_aircraft('A350-900', AircraftManufacturer.airbus, 2)],
              onAircraftSelected: (_) {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.getSemantics(_card('A350-900')),
          matchesSemantics(
            label: 'A350-900, 空客, 2 次, 累计 2,400 km',
            isButton: true,
            hasTapAction: true,
          ),
        );
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'normal decks contain the active card and short screens use a list',
    (tester) async {
      _setSurface(tester, const Size(360, 1000));
      for (final width in [360.0, 700.0, 960.0]) {
        tester.view.physicalSize = Size(width, 1000);
        for (final textScale in [1.0, 1.2]) {
          for (final isLight in [true, false]) {
            await tester.pumpWidget(
              _host(
                AircraftCollectionPage(
                  items: _entries(),
                  onAircraftSelected: (_) {},
                ),
                textScale: textScale,
                isLight: isLight,
              ),
            );
            await tester.pumpAndSettle();
            final deck = tester.widget<PerspectiveCardDeck>(
              find.byType(PerspectiveCardDeck),
            );
            expect(deck.flipInPlace, isFalse);
            expect(deck.recycleArc, isFalse);
            expect(deck.cycleDepth, isTrue);
            expect(deck.showControls, isFalse);
            expect(find.byKey(const ValueKey('deck-position')), findsNothing);
            expect(find.byKey(const ValueKey('deck-next')), findsNothing);
            expect(find.text('累计 · 按搭乘次数排序'), findsNothing);
            final bounds = tester.getRect(_active('A350-900'));
            final viewport = tester.getRect(
              find.byKey(const ValueKey('perspective-deck')),
            );
            expect(bounds.left, greaterThanOrEqualTo(viewport.left));
            expect(bounds.right, lessThanOrEqualTo(viewport.right));
            expect(bounds.top, greaterThanOrEqualTo(viewport.top));
            expect(bounds.bottom, lessThanOrEqualTo(viewport.bottom));
            expect(tester.takeException(), isNull);
          }
        }
      }
      tester.view.physicalSize = const Size(360, 500);
      await tester.pumpWidget(
        _host(
          AircraftCollectionPage(items: _entries(), onAircraftSelected: (_) {}),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const PageStorageKey('aircraft-collection-list')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('perspective-deck')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a missing model asset shows the unavailable fallback safely', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        AircraftCollectionPage(
          items: [_aircraft('A350-900', AircraftManufacturer.airbus, 1)],
          onAircraftSelected: (_) {},
        ),
        bundle: _MissingAircraftBundle(),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('aircraft-art-fallback-A350-900')),
      findsOneWidget,
    );
    expect(find.text('外观图暂不可用'), findsOneWidget);
    expect(find.text('A350-900'), findsOneWidget);
    expect(find.text('外观图待补充'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'partial mileage stays recorded and unknown mileage stays unknown',
    (tester) async {
      _setSurface(tester, const Size(700, 1400));
      final recorded = _aircraft('A350-900', AircraftManufacturer.airbus, 1);
      final missing = _aircraft(
        'A350-900',
        AircraftManufacturer.airbus,
        2,
        distance: null,
        idPrefix: 'missing',
      );
      await tester.pumpWidget(
        _host(
          AircraftCollectionPage(
            items: [
              AircraftCollectionEntry(
                key: 'A350-900',
                type: 'A350-900',
                manufacturer: AircraftManufacturer.airbus,
                flights: [recorded.flights.single, ...missing.flights],
              ),
              _aircraft(
                'B777-300ER',
                AircraftManufacturer.boeing,
                1,
                distance: null,
              ),
            ],
            onAircraftSelected: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('已记录 1,200 km'), findsOneWidget);
      expect(find.text('累计 1,200 km'), findsNothing);
      await _nextCard(tester);
      expect(find.text('里程未记录'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final accessibleNavigation in [false, true]) {
    testWidgets(
      '${accessibleNavigation ? 'accessibleNavigation' : 'disableAnimations'} disables entrance and Hero motion',
      (tester) async {
        await tester.pumpWidget(
          _host(
            AircraftCollectionPage(
              items: [_aircraft('A350-900', AircraftManufacturer.airbus, 1)],
              onAircraftSelected: (_) {},
            ),
            disableAnimations: !accessibleNavigation,
            accessibleNavigation: accessibleNavigation,
          ),
        );
        final artwork = _art('A350-900');
        final before = tester.getTopLeft(artwork);
        _expectHeroDisabled(artwork);
        await tester.pump(const Duration(milliseconds: 260));
        expect(tester.getTopLeft(artwork), before);
        await tester.pump(const Duration(milliseconds: 520));
        expect(tester.getTopLeft(artwork), before);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'returning from detail and changing filters preserve the selected exhibit',
    (tester) async {
      _setSurface(tester, const Size(360, 800));
      final items = _entries();
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) => AircraftCollectionPage(
              items: items,
              onAircraftSelected: (entry) => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    appBar: AppBar(title: Text('Detail ${entry.type}')),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _nextCard(tester);
      expect(_active('A350-1000'), findsOneWidget);
      await tester.tap(_active('A350-1000'));
      await tester.pumpAndSettle();
      expect(find.text('Detail A350-1000'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(_active('A350-1000'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('aircraft-filter-boeing')));
      await tester.pumpAndSettle();
      expect(_art('A350-1000'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('aircraft-filter-all')));
      await tester.pumpAndSettle();
      expect(_active('A350-1000'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('overview supports large text and announces the whole action', (
    tester,
  ) async {
    _setSurface(tester, const Size(360, 900));
    final semantics = tester.ensureSemantics();
    try {
      var taps = 0;
      await tester.pumpWidget(
        _host(
          Scaffold(
            body: AircraftCollectionOverviewCard(
              aircraftCount: 1,
              onTap: () => taps++,
            ),
          ),
          locale: const Locale('en'),
          textScale: 2,
          isLight: false,
        ),
      );
      expect(
        tester.getSemantics(find.byType(AircraftCollectionOverviewCard)),
        matchesSemantics(
          label: 'Aircraft collection, 1 aircraft type flown',
          isButton: true,
          hasTapAction: true,
        ),
      );
      await tester.tap(find.byType(AircraftCollectionOverviewCard));
      expect(taps, 1);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });
}
