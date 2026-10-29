import 'dart:math' as math;

import '../../data/airport_localization.dart';
import '../../data/city_catalog.dart';
import '../../domain/airport.dart';
import '../../domain/flight.dart';
import '../../domain/footprint_sources.dart';
import '../../domain/visited_place.dart';
import '../../domain/transfer_decision.dart';

enum TravelContinent {
  asia,
  europe,
  africa,
  northAmerica,
  southAmerica,
  oceania,
  antarctica,
}

extension TravelContinentCopy on TravelContinent {
  String get nameZh => switch (this) {
    TravelContinent.asia => '亚洲',
    TravelContinent.europe => '欧洲',
    TravelContinent.africa => '非洲',
    TravelContinent.northAmerica => '北美洲',
    TravelContinent.southAmerica => '南美洲',
    TravelContinent.oceania => '大洋洲',
    TravelContinent.antarctica => '南极洲',
  };

  String get nameEn => switch (this) {
    TravelContinent.asia => 'Asia',
    TravelContinent.europe => 'Europe',
    TravelContinent.africa => 'Africa',
    TravelContinent.northAmerica => 'North America',
    TravelContinent.southAmerica => 'South America',
    TravelContinent.oceania => 'Oceania',
    TravelContinent.antarctica => 'Antarctica',
  };
}

const continentCountryGroups = <TravelContinent, String>{
  TravelContinent.asia:
      'AF AM AZ BH BD BT BN KH CN CY GE IN ID IR IQ IL JP JO KZ KW KG LA LB '
      'MY MV MN MM NP KP OM PK PS PH QA SA SG KR LK SY TW TJ TH TL TR TM AE '
      'UZ VN YE HK MO',
  TravelContinent.europe:
      'AL AD AT BY BE BA BG HR CZ DK EE FI FR DE GR HU IS IE IT XK LV LI LT '
      'LU MT MD MC ME NL MK NO PL PT RO RU SM RS SK SI ES SE CH UA GB VA GI '
      'FO GG IM JE AX',
  TravelContinent.africa:
      'DZ AO BJ BW BF BI CV CM CF TD KM CD CG CI DJ EG GQ ER SZ ET GA GM GH '
      'GN GW KE LS LR LY MG MW ML MR MU MA MZ NA NE NG RW ST SN SC SL SO ZA '
      'SS SD TZ TG TN UG EH IO ZM ZW RE YT SH',
  TravelContinent.northAmerica:
      'AG BS BB BZ CA CR CU DM DO SV GD GT HT HN JM MX NI PA KN LC VC TT US '
      'AW BM BQ CW GP GL MQ PR SX TC VI VG MS KY PM MF BL',
  TravelContinent.southAmerica: 'AR BO BR CL CO EC GY PY PE SR UY VE GF FK',
  TravelContinent.oceania:
      'AU FJ KI MH FM NR NZ PW PG WS SB TO TV VU NC PF CK NU TK WF CC CX '
      'NF AS GU MP UM',
  TravelContinent.antarctica: 'AQ BV GS HM TF',
};

final Map<String, TravelContinent> _continentByCountry = {
  for (final entry in continentCountryGroups.entries)
    for (final code in entry.value.split(' ')) code: entry.key,
};

TravelContinent? continentForLocation({
  required String countryCode,
  required double latitude,
  required double longitude,
}) {
  if (!latitude.isFinite ||
      !longitude.isFinite ||
      latitude.abs() > 90 ||
      longitude.abs() > 180) {
    return null;
  }
  final code = countryCode.trim().toUpperCase();
  // Countries spanning the Europe/Asia boundary follow the actual recorded
  // airport or footprint coordinate instead of lighting two continents.
  // The bundled country polygons have no ISO attributes and the map does not
  // include an authoritative continent boundary dataset, so these established
  // meridian rules remain approximations rather than precise border checks.
  switch (code) {
    case 'RU':
      return longitude < 60 ? TravelContinent.europe : TravelContinent.asia;
    case 'TR':
      return longitude < 32 ? TravelContinent.europe : TravelContinent.asia;
    case 'KZ':
      return longitude < 52 ? TravelContinent.europe : TravelContinent.asia;
    case 'EG':
      return longitude >= 33 ? TravelContinent.asia : TravelContinent.africa;
  }
  return _continentByCountry[code];
}

class ExplorationPlace {
  const ExplorationPlace({
    required this.name,
    required this.countryCode,
    required this.latitude,
    required this.longitude,
    this.visitedAt,
  });

  final String name;
  final String countryCode;
  final double latitude;
  final double longitude;
  final DateTime? visitedAt;
}

class FarthestFootprint {
  const FarthestFootprint({required this.place, required this.distanceKm});

  final ExplorationPlace place;
  final double distanceKm;
}

class ContinentVisits {
  const ContinentVisits({
    required this.continent,
    required this.countryCodes,
    required this.places,
  });

  final TravelContinent continent;
  final Set<String> countryCodes;
  final List<ExplorationPlace> places;

  int get countryCount => countryCodes.length;
  bool get isUnlocked => places.isNotEmpty;
}

List<ExplorationPlace> buildExplorationPlaces({
  required List<Flight> flights,
  required List<VisitedPlace> visitedPlaces,
  required Airport? Function(String) airportFor,
  required bool isZh,
  bool includeTransitArrivals = true,
  Iterable<TransferDecision> confirmedTransfers = const [],
}) {
  final result = <ExplorationPlace>[];
  for (final source in buildFootprintSources(
    flights: flights,
    visitedPlaces: visitedPlaces,
    airportFor: airportFor,
    includeTransitArrivals: includeTransitArrivals,
    confirmedTransfers: confirmedTransfers,
  )) {
    final airport = source.airport;
    if (airport != null) {
      result.add(
        ExplorationPlace(
          name: _airportCity(airport, isZh),
          countryCode: airport.countryCode,
          latitude: airport.latitude,
          longitude: airport.longitude,
          visitedAt: source.visitedAt,
        ),
      );
    } else if (source.visitedPlace case final place?) {
      result.add(
        ExplorationPlace(
          name: place.name,
          countryCode: place.countryCode ?? '',
          latitude: place.latitude,
          longitude: place.longitude,
          visitedAt: place.visitedAt,
        ),
      );
    }
  }
  return List.unmodifiable(result.where(_hasValidCoordinate));
}

FarthestFootprint? farthestFromHome({
  required Iterable<ExplorationPlace> places,
  required double homeLatitude,
  required double homeLongitude,
}) {
  FarthestFootprint? farthest;
  for (final place in places) {
    final distance = greatCircleDistanceKm(
      homeLatitude,
      homeLongitude,
      place.latitude,
      place.longitude,
    );
    if (distance < 1) continue;
    if (farthest == null || distance > farthest.distanceKm) {
      farthest = FarthestFootprint(place: place, distanceKm: distance);
    }
  }
  return farthest;
}

List<ContinentVisits> buildContinentVisits(
  Iterable<ExplorationPlace> places, {
  CityCatalog? cityCatalog,
}) {
  final countries = {
    for (final continent in TravelContinent.values) continent: <String>{},
  };
  final groupedPlaces = {
    for (final continent in TravelContinent.values)
      continent: <String, ExplorationPlace>{},
  };
  final identityResolver = CityIdentityResolver(cityCatalog);
  for (final place in places) {
    final continent = continentForLocation(
      countryCode: place.countryCode,
      latitude: place.latitude,
      longitude: place.longitude,
    );
    if (continent == null) continue;
    final country = place.countryCode.trim().toUpperCase();
    if (country.isNotEmpty) countries[continent]!.add(country);
    final locationKey = identityResolver.keyFor(
      name: place.name,
      countryCode: country,
      latitude: place.latitude,
      longitude: place.longitude,
    );
    final previous = groupedPlaces[continent]![locationKey];
    if (previous == null ||
        (place.visitedAt != null &&
            (previous.visitedAt == null ||
                place.visitedAt!.isAfter(previous.visitedAt!)))) {
      groupedPlaces[continent]![locationKey] = place;
    }
  }
  return List.unmodifiable([
    for (final continent in TravelContinent.values)
      ContinentVisits(
        continent: continent,
        countryCodes: Set.unmodifiable(countries[continent]!),
        places: List.unmodifiable(
          groupedPlaces[continent]!.values.toList()..sort((left, right) {
            final a = left.visitedAt;
            final b = right.visitedAt;
            if (a == null) return b == null ? 0 : 1;
            if (b == null) return -1;
            return b.compareTo(a);
          }),
        ),
      ),
  ]);
}

double greatCircleDistanceKm(
  double fromLatitude,
  double fromLongitude,
  double toLatitude,
  double toLongitude,
) {
  const radiusKm = 6371.0088;
  final fromLat = fromLatitude * math.pi / 180;
  final toLat = toLatitude * math.pi / 180;
  final deltaLat = (toLatitude - fromLatitude) * math.pi / 180;
  final deltaLon = (toLongitude - fromLongitude) * math.pi / 180;
  final sinLat = math.sin(deltaLat / 2);
  final sinLon = math.sin(deltaLon / 2);
  final a =
      sinLat * sinLat + math.cos(fromLat) * math.cos(toLat) * sinLon * sinLon;
  return radiusKm * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

bool _hasValidCoordinate(ExplorationPlace place) =>
    place.name.trim().isNotEmpty &&
    place.latitude.isFinite &&
    place.longitude.isFinite &&
    place.latitude.abs() <= 90 &&
    place.longitude.abs() <= 180;

String _airportCity(Airport airport, bool isZh) => isZh
    ? localizedAirportCity(airport)
    : (airport.city.trim().isEmpty
          ? localizedAirportCity(airport)
          : airport.city.trim());
