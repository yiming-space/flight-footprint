import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flight_footprint/core/localization/app_strings.dart';
import 'package:flight_footprint/features/map/detail_map.dart';
import 'package:flight_footprint/features/map/detail_map_style.dart';
import 'package:flight_footprint/features/map/map_models.dart';
import 'package:flight_footprint/ui/theme/app_theme.dart';

class _FailingLoader extends DetailMapStyleLoader {
  int calls = 0;

  @override
  Future<Map<String, dynamic>> load() async {
    calls++;
    throw StateError('fixture failure');
  }
}

class _PendingLoader extends DetailMapStyleLoader {
  final completer = Completer<Map<String, dynamic>>();

  @override
  Future<Map<String, dynamic>> load() => completer.future;
}

Widget _app(
  DetailMapStyleLoader loader, {
  ValueChanged<bool>? onFallbackChanged,
}) => MaterialApp(
  locale: const Locale('zh'),
  supportedLocales: AppStrings.supportedLocales,
  localizationsDelegates: const [
    AppStringsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: Scaffold(
    body: DetailMap(
      mode: MapMode.flight,
      airports: const [],
      routes: const [],
      places: const [],
      fallback: const Text('offline'),
      onFallbackChanged: onFallbackChanged,
      loader: loader,
    ),
  ),
);

Map<String, dynamic> _baseStyle() => {
  'version': 8,
  'glyphs': 'https://example.invalid/fonts/{fontstack}/{range}.pbf',
  'sources': {
    'openmaptiles': {
      'type': 'vector',
      'url': 'https://example.invalid/tiles.json',
      'attribution': '© OpenStreetMap contributors',
    },
  },
  'layers': [
    {'id': 'background', 'type': 'background'},
    {'id': 'water', 'type': 'fill', 'source-layer': 'water'},
    {'id': 'landcover', 'type': 'fill', 'source-layer': 'landcover'},
    {'id': 'border', 'type': 'line', 'source-layer': 'boundary'},
    {
      'id': 'water-name',
      'type': 'symbol',
      'source-layer': 'water_name',
      'paint': {'text-opacity': .5},
    },
    {
      'id': 'road',
      'type': 'line',
      'source-layer': 'transportation',
      'minzoom': 2,
    },
    {
      'id': 'local-road',
      'type': 'line',
      'source-layer': 'transportation',
      'minzoom': 12,
    },
    {'id': 'poi', 'type': 'symbol', 'source-layer': 'poi'},
    {'id': 'terrain', 'type': 'raster'},
    {'id': 'road-shield', 'type': 'symbol'},
    {
      'id': 'city',
      'type': 'symbol',
      'source-layer': 'place',
      'layout': {
        'text-field': ['get', 'name'],
      },
    },
  ],
};

const _emptyCollection = <String, dynamic>{
  'type': 'FeatureCollection',
  'features': <Map<String, dynamic>>[],
};

Map<String, dynamic> _style({required bool light, bool chinese = true}) =>
    buildDetailMapStyle(
      _baseStyle(),
      light: light,
      chinese: chinese,
      points: _emptyCollection,
      routes: _emptyCollection,
      location: _emptyCollection,
    );

Map<String, dynamic> _layer(Map<String, dynamic> style, String id) =>
    (style['layers'] as List).cast<Map<String, dynamic>>().singleWhere(
      (layer) => layer['id'] == id,
    );

void main() {
  const strings = AppStrings(Locale('zh'));

  testWidgets('loading never flashes the differently projected backup map', (
    tester,
  ) async {
    final loader = _PendingLoader();
    await tester.pumpWidget(_app(loader));
    await tester.pump();
    expect(find.text('offline'), findsNothing);
    expect(find.text(strings.t('detailMapLoading')), findsOneWidget);
    expect(find.text(strings.t('retry')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('failure automatically keeps backup and offers only retry', (
    tester,
  ) async {
    final loader = _FailingLoader();
    final fallbacks = <bool>[];
    await tester.pumpWidget(_app(loader, onFallbackChanged: fallbacks.add));
    await tester.pumpAndSettle();
    expect(find.text('offline'), findsOneWidget);
    expect(find.text(strings.t('detailMapFailed')), findsOneWidget);
    expect(loader.calls, 1);
    await tester.tap(find.text(strings.t('retry')));
    await tester.pumpAndSettle();
    expect(loader.calls, 2);
    expect(find.text(strings.t('detailMapFailed')), findsOneWidget);
    expect(find.text(strings.t('offlineBasemap')), findsNothing);
    expect(find.text('offline'), findsOneWidget);
    expect(fallbacks.last, isTrue);
    expect(fallbacks.where((value) => value).length, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('timeout automatically falls back without a map-choice action', (
    tester,
  ) async {
    final loader = _PendingLoader();
    final fallbacks = <bool>[];
    await tester.pumpWidget(_app(loader, onFallbackChanged: fallbacks.add));
    await tester.pump(const Duration(seconds: 26));
    await tester.pump();
    expect(find.text('offline'), findsOneWidget);
    expect(find.text(strings.t('detailMapFailed')), findsOneWidget);
    expect(find.text(strings.t('retry')), findsOneWidget);
    expect(find.text(strings.t('offlineBasemap')), findsNothing);
    expect(fallbacks, [false, true]);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('style completion after disposal does not update widget state', (
    tester,
  ) async {
    final loader = _PendingLoader();
    await tester.pumpWidget(_app(loader));
    await tester.pumpWidget(const SizedBox.shrink());
    loader.completer.complete(_baseStyle());
    await tester.pump();
    await tester.pump(const Duration(seconds: 26));
    expect(tester.takeException(), isNull);
  });

  test('light and dark palettes change land, water and route colors', () {
    final light = _style(light: true);
    final dark = _style(light: false);
    for (final entry in [
      ('background', 'background-color'),
      ('water', 'fill-color'),
      ('ff-routes', 'line-color'),
    ]) {
      final lightColor = (_layer(light, entry.$1)['paint'] as Map)[entry.$2];
      final darkColor = (_layer(dark, entry.$1)['paint'] as Map)[entry.$2];
      expect(lightColor, matches(RegExp(r'^#[0-9a-f]{6}$')));
      expect(lightColor, isNot(darkColor));
    }
  });

  test('style removes visual clutter and delays detailed roads', () {
    final style = _style(light: true);
    final ids = (style['layers'] as List).map((layer) => layer['id']);
    expect(ids, isNot(contains('poi')));
    expect(ids, isNot(contains('terrain')));
    expect(ids, isNot(contains('road-shield')));
    expect(_layer(style, 'road')['minzoom'], 7);
    expect(_layer(style, 'local-road')['minzoom'], 12);
  });

  test('ice-white overview routes retain lavender with restrained opacity', () {
    final paint = _layer(_style(light: true), 'ff-routes')['paint'] as Map;
    expect(paint['line-color'], detailMapColor(AppColors.routePurpleLight));
    expect(paint['line-opacity'], .9);
  });

  test('night geography stays subtly cool with readable land and sea', () {
    final style = _style(light: false);
    Color paintColor(String id, String property) => Color(
      0xff000000 |
          int.parse(
            ((_layer(style, id)['paint'] as Map)[property] as String).substring(
              1,
            ),
            radix: 16,
          ),
    );
    double contrast(Color a, Color b) {
      final luminances = [a.computeLuminance(), b.computeLuminance()]..sort();
      return (luminances.last + .05) / (luminances.first + .05);
    }

    final land = paintColor('background', 'background-color');
    final water = paintColor('water', 'fill-color');
    for (final color in [
      land,
      water,
      paintColor('landcover', 'fill-color'),
      paintColor('border', 'line-color'),
      paintColor('road', 'line-color'),
      paintColor('city', 'text-color'),
      paintColor('water-name', 'text-color'),
    ]) {
      final rgb = color.toARGB32();
      final red = (rgb >> 16) & 255;
      final green = (rgb >> 8) & 255;
      final blue = rgb & 255;
      expect(green, greaterThanOrEqualTo(red));
      expect(blue, greaterThanOrEqualTo(green));
      expect(blue - red, lessThanOrEqualTo(8));
    }
    for (final color in [land, water]) {
      final rgb = color.toARGB32();
      expect(rgb & 255, greaterThan((rgb >> 16) & 255));
    }
    expect(contrast(land, water), greaterThan(1.7));
    for (final surface in [land, water]) {
      expect(
        contrast(paintColor('city', 'text-color'), surface),
        greaterThanOrEqualTo(4.5),
      );
    }
    expect((_layer(style, 'city')['paint'] as Map)['text-opacity'], 1);
    expect((_layer(style, 'border')['paint'] as Map)['line-opacity'], .7);
    expect(
      paintColor('water-name', 'text-color'),
      AppColors.detailMapNightWaterLabel,
    );
    expect(paintColor('ff-routes', 'line-color'), AppColors.routePurple);
  });

  test('overview markers shrink smoothly while location retains a distinct purple dot', () {
    for (final light in [false, true]) {
      final style = _style(light: light);
      final points = _layer(style, 'ff-points')['paint'] as Map;
      expect(points['circle-radius'], [
        'interpolate',
        ['linear'],
        ['zoom'],
        0,
        3.4,
        2,
        3.8,
        5,
        4.5,
      ]);
      expect(points['circle-stroke-width'], [
        'interpolate',
        ['linear'],
        ['zoom'],
        0,
        1.0,
        5,
        1.5,
      ]);
      expect(
        (_layer(style, 'ff-location')['paint'] as Map)['circle-radius'],
        6,
      );
      expect(
        (_layer(style, 'ff-location')['paint'] as Map)['circle-color'],
        '#B69CFF',
      );
      expect(
        (_layer(style, 'ff-location')['paint'] as Map)['circle-stroke-color'],
        '#FFFFFF',
      );
      expect(
        (_layer(style, 'ff-location')['paint'] as Map)['circle-opacity'],
        1,
      );
      expect(
        (_layer(style, 'ff-location')['paint'] as Map)['circle-stroke-opacity'],
        1,
      );
    }
  });

  test('record sources coexist with the attributed basemap source', () {
    final style = _style(light: true);
    final sources = style['sources'] as Map;
    expect(
      sources['openmaptiles'],
      (_baseStyle()['sources'] as Map)['openmaptiles'],
    );
    expect(style['glyphs'], _baseStyle()['glyphs']);
    for (final id in [
      'ff-routes',
      'ff-points',
      'ff-location',
      'ff-regions',
      'ff-route-selection',
    ]) {
      expect(sources[id], {'type': 'geojson', 'data': _emptyCollection});
      expect(_layer(style, id)['source'], id);
    }
  });

  test(
    'overview and selection share direction offsets but differ in weight',
    () {
      final style = _style(light: false);
      final base = _layer(style, 'ff-routes')['paint'] as Map;
      final selected = _layer(style, 'ff-route-selection')['paint'] as Map;
      expect(base['line-width'], [
        'interpolate',
        ['linear'],
        ['zoom'],
        0,
        1.0,
        2,
        1.15,
        5,
        1.4,
        12,
        1.65,
      ]);
      expect(base['line-offset'], [
        'coalesce',
        ['get', 'offset'],
        0,
      ]);
      expect(selected['line-offset'], base['line-offset']);
      expect(selected['line-color'], base['line-color']);
      expect(selected['line-opacity'], 1);
      expect(base['line-opacity'], lessThan(selected['line-opacity'] as num));
      expect(selected['line-width'], greaterThan(1.3));
      final ids = (style['layers'] as List).map((l) => l['id']).toList();
      expect(
        ids.indexOf('ff-route-selection'),
        greaterThan(ids.indexOf('ff-routes')),
      );
      expect(
        ids.indexOf('ff-route-selection'),
        lessThan(ids.indexOf('ff-points')),
      );
    },
  );

  test(
    'footprint fill stays below water masks, roads, boundaries and labels',
    () {
      final style = _style(light: false);
      final ids = (style['layers'] as List).map((l) => l['id']).toList();
      final index = ids.indexOf('ff-regions');
      for (final above in [
        'ff-region-water-water',
        'border',
        'road',
        'city',
        'ff-routes',
        'ff-points',
        'ff-labels',
      ]) {
        expect(index, lessThan(ids.indexOf(above)));
      }
      expect(ids.indexOf('landcover'), lessThan(index));
      final region = _layer(style, 'ff-regions');
      expect(region['maxzoom'], 8);
      final paint = region['paint'] as Map;
      expect(paint['fill-antialias'], isTrue);
      expect(paint.containsKey('fill-outline-color'), isFalse);
      expect((paint['fill-opacity'] as List).last, 0);
      expect(
        paint['fill-color'],
        detailMapColor(AppColors.detailFootprintDark),
      );
      expect(
        (_layer(_style(light: true), 'ff-regions')['paint']
            as Map)['fill-color'],
        detailMapColor(AppColors.detailFootprintLight),
      );
    },
  );

  test(
    'basemap labels prefer the selected language with local-name fallback',
    () {
      for (final chinese in [true, false]) {
        final style = _style(light: true, chinese: chinese);
        final name = [
          'coalesce',
          if (chinese) ['get', 'name:zh-Hans'],
          ['get', chinese ? 'name:zh' : 'name:en'],
          ['get', 'name_en'],
          ['get', 'name'],
        ];
        expect((_layer(style, 'city')['layout'] as Map)['text-field'], [
          'case',
          [
            '>=',
            ['index-of', ';', name],
            0,
          ],
          [
            'slice',
            name,
            0,
            ['index-of', ';', name],
          ],
          name,
        ]);
        expect((_layer(style, 'ff-labels')['layout'] as Map)['text-field'], [
          'get',
          'label',
        ]);
      }
    },
  );
}
