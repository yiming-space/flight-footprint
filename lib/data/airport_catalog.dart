import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart';

import 'airport_localization.dart';
import '../domain/airport.dart';

/// A country represented by one or more airports in the offline catalogue.
/// Keeping this small view model next to [AirportCatalog] lets the picker
/// offer a country-first search without loading another network dataset.
class AirportCountry {
  const AirportCountry({
    required this.code,
    required this.name,
    required this.englishName,
    required this.airportCount,
  });

  final String code;
  final String name;
  final String englishName;
  final int airportCount;
}

class AirportCatalog {
  AirportCatalog(this._airports)
    : _airportsByCountry = _buildCountryIndex(_airports),
      _searchIndex = _buildSearchIndex(_airports.values);

  static const assetPath = 'assets/data/airport-coordinates.json';
  final Map<String, Airport> _airports;
  final Map<String, List<Airport>> _airportsByCountry;
  final List<_AirportSearchEntry> _searchIndex;

  late final List<AirportCountry> _countries =
      [
        for (final entry in _airportsByCountry.entries)
          AirportCountry(
            code: entry.key,
            name: localizedCountryName(entry.key),
            englishName: localizedCountryEnglishName(entry.key),
            airportCount: entry.value.length,
          ),
      ]..sort((left, right) {
        final name = left.name.compareTo(right.name);
        if (name != 0) return name;
        return left.code.compareTo(right.code);
      });

  factory AirportCatalog.fromJsonString(String source) {
    final raw = jsonDecode(source) as Map<String, dynamic>;
    final airports = <String, Airport>{};
    for (final entry in raw.entries) {
      final value = entry.value;
      if (value is! List || value.length < 5) continue;
      final longitude = value[0];
      final latitude = value[1];
      if (longitude is! num || latitude is! num) continue;
      final code = entry.key.toUpperCase();
      airports[code] = Airport(
        iataCode: code,
        longitude: longitude.toDouble(),
        latitude: latitude.toDouble(),
        name: value[2]?.toString() ?? '',
        city: value[3]?.toString() ?? '',
        countryCode: value[4]?.toString() ?? '',
        icaoCode: value.length > 5 ? value[5]?.toString() ?? '' : '',
        type: value.length > 6 ? value[6]?.toString() ?? '' : '',
        scheduledService: value.length > 7 && _isTrue(value[7]),
        isoRegion: value.length > 8 ? value[8]?.toString() ?? '' : '',
        keywords: value.length > 9 ? _keywords(value[9]) : const [],
      );
    }
    return AirportCatalog(Map.unmodifiable(airports));
  }

  static Future<AirportCatalog> load({AssetBundle? bundle}) async {
    final source = await (bundle ?? rootBundle).loadString(assetPath);
    return AirportCatalog.fromJsonString(source);
  }

  Iterable<Airport> get values => _airports.values;

  /// Countries represented by the bundled airport data, sorted by their
  /// localized display name. The list is built lazily so app startup keeps
  /// the same cost as before.
  List<AirportCountry> get countries => List.unmodifiable(_countries);

  Airport? findByIata(String code) => _airports[code.trim().toUpperCase()];

  AirportCountry? findCountry(String query) {
    final normalized = _normalizeSearchText(query);
    if (normalized.isEmpty) return null;
    for (final country in _countries) {
      final aliases = <String>[country.code, country.name, country.englishName];
      if (aliases.any((alias) => _normalizeSearchText(alias) == normalized)) {
        return country;
      }
    }
    return null;
  }

  /// Returns country suggestions for the airport picker. Matching supports
  /// Chinese names, English names and ISO alpha-2 codes.
  Iterable<AirportCountry> searchCountries(String query, {int limit = 8}) {
    final normalized = _normalizeSearchText(query);
    if (normalized.isEmpty || limit <= 0) return const [];
    final matches = <_ScoredCountry>[];
    for (final country in _countries) {
      final score = _bestScore(normalized, <String, int>{
        country.code: 0,
        country.name: 2,
        country.englishName: 3,
      });
      if (score != null) {
        matches.add(_ScoredCountry(country, score));
      }
    }
    matches.sort((left, right) {
      final score = left.score.compareTo(right.score);
      if (score != 0) return score;
      final count = right.country.airportCount.compareTo(
        left.country.airportCount,
      );
      if (count != 0) return count;
      return left.country.code.compareTo(right.country.code);
    });
    return matches.take(limit).map((match) => match.country);
  }

  /// Lists all airports in one country. Scheduled and larger facilities are
  /// shown first, while smaller facilities remain available further down the
  /// list for users who need an exact regional airport.
  List<Airport> airportsForCountry(String countryCode, {int? limit}) {
    final code = countryCode.trim().toUpperCase();
    final airports = [...(_airportsByCountry[code] ?? const <Airport>[])];
    airports.sort(_compareAirports);
    final result = limit == null ? airports : airports.take(limit).toList();
    return List.unmodifiable(result);
  }

  Iterable<Airport> search(String query, {int limit = 20}) {
    final normalized = _normalizeSearchText(query);
    if (normalized.isEmpty || limit <= 0) return const [];
    final matches = <_ScoredAirport>[];
    for (final entry in _searchIndex) {
      final score = _bestNormalizedScore(normalized, entry.fields);
      if (score != null) {
        matches.add(_ScoredAirport(entry.airport, score));
      }
    }
    matches.sort((left, right) {
      final score = left.score.compareTo(right.score);
      if (score != 0) return score;
      final scheduled =
          right.airport.scheduledService == left.airport.scheduledService
          ? 0
          : right.airport.scheduledService
          ? 1
          : -1;
      if (scheduled != 0) return scheduled;
      final type = _typeRank(left.airport.type)
          .compareTo(_typeRank(right.airport.type));
      if (type != 0) return type;
      return left.airport.iataCode.compareTo(right.airport.iataCode);
    });
    return matches.take(limit).map((match) => match.airport);
  }

  static bool _isTrue(dynamic value) {
    if (value is bool) return value;
    return value?.toString().trim().toLowerCase() == 'yes' ||
        value?.toString().trim().toLowerCase() == 'true';
  }

  static List<String> _keywords(dynamic value) {
    final values = value is List
        ? value
        : value is String
        ? value.split(',')
        : const [];
    final result = <String>[];
    final seen = <String>{};
    for (final item in values) {
      final keyword = item?.toString().trim() ?? '';
      final key = keyword.toLowerCase();
      if (keyword.isEmpty || !seen.add(key)) continue;
      result.add(keyword);
    }
    return List.unmodifiable(result);
  }

  static Map<String, List<Airport>> _buildCountryIndex(
    Map<String, Airport> airports,
  ) {
    final groups = <String, List<Airport>>{};
    for (final airport in airports.values) {
      final code = airport.countryCode.trim().toUpperCase();
      if (code.isEmpty) continue;
      groups.putIfAbsent(code, () => <Airport>[]).add(airport);
    }
    final indexed = <String, List<Airport>>{
      for (final entry in groups.entries)
        entry.key: List<Airport>.unmodifiable(entry.value),
    };
    return Map.unmodifiable(indexed);
  }

  static List<_AirportSearchEntry> _buildSearchIndex(
    Iterable<Airport> airports,
  ) => [
    for (final airport in airports)
      _AirportSearchEntry(airport, _searchFields(airport)),
  ];

  static List<_AirportSearchField> _searchFields(Airport airport) {
    final localizedCity = localizedAirportCity(airport);
    final localizedName = localizedAirportName(airport);
    final fields = <String, int>{
      airport.iataCode: 0,
      localizedCity: 10,
      '$localizedCity机场': 11,
      localizedName: 12,
      for (final alias in localizedAirportSearchAliases(airport)) alias: 11,
      ...{for (final keyword in airport.keywords) keyword: 14},
      localizedCountryName(airport.countryCode): 4,
      localizedCountryEnglishName(airport.countryCode): 5,
      airport.countryCode: 6,
      airport.city: 20,
      airport.name: 24,
      airport.icaoCode: 26,
      airport.isoRegion: 30,
    };
    return [
      for (final entry in fields.entries)
        if (_normalizeSearchText(entry.key).isNotEmpty)
          _AirportSearchField(_normalizeSearchText(entry.key), entry.value),
    ];
  }

  static int? _bestNormalizedScore(
    String query,
    List<_AirportSearchField> fields,
  ) {
    int? best;
    for (final field in fields) {
      final value = field.value;
      final offset = value == query
          ? 0
          : value.startsWith(query)
          ? 1
          : value.contains(query)
          ? 2
          : query.contains(value)
          ? 3
          : null;
      if (offset == null) continue;
      final score = field.weight + offset;
      if (best == null || score < best) best = score;
    }
    return best;
  }

  static int _compareAirports(Airport left, Airport right) {
    final scheduled = right.scheduledService == left.scheduledService
        ? 0
        : right.scheduledService
        ? -1
        : 1;
    if (scheduled != 0) return scheduled;
    final type = _typeRank(left.type).compareTo(_typeRank(right.type));
    if (type != 0) return type;
    final city = localizedAirportCity(left)
        .compareTo(localizedAirportCity(right));
    if (city != 0) return city;
    return left.iataCode.compareTo(right.iataCode);
  }

  static int? _bestScore(String query, Map<String, int> fields) {
    int? best;
    for (final entry in fields.entries) {
      final value = _normalizeSearchText(entry.key);
      if (value.isEmpty) continue;
      final offset = value == query
          ? 0
          : value.startsWith(query)
          ? 1
          : value.contains(query)
          ? 2
          : query.contains(value)
          ? 3
          : null;
      if (offset == null) continue;
      final score = entry.value + offset;
      if (best == null || score < best) best = score;
    }
    return best;
  }

  static String _normalizeSearchText(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[\s\-·•_/.,，。:：()（）【】\[\]]'), '');

  static int _typeRank(String type) {
    switch (type.trim().toLowerCase()) {
      case 'large_airport':
        return 0;
      case 'medium_airport':
        return 1;
      case 'small_airport':
        return 2;
      case 'seaplane_base':
        return 3;
      case 'heliport':
        return 4;
      case 'closed':
        return 5;
      default:
        return 6;
    }
  }

  double? distanceKmForIata(String departureIata, String arrivalIata) {
    final from = findByIata(departureIata);
    final to = findByIata(arrivalIata);
    return from == null || to == null ? null : greatCircleDistanceKm(from, to);
  }

  static double greatCircleDistanceKm(Airport from, Airport to) =>
      haversineDistanceKm(
        fromLatitude: from.latitude,
        fromLongitude: from.longitude,
        toLatitude: to.latitude,
        toLongitude: to.longitude,
      );

  static double haversineDistanceKm({
    required double fromLatitude,
    required double fromLongitude,
    required double toLatitude,
    required double toLongitude,
  }) {
    const earthRadiusKm = 6371.0088;
    double radians(double degrees) => degrees * math.pi / 180;
    final deltaLatitude = radians(toLatitude - fromLatitude);
    final deltaLongitude = radians(toLongitude - fromLongitude);
    final a =
        math.pow(math.sin(deltaLatitude / 2), 2).toDouble() +
        math.cos(radians(fromLatitude)) *
            math.cos(radians(toLatitude)) *
            math.pow(math.sin(deltaLongitude / 2), 2).toDouble();
    return 2 * earthRadiusKm * math.asin(math.sqrt(a));
  }
}

class _ScoredAirport {
  const _ScoredAirport(this.airport, this.score);

  final Airport airport;
  final int score;
}

class _AirportSearchEntry {
  const _AirportSearchEntry(this.airport, this.fields);

  final Airport airport;
  final List<_AirportSearchField> fields;
}

class _AirportSearchField {
  const _AirportSearchField(this.value, this.weight);

  final String value;
  final int weight;
}

class _ScoredCountry {
  const _ScoredCountry(this.country, this.score);

  final AirportCountry country;
  final int score;
}
