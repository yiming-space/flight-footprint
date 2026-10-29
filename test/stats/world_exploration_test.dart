import 'package:flutter_test/flutter_test.dart';

import 'package:flight_footprint/data/city_catalog.dart';
import 'package:flight_footprint/features/stats/world_exploration.dart';

void main() {
  group('continentForLocation', () {
    test(
      'assigns geographic sides of transcontinental countries by location',
      () {
        expect(
          continentForLocation(countryCode: 'RU', latitude: 55, longitude: 37),
          TravelContinent.europe,
        );
        expect(
          continentForLocation(countryCode: 'ru', latitude: 55, longitude: 100),
          TravelContinent.asia,
        );
        expect(
          continentForLocation(countryCode: 'TR', latitude: 41, longitude: 29),
          TravelContinent.europe,
        );
        expect(
          continentForLocation(countryCode: 'TR', latitude: 39, longitude: 35),
          TravelContinent.asia,
        );
        expect(
          continentForLocation(countryCode: 'KZ', latitude: 51, longitude: 50),
          TravelContinent.europe,
        );
        expect(
          continentForLocation(countryCode: 'EG', latitude: 30, longitude: 32),
          TravelContinent.africa,
        );
        expect(
          continentForLocation(countryCode: 'EG', latitude: 30, longitude: 34),
          TravelContinent.asia,
        );
      },
    );

    test('rejects invalid coordinates and unknown countries', () {
      expect(
        continentForLocation(
          countryCode: 'CN',
          latitude: double.nan,
          longitude: 0,
        ),
        isNull,
      );
      expect(
        continentForLocation(countryCode: 'CN', latitude: 91, longitude: 0),
        isNull,
      );
      expect(
        continentForLocation(countryCode: 'XX', latitude: 0, longitude: 0),
        isNull,
      );
    });
  });

  test('continent country groups do not assign a code more than once', () {
    final seen = <String, TravelContinent>{};
    for (final entry in continentCountryGroups.entries) {
      for (final code in entry.value.split(' ')) {
        expect(
          seen,
          isNot(contains(code)),
          reason: '$code appears in two groups',
        );
        seen[code] = entry.key;
      }
    }
    expect(seen['CN'], TravelContinent.asia);
    expect(seen['US'], TravelContinent.northAmerica);
    expect(seen['BR'], TravelContinent.southAmerica);
    expect(seen['AQ'], TravelContinent.antarctica);
  });

  test(
    'buildContinentVisits keeps split-country visits on their actual continent',
    () {
      final visits = buildContinentVisits(const [
        ExplorationPlace(
          name: 'Moscow',
          countryCode: 'RU',
          latitude: 55.75,
          longitude: 37.62,
        ),
        ExplorationPlace(
          name: 'Vladivostok',
          countryCode: 'RU',
          latitude: 43.12,
          longitude: 131.89,
        ),
      ]);

      final europe = visits.singleWhere(
        (item) => item.continent == TravelContinent.europe,
      );
      final asia = visits.singleWhere(
        (item) => item.continent == TravelContinent.asia,
      );
      expect(europe.countryCodes, {'RU'});
      expect(asia.countryCodes, {'RU'});
      expect(europe.places.map((place) => place.name), ['Moscow']);
      expect(asia.places.map((place) => place.name), ['Vladivostok']);
    },
  );

  test(
    'buildContinentVisits uses shared city aliases when a catalogue is given',
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
      final visits = buildContinentVisits([
        ExplorationPlace(
          name: 'Shanghai',
          countryCode: 'CN',
          latitude: 31.23,
          longitude: 121.47,
          visitedAt: DateTime(2024),
        ),
        ExplorationPlace(
          name: '上海',
          countryCode: 'CN',
          latitude: 31.23,
          longitude: 121.47,
          visitedAt: DateTime(2025),
        ),
        const ExplorationPlace(
          name: '苏州',
          countryCode: 'CN',
          latitude: 31.30,
          longitude: 120.58,
        ),
      ], cityCatalog: catalog);

      final asia = visits.singleWhere(
        (item) => item.continent == TravelContinent.asia,
      );
      expect(asia.places, hasLength(2));
      expect(asia.places.map((place) => place.name), ['上海', '苏州']);
    },
  );

  test('buildContinentVisits separates distant unknown homonyms', () {
    final visits = buildContinentVisits(const [
      ExplorationPlace(
        name: 'Springfield',
        countryCode: 'US',
        latitude: 39.78,
        longitude: -90.65,
      ),
      ExplorationPlace(
        name: 'Springfield',
        countryCode: 'US',
        latitude: 42.10,
        longitude: -72.59,
      ),
    ]);

    final northAmerica = visits.singleWhere(
      (item) => item.continent == TravelContinent.northAmerica,
    );
    expect(northAmerica.places, hasLength(2));
  });
}
