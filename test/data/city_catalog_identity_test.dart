import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:flight_footprint/data/city_catalog.dart';

void main() {
  test(
    'city identity canonicalizes known aliases without coordinate fallback',
    () {
      final catalog = CityCatalog([
        const CityCenter(
          name: '上海',
          aliases: ['Shanghai'],
          longitude: 121.47,
          latitude: 31.23,
          province: '上海市',
          countryCode: 'CN',
        ),
      ]);

      expect(catalog.cityIdentityKey('Shanghai', countryCode: 'cn'), 'CN:上海');
      expect(catalog.cityIdentityKey('上海', countryCode: 'CN'), 'CN:上海');
      // City labels use the existing China suffix normalization, but an
      // unknown nearby city name must not resolve to the only catalogue entry.
      expect(catalog.cityIdentityKey('苏州市', countryCode: 'CN'), 'CN:苏州');
    },
  );

  test(
    'uses country, known aliases and position to separate same-name cities',
    () {
      final catalog = CityCatalog([
        const CityCenter(
          name: 'Springfield',
          aliases: ['Springfield Airport'],
          longitude: -90.65,
          latitude: 39.78,
          province: 'Illinois',
          countryCode: 'US',
        ),
        const CityCenter(
          name: 'Springfield',
          aliases: ['Springfield Airport'],
          longitude: -72.59,
          latitude: 42.10,
          province: 'Massachusetts',
          countryCode: 'US',
        ),
        const CityCenter(
          name: 'Springfield',
          longitude: -90.65,
          latitude: 39.78,
          province: 'Ontario',
          countryCode: 'CA',
        ),
      ]);

      final illinois = catalog.cityIdentityKey(
        'Springfield Airport',
        countryCode: 'US',
        latitude: 39.78,
        longitude: -90.65,
      );
      final massachusetts = catalog.cityIdentityKey(
        'Springfield Airport',
        countryCode: 'US',
        latitude: 42.10,
        longitude: -72.59,
      );
      final canada = catalog.cityIdentityKey(
        'Springfield',
        countryCode: 'CA',
        latitude: 39.78,
        longitude: -90.65,
      );

      expect(illinois, isNot(massachusetts));
      expect(illinois, isNot(canada));
      expect(
        catalog.cityIdentityKey(
          'Springfield Airport',
          countryCode: 'US',
          latitude: 39.80,
          longitude: -90.63,
        ),
        illinois,
      );
    },
  );

  test('catalogue ingestion retains distant homonyms in one country', () {
    final catalog = CityCatalog.fromJsonString('''
      [
        {"name":"Springfield","longitude":-90.65,"latitude":39.78,"province":"Illinois","countryCode":"US","aliases":["Airport"]},
        {"name":"Springfield","longitude":-72.59,"latitude":42.10,"province":"Massachusetts","countryCode":"US","aliases":["Airport"]}
      ]
    ''');

    expect(catalog.cities, hasLength(2));
    expect(
      catalog.cityIdentityKey(
        'Airport',
        countryCode: 'US',
        latitude: 39.78,
        longitude: -90.65,
      ),
      isNot(
        catalog.cityIdentityKey(
          'Airport',
          countryCode: 'US',
          latitude: 42.10,
          longitude: -72.59,
        ),
      ),
    );
  });

  test(
    'an unknown nearby name keeps its supplied name during canonicalization',
    () {
      final catalog = CityCatalog([
        const CityCenter(
          name: '上海',
          longitude: 121.47,
          latitude: 31.23,
          province: '上海市',
          countryCode: 'CN',
        ),
      ]);

      expect(
        catalog.canonicalCityName(
          '苏州',
          countryCode: 'CN',
          latitude: 31.30,
          longitude: 120.60,
          allowCoordinateFallback: false,
        ),
        '苏州',
      );
    },
  );

  test('batch resolver clusters unknown homonyms within 120 km only', () {
    final resolver = CityIdentityResolver(null);
    final first = resolver.keyFor(
      name: 'Springfield',
      countryCode: 'US',
      latitude: 39.78,
      longitude: -90.65,
    );
    final nearby = resolver.keyFor(
      name: 'Springfield',
      countryCode: 'US',
      latitude: 39.80,
      longitude: -90.63,
    );
    final distant = resolver.keyFor(
      name: 'Springfield',
      countryCode: 'US',
      latitude: 42.10,
      longitude: -72.59,
    );
    final otherCountry = resolver.keyFor(
      name: 'Springfield',
      countryCode: 'CA',
      latitude: 39.78,
      longitude: -90.65,
    );

    expect(nearby, first);
    expect(distant, isNot(first));
    expect(otherCountry, isNot(first));
  });

  test('measures repeated identity lookups against a large city catalogue', () {
    const cityCount = 20000;
    const lookupCount = 10000;
    final catalog = CityCatalog([
      for (var index = 0; index < cityCount; index++)
        CityCenter(
          name: 'City $index',
          aliases: ['Alias $index'],
          longitude: (index % 360) - 180,
          latitude: (index % 160) - 80,
          province: '',
          countryCode: 'US',
        ),
    ]);

    final warmup = Stopwatch()..start();
    expect(
      catalog.cityIdentityKey('Alias 12345', countryCode: 'US'),
      'US:city12345',
    );
    warmup.stop();

    final repeated = Stopwatch()..start();
    for (var index = 0; index < lookupCount; index++) {
      final cityIndex = index % cityCount;
      expect(
        catalog.cityIdentityKey('Alias $cityIndex', countryCode: 'US'),
        'US:city$cityIndex',
      );
    }
    repeated.stop();
    debugPrint(
      'CityCatalog: $cityCount entries; index warmup ${warmup.elapsedMilliseconds}ms; '
      '$lookupCount repeated lookups ${repeated.elapsedMilliseconds}ms',
    );
  });
}
