import 'package:flight_footprint/domain/airport.dart';
import 'package:flight_footprint/domain/flight.dart';
import 'package:flight_footprint/domain/transfer_decision.dart';
import 'package:flight_footprint/features/stats/personal_travel_summary.dart';
import 'package:flutter_test/flutter_test.dart';

Airport _airport(
  String code,
  String city,
  String country, {
  String? timeZoneId,
}) => Airport(
  iataCode: code,
  longitude: 0,
  latitude: 0,
  name: '$city airport',
  city: city,
  countryCode: country,
  timeZoneId: timeZoneId,
);

final _airports = {
  'PVG': _airport('PVG', 'Shanghai', 'CN', timeZoneId: 'Asia/Shanghai'),
  'SHA': _airport('SHA', '  shanghai  ', ' cn ', timeZoneId: 'Asia/Shanghai'),
  'PEK': _airport('PEK', 'Beijing', 'CN'),
  'LHR': _airport('LHR', 'London', 'GB'),
  'YXU': _airport('YXU', 'London', 'CA'),
  'SIN': _airport('SIN', 'Singapore', 'SG', timeZoneId: 'Asia/Singapore'),
};

Flight _flight(
  String id, {
  String from = 'PVG',
  String to = 'PEK',
  DateTime? date,
  DateTime? arrival,
  int? duration,
  String? type,
  FlightStatus status = FlightStatus.completed,
}) => Flight(
  id: id,
  departureIata: from,
  arrivalIata: to,
  departedAt: date ?? DateTime(2026, 6, 1, 12),
  arrivedAt: arrival,
  durationMinutes: duration,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  aircraftType: type,
  status: status,
);

PersonalTravelSummary _summary(Iterable<Flight> flights, {int year = 2026}) =>
    buildPersonalTravelSummary(
      flights,
      year: year,
      airportFor: (code) => _airports[code],
      // Grouping must use the original city, even when localization maps
      // distinct country/city identities to an identical display name.
      cityNameFor: (airport) => 'Display ${airport.city.trim()}',
    );

void main() {
  test('year grouping uses the departure airport calendar year', () {
    final flight = _flight(
      'singapore-new-year',
      from: 'SIN',
      to: 'PEK',
      date: DateTime.utc(2025, 12, 31, 18, 30),
    );

    final repeatedRoute = _flight(
      'singapore-new-year-2',
      from: 'SIN',
      to: 'PEK',
      date: DateTime.utc(2025, 12, 31, 19, 30),
    );
    expect(
      _summary([flight, repeatedRoute], year: 2026).frequentRoute?.count,
      2,
    );
    expect(_summary([flight, repeatedRoute], year: 2025).frequentRoute, isNull);
  });

  test('confirmed transfer endpoints do not create a new city memory', () {
    final inbound = _flight(
      'inbound',
      from: 'PVG',
      to: 'SIN',
      date: DateTime(2026, 5, 1, 8),
      arrival: DateTime(2026, 5, 1, 11),
    );
    final outbound = _flight(
      'outbound',
      from: 'SIN',
      to: 'PEK',
      date: DateTime(2026, 5, 1, 13),
      arrival: DateTime(2026, 5, 1, 19),
    );
    final repeatedInbound = _flight(
      'inbound-repeat',
      from: 'PVG',
      to: 'SIN',
      date: DateTime(2026, 5, 8, 8),
      arrival: DateTime(2026, 5, 8, 11),
    ).copyWith(isTransitArrival: true);
    final decision = TransferDecision.fromFlights(
      inbound: inbound,
      outbound: outbound,
      status: TransferDecisionStatus.confirmed,
      decidedAt: DateTime(2026, 5, 1, 12),
    );
    final result = buildPersonalTravelSummary(
      [inbound, outbound, repeatedInbound],
      year: 2026,
      airportFor: (code) => _airports[code],
      cityNameFor: (airport) => airport.city,
      includeTransitArrivals: false,
      confirmedTransfers: [decision],
    );

    expect(result.newCities.map((city) => city.name), ['Beijing']);
    // A single recorded leg is below the existing frequent-route threshold.
    // The repeated inbound proves the confirmed transfer endpoint is removed
    // by flight ID and endpoint, not by deleting that route from the summary.
    expect(result.frequentRoute?.count, 2);
    expect(result.frequentRoute?.flights, contains(repeatedInbound));
  });

  test(
    'historical departures prevent a false new home; multiple airports merge',
    () {
      final old = _flight(
        'old',
        from: 'PVG',
        to: 'SIN',
        date: DateTime(2025, 1, 1),
      );
      final home = _flight('home', from: 'SIN', to: 'SHA');
      final beijing = _flight(
        'new',
        from: 'SHA',
        to: 'PEK',
        date: DateTime(2026, 7, 1),
      );
      final result = _summary([beijing, home, old, old]);
      expect(result.newCities.map((city) => city.key), ['CN|BEIJING']);
      expect(result.newCities.single.name, 'Display Beijing');
      expect(result.newCities.single.firstFlight, same(beijing));
      expect(_summary([old], year: 2025).newCities.single.key, 'SG|SINGAPORE');
    },
  );

  test(
    'new cities follow full history and keep same-named countries distinct',
    () {
      final oldLondon = _flight('old', to: 'LHR', date: DateTime(2025, 1, 1));
      final repeated = _flight('repeat', to: 'LHR');
      final canadian = _flight('ca', to: 'YXU', date: DateTime(2026, 8, 1));
      final result = _summary([repeated, canadian, oldLondon]);
      expect(result.newCities.map((city) => city.key), ['CA|LONDON']);
      final both = _summary([_flight('gb', to: 'LHR'), canadian]);
      expect(both.newCities.map((city) => city.countryCode), ['CA', 'GB']);
    },
  );

  test(
    'a first arrival can cross New Year independently of the flight departure',
    () {
      final departure = DateTime(2025, 12, 31, 23);
      final arrival = DateTime(2026, 1, 1, 2);
      final flight = _flight(
        'overnight',
        date: departure,
        arrival: arrival,
        type: 'A350',
      );
      final result = _summary([flight]);
      expect(result.newCities.single.arrivedAt, arrival);
      expect(result.newCities.single.firstFlight, same(flight));
      expect(result.newAircraft, isEmpty);
      expect(result.frequentRoute, isNull);
      expect(_summary([flight], year: 2025).newCities, isEmpty);
      expect(_summary([flight], year: 2025).newAircraft.single.type, 'A350');
    },
  );

  test('arrival uses valid timestamp then legal duration then departure', () {
    final departure = DateTime(2025, 12, 31, 23);
    final inferred = _flight(
      'duration',
      date: departure,
      arrival: departure.subtract(const Duration(hours: 1)),
      duration: 120,
    );
    expect(
      _summary([inferred]).newCities.single.arrivedAt,
      DateTime(2026, 1, 1, 1),
    );
    final valid = _flight(
      'valid',
      date: departure,
      arrival: DateTime(2026, 1, 1, 3),
      duration: 120,
    );
    expect(
      _summary([valid]).newCities.single.arrivedAt,
      DateTime(2026, 1, 1, 3),
    );
    for (final duration in [null, 0, -1, 2881]) {
      final missing = _flight('missing', date: departure, duration: duration);
      expect(_summary([missing]).newCities, isEmpty);
      expect(
        _summary([missing], year: 2025).newCities.single.arrivedAt,
        departure,
      );
    }
  });

  test('unknown airports and incomplete flights never fabricate cities or aircraft', () {
    final result = _summary([
      _flight('unknown', from: '???', to: 'ZZZ'),
      _flight('future', to: 'LHR', type: 'A380', status: FlightStatus.upcoming),
      _flight('missing-type'),
    ]);
    expect(result.newCities.map((city) => city.key), ['CN|BEIJING']);
    expect(result.newAircraft, isEmpty);
    expect(result.frequentRoute, isNull);
  });

  test(
    'aircraft firsts reuse collection normalization and preserve variants',
    () {
      final result = _summary([
        _flight('old-a320', type: 'Airbus a320', date: DateTime(2025)),
        _flight('again-a320', type: '空客A320'),
        _flight('neo', type: 'a320neo', date: DateTime(2026, 9, 1)),
        _flight('max', type: 'Boeing 737 MAX 8', date: DateTime(2026, 8, 1)),
        _flight('base', type: '737', date: DateTime(2026, 7, 1)),
        _flight('unknown', type: 'Unknown'),
        _flight('blank', type: '  '),
      ]);
      expect(result.newAircraft.map((entry) => entry.type), [
        'A320NEO',
        '737 MAX 8',
        '737',
      ]);
    },
  );

  test(
    'routes merge directions and ignore repeated ids, blank and same airports',
    () {
      final first = _flight(
        'first',
        from: ' pvg ',
        to: 'pek',
        date: DateTime(2026, 2, 1),
      );
      final latest = _flight(
        'latest',
        from: 'PEK',
        to: 'PVG',
        date: DateTime(2026, 8, 1),
      );
      final result = _summary([
        latest,
        first,
        latest,
        _flight('same', from: 'pvg', to: 'PVG'),
        _flight('empty', from: '', to: 'PEK'),
        _flight('older', date: DateTime(2025)),
        _flight('future', status: FlightStatus.upcoming),
      ]);
      final route = result.frequentRoute!;
      expect(route.departureIata, 'PEK');
      expect(route.arrivalIata, 'PVG');
      expect(route.fromCity, 'Display Beijing');
      expect(route.toCity, 'Display Shanghai');
      expect(route.count, 2);
      expect(route.flights, [latest, first]);
      expect(_summary([first, first]).frequentRoute, isNull);
      // Frequency is a count of legs, not proof that both directions occurred.
      expect(
        _summary([first, _flight('same-direction')]).frequentRoute!.count,
        2,
      );
    },
  );

  test('route ties use latest leg then stable airport key', () {
    final day = DateTime(2026, 10, 1);
    final input = [
      _flight('pvg-1'),
      _flight('pvg-2', date: day),
      _flight('sin-1', to: 'SIN'),
      _flight('sin-2', to: 'SIN', date: day),
    ];
    expect(_summary(input.reversed).frequentRoute!.departureIata, 'PEK');
    final newer = _flight('sin-3', to: 'SIN', date: DateTime(2026, 11, 1));
    expect(
      _summary([input[0], input[1], input[2], newer])
          .frequentRoute!
          .arrivalIata,
      'SIN',
    );
    final unknown = _summary([
      _flight('a', from: 'ZZZ', to: 'XXX'),
      _flight('b', from: 'XXX', to: 'ZZZ'),
    ]).frequentRoute!;
    expect([unknown.fromCity, unknown.toCity], ['XXX', 'ZZZ']);
  });

  test('firsts and route legs use ids to stabilize identical timestamps', () {
    final a = _flight('a', to: 'LHR', type: 'A350');
    final b = _flight('b', to: 'YXU', type: 'C919');
    final sameType = _flight('z', to: 'LHR', type: 'A350');
    final result = _summary([sameType, b, a]);
    expect(result.newCities.map((city) => city.firstFlight.id), ['a', 'b']);
    expect(result.newAircraft.map((entry) => entry.firstFlight.id), ['a', 'b']);
    expect(result.frequentRoute!.flights.map((flight) => flight.id), [
      'a',
      'z',
    ]);
  });

  test('first completed duplicate wins, output snapshots are immutable, empty year stays empty', () {
    final first = _flight('duplicate', type: 'A350');
    final duplicate = _flight('duplicate', to: 'LHR', type: 'C919');
    final input = [
      _flight('duplicate', status: FlightStatus.upcoming),
      first,
      duplicate,
    ];
    final original = input.toList();
    final result = _summary(input);
    expect(input, original);
    expect(result.newCities.single.firstFlight, same(first));
    expect(result.newAircraft.single.type, 'A350');
    expect(result.frequentRoute, isNull);
    expect(() => result.newCities.clear(), throwsUnsupportedError);
    expect(() => result.newAircraft.clear(), throwsUnsupportedError);
    final route = _summary([first, _flight('other')]).frequentRoute!;
    expect(() => route.flights.clear(), throwsUnsupportedError);
    input.clear();
    expect(result.newCities, hasLength(1));
    final empty = _summary(original, year: 2030);
    expect(empty.year, 2030);
    expect(empty.newCities, isEmpty);
    expect(empty.newAircraft, isEmpty);
    expect(empty.frequentRoute, isNull);
  });
}
