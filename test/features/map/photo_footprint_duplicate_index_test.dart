import 'package:flutter_test/flutter_test.dart';
import 'package:flight_footprint/data/city_catalog.dart';
import 'package:flight_footprint/domain/visited_place.dart';
import 'package:flight_footprint/features/map/photo_footprint_duplicate_index.dart';

void main() {
  final catalog = CityCatalog([
    const CityCenter(
      name: '上海',
      longitude: 121.47,
      latitude: 31.23,
      province: '上海市',
      countryCode: 'CN',
    ),
  ]);

  test('matches city identity, nearby locations, and country semantics', () {
    final index = PhotoFootprintDuplicateIndex(
      catalog: catalog,
      places: [
        _place(name: '上海市', latitude: 31.23, longitude: 121.47),
        _place(
          name: 'Paris',
          latitude: 48.8566,
          longitude: 2.3522,
          countryCode: 'FR',
        ),
        _place(
          name: 'Unknown',
          latitude: 35,
          longitude: 139,
          countryCode: null,
        ),
      ],
    );

    expect(
      index.containsCityKey(
        catalog.canonicalCityKey(
          '上海',
          countryCode: 'CN',
          latitude: 31.23,
          longitude: 121.47,
        ),
      ),
      isTrue,
    );
    expect(
      index.isNearExisting(countryCode: 'FR', latitude: 48.85, longitude: 2.35),
      isTrue,
    );
    // Missing country codes remain eligible for proximity checks, matching
    // the former scan's country filter.
    expect(
      index.isNearExisting(countryCode: 'JP', latitude: 35, longitude: 139),
      isTrue,
    );
    expect(
      index.isNearExisting(
        countryCode: 'CN',
        latitude: 48.8566,
        longitude: 2.3522,
      ),
      isFalse,
    );
  });

  test('ignores province rows and preserves 25 km boundary behavior', () {
    final index = PhotoFootprintDuplicateIndex(
      catalog: catalog,
      places: [
        _place(name: '浙江省', latitude: 31.23, longitude: 121.47),
        _place(name: 'Test City', latitude: 0, longitude: 0, countryCode: 'US'),
      ],
    );

    expect(
      index.containsCityKey(
        catalog.canonicalCityKey(
          '浙江省',
          countryCode: 'CN',
          latitude: 31.23,
          longitude: 121.47,
        ),
      ),
      isFalse,
    );
    expect(
      index.isNearExisting(countryCode: 'US', latitude: 0, longitude: 0.224),
      isTrue,
    );
    expect(
      index.isNearExisting(countryCode: 'US', latitude: 0, longitude: 0.226),
      isFalse,
    );
  });
}

VisitedPlace _place({
  required String name,
  required double latitude,
  required double longitude,
  String? countryCode = 'CN',
}) {
  final now = DateTime.utc(2026);
  return VisitedPlace(
    id: name,
    name: name,
    latitude: latitude,
    longitude: longitude,
    visitedAt: now,
    createdAt: now,
    updatedAt: now,
    countryCode: countryCode,
  );
}
