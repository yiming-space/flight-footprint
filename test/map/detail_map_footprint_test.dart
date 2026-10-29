import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flight_footprint/features/map/detail_map_footprint.dart';
import 'package:flight_footprint/features/map/map_models.dart';

Map<String, dynamic> _collection(List<Map<String, dynamic>> features) => {
  'type': 'FeatureCollection',
  'features': features,
};
List<List<double>> _box(double x, double y, [double size = 4]) => [
  [x, y],
  [x + size, y],
  [x + size, y + size],
  [x, y + size],
  [x, y],
];
Map<String, dynamic> _polygon(
  String name,
  List<List<List<double>>> rings, {
  int? adcode,
  String? isoCode,
}) => {
  'type': 'Feature',
  'properties': {'name': name, 'adcode': ?adcode, 'ISO_A2_EH': ?isoCode},
  'geometry': {'type': 'Polygon', 'coordinates': rings},
};
MapPlace _place(double x, double y, {String? country, bool visited = true}) =>
    MapPlace(
      name: '',
      latitude: y,
      longitude: x,
      countryCode: country,
      isVisited: visited,
    );
List _features(Map<String, dynamic> result) => result['features'] as List;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'visiting one island retains the whole country feature exactly once',
    () {
      final country = {
        'type': 'Feature',
        'properties': {'name': 'islands'},
        'geometry': {
          'type': 'MultiPolygon',
          'coordinates': [
            [_box(10, 10)],
            [_box(20, 10)],
          ],
        },
      };
      final boundaries = DetailFootprintBoundaries(
        countries: _collection([country]),
        provinces: emptyDetailFootprint,
      );
      final result = boundaries.select([_place(11, 11), _place(21, 11)]);
      expect(_features(result), [country]);
    },
  );

  test('holes, unvisited and invalid coordinates never light regions', () {
    final boundaries = DetailFootprintBoundaries(
      countries: _collection([
        _polygon('hole', [_box(10, 10), _box(11, 11, 1)]),
      ]),
      provinces: emptyDetailFootprint,
    );
    expect(
      _features(
        boundaries.select([
          _place(11.5, 11.5),
          _place(10.5, 10.5, visited: false),
          _place(double.nan, 10),
          _place(10, double.infinity),
          _place(370, 10),
        ]),
      ),
      isEmpty,
    );
    expect(_features(boundaries.select([_place(10.5, 10.5)])), hasLength(1));
  });

  test('known country codes cannot light another country feature', () {
    final us = _polygon('United States', [_box(-80, 35)], isoCode: 'US');
    final uk = _polygon('United Kingdom', [_box(-5, 50)], isoCode: 'GB');
    final unassigned = _polygon('unassigned', [_box(20, 20)], isoCode: '-99');
    final boundaries = DetailFootprintBoundaries(
      countries: _collection([us, uk, unassigned]),
      provinces: emptyDetailFootprint,
    );

    expect(
      _features(
        boundaries.select([
          _place(-2, 51, country: 'US'),
          _place(-77, 38, country: 'GB'),
          _place(21, 21, country: 'XX'),
        ]),
      ),
      isEmpty,
    );
    expect(
      _features(
        boundaries.select([
          _place(-77, 38, country: 'US'),
          _place(-2, 51, country: 'GB'),
        ]),
      ),
      unorderedEquals([us, uk]),
    );
  });

  test('dateline polygon matches both sides but not Greenwich', () {
    final boundaries = DetailFootprintBoundaries(
      countries: _collection([
        _polygon('dateline', [
          [
            [179, 10],
            [-179, 10],
            [-179, 14],
            [179, 14],
            [179, 10],
          ],
        ]),
      ]),
      provinces: emptyDetailFootprint,
    );
    for (final x in [179.5, -179.5]) {
      expect(_features(boundaries.select([_place(x, 12)])), hasLength(1));
    }
    expect(_features(boundaries.select([_place(0, 12)])), isEmpty);
  });

  test(
    'domestic records light only the visited province, even without code',
    () {
      final country = _polygon('China', [_box(110, 35, 15)]);
      final province = _polygon('Beijing', [_box(115, 39, 2)]);
      final other = _polygon('other', [_box(110, 35)]);
      final boundaries = DetailFootprintBoundaries(
        countries: _collection([country]),
        provinces: _collection([province, other]),
      );
      for (final code in ['CN', 'cn', null]) {
        expect(
          _features(boundaries.select([_place(116.4, 39.9, country: code)])),
          [province],
        );
      }
      expect(_features(boundaries.select(const [])), isEmpty);
    },
  );

  test(
    'province fills require a compatible country code when one is known',
    () {
      final province = _polygon('Beijing', [_box(115, 39, 2)], adcode: 110000);
      final boundaries = DetailFootprintBoundaries(
        countries: emptyDetailFootprint,
        provinces: _collection([province]),
      );

      expect(
        _features(boundaries.select([_place(116, 40, country: 'US')])),
        isEmpty,
      );
      expect(_features(boundaries.select([_place(116, 40, country: 'CN')])), [
        province,
      ]);
      expect(_features(boundaries.select([_place(116, 40)])), [province]);
    },
  );

  test(
    'Hong Kong airport coastal mismatch still selects only Hong Kong',
    () async {
      Future<Map<String, dynamic>> read(String name) async =>
          jsonDecode(await rootBundle.loadString('assets/data/$name.geo.json'))
              as Map<String, dynamic>;
      final boundaries = DetailFootprintBoundaries(
        countries: await read('world-countries-50m'),
        provinces: await read('china-provinces'),
      );
      final airports = jsonDecode(
        await rootBundle.loadString('assets/data/airport-coordinates.json'),
      ) as Map;
      final hkg = airports['HKG'] as List;
      final airport = _place(
        (hkg[0] as num).toDouble(),
        (hkg[1] as num).toDouble(),
        country: hkg[4] as String,
      );
      final result = _features(boundaries.select([airport]));
      expect(result.map((f) => f['properties']['adcode']), [810000]);
      // The island's world feature and provincial feature must not both draw.
      final island = _place(114.158, 22.281, country: 'hk');
      expect(
        _features(boundaries.select([airport, island]))
            .map((f) => f['properties']['adcode']),
        [810000],
      );
      expect(
        _features(boundaries.select([_place(-77.03, 38.9, country: 'HK')]))
            .any((f) => f['properties']['adcode'] == 810000),
        isFalse,
      );
      expect(
        _features(
          boundaries.select([
            _place(113.914862, 22.31184, country: 'HK', visited: false),
          ]),
        ),
        isEmpty,
      );
      expect(
        _features(boundaries.select([_place(113.8107, 22.6393, country: 'CN')]))
            .map((f) => f['properties']['adcode']),
        [440000],
      );
    },
  );

  test(
    'bundled geometry selects Beijing/Guangdong and whole foreign features',
    () async {
      Future<Map<String, dynamic>> read(String name) async =>
          jsonDecode(await rootBundle.loadString('assets/data/$name.geo.json'))
              as Map<String, dynamic>;
      final boundaries = DetailFootprintBoundaries(
        countries: await read('world-countries-50m'),
        provinces: await read('china-provinces'),
      );
      final domestic = _features(
        boundaries.select([
          _place(116.4, 39.9, country: 'CN'),
          _place(113.3, 23.1, country: 'CN'),
        ]),
      );
      expect(
        domestic.map((f) => f['properties']['adcode']),
        unorderedEquals([110000, 440000]),
      );
      final overseas = _features(
        boundaries.select([
          // Use an inland observation: the bundled overview geometry omits
          // small coastal islands such as Manhattan. Never guess a nearby
          // country's assignment just to force a match.
          _place(-77.03, 38.9, country: 'US'),
          _place(-0.12, 51.5, country: 'GB'),
        ]),
      );
      expect(overseas, hasLength(2));
      final computed = await DetailFootprintLoader().load([
        _place(116.4, 39.9, country: 'CN'),
      ]);
      expect(jsonDecode(computed.encoded), computed.collection);
      expect(_features(computed.collection), hasLength(1));
    },
  );
}
