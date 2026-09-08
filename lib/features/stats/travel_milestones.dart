import '../../domain/flight.dart';

typedef CityNameResolver = String? Function(String iataCode);

class TravelMilestones {
  const TravelMilestones({
    required this.firstArrival,
    required this.latestNewCities,
    required this.routes,
  });

  final FirstArrivalMilestone? firstArrival;
  final YearNewCitiesMilestone? latestNewCities;
  final List<RouteFrequencyMilestone> routes;

  RouteFrequencyMilestone? get frequentRoute => routes.firstOrNull;

  factory TravelMilestones.fromFlights(
    Iterable<Flight> flights, {
    required CityNameResolver cityNameFor,
  }) {
    final completed = flights.where((flight) => flight.isCompleted).toList()
      ..sort((a, b) => a.departedAt.compareTo(b.departedAt));

    FirstArrivalMilestone? firstArrival;
    final firstArrivalByCity = <String, DateTime>{};
    final routeFlights = <String, List<Flight>>{};
    final routeLabels = <String, (String, String)>{};

    for (final flight in completed) {
      final arrivalCity = cityNameFor(flight.arrivalIata)?.trim();
      if (arrivalCity != null && arrivalCity.isNotEmpty) {
        final localDate = flight.departedAt.toLocal();
        firstArrival ??= FirstArrivalMilestone(
          city: arrivalCity,
          flight: flight,
        );
        firstArrivalByCity.putIfAbsent(arrivalCity, () => localDate);
      }

      final codes = [
        flight.departureIata.trim().toUpperCase(),
        flight.arrivalIata.trim().toUpperCase(),
      ]..sort();
      if (codes.any((code) => code.isEmpty)) continue;
      final key = codes.join('-');
      routeFlights.putIfAbsent(key, () => <Flight>[]).add(flight);
      routeLabels.putIfAbsent(
        key,
        () => (
          cityNameFor(codes[0])?.trim().isNotEmpty == true
              ? cityNameFor(codes[0])!.trim()
              : codes[0],
          cityNameFor(codes[1])?.trim().isNotEmpty == true
              ? cityNameFor(codes[1])!.trim()
              : codes[1],
        ),
      );
    }

    final citiesByYear = <int, List<String>>{};
    for (final entry in firstArrivalByCity.entries) {
      citiesByYear
          .putIfAbsent(entry.value.year, () => <String>[])
          .add(entry.key);
    }
    for (final cities in citiesByYear.values) {
      cities.sort();
    }
    final latestYear = citiesByYear.keys.isEmpty
        ? null
        : citiesByYear.keys.reduce((a, b) => a > b ? a : b);

    final routes =
        <RouteFrequencyMilestone>[
          for (final entry in routeFlights.entries)
            RouteFrequencyMilestone(
              from: routeLabels[entry.key]!.$1,
              to: routeLabels[entry.key]!.$2,
              flights: List.unmodifiable(entry.value),
            ),
        ]..sort((a, b) {
          final byCount = b.flights.length.compareTo(a.flights.length);
          if (byCount != 0) return byCount;
          return a.label.compareTo(b.label);
        });

    return TravelMilestones(
      firstArrival: firstArrival,
      latestNewCities: latestYear == null
          ? null
          : YearNewCitiesMilestone(
              year: latestYear,
              cities: List.unmodifiable(citiesByYear[latestYear]!),
            ),
      routes: List.unmodifiable(routes),
    );
  }
}

class FirstArrivalMilestone {
  const FirstArrivalMilestone({required this.city, required this.flight});

  final String city;
  final Flight flight;
}

class YearNewCitiesMilestone {
  const YearNewCitiesMilestone({required this.year, required this.cities});

  final int year;
  final List<String> cities;
}

class RouteFrequencyMilestone {
  const RouteFrequencyMilestone({
    required this.from,
    required this.to,
    required this.flights,
  });

  final String from;
  final String to;
  final List<Flight> flights;

  String get label => '$from — $to';
}
