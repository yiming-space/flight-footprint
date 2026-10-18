import 'dart:async';
import 'dart:convert';

import 'package:flight_footprint/features/map/detail_map_data.dart';
import 'package:flight_footprint/features/map/detail_map_routes.dart';
import 'package:flight_footprint/features/map/map_models.dart';
import 'package:flutter_test/flutter_test.dart';

const a = MapAirport(code: 'AAA', name: 'Alpha', latitude: 20, longitude: 30);
const b = MapAirport(code: 'BBB', name: 'Beta', latitude: 40, longitude: 50);
const outbound = MapRoute(from: a, to: b);
const inbound = MapRoute(from: b, to: a);
List<Map<String, dynamic>> features(DetailRouteData data) =>
    (data.collection['features'] as List).cast<Map<String, dynamic>>();

void main() {
  test(
    'only same-direction duplicates merge; return direction stays separate',
    () {
      final records = [outbound, outbound, inbound];
      final data = DetailRouteCache().data(records);
      final lines = features(data);
      expect(lines, hasLength(2));
      expect(lines.map((f) => f['properties']['count']), [2, 1]);
      expect(lines.map((f) => f['properties']['index']), [0, 2]);
      expect(lines.map((f) => f['properties']['offset']), [0.0, 0.0]);
      expect(records, hasLength(3));
      expect(data.selected(2)['features'], [lines[1]]);
      expect(data.selected(1)['features'], isEmpty);
      expect(data.selected(null)['features'], isEmpty);
    },
  );

  test(
    'one-way geometry remains unshifted and independent tracks are retained',
    () {
      const track = MapRoute(
        from: a,
        to: b,
        track: [
          MapCoordinate(20, 30),
          MapCoordinate(25, 42),
          MapCoordinate(40, 50),
        ],
      );
      final data = DetailRouteCache().data([outbound, track, track]);
      expect(features(data), hasLength(2));
      expect(features(data).map((f) => f['properties']['count']), [1, 2]);
      expect(
        features(data).every((f) => f['properties']['offset'] == 0),
        isTrue,
      );
      expect(features(data)[1]['geometry']['coordinates'], [
        [30.0, 20.0],
        [42.0, 25.0],
        [50.0, 40.0],
      ]);
    },
  );

  test(
    'geometry and encoded collection are cached independently from selection',
    () {
      var calls = 0;
      final cache = DetailRouteCache(
        coordinateBuilder: (route) {
          calls++;
          return detailIllustratedRouteCoordinates(route);
        },
      );
      final records = [outbound, outbound, inbound];
      final first = cache.data(records);
      for (var i = 0; i < 20; i++) {
        expect(identical(first, cache.data(records)), isTrue);
        first.selected(i.isEven ? 0 : 2);
      }
      expect(calls, 2);
      final rebuilt = cache.data([outbound, outbound, inbound]);
      expect(rebuilt.encoded, first.encoded);
      expect(calls, 2);
      expect(features(cache.data(records, enabled: false)), isEmpty);
      expect(cache.data(records).encoded, first.encoded);
    },
  );

  test(
    'dateline return routes preserve the short crossing and both directions',
    () {
      const west = MapAirport(
        code: 'W',
        name: '',
        latitude: 30,
        longitude: 170,
      );
      const east = MapAirport(
        code: 'E',
        name: '',
        latitude: 30,
        longitude: -170,
      );
      final data = DetailRouteCache().data(const [
        MapRoute(from: west, to: east),
        MapRoute(from: east, to: west),
      ]);
      for (final line in features(data)) {
        final points = line['geometry']['coordinates'] as List;
        expect(((points.last[0] as num) - (points.first[0] as num)).abs(), 20);
      }
    },
  );

  test(
    'directed pixel offsets select the closer outbound or return stroke',
    () {
      const forward = [Offset(0, 0), Offset(100, 0)];
      const reverse = [Offset(100, 0), Offset(0, 0)];
      expect(
        detailRouteScreenDistance(const Offset(50, 1.3), forward, offset: 1.3),
        0,
      );
      expect(
        detailRouteScreenDistance(const Offset(50, 1.3), reverse, offset: 1.3),
        2.6,
      );
      expect(
        detailRouteScreenDistance(const Offset(50, -1.3), reverse, offset: 1.3),
        0,
      );
      expect(
        detailRouteScreenDistance(const Offset(50, -1.3), forward, offset: 1.3),
        2.6,
      );
      expect(
        detailRouteScreenDistance(const Offset(0, 0), const []),
        double.infinity,
      );
      expect(
        detailRouteScreenDistance(const Offset(0, 0), const [
          Offset.zero,
          Offset.zero,
        ]),
        double.infinity,
      );
    },
  );

  test('hit ranking handles projected world copies at the date line', () {
    expect(
      detailRouteScreenDistance(const Offset(0, 0), const [
        Offset(490, 0),
        Offset(10, 0),
      ], worldWidth: 500),
      0,
    );
  });

  test(
    'repeated 400 records reduce to two geometries and a smaller source',
    () {
      final records = [
        for (var i = 0; i < 200; i++) ...[outbound, inbound],
      ];
      final baseline = jsonEncode(
        detailFeatureCollection([
          for (var i = 0; i < records.length; i++)
            {
              'type': 'Feature',
              'properties': {'kind': 'route', 'index': i},
              'geometry': {
                'type': 'LineString',
                'coordinates': detailRouteCoordinates(records[i]),
              },
            },
        ]),
      );
      var computations = 0;
      final data = DetailRouteCache(
        coordinateBuilder: (route) {
          computations++;
          return detailIllustratedRouteCoordinates(route);
        },
      ).data(records);
      expect(computations, 2);
      expect(features(data), hasLength(2));
      expect(data.encoded.length, lessThan(baseline.length * .02));
      // Deterministic operation/payload evidence, not a device FPS benchmark.
      // ignore: avoid_print
      print(
        'route fixture: 400 -> $computations geometry computations; '
        '${baseline.length} -> ${data.encoded.length} JSON characters',
      );
    },
  );

  test('unchanged routes are not resent after a location update; new style invalidates cache', () async {
    final cache = DetailSourceCache();
    final style = Object();
    final sent = <String>[];
    Future<void> send(Object s, String id, String data) => cache.update(
      style: s,
      id: id,
      data: data,
      send: () async {
        sent.add(id);
      },
    );
    await send(style, 'routes', 'geometry');
    await send(style, 'location', 'first');
    await send(style, 'routes', 'geometry');
    await send(style, 'location', 'second');
    expect(sent.where((id) => id == 'routes'), hasLength(1));
    await send(Object(), 'routes', 'geometry');
    expect(sent.where((id) => id == 'routes'), hasLength(2));
  });

  test('failed source uploads remain retryable and stale style completions are ignored', () async {
    final cache = DetailSourceCache();
    final firstStyle = Object(), secondStyle = Object();
    var sends = 0;
    Future<void> send(
      Object style,
      String data,
      Future<void> Function() action,
    ) => cache.update(
      style: style,
      id: 'routes',
      data: data,
      send: () async {
        sends++;
        await action();
      },
    );
    await expectLater(
      send(firstStyle, 'A', () async {
        throw StateError('fixture');
      }),
      throwsStateError,
    );
    await send(firstStyle, 'A', () async {});
    expect(sends, 2);
    final pending = Completer<void>();
    final old = send(firstStyle, 'old', () => pending.future);
    await send(secondStyle, 'new', () async {});
    pending.complete();
    await old;
    await send(secondStyle, 'new', () async {});
    expect(sends, 4);
  });
}
