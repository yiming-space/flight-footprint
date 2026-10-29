import '../../domain/airport.dart';
import '../../domain/flight.dart';
import '../../domain/footprint_sources.dart';
import '../../domain/transfer_decision.dart';
import '../../data/flight_time_resolver.dart';
import 'aircraft_collection.dart';

class PersonalTravelSummary {
  PersonalTravelSummary({
    required this.year,
    required List<NewCityMoment> newCities,
    required List<NewAircraftMoment> newAircraft,
    required this.frequentRoute,
  }) : newCities = List.unmodifiable(newCities),
       newAircraft = List.unmodifiable(newAircraft);

  final int year;
  final List<NewCityMoment> newCities;
  final List<NewAircraftMoment> newAircraft;
  final FrequentRouteMoment? frequentRoute;
}

class NewCityMoment {
  const NewCityMoment({
    required this.key,
    required this.name,
    required this.countryCode,
    required this.firstFlight,
    required this.arrivedAt,
  });

  final String key;
  final String name;
  final String countryCode;
  final Flight firstFlight;
  final DateTime arrivedAt;
}

class NewAircraftMoment {
  const NewAircraftMoment({required this.type, required this.firstFlight});

  final String type;
  final Flight firstFlight;
}

class FrequentRouteMoment {
  FrequentRouteMoment({
    required this.departureIata,
    required this.arrivalIata,
    required this.fromCity,
    required this.toCity,
    required List<Flight> flights,
  }) : flights = List.unmodifiable(flights);

  // Airport codes are in stable alphabetical order, rather than implying that
  // the recorded flights necessarily include both travel directions.
  final String departureIata;
  final String arrivalIata;
  final String fromCity;
  final String toCity;
  final List<Flight> flights;

  int get count => flights.length;
}

/// Year-specific memories derived only from the recorded completed history.
/// Local calendar years match the flight list's year filter. Missing airport
/// or aircraft data stays unknown rather than being inferred from a route.
PersonalTravelSummary buildPersonalTravelSummary(
  Iterable<Flight> flights, {
  required int year,
  required Airport? Function(String) airportFor,
  required String Function(Airport) cityNameFor,
  bool includeTransitArrivals = true,
  Iterable<TransferDecision> confirmedTransfers = const [],
}) {
  final seen = <String>{};
  final history = flights
      .where((flight) => flight.isCompleted && seen.add(flight.id))
      .toList();
  final excludedTransferEndpoints = includeTransitArrivals
      ? const <({String flightId, bool isArrival})>{}
      : confirmedTransitFootprintEndpoints(history, confirmedTransfers);
  final evidence = <String, _CityEvidence>{};
  final routes = <String, List<Flight>>{};

  void recordCity(Flight flight, String iata, DateTime time, bool arrival) {
    final airport = airportFor(_iata(iata));
    if (airport == null) return;
    final city = _normalize(airport.city);
    final country = airport.countryCode.trim().toUpperCase();
    if (city.isEmpty || country.isEmpty) return;
    final key = '$country|$city';
    final candidate = _CityEvidence(airport, flight, time, arrival);
    final old = evidence[key];
    if (old == null || candidate.compareTo(old) < 0) {
      evidence[key] = candidate;
    }
  }

  for (final flight in history) {
    if (!excludedTransferEndpoints.contains(
      (flightId: flight.id, isArrival: false),
    )) {
      recordCity(flight, flight.departureIata, flight.departedAt, false);
    }
    if (includeTransitArrivals || !flight.isTransitArrival) {
      if (!excludedTransferEndpoints.contains(
        (flightId: flight.id, isArrival: true),
      )) {
        recordCity(flight, flight.arrivalIata, _arrivalTime(flight), true);
      }
    }
    final departureYear = FlightTimeResolver.calendarYearAtAirport(
      flight.departedAt,
      airportFor(flight.departureIata)?.timeZoneId,
    );
    if (departureYear != year) continue;
    final from = _iata(flight.departureIata);
    final to = _iata(flight.arrivalIata);
    if (from.isEmpty || to.isEmpty || from == to) continue;
    final key = from.compareTo(to) < 0 ? '$from|$to' : '$to|$from';
    routes.putIfAbsent(key, () => []).add(flight);
  }

  final cities =
      [
        for (final entry in evidence.entries)
          if (entry.value.arrival &&
              FlightTimeResolver.calendarYearAtAirport(
                    entry.value.time,
                    entry.value.airport.timeZoneId,
                  ) ==
                  year)
            NewCityMoment(
              key: entry.key,
              name: _cityName(entry.value.airport, cityNameFor),
              countryCode: entry.value.airport.countryCode.trim().toUpperCase(),
              firstFlight: entry.value.flight,
              arrivedAt: entry.value.time,
            ),
      ]..sort((left, right) {
        final time = right.arrivedAt.compareTo(left.arrivedAt);
        return time != 0
            ? time
            : left.firstFlight.id.compareTo(right.firstFlight.id);
      });

  final aircraft = <NewAircraftMoment>[];
  for (final entry in buildAircraftCollection(history)) {
    final chronological = entry.flights.toList()..sort(_oldestFirst);
    final first = chronological.first;
    if (FlightTimeResolver.calendarYearAtAirport(
          first.departedAt,
          airportFor(first.departureIata)?.timeZoneId,
        ) ==
        year) {
      aircraft.add(NewAircraftMoment(type: entry.type, firstFlight: first));
    }
  }
  aircraft.sort((left, right) {
    final time = right.firstFlight.departedAt.compareTo(
      left.firstFlight.departedAt,
    );
    return time != 0
        ? time
        : left.firstFlight.id.compareTo(right.firstFlight.id);
  });

  final frequent = routes.entries
      .where((entry) => entry.value.length >= 2)
      .toList();
  for (final entry in frequent) {
    entry.value.sort((left, right) {
      final time = right.departedAt.compareTo(left.departedAt);
      return time != 0 ? time : left.id.compareTo(right.id);
    });
  }
  frequent.sort((left, right) {
    final count = right.value.length.compareTo(left.value.length);
    if (count != 0) return count;
    final recent = right.value.first.departedAt.compareTo(
      left.value.first.departedAt,
    );
    return recent != 0 ? recent : left.key.compareTo(right.key);
  });
  FrequentRouteMoment? route;
  if (frequent.isNotEmpty) {
    final selected = frequent.first;
    final codes = selected.key.split('|');
    String routeCity(String code) {
      final airport = airportFor(code);
      return airport == null ? code : _cityName(airport, cityNameFor);
    }

    route = FrequentRouteMoment(
      departureIata: codes[0],
      arrivalIata: codes[1],
      fromCity: routeCity(codes[0]),
      toCity: routeCity(codes[1]),
      flights: selected.value,
    );
  }
  return PersonalTravelSummary(
    year: year,
    newCities: cities,
    newAircraft: aircraft,
    frequentRoute: route,
  );
}

String _iata(String value) => value.trim().toUpperCase();
String _normalize(String value) =>
    value.trim().replaceAll(RegExp(r'\s+'), ' ').toUpperCase();
String _cityName(Airport airport, String Function(Airport) cityNameFor) {
  final localized = cityNameFor(airport).trim();
  return localized.isEmpty ? airport.city.trim() : localized;
}

DateTime _arrivalTime(Flight flight) {
  final arrival = flight.arrivedAt;
  if (arrival != null && arrival.isAfter(flight.departedAt)) return arrival;
  final duration = flight.durationMinutes;
  if (duration != null && duration > 0 && duration <= 48 * 60) {
    return flight.departedAt.add(Duration(minutes: duration));
  }
  return flight.departedAt;
}

int _oldestFirst(Flight left, Flight right) {
  final time = left.departedAt.compareTo(right.departedAt);
  return time != 0 ? time : left.id.compareTo(right.id);
}

class _CityEvidence implements Comparable<_CityEvidence> {
  const _CityEvidence(this.airport, this.flight, this.time, this.arrival);
  final Airport airport;
  final Flight flight;
  final DateTime time;
  final bool arrival;

  @override
  int compareTo(_CityEvidence other) {
    final date = time.compareTo(other.time);
    if (date != 0) return date;
    // Simultaneous departure evidence conservatively prevents a false first
    // visit, including same-city airport transfers and missing arrival times.
    if (arrival != other.arrival) return arrival ? 1 : -1;
    return flight.id.compareTo(other.flight.id);
  }
}
