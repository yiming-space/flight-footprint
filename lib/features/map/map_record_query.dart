import '../../domain/flight.dart';
import '../../domain/visited_place.dart';
import 'map_models.dart';

bool flightMatchesMapSelection(
  Flight flight,
  MapSelection selection, {
  required MapAirport? Function(String code) airportFor,
}) {
  final route = selection.route;
  if (route != null) {
    return flight.departureIata == route.from.code &&
        flight.arrivalIata == route.to.code;
  }
  final codes = selection.airports.map((a) => a.code).toSet();
  if (codes.contains(flight.departureIata) ||
      codes.contains(flight.arrivalIata)) {
    return true;
  }
  return selection.places.any((place) {
    return [
      airportFor(flight.departureIata),
      airportFor(flight.arrivalIata),
    ].whereType<MapAirport>().any(
      (a) =>
          normalizedMapLabel(a.name) == normalizedMapLabel(place.name) ||
          ((a.latitude - place.latitude).abs() < .15 &&
              (a.longitude - place.longitude).abs() < .15),
    );
  });
}

bool placeMatchesMapSelection(VisitedPlace place, MapSelection selection) {
  return selection.places.any(
        (p) =>
            p.id == place.id ||
            (normalizedMapLabel(p.name, countryCode: p.countryCode) ==
                    normalizedMapLabel(
                      place.name,
                      countryCode: place.countryCode,
                    ) &&
                (p.countryCode == null || p.countryCode == place.countryCode)),
      ) ||
      selection.airports.any(
        (a) =>
            normalizedMapLabel(a.name) == normalizedMapLabel(place.name) ||
            ((a.latitude - place.latitude).abs() < .15 &&
                (a.longitude - place.longitude).abs() < .15),
      );
}
