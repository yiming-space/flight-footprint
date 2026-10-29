import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flight_footprint/features/map/geojson_map_data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'bundled Natural Earth countries retain source identity metadata',
    () async {
      final source = jsonDecode(
        await rootBundle.loadString('assets/data/world-countries-50m.geo.json'),
      ) as Map<String, dynamic>;
      final features = source['features'] as List;

      expect(source['license'], 'Public Domain');
    expect(
      source['sourceSha256'],
      '3e458fc036ad0a66411f2c1e6cac49c5d7bfb81cb1123bc513b22511a2b7fdeb',
    );
      expect(features, hasLength(242));
      expect(
        features.map((feature) => feature['properties']['ISO_A2_EH']).toSet(),
        containsAll(['CN', 'US', 'GB']),
      );
      expect(
        features.every((feature) {
          final code = feature['properties']['ISO_A2_EH'];
          return code is String &&
              (RegExp(r'^[A-Z]{2}$').hasMatch(code) || code == '-99');
        }),
        isTrue,
      );
    },
  );

  test('country polygon point lookup wraps at the antimeridian', () {
    final polygon = MapPolygon([
      [
        [179, 10],
        [-179, 10],
        [-179, 14],
        [179, 14],
        [179, 10],
      ],
    ]);

    expect(polygon.containsPoint(179.5, 12), isTrue);
    expect(polygon.containsPoint(-179.5, 12), isTrue);
    expect(polygon.containsPoint(0, 12), isFalse);
    expect(polygon.containsPoint(double.nan, 12), isFalse);
    expect(polygon.containsPoint(181, 12), isFalse);
    expect(polygon.containsPoint(0, 91), isFalse);
  });

  test('country polygon point lookup keeps holes unlit', () {
    final polygon = MapPolygon([
      [
        [0, 0],
        [10, 0],
        [10, 10],
        [0, 10],
        [0, 0],
      ],
      [
        [4, 4],
        [6, 4],
        [6, 6],
        [4, 6],
        [4, 4],
      ],
    ]);

    expect(polygon.containsPoint(2, 2), isTrue);
    expect(polygon.containsPoint(5, 5), isFalse);
  });

  test('country ISO metadata survives polygon decoding', () {
    final data = GeoJsonMapData.fromJson({
      'type': 'FeatureCollection',
      'features': [
        {
          'type': 'Feature',
          'properties': {'ISO_A2_EH': 'GB', 'CONTINENT': 'Europe'},
          'geometry': {
            'type': 'Polygon',
            'coordinates': [
              [
                [-1, 50],
                [1, 50],
                [1, 52],
                [-1, 50],
              ],
            ],
          },
        },
      ],
    });

    expect(data.polygons.single.countryCode, 'GB');
    expect(data.polygons.single.properties['CONTINENT'], 'Europe');
  });

  test('China admin polygons require their matching country code', () {
    const mainland = MapPolygon([], properties: {'adcode': 110000});
    const hongKong = MapPolygon([], properties: {'adcode': 810000});
    const macau = MapPolygon([], properties: {'adcode': 820000});
    const taiwan = MapPolygon([], properties: {'adcode': 710000});

    expect(mainland.matchesChinaAdministrativeRegion('CN'), isTrue);
    expect(mainland.matchesChinaAdministrativeRegion('US'), isFalse);
    expect(hongKong.matchesChinaAdministrativeRegion('HK'), isTrue);
    expect(hongKong.matchesChinaAdministrativeRegion('CN'), isFalse);
    expect(macau.matchesChinaAdministrativeRegion('MO'), isTrue);
    expect(taiwan.matchesChinaAdministrativeRegion('TW'), isTrue);
    expect(mainland.matchesChinaAdministrativeRegion(null), isTrue);
  });

  test('parses Polygon and MultiPolygon feature collections', () {
    final data = GeoJsonMapData.fromJson({
      'type': 'FeatureCollection',
      'features': [
        {
          'type': 'Feature',
          'geometry': {
            'type': 'Polygon',
            'coordinates': [
              [
                [0, 0],
                [10, 0],
                [10, 10],
                [0, 0],
              ],
            ],
          },
        },
        {
          'type': 'Feature',
          'geometry': {
            'type': 'MultiPolygon',
            'coordinates': [
              [
                [
                  [20, 20],
                  [30, 20],
                  [30, 30],
                  [20, 20],
                ],
              ],
            ],
          },
        },
      ],
    });

    expect(data.polygons, hasLength(2));
    expect(data.polygons.first.rings.first.first, [0, 0]);
  });

  test('ignores unsupported and underspecified geometries', () {
    final data = GeoJsonMapData.fromJson({
      'type': 'FeatureCollection',
      'features': [
        {
          'geometry': {
            'type': 'Point',
            'coordinates': [1, 2],
          },
        },
        {
          'geometry': {
            'type': 'Polygon',
            'coordinates': [[]],
          },
        },
      ],
    });
    expect(data.polygons, isEmpty);
  });

  test('parses line features used by the web map boundary layers', () {
    final data = GeoJsonMapData.fromJson({
      'type': 'FeatureCollection',
      'features': [
        {
          'geometry': {
            'type': 'MultiLineString',
            'coordinates': [
              [
                [100, 20],
                [101, 21],
              ],
            ],
          },
        },
      ],
    });
    expect(data.lines, hasLength(1));
    expect(data.lines.single.points.last, [101, 21]);
  });
}
