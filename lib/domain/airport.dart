/// A geocoded airport loaded from the bundled IATA catalogue.
class Airport {
  const Airport({
    required this.iataCode,
    required this.longitude,
    required this.latitude,
    required this.name,
    required this.city,
    required this.countryCode,
    this.icaoCode = '',
    this.type = '',
    this.scheduledService = false,
    this.isoRegion = '',
    this.keywords = const [],
  });

  final String iataCode;
  final double longitude;
  final double latitude;
  final String name;
  final String city;
  final String countryCode;

  /// The stable ICAO identifier from the airport source, when available.
  final String icaoCode;

  /// OurAirports facility type (large_airport, medium_airport, heliport...).
  final String type;

  /// Whether the source marks this facility as having scheduled service.
  final bool scheduledService;

  /// ISO 3166-2 region, useful when two municipalities share a name.
  final String isoRegion;

  /// Alternate names, local-language names and legacy identifiers supplied by
  /// the source. These are searchable but do not replace the official name.
  final List<String> keywords;
}
