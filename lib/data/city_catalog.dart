import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart';

import 'airport_catalog.dart';
import 'airport_localization.dart';

/// A city that can be added to the travel footprint without a network call.
///
/// Chinese cities come from the province catalogue. International cities are
/// derived from the bundled airport catalogue so the picker covers the same
/// worldwide geography as flight-record search.
class CityCenter {
  const CityCenter({
    required this.name,
    required this.longitude,
    required this.latitude,
    required this.province,
    this.countryCode = 'CN',
    this.aliases = const [],
    this.isAdministrativeRegion = false,
  });

  final String name;
  final double longitude;
  final double latitude;
  final String province;
  final String countryCode;
  final List<String> aliases;

  /// Province-level rows are kept in the bundled China catalogue for
  /// province progress calculations, but they are not valid photo-city
  /// matches and should not become a map label.
  final bool isAdministrativeRegion;

  String get regionLabel {
    if (province.trim().isNotEmpty) return province;
    return localizedCountryName(countryCode);
  }

  bool matches(String query) {
    final values = <String>[name, province, countryCode, ...aliases];
    final normalizedQuery = CityCatalog.normalizeLookup(query);
    return normalizedQuery.isNotEmpty &&
        values.any(
          (value) =>
              CityCatalog.normalizeLookup(value).contains(normalizedQuery),
        );
  }

  CityCenter copyWith({
    String? name,
    double? longitude,
    double? latitude,
    String? province,
    String? countryCode,
    List<String>? aliases,
    bool? isAdministrativeRegion,
  }) => CityCenter(
    name: name ?? this.name,
    longitude: longitude ?? this.longitude,
    latitude: latitude ?? this.latitude,
    province: province ?? this.province,
    countryCode: countryCode ?? this.countryCode,
    aliases: aliases ?? this.aliases,
    isAdministrativeRegion:
        isAdministrativeRegion ?? this.isAdministrativeRegion,
  );
}

/// A small, dependency-free normalizer shared by city search, photo imports
/// and map labels. It intentionally only removes a terminal “市” for China;
/// names such as “胡志明市” are valid international city names and must stay
/// intact.
String normalizeMapCityName(String value, {String? countryCode}) {
  var normalized = value
      .trim()
      .replaceAll(RegExp(r'\s*[（(][^）)]*[）)]'), '')
      .replaceAll(RegExp(r'\s*[，,;；|].*$'), '')
      .trim();
  if (countryCode?.trim().toUpperCase() == 'CN' && normalized.endsWith('市')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized;
}

bool isProvinceMapName(String value) {
  final normalized = value.trim();
  return normalized.endsWith('省') ||
      normalized.endsWith('自治区') ||
      normalized.endsWith('特别行政区');
}

/// Lazily built lookup tables for repeated map, exploration and ranking
/// identity queries. Candidate lists retain catalogue order and can contain
/// multiple same-name cities for coordinate disambiguation.
class _CityIdentityIndex {
  _CityIdentityIndex(List<CityCenter> cities) {
    for (var index = 0; index < cities.length; index++) {
      final city = cities[index];
      _order[city] = index;
      final country = city.countryCode.trim().toUpperCase();
      for (final alias in <String>{city.name, ...city.aliases}) {
        final normalized = CityCatalog.normalizeLookup(
          normalizeMapCityName(alias, countryCode: country),
        );
        if (normalized.isEmpty) continue;
        _append(_byCountryAlias, '$country|$normalized', city);
        _append(_byGlobalAlias, normalized, city);
      }
      final nameKey = '$country|${CityCatalog.normalizeLookup(city.name)}';
      _append(_byCountryName, nameKey, city);
    }
  }

  final Map<String, List<CityCenter>> _byCountryAlias = {};
  final Map<String, List<CityCenter>> _byGlobalAlias = {};
  final Map<String, List<CityCenter>> _byCountryName = {};
  final Map<CityCenter, int> _order = {};

  static void _append(
    Map<String, List<CityCenter>> index,
    String key,
    CityCenter city,
  ) => index.putIfAbsent(key, () => <CityCenter>[]).add(city);

  List<CityCenter> aliasCandidates(
    String value, {
    required String countryCode,
  }) {
    if (countryCode.isNotEmpty) {
      final normalized = CityCatalog.normalizeLookup(
        normalizeMapCityName(value, countryCode: countryCode),
      );
      return _byCountryAlias['$countryCode|$normalized'] ?? const [];
    }
    final normalized = CityCatalog.normalizeLookup(value);
    final chinaNormalized = CityCatalog.normalizeLookup(
      normalizeMapCityName(value, countryCode: 'CN'),
    );
    final candidates = <CityCenter>{
      ...?_byGlobalAlias[normalized],
      ...?_byGlobalAlias[chinaNormalized],
    }.toList();
    candidates.sort((a, b) => _order[a]!.compareTo(_order[b]!));
    return candidates;
  }

  List<CityCenter> sameNameCandidates(String countryCode, String name) =>
      _byCountryName['${countryCode.trim().toUpperCase()}|${CityCatalog.normalizeLookup(name)}'] ??
      const [];
}

/// Resolves city identities across an ordered batch of places. Known catalogue
/// aliases use CityCatalog's country/name/coordinate matching; unknown names
/// are grouped into local 120 km clusters so separate distant homonyms do not
/// collapse into one map or exploration entry.
class CityIdentityResolver {
  CityIdentityResolver(this.catalog);

  final CityCatalog? catalog;
  final Map<String, List<_UnknownCityCluster>> _unknownClusters = {};

  String keyFor({
    required String name,
    required String? countryCode,
    required double latitude,
    required double longitude,
  }) {
    final country = countryCode?.trim().toUpperCase() ?? '';
    final known = catalog?.resolveCity(
      name,
      countryCode: country,
      latitude: latitude,
      longitude: longitude,
      allowCoordinateFallback: false,
    );
    if (known != null) {
      return catalog!.cityIdentityKey(
        name,
        countryCode: country,
        latitude: latitude,
        longitude: longitude,
      );
    }

    final normalizedName = CityCatalog.normalizeLookup(
      normalizeMapCityName(name, countryCode: country),
    );
    final baseKey = '$country:$normalizedName';
    if (normalizedName.isEmpty ||
        !latitude.isFinite ||
        !longitude.isFinite ||
        latitude.abs() > 90 ||
        longitude.abs() > 180) {
      return baseKey;
    }
    final clusters = _unknownClusters.putIfAbsent(
      baseKey,
      () => <_UnknownCityCluster>[],
    );
    for (var index = 0; index < clusters.length; index++) {
      final cluster = clusters[index];
      if (CityCatalog.distanceKm(
            fromLatitude: latitude,
            fromLongitude: longitude,
            toLatitude: cluster.latitude,
            toLongitude: cluster.longitude,
          ) <=
          120) {
        return index == 0 ? baseKey : '$baseKey:${cluster.id}';
      }
    }
    final cluster = _UnknownCityCluster(
      id: '${latitude.toStringAsFixed(3)},${longitude.toStringAsFixed(3)}',
      latitude: latitude,
      longitude: longitude,
    );
    clusters.add(cluster);
    return clusters.length == 1 ? baseKey : '$baseKey:${cluster.id}';
  }
}

class _UnknownCityCluster {
  const _UnknownCityCluster({
    required this.id,
    required this.latitude,
    required this.longitude,
  });

  final String id;
  final double latitude;
  final double longitude;
}

/// Offline city picker for manually adding a travel footprint. Keeping the
/// catalogue bundled means adding a place works without network access.
class CityCatalog {
  CityCatalog(List<CityCenter> cities)
    : cities = List<CityCenter>.unmodifiable(cities);

  static const assetPath = 'assets/data/china-city-centers.json';
  static const _airportAssetPath = 'assets/data/airport-coordinates.json';
  static Future<CityCatalog>? _worldCache;
  final List<CityCenter> cities;
  late final _CityIdentityIndex _identityIndex = _CityIdentityIndex(cities);

  factory CityCatalog.fromJsonString(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! List) return CityCatalog(const []);
    final cities = <CityCenter>[];
    for (final value in decoded) {
      if (value is! Map) continue;
      final rawName = value['name']?.toString().trim() ?? '';
      final longitude = value['longitude'];
      final latitude = value['latitude'];
      final countryCode =
          value['countryCode']?.toString().toUpperCase() ?? 'CN';
      if (rawName.isEmpty || longitude is! num || latitude is! num) continue;
      cities.add(
        CityCenter(
          name: _canonicalCityName(rawName, countryCode: countryCode),
          longitude: longitude.toDouble(),
          latitude: latitude.toDouble(),
          province: value['province']?.toString() ?? '',
          countryCode: countryCode,
          aliases: <String>{rawName, ..._stringList(value['aliases'])}.toList(),
          isAdministrativeRegion: _isProvinceName(rawName, countryCode),
        ),
      );
    }
    final deduplicated = <String, CityCenter>{};
    for (final city in cities) {
      final baseKey = _keyFor(city.countryCode, city.name);
      final existingKey = _nearbyCityKey(deduplicated, baseKey, city);
      final existing = existingKey == null ? null : deduplicated[existingKey];
      if (existing == null) {
        deduplicated[_uniqueCityKey(deduplicated, baseKey, city)] = city;
        continue;
      }
      // A source can contain both “丽江” and “丽江市”. Keep one canonical
      // city centre and retain every source spelling for lookup/deduplication.
      deduplicated[existingKey!] = existing.copyWith(
        aliases: <String>{...existing.aliases, ...city.aliases}.toList(),
        isAdministrativeRegion:
            existing.isAdministrativeRegion && city.isAdministrativeRegion,
      );
    }
    return CityCatalog(List.unmodifiable(deduplicated.values));
  }

  static List<String> _stringList(dynamic value) => [
    for (final item in (value is List ? value : const []))
      if (item != null && item.toString().trim().isNotEmpty) item.toString(),
  ];

  /// Load only the Chinese catalogue. This is useful for resolving province
  /// progress without parsing the much larger worldwide airport file.
  static Future<CityCatalog> loadChina({AssetBundle? bundle}) async {
    final source = await (bundle ?? rootBundle).loadString(assetPath);
    return CityCatalog.fromJsonString(source);
  }

  /// Load Chinese cities plus a deduplicated worldwide airport-city index.
  static Future<CityCatalog> load({
    AssetBundle? bundle,
    bool includeWorld = true,
  }) {
    // The worldwide index is immutable bundled data. Reuse the parsed result
    // across sheets so reopening “补充城市” never stalls its animation.
    if (includeWorld && bundle == null) {
      return _worldCache ??= _loadWorld(rootBundle);
    }
    return _loadWorld(bundle ?? rootBundle, includeWorld: includeWorld);
  }

  static Future<CityCatalog> _loadWorld(
    AssetBundle assetBundle, {
    bool includeWorld = true,
  }) async {
    final chinaSource = await assetBundle.loadString(assetPath);
    final china = CityCatalog.fromJsonString(chinaSource);
    if (!includeWorld) return china;
    final airportSource = await assetBundle.loadString(_airportAssetPath);
    return china.withAirports(AirportCatalog.fromJsonString(airportSource));
  }

  CityCatalog withAirports(AirportCatalog catalog) {
    final merged = <String, CityCenter>{};
    for (final city in cities) {
      final baseKey = _keyFor(city.countryCode, city.name);
      final existingKey = _nearbyCityKey(merged, baseKey, city);
      if (existingKey == null) {
        merged[_uniqueCityKey(merged, baseKey, city)] = city;
      } else {
        final existing = merged[existingKey]!;
        merged[existingKey] = existing.copyWith(
          aliases: <String>{...existing.aliases, ...city.aliases}.toList(),
          isAdministrativeRegion:
              existing.isAdministrativeRegion && city.isAdministrativeRegion,
        );
      }
    }
    for (final airport in catalog.values) {
      final rawCity = airport.city.trim();
      if (rawCity.isEmpty ||
          !airport.latitude.isFinite ||
          !airport.longitude.isFinite) {
        continue;
      }
      final localizedCity = localizedAirportCity(airport);
      final countryCode = airport.countryCode.trim().toUpperCase();
      final name = _canonicalCityName(
        localizedCity.isEmpty ? rawCity : localizedCity,
        countryCode: countryCode,
      );
      final key = _keyFor(countryCode, name);
      final aliases = <String>{
        name,
        rawCity,
        airport.iataCode,
        airport.name,
        localizedCity,
        if (localizedCity.isNotEmpty) '$localizedCity机场',
      }..removeWhere((value) => value.trim().isEmpty);
      final existingKey = _nearbyCityKey(
        merged,
        key,
        CityCenter(
          name: name,
          longitude: airport.longitude,
          latitude: airport.latitude,
          province: localizedCountryName(countryCode),
          countryCode: countryCode,
        ),
      );
      final existing = existingKey == null ? null : merged[existingKey];
      if (existing != null) {
        // Keep the curated city centre but add the airport's source-language
        // spelling. This lets old “Lijiang” records resolve to “丽江”.
        merged[existingKey!] = existing.copyWith(
          aliases: <String>{...existing.aliases, ...aliases}.toList(),
        );
        continue;
      }
      final center = CityCenter(
        name: name,
        longitude: airport.longitude,
        latitude: airport.latitude,
        province: localizedCountryName(countryCode),
        countryCode: countryCode,
        aliases: List.unmodifiable(aliases),
      );
      merged[_uniqueCityKey(merged, key, center)] = center;
    }
    return CityCatalog(List.unmodifiable(merged.values));
  }

  static String _keyFor(String countryCode, String name) =>
      '${countryCode.trim().toUpperCase()}|${normalizeLookup(name)}';

  static String? _nearbyCityKey(
    Map<String, CityCenter> existing,
    String baseKey,
    CityCenter candidate,
  ) {
    for (final entry in existing.entries) {
      if (entry.key != baseKey && !entry.key.startsWith('$baseKey@')) continue;
      if (distanceKm(
            fromLatitude: candidate.latitude,
            fromLongitude: candidate.longitude,
            toLatitude: entry.value.latitude,
            toLongitude: entry.value.longitude,
          ) <=
          120) {
        return entry.key;
      }
    }
    return null;
  }

  static String _uniqueCityKey(
    Map<String, CityCenter> existing,
    String baseKey,
    CityCenter candidate,
  ) {
    if (!existing.containsKey(baseKey)) return baseKey;
    return '$baseKey@${candidate.latitude.toStringAsFixed(3)},${candidate.longitude.toStringAsFixed(3)}';
  }

  List<CityCenter> search(String query, {int limit = 12}) {
    final normalized = normalizeLookup(query);
    if (normalized.isEmpty) return const [];
    final matches = cities
        .where(
          (city) => !city.isAdministrativeRegion && city.matches(normalized),
        )
        .toList();
    matches.sort((left, right) {
      int score(CityCenter city) {
        final name = normalizeLookup(city.name);
        if (name == normalized) return 0;
        if (name.startsWith(normalized)) return 1;
        return 2;
      }

      return score(left).compareTo(score(right));
    });
    return matches.take(limit).toList(growable: false);
  }

  /// Finds the nearest bundled city for a GPS coordinate. The catalogue is
  /// intentionally offline: Chinese city centres and worldwide airport-city
  /// entries provide a practical match without sending a photo location to a
  /// geocoding service.
  CityCenter? nearest(
    double latitude,
    double longitude, {
    double maxDistanceKm = 120,
    String? countryCode,
  }) {
    if (!latitude.isFinite ||
        !longitude.isFinite ||
        latitude.abs() > 90 ||
        longitude.abs() > 180 ||
        maxDistanceKm <= 0) {
      return null;
    }
    CityCenter? nearest;
    var bestDistance = double.infinity;
    final normalizedCountry = countryCode?.trim().toUpperCase() ?? '';
    for (final city in cities) {
      if (city.isAdministrativeRegion ||
          (normalizedCountry.isNotEmpty &&
              city.countryCode.trim().toUpperCase() != normalizedCountry)) {
        continue;
      }
      final distance = distanceKm(
        fromLatitude: latitude,
        fromLongitude: longitude,
        toLatitude: city.latitude,
        toLongitude: city.longitude,
      );
      if (distance < bestDistance) {
        bestDistance = distance;
        nearest = city;
      }
    }
    return bestDistance <= maxDistanceKm ? nearest : null;
  }

  /// Resolve a saved/imported city name to the one canonical display name.
  /// Direct aliases handle old English/pinyin records; coordinates provide a
  /// safe fallback for a reverse-geocoder spelling that is not in the alias
  /// table yet.
  CityCenter? resolveCity(
    String value, {
    String? countryCode,
    double? latitude,
    double? longitude,
    bool allowCoordinateFallback = true,
  }) {
    final lookup = normalizeLookup(value);
    final normalizedCountry = countryCode?.trim().toUpperCase() ?? '';
    if (lookup.isNotEmpty) {
      final matches = <CityCenter>[];
      final candidates = _identityIndex.aliasCandidates(
        value,
        countryCode: normalizedCountry,
      );
      for (final city in candidates) {
        if (city.isAdministrativeRegion ||
            (normalizedCountry.isNotEmpty &&
                city.countryCode.trim().toUpperCase() != normalizedCountry)) {
          continue;
        }
        final values = <String>[city.name, ...city.aliases];
        if (values.any(
          (candidate) =>
              normalizeLookup(
                normalizeMapCityName(candidate, countryCode: city.countryCode),
              ) ==
              normalizeLookup(
                normalizeMapCityName(value, countryCode: city.countryCode),
              ),
        )) {
          matches.add(city);
        }
      }
      if (matches.isNotEmpty) {
        // A known spelling is the strongest signal. When that spelling names
        // multiple places in one country, use the supplied position to select
        // the local city cluster (for example, airport records in same-named
        // cities). Without coordinates retain deterministic catalogue order.
        if (latitude != null && longitude != null) {
          matches.sort(
            (a, b) =>
                distanceKm(
                  fromLatitude: latitude,
                  fromLongitude: longitude,
                  toLatitude: a.latitude,
                  toLongitude: a.longitude,
                ).compareTo(
                  distanceKm(
                    fromLatitude: latitude,
                    fromLongitude: longitude,
                    toLatitude: b.latitude,
                    toLongitude: b.longitude,
                  ),
                ),
          );
        }
        return matches.first;
      }
    }
    if (allowCoordinateFallback && latitude != null && longitude != null) {
      return nearest(
        latitude,
        longitude,
        maxDistanceKm: 120,
        countryCode: normalizedCountry.isEmpty ? null : normalizedCountry,
      );
    }
    return null;
  }

  String canonicalCityName(
    String value, {
    String? countryCode,
    double? latitude,
    double? longitude,
    bool allowCoordinateFallback = true,
  }) {
    final city = resolveCity(
      value,
      countryCode: countryCode,
      latitude: latitude,
      longitude: longitude,
      allowCoordinateFallback: allowCoordinateFallback,
    );
    return city?.name ??
        _canonicalCityName(value, countryCode: countryCode ?? '');
  }

  String canonicalCityKey(
    String value, {
    String? countryCode,
    double? latitude,
    double? longitude,
  }) {
    final city = resolveCity(
      value,
      countryCode: countryCode,
      latitude: latitude,
      longitude: longitude,
    );
    final code = city?.countryCode ?? countryCode ?? '';
    return _keyFor(
      code,
      city?.name ?? _canonicalCityName(value, countryCode: code),
    );
  }

  /// Stable identity for a named city, shared by map and exploration views.
  ///
  /// Known names and country are resolved first. Coordinates disambiguate
  /// catalogue entries that share a name and keep airports in one local city
  /// cluster together.
  String cityIdentityKey(
    String value, {
    String? countryCode,
    double? latitude,
    double? longitude,
  }) {
    final city = resolveCity(
      value,
      countryCode: countryCode,
      latitude: latitude,
      longitude: longitude,
      allowCoordinateFallback: false,
    );
    final code = city?.countryCode ?? countryCode ?? '';
    final name = city?.name ?? _canonicalCityName(value, countryCode: code);
    // Preserve separate catalogue clusters when one exact name occurs more
    // than once in a country. The center coordinate is stable across all
    // airports whose known alias resolves to that cluster.
    final siblings = _identityIndex
        .sameNameCandidates(code, name)
        .where((candidate) => !candidate.isAdministrativeRegion)
        .toList();
    final suffix = siblings.length > 1 && city != null
        ? ':${city.latitude.toStringAsFixed(3)},${city.longitude.toStringAsFixed(3)}'
        : '';
    final key = _keyFor(code, name);
    final separator = key.indexOf('|');
    return separator < 0
        ? '$key$suffix'
        : '${key.substring(0, separator)}:${key.substring(separator + 1)}$suffix';
  }

  static String normalizeLookup(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[\s\-·•_/.,，。:：()（）【】\[\]]'), '');

  static double distanceKm({
    required double fromLatitude,
    required double fromLongitude,
    required double toLatitude,
    required double toLongitude,
  }) {
    const earthRadiusKm = 6371.0088;
    final fromLat = fromLatitude * math.pi / 180;
    final toLat = toLatitude * math.pi / 180;
    final deltaLat = (toLatitude - fromLatitude) * math.pi / 180;
    final deltaLon = (toLongitude - fromLongitude) * math.pi / 180;
    final a =
        math.sin(deltaLat / 2) * math.sin(deltaLat / 2) +
        math.cos(fromLat) *
            math.cos(toLat) *
            math.sin(deltaLon / 2) *
            math.sin(deltaLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusKm * c;
  }

  /// Resolve a Chinese province from a saved city. Exact names cover the
  /// bundled airport/localization labels; the nearest catalogue city is a
  /// conservative fallback for an airport whose display name is not curated.
  String? provinceFor(String name, {double? longitude, double? latitude}) {
    final normalized = _normalizeCityName(name);
    for (final city in cities) {
      if (city.countryCode != 'CN' ||
          city.isAdministrativeRegion ||
          _normalizeCityName(city.name) != normalized) {
        continue;
      }
      return city.province.trim().isEmpty ? null : city.province;
    }
    if (longitude == null || latitude == null) return null;
    CityCenter? nearest;
    var bestDistance = double.infinity;
    for (final city in cities) {
      if (city.countryCode != 'CN' ||
          city.isAdministrativeRegion ||
          city.province.trim().isEmpty) {
        continue;
      }
      final dx = city.longitude - longitude;
      final dy = city.latitude - latitude;
      final distance = dx * dx + dy * dy;
      if (distance < bestDistance) {
        bestDistance = distance;
        nearest = city;
      }
    }
    // Keep the fallback local to a province-sized neighbourhood; an airport
    // in a missing/unknown city must not light up a random distant province.
    return bestDistance <= 4.5 ? nearest?.province : null;
  }

  static String _canonicalCityName(
    String value, {
    required String countryCode,
  }) => normalizeMapCityName(value, countryCode: countryCode);

  static bool _isProvinceName(String value, String countryCode) {
    if (countryCode.trim().toUpperCase() != 'CN') return false;
    final normalized = value.trim();
    return normalized.endsWith('省') ||
        normalized.endsWith('自治区') ||
        normalized.endsWith('特别行政区');
  }

  static String _normalizeCityName(String value) =>
      normalizeLookup(normalizeMapCityName(value, countryCode: 'CN'))
          .replaceAll(RegExp(r'(地区|自治州)$'), '');
}
