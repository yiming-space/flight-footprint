import 'package:flutter_test/flutter_test.dart';
import 'package:flight_footprint/domain/flight.dart';
import 'package:flight_footprint/domain/visited_place.dart';
import 'package:flight_footprint/features/map/map_models.dart';
import 'package:flight_footprint/features/map/map_record_query.dart';

void main() {
  const a = MapAirport(code: 'AAA', name: 'Alpha', latitude: 20, longitude: 30);
  const b = MapAirport(code: 'BBB', name: 'Beta', latitude: 40, longitude: 50);
  final date = DateTime.utc(2026);
  Flight flight(String from, String to) => Flight(
    id: '$from$to',
    departureIata: from,
    arrivalIata: to,
    departedAt: date,
    createdAt: date,
    updatedAt: date,
  );
  MapAirport? airportFor(String code) => code == 'AAA'
      ? a
      : code == 'BBB'
      ? b
      : null;
  test('route selection distinguishes outbound from inbound records', () {
    const selection = MapSelection(
      route: MapRoute(from: a, to: b),
    );
    expect(
      flightMatchesMapSelection(
        flight('AAA', 'BBB'),
        selection,
        airportFor: airportFor,
      ),
      isTrue,
    );
    expect(
      flightMatchesMapSelection(
        flight('BBB', 'AAA'),
        selection,
        airportFor: airportFor,
      ),
      isFalse,
    );
    expect(
      flightMatchesMapSelection(
        flight('AAA', 'XXX'),
        selection,
        airportFor: airportFor,
      ),
      isFalse,
    );
  });
  test('city selection finds nearby airport records and matching visits', () {
    const selection = MapSelection(
      places: [MapPlace(name: 'Beta', latitude: 40, longitude: 50)],
    );
    expect(
      flightMatchesMapSelection(
        flight('AAA', 'BBB'),
        selection,
        airportFor: airportFor,
      ),
      isTrue,
    );
    expect(
      placeMatchesMapSelection(
        VisitedPlace(
          id: 'v',
          name: 'Beta',
          latitude: 40,
          longitude: 50,
          visitedAt: date,
          createdAt: date,
          updatedAt: date,
        ),
        selection,
      ),
      isTrue,
    );
  });
}
