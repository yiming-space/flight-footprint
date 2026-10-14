import '../../data/airline_catalog.dart';
import '../../domain/flight.dart';

class AirlineRankingEntry {
  AirlineRankingEntry({
    required this.name,
    required this.iataCode,
    required Iterable<Flight> flights,
  }) : flights = List<Flight>.unmodifiable(flights);

  final String name;
  final String? iataCode;
  final List<Flight> flights;

  int get count => flights.length;
}

/// Groups completed records by airline identity, not by the spelling stored
/// in each record. An explicit airline always wins over a codeshare number.
List<AirlineRankingEntry> buildAirlineRanking(Iterable<Flight> flights) {
  final groups =
      <String, ({String name, String? iata, List<Flight> flights})>{};
  for (final flight in flights) {
    if (!flight.isCompleted) continue;
    final explicitName = (flight.airline ?? '').trim().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
    final iata = explicitName.isNotEmpty
        ? airlineIataForName(explicitName)
        : _iataFromFlightNumber(flight.flightNumber);
    if (explicitName.isEmpty && iata == null) continue;

    final name = iata == null
        ? explicitName
        : airlineNameForPrefix(iata) ?? explicitName;
    final key = iata == null ? 'name:${name.toUpperCase()}' : 'iata:$iata';
    final group = groups.putIfAbsent(
      key,
      () => (name: name, iata: iata, flights: <Flight>[]),
    );
    group.flights.add(flight);
  }

  final entries = groups.values.map((group) {
    group.flights.sort((left, right) {
      final dateOrder = right.departedAt.compareTo(left.departedAt);
      return dateOrder != 0 ? dateOrder : left.id.compareTo(right.id);
    });
    return AirlineRankingEntry(
      name: group.name,
      iataCode: group.iata,
      flights: group.flights,
    );
  }).toList();
  entries.sort((left, right) {
    final countOrder = right.count.compareTo(left.count);
    if (countOrder != 0) return countOrder;
    final nameOrder = left.name.toUpperCase().compareTo(
      right.name.toUpperCase(),
    );
    return nameOrder != 0 ? nameOrder : left.name.compareTo(right.name);
  });
  return List<AirlineRankingEntry>.unmodifiable(entries);
}

String? _iataFromFlightNumber(String? value) {
  final number = (value ?? '').trim().toUpperCase().replaceAll(
    RegExp(r'\s+'),
    '',
  );
  final prefix = RegExp(r'^([A-Z0-9]{2}|[A-Z]{3})(?=\d)')
      .firstMatch(number)
      ?.group(1);
  if (prefix == null || !RegExp(r'[A-Z]').hasMatch(prefix)) return null;
  return airlineIataForName(prefix);
}
