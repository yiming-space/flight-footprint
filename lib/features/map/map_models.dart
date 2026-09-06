import 'package:flutter/foundation.dart';

/// Keeps map labels compact and stable across imported data sources. Chinese
/// city records commonly alternate between “丽江” and “丽江市”; map labels
/// use the shorter form while international names such as “胡志明市” stay
/// untouched when their country code is known.
String normalizedMapLabel(String value, {String? countryCode}) =>
    _normalizedMapLabel(value, countryCode: countryCode);

String _normalizedMapLabel(String value, {String? countryCode}) {
  var result = value
      .trim()
      .replaceAll(RegExp(r'\s*[（(][^）)]*[）)]'), '')
      .replaceAll(RegExp(r'\s*[，,;；|].*$'), '')
      .trim();
  // Map labels are painted as one compact line. Some imported airport names
  // contain a line break (or spaces) between Chinese characters. Preserving
  // those break opportunities lets TextPainter wrap one glyph per line,
  // which looks like a broken vertical label on the rotating globe.
  if (RegExp(r'[\u3400-\u9fff]').hasMatch(result)) {
    result = result.replaceAll(RegExp(r'[\s\u200B-\u200D\u2060\uFEFF]+'), '');
  } else {
    result = result.replaceAll(RegExp(r'\s+'), ' ');
  }
  if (countryCode?.trim().toUpperCase() == 'CN' && result.endsWith('市')) {
    result = result.substring(0, result.length - 1);
  }
  return result;
}

bool isProvinceMapLabel(String value) {
  final normalized = value.trim();
  return normalized.endsWith('省') ||
      normalized.endsWith('自治区') ||
      normalized.endsWith('特别行政区');
}

enum MapMode { flight, travelFootprint }

/// A hit on visible map artwork. Empty-space taps do not create a selection.
@immutable
class MapSelection {
  const MapSelection({
    this.airports = const [],
    this.places = const [],
    this.route,
  });
  final List<MapAirport> airports;
  final List<MapPlace> places;
  final MapRoute? route;
}

@immutable
class MapAirport {
  const MapAirport({
    required this.code,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.isPrimary = false,
  });

  final String code;
  final String name;
  final double latitude;
  final double longitude;
  final bool isPrimary;
}

@immutable
class MapRoute {
  const MapRoute({
    required this.from,
    required this.to,
    this.isHighlight = false,
    this.label,
    this.track = const [],
  });

  final MapAirport from;
  final MapAirport to;
  final bool isHighlight;
  final String? label;
  final List<MapCoordinate> track;
}

@immutable
class MapPlace {
  const MapPlace({
    required this.name,
    required this.latitude,
    required this.longitude,
    this.isVisited = true,
    this.countryCode,
    this.visits = 1,
    this.id,
    this.visitedAt,
    this.isDeletable = false,
  });

  final String name;
  final double latitude;
  final double longitude;
  final bool isVisited;
  final String? countryCode;
  final int visits;

  /// Links a rendered point back to a local record when it comes from a
  /// manually added travel footprint. Flight-derived airport points leave
  /// this null so map cleanup can never remove a flight by accident.
  final String? id;
  final DateTime? visitedAt;
  final bool isDeletable;
}

@immutable
class MapCoordinate {
  const MapCoordinate(this.latitude, this.longitude);
  final double latitude;
  final double longitude;
}
