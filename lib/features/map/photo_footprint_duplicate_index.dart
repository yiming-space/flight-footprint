import 'dart:math' as math;

import '../../data/city_catalog.dart';
import '../../domain/visited_place.dart';
import 'map_models.dart';

/// Exact photo-import duplicate checks with a coarse geographic prefilter.
/// The final 25 km decision still uses the same distance calculation as the
/// original linear scan.
class PhotoFootprintDuplicateIndex {
  PhotoFootprintDuplicateIndex({
    required CityCatalog catalog,
    required Iterable<VisitedPlace> places,
  }) {
    for (final place in places) {
      if (isProvinceMapLabel(place.name)) continue;
      final key = catalog.canonicalCityKey(
        place.name,
        countryCode: place.countryCode,
        latitude: place.latitude,
        longitude: place.longitude,
      );
      _cityKeys.add(key);
      if (!place.latitude.isFinite ||
          !place.longitude.isFinite ||
          place.latitude.abs() > 90 ||
          place.longitude.abs() > 180) {
        continue;
      }
      final country = place.countryCode?.trim().toUpperCase() ?? '';
      final point = _PhotoPlacePoint(
        latitude: place.latitude,
        longitude: place.longitude,
      );
      final latCell = _latCell(point.latitude);
      _latitudeBands.putIfAbsent('$country|$latCell', () => []).add(point);
      final lonCell = _lonCell(point.longitude);
      _cells.putIfAbsent('$country|$latCell|$lonCell', () => []).add(point);
    }
  }

  static const _cellDegrees = .2;
  final Set<String> _cityKeys = {};
  final Map<String, List<_PhotoPlacePoint>> _cells = {};
  final Map<String, List<_PhotoPlacePoint>> _latitudeBands = {};

  bool containsCityKey(String key) => _cityKeys.contains(key);

  bool isNearExisting({
    required String countryCode,
    required double latitude,
    required double longitude,
    double maxDistanceKm = 25,
  }) {
    final country = countryCode.trim().toUpperCase();
    final latCell = _latCell(latitude);
    final cosLatitude = math.cos(latitude * math.pi / 180).abs();
    final lonRadius = cosLatitude < .15
        ? null
        : (maxDistanceKm / (111.2 * cosLatitude * _cellDegrees)).ceil() + 1;
    final candidates = <_PhotoPlacePoint>[];
    for (var latOffset = -3; latOffset <= 3; latOffset++) {
      final band = '$country|${latCell + latOffset}';
      if (lonRadius == null) {
        candidates.addAll(_latitudeBands[band] ?? const []);
        continue;
      }
      for (var lonOffset = -lonRadius; lonOffset <= lonRadius; lonOffset++) {
        final lonCell = (_lonCell(longitude) + lonOffset) % 1800;
        final wrappedLonCell = lonCell < 0 ? lonCell + 1800 : lonCell;
        candidates.addAll(_cells['$band|$wrappedLonCell'] ?? const []);
      }
    }
    // Unspecified-country records have always been eligible for a proximity
    // duplicate regardless of the photo's country. Include those candidates.
    if (country.isNotEmpty) {
      for (var latOffset = -3; latOffset <= 3; latOffset++) {
        final band = '|${latCell + latOffset}';
        if (lonRadius == null) {
          candidates.addAll(_latitudeBands[band] ?? const []);
        } else {
          for (
            var lonOffset = -lonRadius;
            lonOffset <= lonRadius;
            lonOffset++
          ) {
            final lonCell = (_lonCell(longitude) + lonOffset) % 1800;
            final wrappedLonCell = lonCell < 0 ? lonCell + 1800 : lonCell;
            candidates.addAll(_cells['$band|$wrappedLonCell'] ?? const []);
          }
        }
      }
    }
    return candidates.any(
      (place) =>
          CityCatalog.distanceKm(
            fromLatitude: place.latitude,
            fromLongitude: place.longitude,
            toLatitude: latitude,
            toLongitude: longitude,
          ) <=
          maxDistanceKm,
    );
  }

  static int _latCell(double latitude) =>
      ((latitude + 90) / _cellDegrees).floor();

  static int _lonCell(double longitude) =>
      ((longitude + 180) / _cellDegrees).floor() % 1800;
}

class _PhotoPlacePoint {
  const _PhotoPlacePoint({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;
}
