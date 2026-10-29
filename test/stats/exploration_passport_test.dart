import 'package:flight_footprint/core/localization/app_strings.dart';
import 'package:flight_footprint/domain/airport.dart';
import 'package:flight_footprint/features/stats/continent_exploration_card.dart';
import 'package:flight_footprint/features/stats/exploration_map_artwork.dart';
import 'package:flight_footprint/features/stats/exploration_passport.dart';
import 'package:flight_footprint/features/stats/farthest_footprint_card.dart';
import 'package:flight_footprint/features/stats/personal_travel_summary.dart';
import 'package:flight_footprint/features/stats/world_exploration.dart';
import 'package:flight_footprint/ui/theme/app_theme.dart';
import 'package:flight_footprint/ui/widgets/app_widgets.dart';
import 'package:flight_footprint/ui/widgets/country_flag.dart';
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

final _places = [
  const ExplorationPlace(
    name: 'Singapore',
    countryCode: 'SG',
    latitude: 1.35,
    longitude: 103.82,
  ),
  const ExplorationPlace(
    name: 'London',
    countryCode: 'GB',
    latitude: 51.5,
    longitude: -.12,
  ),
  const ExplorationPlace(
    name: 'Cape Town',
    countryCode: 'ZA',
    latitude: -33.92,
    longitude: 18.42,
  ),
  const ExplorationPlace(
    name: 'San Francisco',
    countryCode: 'US',
    latitude: 37.77,
    longitude: -122.42,
  ),
  ExplorationPlace(
    name: 'São Paulo',
    countryCode: 'BR',
    latitude: -23.55,
    longitude: -46.63,
    visitedAt: DateTime(2026, 9, 10),
  ),
  const ExplorationPlace(
    name: 'Sydney',
    countryCode: 'AU',
    latitude: -33.87,
    longitude: 151.21,
  ),
];

Widget _host(
  Widget content, {
  bool light = false,
  double scale = 1,
  bool reduced = false,
  bool accessible = false,
  Locale locale = const Locale('en'),
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
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      textScaler: TextScaler.linear(scale),
      disableAnimations: reduced,
      accessibleNavigation: accessible,
    ),
    child: child!,
  ),
  home: Scaffold(body: SafeArea(child: content)),
);

void _surface(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

ExplorationPassport _passport({
  Airport? home,
  VoidCallback? choose,
  PersonalTravelSummary? memorySummary,
}) => ExplorationPassport(
  places: _places,
  worldCount: 6,
  home: home,
  homeLoaded: true,
  onChooseHome: choose ?? () {},
  memorySummary: memorySummary,
);

Finder get _mementoMaps => find.descendant(
  of: find.byType(FarthestFootprintCard),
  matching: find.byType(ExplorationMapArtwork),
);

int _displayedDistance(WidgetTester tester) {
  final metric = tester.widget<Text>(
    find.byKey(const ValueKey('farthest-footprint-distance-value')),
  );
  return int.parse(
    metric.textSpan!.toPlainText().replaceAll(RegExp(r'\D'), ''),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async => ExplorationMapArtwork.preload());

  testWidgets(
    'passport groups exploration results and gives Antarctica a full row',
    (tester) async {
      _surface(tester, const Size(430, 1600));
      var choices = 0;
      await tester.pumpWidget(_host(_passport(choose: () => choices++)));
      await tester.pumpAndSettle();
      expect(find.text('Countries/regions visited: 6'), findsNothing);
      expect(
        find.byKey(const ValueKey('exploration-visited-summary')),
        findsNothing,
      );
      expect(tester.getTopLeft(find.byType(FarthestFootprintCard)).dy, 20);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(
        find.byKey(const ValueKey('exploration-world-percent')),
        findsNothing,
      );
      expect(find.text('6 / 7 unlocked'), findsOneWidget);
      expect(find.byType(ContinentExplorationCard), findsNWidgets(7));
      final antarctica = find.byKey(
        const ValueKey('exploration-continent-antarctica'),
      );
      expect(tester.widget<ContinentExplorationCard>(antarctica).wide, isTrue);
      expect(tester.getSize(antarctica).width, closeTo(390, .1));
      await tester.tap(find.text('Set home city'));
      expect(choices, 1);
      expect(_mementoMaps, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('memento tightens top spacing without shrinking touch targets', (
    tester,
  ) async {
    _surface(tester, const Size(430, 1500));
    await tester.pumpWidget(_host(_passport(home: _home)));
    await tester.pumpAndSettle();
    final card = find.byType(FarthestFootprintCard);
    final surface = tester.widget<SurfaceCard>(
      find.descendant(of: card, matching: find.byType(SurfaceCard)),
    );
    expect(surface.showBorder, isFalse);
    expect(
      surface.padding.resolve(TextDirection.ltr),
      const EdgeInsets.fromLTRB(16, 12, 16, 20),
    );
    final edit = find.descendant(of: card, matching: find.byType(IconButton));
    final info = find.descendant(
      of: card,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Tooltip && widget.triggerMode == TooltipTriggerMode.tap,
      ),
    );
    for (final action in [edit, info]) {
      expect(tester.getSize(action).width, greaterThanOrEqualTo(48));
      expect(tester.getSize(action).height, greaterThanOrEqualTo(48));
    }
    expect(tester.getCenter(edit).dy, tester.getCenter(info).dy);
    final heading = find.byKey(const ValueKey('farthest-footprint-heading'));
    expect(tester.getRect(info).left - tester.getRect(heading).right, 8);
    expect(tester.getCenter(heading).dy, tester.getCenter(info).dy);
    expect(tester.getRect(edit).right, tester.getRect(card).right - 16);
    expect(tester.getRect(info).right, lessThan(tester.getRect(edit).left));
    final editIcon = tester.widget<IconButton>(edit).icon;
    expect(editIcon, isA<Icon>());
    expect((editIcon as Icon).size, 22);
    expect(
      tester.widget<Icon>(find.byIcon(Icons.info_outline_rounded)).size,
      18,
    );
    final distance = find.byKey(
      const ValueKey('farthest-footprint-distance-value'),
    );
    expect(
      tester.getRect(distance).top,
      greaterThan(tester.getRect(edit).bottom),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('info mark optically aligns without moving its touch target', (
    tester,
  ) async {
    _surface(tester, const Size(430, 1800));
    for (final locale in [const Locale('zh'), const Locale('en')]) {
      for (final scale in [1.0, 2.0]) {
        await tester.pumpWidget(
          _host(
            _passport(home: _home),
            locale: locale,
            scale: scale,
          ),
        );
        await tester.pumpAndSettle();
        final headerError = tester.takeException();
        expect(
          headerError,
          isNull,
          reason: headerError is FlutterError
              ? headerError.toStringDeep()
              : 'header grid at $locale scale=$scale: $headerError',
        );
        final title = find.byKey(const ValueKey('farthest-footprint-heading'));
        final icon = find.byIcon(Icons.info_outline_rounded);
        final target = find.ancestor(
          of: icon,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Tooltip &&
                widget.triggerMode == TooltipTriggerMode.tap,
          ),
        );
        expect(tester.getSize(target), const Size(48, 48));
        expect(tester.getCenter(target).dy, tester.getCenter(title).dy);
        expect(
          tester.getCenter(icon).dy - tester.getCenter(title).dy,
          closeTo(locale.languageCode == 'zh' ? 1.5 * scale : 0, .01),
        );
        expect(tester.getRect(target).contains(tester.getCenter(icon)), isTrue);
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets('memento presents the actual destination, country and date', (
    tester,
  ) async {
    _surface(tester, const Size(430, 1500));
    var choices = 0;
    await tester.pumpWidget(
      _host(_passport(home: _home, choose: () => choices++)),
    );
    await tester.pumpAndSettle();
    expect(find.text('São Paulo'), findsOneWidget);
    expect(find.text('Brazil'), findsOneWidget);
    expect(find.text('BR'), findsNothing);
    expect(find.text('Edit'), findsNothing);
    expect(find.text('Shanghai'), findsOneWidget);
    expect(find.text('Sep 10, 2026'), findsOneWidget);
    final home = find.byKey(const ValueKey('farthest-footprint-home'));
    final destination = find.byKey(
      const ValueKey('farthest-footprint-destination'),
    );
    final connection = find.byKey(
      const ValueKey('farthest-footprint-connection'),
    );
    final distance = find.byKey(
      const ValueKey('farthest-footprint-distance-value'),
    );
    final date = find.byKey(const ValueKey('farthest-footprint-date'));
    expect(tester.getRect(distance).top, lessThan(tester.getRect(home).top));
    expect(
      tester.getRect(connection).left,
      greaterThan(tester.getRect(home).right),
    );
    expect(
      tester.getRect(connection).right,
      lessThan(tester.getRect(destination).left),
    );
    expect(
      tester.getRect(destination).bottom,
      lessThan(tester.getRect(date).top),
    );
    expect(tester.getRect(home).overlaps(tester.getRect(distance)), isFalse);
    expect(tester.getSize(connection).width, greaterThan(40));
    expect(tester.getTopLeft(distance).dx, tester.getTopLeft(home).dx);
    expect(tester.widget<Text>(distance).textAlign, TextAlign.center);
    expect(
      tester.widget<Text>(distance).textSpan!.style!.fontSize,
      greaterThanOrEqualTo(40),
    );
    final flag = find.descendant(
      of: find.byType(FarthestFootprintCard),
      matching: find.byWidgetPredicate(
        (widget) => widget is CountryFlag && widget.size == 24,
      ),
    );
    expect(tester.widget<CountryFlag>(flag).code, 'BR');
    expect(tester.widget<CountryFlag>(flag).size, 24);
    expect(
      find.ancestor(of: connection, matching: find.byType(ExcludeSemantics)),
      findsOneWidget,
    );
    final painter = tester.widget<CustomPaint>(connection).painter!;
    expect(painter.shouldRepaint(painter), isFalse);
    expect(_mementoMaps, findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.tap(find.byTooltip('Set home city'));
    expect(choices, 1);
    await tester.tap(find.byIcon(Icons.info_outline_rounded));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Approximate straight-line distance'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('farthest card returns after a cut without losing its date', (
    tester,
  ) async {
    _surface(tester, const Size(411, 900));
    final summary = PersonalTravelSummary(
      year: 2026,
      newCities: const [],
      newAircraft: const [],
      frequentRoute: null,
    );
    for (final light in [false, true]) {
      await tester.pumpWidget(
        _host(
          _passport(home: _home, memorySummary: summary),
          locale: const Locale('zh'),
          light: light,
        ),
      );
      await tester.pumpAndSettle();
      final deck = find.byKey(const ValueKey('exploration-memory-deck'));
      await tester.drag(deck, const Offset(-180, 0));
      await tester.pumpAndSettle();
      await tester.drag(deck, const Offset(180, 0));
      await tester.pumpAndSettle();

      final farthest = find.byType(FarthestFootprintCard);
      final date = find.byKey(const ValueKey('farthest-footprint-date'));
      final surface = tester.widget<SurfaceCard>(
        find.descendant(of: farthest, matching: find.byType(SurfaceCard)),
      );
      expect(
        tester
            .widget<Semantics>(
              find.byKey(const ValueKey('exploration-memory-deck-semantics')),
            )
            .properties
            .value,
        '1 / 4',
      );
      expect(
        Theme.of(tester.element(farthest)).brightness,
        light ? Brightness.light : Brightness.dark,
      );
      expect(surface.color, tester.element(farthest).appColors.cardSurface);
      expect(date.hitTestable(), findsOneWidget);
      expect(
        tester.getRect(date).bottom,
        lessThanOrEqualTo(tester.getRect(farthest).bottom),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets(
    'home flag follows its country and stays beside the small label',
    (tester) async {
      _surface(tester, const Size(430, 1500));
      for (final code in ['CN', 'US', '', '???']) {
        final home = Airport(
          iataCode: _home.iataCode,
          latitude: _home.latitude,
          longitude: _home.longitude,
          name: _home.name,
          city: _home.city,
          countryCode: code,
        );
        await tester.pumpWidget(_host(_passport(home: home)));
        await tester.pumpAndSettle();
        final flag = find.byKey(const ValueKey('farthest-footprint-home-flag'));
        if (code.isEmpty || code == '???') {
          expect(flag, findsNothing);
        } else {
          expect(tester.widget<CountryFlag>(flag).code, code);
          expect(tester.widget<CountryFlag>(flag).size, 16);
          expect(tester.widget<CountryFlag>(flag).showBorder, isFalse);
          final label = find.byKey(
            const ValueKey('farthest-footprint-home-label'),
          );
          expect(tester.getRect(label).left - tester.getRect(flag).right, 6);
          expect(tester.getCenter(flag).dy, tester.getCenter(label).dy);
        }
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('unknown destination details never invent a country or date', (
    tester,
  ) async {
    _surface(tester, const Size(430, 900));
    await tester.pumpWidget(
      _host(
        FarthestFootprintCard(
          home: _home,
          farthest: const FarthestFootprint(
            place: ExplorationPlace(
              name: '',
              countryCode: '',
              latitude: -23.55,
              longitude: -46.63,
            ),
            distanceKm: 18000,
          ),
          homeLoaded: true,
          onChooseHome: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(FarthestFootprintCard));
    expect(find.text(context.strings.t('unknown')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('farthest-footprint-country')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('farthest-footprint-country-mark')),
      findsNothing,
    );
    expect(
      find.text(context.strings.t('photoFootprintDateUnknown')),
      findsOneWidget,
    );
    expect(_displayedDistance(tester), 18000);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a continent opens real visits in a dismissible bottom sheet', (
    tester,
  ) async {
    _surface(tester, const Size(430, 1700));
    await tester.pumpWidget(_host(_passport()));
    await tester.pumpAndSettle();
    final asia = find.byKey(const ValueKey('exploration-continent-asia'));
    final nextRow = find.byKey(
      const ValueKey('exploration-continent-northAmerica'),
    );
    final nextRowTop = tester.getRect(nextRow).top;
    await tester.tap(asia);
    await tester.pumpAndSettle();
    final detail = find.byKey(const ValueKey('exploration-detail-asia'));
    expect(
      find.descendant(of: detail, matching: find.text('Singapore')),
      findsAtLeastNWidgets(1),
    );
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(tester.getRect(nextRow).top, nextRowTop);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(detail, findsNothing);
    await tester.tap(
      find.byKey(const ValueKey('exploration-continent-antarctica')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Locked'), findsOneWidget);
    expect(
      find.text('No recorded visits on this continent yet'),
      findsOneWidget,
    );
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('continent sheet scrolls long visit lists with large text', (
    tester,
  ) async {
    _surface(tester, const Size(320, 700));
    final manyPlaces = [
      for (var index = 0; index < 15; index++)
        ExplorationPlace(
          name: 'City $index',
          countryCode: 'SG',
          latitude: 1.35,
          longitude: 103.82,
        ),
    ];
    for (final light in [false, true]) {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        _host(
          ExplorationPassport(
            places: manyPlaces,
            worldCount: 1,
            home: null,
            homeLoaded: true,
            onChooseHome: () {},
          ),
          light: light,
          scale: 2,
        ),
      );
      await tester.pumpAndSettle();
      final asia = find.byKey(const ValueKey('exploration-continent-asia'));
      await tester.scrollUntilVisible(asia, 300);
      await tester.pumpAndSettle();
      await tester.tap(asia);
      await tester.pumpAndSettle();
      final detail = find.byKey(const ValueKey('exploration-detail-asia'));
      final list = find.descendant(of: detail, matching: find.byType(ListView));
      await tester.dragUntilVisible(
        find.text('City 14'),
        list,
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
      expect(find.text('City 14').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'choosing home animates distance once without a map; saved home shows final distance',
    (tester) async {
      _surface(tester, const Size(430, 1500));
      final home = ValueNotifier<Airport?>(null);
      addTearDown(home.dispose);
      await tester.pumpWidget(
        _host(
          ValueListenableBuilder<Airport?>(
            valueListenable: home,
            builder: (context, value, child) => _passport(home: value),
          ),
        ),
      );
      await tester.pumpAndSettle();
      home.value = _home;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      final expected = farthestFromHome(
        places: _places,
        homeLatitude: _home.latitude,
        homeLongitude: _home.longitude,
      )!.distanceKm.round();
      expect(_displayedDistance(tester), inExclusiveRange(0, expected));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('farthest-footprint-destination')),
            )
            .data,
        'São Paulo',
      );
      expect(_displayedDistance(tester), expected);
      expect(_mementoMaps, findsNothing);
      expect(tester.binding.transientCallbackCount, 0);

      await tester.pumpWidget(_host(_passport(home: _home), reduced: true));
      await tester.pumpAndSettle();
      expect(_displayedDistance(tester), expected);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('empty/loading records never fabricate a journey', (
    tester,
  ) async {
    _surface(tester, const Size(360, 1300));
    await tester.pumpWidget(
      _host(
        FarthestFootprintCard(
          home: null,
          farthest: null,
          homeLoaded: false,
          onChooseHome: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Loading home city…'), findsOneWidget);
    expect(_mementoMaps, findsNothing);
    expect(
      find.byKey(const ValueKey('farthest-footprint-connection')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('farthest-footprint-distance')),
      findsNothing,
    );
    await tester.pumpWidget(
      _host(
        FarthestFootprintCard(
          home: _home,
          farthest: null,
          homeLoaded: true,
          onChooseHome: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No recorded places to measure yet'), findsOneWidget);
    expect(_mementoMaps, findsNothing);
    expect(
      find.byKey(const ValueKey('farthest-footprint-connection')),
      findsNothing,
    );
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'compact/large text and both themes preserve scrollable content',
    (tester) async {
      _surface(tester, const Size(320, 1000));
      for (final light in [false, true]) {
        // Start each theme at the top instead of restoring the previous
        // theme's deliberate scroll down to Antarctica.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(
          _host(
            _passport(home: _home),
            light: light,
            scale: 2,
            accessible: true,
            locale: const Locale('zh'),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          find.byKey(const ValueKey('farthest-footprint-country-mark')),
          findsNothing,
        );
        final home = find.byKey(const ValueKey('farthest-footprint-home'));
        final date = find.byKey(const ValueKey('farthest-footprint-date'));
        expect(tester.getRect(home).bottom, lessThan(tester.getRect(date).top));
        final antarctica = find.byKey(
          const ValueKey('exploration-continent-antarctica'),
        );
        await tester.scrollUntilVisible(antarctica, 350);
        await tester.pumpAndSettle();
        expect(antarctica, findsOneWidget);
        expect(tester.takeException(), isNull);
        expect(tester.binding.transientCallbackCount, 0);
      }
    },
  );

  testWidgets('long city names keep a readable two-place relationship', (
    tester,
  ) async {
    _surface(tester, const Size(320, 1100));
    const longHome = Airport(
      iataCode: 'SFO',
      latitude: 37.6,
      longitude: -122.4,
      name: 'San Francisco International',
      city: 'San Francisco Bay Area',
      countryCode: 'US',
    );
    for (final light in [false, true]) {
      await tester.pumpWidget(
        _host(
          SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: FarthestFootprintCard(
              home: longHome,
              farthest: const FarthestFootprint(
                place: ExplorationPlace(
                  name: 'San Carlos de Bariloche',
                  countryCode: 'AR',
                  latitude: -41.1,
                  longitude: -71.3,
                ),
                distanceKm: 18000,
              ),
              homeLoaded: true,
              onChooseHome: () {},
            ),
          ),
          light: light,
          scale: 2,
          reduced: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(longHome.city), findsOneWidget);
      expect(find.text('San Carlos de Bariloche'), findsOneWidget);
      final home = find.byKey(const ValueKey('farthest-footprint-home'));
      final destination = find.byKey(
        const ValueKey('farthest-footprint-destination'),
      );
      final distance = find.byKey(
        const ValueKey('farthest-footprint-distance-value'),
      );
      final date = find.byKey(const ValueKey('farthest-footprint-date'));
      expect(tester.getRect(distance).top, lessThan(tester.getRect(home).top));
      expect(
        tester.getRect(home).bottom,
        lessThan(tester.getRect(destination).top),
      );
      expect(
        tester.getRect(destination).bottom,
        lessThan(tester.getRect(date).top),
      );
      final text = tester.widget<Text>(distance);
      final foreground = text.textSpan!.style!.color!;
      final background = light
          ? AppThemeColors.light.surface
          : AppThemeColors.dark.surfaceElevated;
      final a = foreground.computeLuminance();
      final b = background.computeLuminance();
      expect(
        (a + .05) / (b + .05),
        light ? lessThanOrEqualTo(1 / 3) : greaterThanOrEqualTo(3),
      );
      expect(_mementoMaps, findsNothing);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('full-width distance and route adapt across widths and locales', (
    tester,
  ) async {
    _surface(tester, const Size(430, 1500));
    for (final width in [320.0, 430.0, 720.0]) {
      tester.view.physicalSize = Size(width, 1500);
      for (final locale in [const Locale('zh'), const Locale('en')]) {
        for (final light in [false, true]) {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpWidget(
            _host(
              _passport(home: _home),
              locale: locale,
              light: light,
            ),
          );
          await tester.pumpAndSettle();
          final destination = find.byKey(
            const ValueKey('farthest-footprint-destination'),
          );
          final home = find.byKey(const ValueKey('farthest-footprint-home'));
          final distance = find.byKey(
            const ValueKey('farthest-footprint-distance-value'),
          );
          final date = find.byKey(const ValueKey('farthest-footprint-date'));
          final connection = find.byKey(
            const ValueKey('farthest-footprint-connection'),
          );
          expect(
            tester.getRect(distance).top,
            lessThan(tester.getRect(home).top),
          );
          if (width < 400) {
            expect(
              tester.getRect(home).bottom,
              lessThan(tester.getRect(connection).top),
            );
            expect(
              tester.getRect(connection).bottom,
              lessThan(tester.getRect(destination).top),
            );
          } else {
            expect(
              tester.getRect(connection).left,
              greaterThan(tester.getRect(home).right),
            );
            expect(
              tester.getRect(connection).right,
              lessThan(tester.getRect(destination).left),
            );
          }
          expect(
            tester.getRect(destination).bottom,
            lessThan(tester.getRect(date).top),
          );
          expect(
            tester.getRect(home).overlaps(tester.getRect(distance)),
            isFalse,
          );
          expect(tester.getRect(home).overlaps(tester.getRect(date)), isFalse);
          expect(tester.getSize(connection).width, greaterThan(40));
          expect(
            tester.widget<Text>(destination).overflow,
            isNot(TextOverflow.ellipsis),
          );
          expect(tester.takeException(), isNull);
          expect(tester.binding.transientCallbackCount, 0);
        }
      }
    }
  });
}
