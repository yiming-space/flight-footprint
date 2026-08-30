import 'package:flutter_test/flutter_test.dart';
import 'package:flight_footprint/features/map/geojson_map_data.dart';

void main() {
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
