import 'airport.dart';
import 'flight.dart';
import 'visited_place.dart';

/// A saved endpoint or footprint that cannot be placed reliably on the map.
/// This is diagnostic only: it never mutates or merges the source records.
class RecordHealthIssue {
  const RecordHealthIssue.flight({required this.flight, required this.problems})
    : place = null;

  const RecordHealthIssue.place({required this.place, required this.problems})
    : flight = null;

  final Flight? flight;
  final VisitedPlace? place;
  final List<RecordHealthProblem> problems;
}

enum RecordHealthProblem {
  unknownDepartureAirport,
  unknownArrivalAirport,
  invalidDepartureCoordinates,
  invalidArrivalCoordinates,
  emptyPlaceName,
  invalidPlaceCoordinates,
}

class RecordHealthReport {
  const RecordHealthReport({
    required this.flights,
    required this.places,
    required this.suspectedDuplicateGroups,
  });

  final List<RecordHealthIssue> flights;
  final List<RecordHealthIssue> places;
  final List<List<Flight>> suspectedDuplicateGroups;

  int get count =>
      flights.length + places.length + suspectedDuplicateGroups.length;
}

RecordHealthReport inspectRecordHealth({
  required Iterable<Flight> flights,
  required Iterable<VisitedPlace> places,
  required Airport? Function(String iata) airportFor,
}) {
  final flightRecords = flights.toList(growable: false);
  final flightIssues = <RecordHealthIssue>[];
  for (final flight in flightRecords) {
    if (!flight.isCompleted) continue;
    final problems = <RecordHealthProblem>[];
    for (final endpoint in [
      (true, flight.departureIata),
      (false, flight.arrivalIata),
    ]) {
      final isDeparture = endpoint.$1;
      final code = endpoint.$2.trim().toUpperCase();
      final airport = code.isEmpty ? null : airportFor(code);
      if (airport == null) {
        problems.add(
          isDeparture
              ? RecordHealthProblem.unknownDepartureAirport
              : RecordHealthProblem.unknownArrivalAirport,
        );
      } else if (!_validCoordinates(airport.latitude, airport.longitude)) {
        problems.add(
          isDeparture
              ? RecordHealthProblem.invalidDepartureCoordinates
              : RecordHealthProblem.invalidArrivalCoordinates,
        );
      }
    }
    if (problems.isNotEmpty) {
      flightIssues.add(
        RecordHealthIssue.flight(
          flight: flight,
          problems: List.unmodifiable(problems),
        ),
      );
    }
  }

  final placeIssues = <RecordHealthIssue>[];
  for (final place in places) {
    final problems = <RecordHealthProblem>[];
    if (place.name.trim().isEmpty) {
      problems.add(RecordHealthProblem.emptyPlaceName);
    }
    if (!_validCoordinates(place.latitude, place.longitude)) {
      problems.add(RecordHealthProblem.invalidPlaceCoordinates);
    }
    if (problems.isNotEmpty) {
      placeIssues.add(
        RecordHealthIssue.place(
          place: place,
          problems: List.unmodifiable(problems),
        ),
      );
    }
  }

  return RecordHealthReport(
    flights: List.unmodifiable(flightIssues),
    places: List.unmodifiable(placeIssues),
    suspectedDuplicateGroups: findSuspectedDuplicateFlights(flightRecords),
  );
}

/// Groups completed flights only when every available identity field agrees.
/// A non-empty flight number is required; IDs are intentionally not used as a
/// deduplication key because different IDs must remain independently reviewable.
List<List<Flight>> findSuspectedDuplicateFlights(Iterable<Flight> flights) {
  final groups = <(String, String, String, int), List<Flight>>{};
  final seenIds = <(String, String, String, int), Set<String>>{};
  for (final flight in flights) {
    if (!flight.isCompleted) continue;
    final number = flight.flightNumber?.trim().toUpperCase() ?? '';
    final departure = flight.departureIata.trim().toUpperCase();
    final arrival = flight.arrivalIata.trim().toUpperCase();
    final id = flight.id.trim();
    if (id.isEmpty || number.isEmpty || departure.isEmpty || arrival.isEmpty) {
      continue;
    }
    final key = (
      number,
      departure,
      arrival,
      flight.departedAt.microsecondsSinceEpoch,
    );
    final ids = seenIds.putIfAbsent(key, () => <String>{});
    if (ids.add(id)) groups.putIfAbsent(key, () => []).add(flight);
  }
  return List.unmodifiable([
    for (final group in groups.values)
      if (group.length > 1) List<Flight>.unmodifiable(group),
  ]);
}

bool _validCoordinates(double latitude, double longitude) =>
    latitude.isFinite &&
    longitude.isFinite &&
    latitude >= -90 &&
    latitude <= 90 &&
    longitude >= -180 &&
    longitude <= 180;
