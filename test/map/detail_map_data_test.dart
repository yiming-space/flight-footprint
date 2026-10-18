import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:flight_footprint/features/map/detail_map_data.dart';
import 'package:flight_footprint/features/map/map_models.dart';

MapAirport _airport(double latitude, double longitude) => MapAirport(
  code: 'TEST',
  name: 'Test',
  latitude: latitude,
  longitude: longitude,
);

void main() {
  test(
    'illustrative return arcs bow on opposite sides of the airport chord',
    () {
      final from = _airport(30.57, 103.95), to = _airport(40.08, 116.58);
      final forward = detailIllustratedRouteCoordinates(
        MapRoute(from: from, to: to),
      );
      final reverse = detailIllustratedRouteCoordinates(
        MapRoute(from: to, to: from),
      );
      List<double> project(List<double> p) => [
        p[0] * math.pi / 180,
        math.log(math.tan(math.pi / 4 + p[1] * math.pi / 360)),
      ];
      final a = project(forward.first), b = project(forward.last);
      double side(List<List<double>> path) {
        final p = project(path[path.length ~/ 2]);
        return (b[0] - a[0]) * (p[1] - a[1]) - (b[1] - a[1]) * (p[0] - a[0]);
      }

      expect(forward.first, [103.95, 30.57]);
      expect(forward.last, [116.58, 40.08]);
      expect(reverse.first, forward.last);
      expect(reverse.last, forward.first);
      expect(side(forward), greaterThan(0));
      expect(side(reverse), lessThan(0));
      expect(side(forward), closeTo(-side(reverse), 1e-12));
      expect(
        detailIllustratedRouteCoordinates(MapRoute(from: from, to: to)),
        forward,
      );
    },
  );

  test(
    'illustrative arcs bound polar/coincident geometry and unwrap dateline',
    () {
      for (final pair in [
        (_airport(30, 170), _airport(30, -170)),
        (_airport(10, 20), _airport(10, 20)),
        (_airport(90, 0), _airport(-90, 180)),
        (_airport(89, 179), _airport(89, -179)),
      ]) {
        final points = detailIllustratedRouteCoordinates(
          MapRoute(from: pair.$1, to: pair.$2),
        );
        expect(points.length, inInclusiveRange(2, 65));
        expect(points.expand((p) => p).every((v) => v.isFinite), isTrue);
        expect(
          points.every((p) => p[1].abs() <= 85.0511287798066 + 1e-10),
          isTrue,
        );
        for (var i = 1; i < points.length; i++) {
          expect((points[i][0] - points[i - 1][0]).abs(), lessThan(180));
        }
      }
      final points = detailIllustratedRouteCoordinates(
        MapRoute(from: _airport(30, 170), to: _airport(30, -170)),
      );
      expect(points.first, [170, 30]);
      expect(points.last, [190, 30]);
    },
  );

  test('illustration never reshapes an actual recorded track', () {
    final route = MapRoute(
      from: _airport(0, 0),
      to: _airport(1, 1),
      track: const [
        MapCoordinate(2, 179),
        MapCoordinate(3, -179),
        MapCoordinate(4, -175),
      ],
    );
    expect(
      detailIllustratedRouteCoordinates(route),
      detailRouteCoordinates(route),
    );
  });

  test('great circle follows the short dateline crossing', () {
    final coordinates = detailRouteCoordinates(
      MapRoute(from: _airport(30, 170), to: _airport(30, -170)),
    );
    expect(coordinates.length, inInclusiveRange(2, 65));
    expect(coordinates.first, [170, 30]);
    expect(coordinates.last, [190, 30]);
    expect(coordinates[coordinates.length ~/ 2][1], greaterThan(30));
    for (var i = 1; i < coordinates.length; i++) {
      expect((coordinates[i][0] - coordinates[i - 1][0]).abs(), lessThan(180));
    }
  });

  test('coincident and near antipodal endpoints stay finite', () {
    for (final end in [
      (10.0, 20.0),
      (-10.0, -160.0),
      (-10.00000000001, -160.0),
    ]) {
      final coordinates = detailRouteCoordinates(
        MapRoute(from: _airport(10, 20), to: _airport(end.$1, end.$2)),
      );
      expect(coordinates.length, inInclusiveRange(2, 65));
      expect(
        coordinates.expand((point) => point).every((value) => value.isFinite),
        isTrue,
      );
      expect(coordinates.first, [20, 10]);
      expect(coordinates.last[1], end.$1);
    }
  });

  test(
    'recorded track preserves positions and unwraps successive crossings',
    () {
      final coordinates = detailRouteCoordinates(
        MapRoute(
          from: _airport(0, 0),
          to: _airport(1, 1),
          track: const [
            MapCoordinate(2, 179),
            MapCoordinate(3, -179),
            MapCoordinate(4, -175),
          ],
        ),
      );
      expect(coordinates, [
        [179, 2],
        [181, 3],
        [185, 4],
      ]);
    },
  );

  test(
    'center handles empty, single point, latitude clamp and dateline bounds',
    () {
      final empty = detailMapCenter(const []);
      expect([empty.latitude, empty.longitude], [20, 0]);
      final single = detailMapCenter(const [MapCoordinate(90, 181)]);
      expect([single.latitude, single.longitude], [80, -179]);
      final crossing = detailMapCenter(const [
        MapCoordinate(10, 170),
        MapCoordinate(30, -170),
      ]);
      expect(crossing.latitude, 20);
      expect(crossing.longitude.abs(), 180);
      final ordinary = detailMapCenter(const [
        MapCoordinate(-10, -30),
        MapCoordinate(30, 10),
      ]);
      expect([ordinary.latitude, ordinary.longitude], [10, -10]);
    },
  );

  test(
    'point features and collection preserve GeoJSON order and record keys',
    () {
      final feature = detailPointFeature(
        const MapCoordinate(12, 34),
        kind: 'place',
        index: 2,
        label: '上海',
      );
      expect(feature, {
        'type': 'Feature',
        'properties': {'kind': 'place', 'index': 2, 'label': '上海'},
        'geometry': {
          'type': 'Point',
          'coordinates': [34, 12],
        },
      });
      expect(detailFeatureCollection([feature]), {
        'type': 'FeatureCollection',
        'features': [feature],
      });
      expect(detailFeatureCollection([])['features'], isEmpty);
    },
  );
}
