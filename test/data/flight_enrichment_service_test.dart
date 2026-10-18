import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:flight_footprint/data/flight_enrichment_service.dart';

class _FakeClient extends http.BaseClient {
  _FakeClient(this.handler);

  final FutureOr<http.Response> Function(http.BaseRequest request) handler;
  final requests = <http.BaseRequest>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    final response = await handler(request);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      reasonPhrase: response.reasonPhrase,
      request: request,
    );
  }
}

final _now = DateTime(2026, 10, 14, 12);

bool _isLive(http.BaseRequest request) =>
    request.url.host == 'api.adsb.lol' &&
    request.url.path.startsWith('/v2/callsign/');

Map<String, Object?> _plane({
  String callsign = 'CCA123',
  Object seen = 10,
  String hex = '780123',
  String? registration = 'B-1234',
  String? type = 'A20N',
}) => {
  'flight': callsign,
  'seen': seen,
  'hex': hex,
  'r': ?registration,
  't': ?type,
};

http.Response _liveResponse(
  List<Map<String, Object?>> aircraft, {
  DateTime? observedAt,
  bool milliseconds = false,
}) => http.Response(
  jsonEncode({
    'now': milliseconds
        ? (observedAt ?? _now).millisecondsSinceEpoch
        : (observedAt ?? _now).millisecondsSinceEpoch / 1000,
    'ac': aircraft,
  }),
  200,
);

http.Response _routeResponse({
  String departure = 'PEK',
  String arrival = 'SZX',
  String? departedAt,
  String? arrivedAt,
  String? type,
  String? registration,
}) => http.Response(
  jsonEncode({
    'response': {
      'flightroute': {
        'callsign_iata': 'CA123',
        'origin': {'iata_code': departure},
        'destination': {'iata_code': arrival},
        'departure_time': ?departedAt,
        'arrival_time': ?arrivedAt,
        if (type != null || registration != null)
          'aircraft': {'type': ?type, 'registration': ?registration},
      },
    },
  }),
  200,
);

_FakeClient _liveClient(
  FutureOr<http.Response> Function(http.BaseRequest request) live, {
  http.Response? route,
  http.Response? aircraft,
}) => _FakeClient((request) {
  if (_isLive(request)) return live(request);
  if (request.url.path.startsWith('/v0/aircraft/')) {
    return aircraft ?? http.Response('{}', 404);
  }
  if (request.url.path == '/v0/callsign/CCA123' && route != null) {
    return route;
  }
  return http.Response('{}', 404);
});

Future<FlightEnrichment?> _lookupToday(
  _FakeClient client, {
  String? departureIata,
  String? arrivalIata,
}) =>
    FlightEnrichmentService(
      enableLiveAircraft: true,
      enableAdsbLolRouteset: true,
      client: client,
      now: () => _now,
    ).lookup(
      airline: '国航',
      flightNumber: 'CA123',
      flightDate: _now,
      departureIata: departureIata,
      arrivalIata: arrivalIata,
    );

void main() {
  group('live lookup reliability', () {
    for (final example in <(http.Response, AircraftLookupStatus)>[
      (_liveResponse([]), AircraftLookupStatus.noMatch),
      (http.Response('{}', 503), AircraftLookupStatus.unavailable),
      (http.Response('{}', 429), AircraftLookupStatus.rateLimited),
      (http.Response('not json', 200), AircraftLookupStatus.unavailable),
      (
        _liveResponse([
          _plane(),
          _plane(hex: '780456', registration: 'B-5678'),
        ]),
        AircraftLookupStatus.ambiguous,
      ),
      (
        _liveResponse([
          _plane(),
        ], observedAt: _now.subtract(const Duration(seconds: 180))),
        AircraftLookupStatus.stale,
      ),
      (
        _liveResponse([_plane(type: null)]),
        AircraftLookupStatus.typeUnavailable,
      ),
    ]) {
      test('reports ${example.$2} even without route data', () async {
        final result = await _lookupToday(_liveClient((_) => example.$1));
        expect(result, isNotNull);
        expect(result!.aircraftLookupStatus, example.$2);
        expect(result.aircraftLookupAttempted, isTrue);
        expect(result.aircraftType, isNull);
      });
    }

    test(
      'rejects future observations inside the old five-minute clock window',
      () async {
        final result = await _lookupToday(
          _liveClient(
            (_) => _liveResponse([
              _plane(seen: 0),
            ], observedAt: _now.add(const Duration(seconds: 60))),
          ),
        );
        expect(result?.aircraftLookupStatus, AircraftLookupStatus.stale);
        expect(result?.aircraftType, isNull);
      },
    );

    test('retains an explicit airport-conflict reason', () async {
      final result = await _lookupToday(
        _liveClient((_) => _liveResponse([_plane()]), route: _routeResponse()),
        departureIata: 'CAN',
      );
      expect(result?.aircraftLookupStatus, AircraftLookupStatus.routeConflict);
      expect(result?.aircraftType, isNull);
    });

    test('identical concurrent lookups share one request workflow', () async {
      final response = Completer<http.Response>();
      final client = _liveClient((_) => response.future);
      final service = FlightEnrichmentService(
        client: client,
        now: () => _now,
        enableLiveAircraft: true,
        enableAdsbLolRouteset: true,
      );
      addTearDown(service.dispose);
      final first = service.lookup(
        airline: '国航',
        flightNumber: 'CA123',
        flightDate: _now,
      );
      final second = service.lookup(
        airline: '国航',
        flightNumber: 'CA123',
        flightDate: _now,
      );
      expect(identical(first, second), isTrue);
      response.complete(_liveResponse([_plane()]));
      final results = await Future.wait([first, second]);
      expect(
        results.every((result) => result?.aircraftType == 'A320neo'),
        isTrue,
      );
      expect(client.requests.where(_isLive), hasLength(1));
    });

    test(
      'short memory cache expires and airport edits do not reuse it',
      () async {
        var instant = _now;
        final client = _liveClient(
          (_) => _liveResponse([_plane()], observedAt: instant),
          route: _routeResponse(),
        );
        final service = FlightEnrichmentService(
          client: client,
          now: () => instant,
          enableLiveAircraft: true,
          enableAdsbLolRouteset: true,
        );
        addTearDown(service.dispose);
        Future<FlightEnrichment?> query({String? departure}) => service.lookup(
          airline: '国航',
          flightNumber: 'CA123',
          flightDate: _now,
          departureIata: departure,
        );
        expect((await query())?.aircraftType, 'A320neo');
        final requests = client.requests.length;
        expect((await query())?.aircraftType, 'A320neo');
        expect(client.requests.length, requests);
        expect(
          (await query(departure: 'CAN'))?.aircraftLookupStatus,
          AircraftLookupStatus.routeConflict,
        );
        expect(client.requests.where(_isLive), hasLength(2));
        instant = instant.add(const Duration(seconds: 16));
        expect((await query())?.aircraftType, 'A320neo');
        expect(client.requests.where(_isLive), hasLength(3));
      },
    );

    test('cached observations cannot outlive their freshness limit', () async {
      var instant = _now;
      final client = _liveClient((_) => _liveResponse([_plane(seen: 115)]));
      final service = FlightEnrichmentService(
        client: client,
        now: () => instant,
        enableLiveAircraft: true,
        enableAdsbLolRouteset: true,
      );
      addTearDown(service.dispose);
      Future<FlightEnrichment?> query() => service.lookup(
        airline: '国航',
        flightNumber: 'CA123',
        flightDate: _now,
      );
      expect((await query())?.aircraftType, 'A320neo');
      instant = instant.add(const Duration(seconds: 10));
      expect((await query())?.aircraftLookupStatus, AircraftLookupStatus.stale);
      expect(client.requests.where(_isLive), hasLength(2));
    });

    test(
      'unavailable results remain retryable instead of poisoning the cache',
      () async {
        var failed = true;
        final client = _liveClient(
          (_) => failed ? http.Response('{}', 503) : _liveResponse([_plane()]),
        );
        final service = FlightEnrichmentService(
          client: client,
          now: () => _now,
          enableLiveAircraft: true,
          enableAdsbLolRouteset: true,
        );
        addTearDown(service.dispose);
        Future<FlightEnrichment?> query() => service.lookup(
          airline: '国航',
          flightNumber: 'CA123',
          flightDate: _now,
        );
        expect(
          (await query())?.aircraftLookupStatus,
          AircraftLookupStatus.unavailable,
        );
        failed = false;
        expect((await query())?.aircraftType, 'A320neo');
        expect(client.requests.where(_isLive), hasLength(2));
      },
    );

    test(
      'a total deadline bounds both live lookup and sequential route fallbacks',
      () async {
        final client = _FakeClient((_) => Completer<http.Response>().future);
        final service = FlightEnrichmentService(
          client: client,
          now: () => _now,
          enableLiveAircraft: true,
          enableAdsbLolRouteset: true,
          requestTimeout: const Duration(seconds: 7),
          lookupTimeout: const Duration(milliseconds: 40),
        );
        addTearDown(service.dispose);
        final clock = Stopwatch()..start();
        final result = await service.lookup(
          airline: '国航',
          flightNumber: 'CA123',
          flightDate: _now,
        );
        expect(clock.elapsed, lessThan(const Duration(milliseconds: 500)));
        expect(result?.aircraftLookupStatus, AircraftLookupStatus.unavailable);
        expect(client.requests.length, lessThanOrEqualTo(2));
      },
    );

    test(
      'completed routes are preserved when live lookup reaches the deadline',
      () async {
        final client = _liveClient(
          (_) => Completer<http.Response>().future,
          route: _routeResponse(),
        );
        final service = FlightEnrichmentService(
          client: client,
          now: () => _now,
          enableLiveAircraft: true,
          enableAdsbLolRouteset: true,
          lookupTimeout: const Duration(milliseconds: 40),
        );
        addTearDown(service.dispose);
        final result = await service.lookup(
          airline: '国航',
          flightNumber: 'CA123',
          flightDate: _now,
        );
        expect(result?.departureIata, 'PEK');
        expect(result?.aircraftLookupStatus, AircraftLookupStatus.unavailable);
      },
    );

    test('disposal prevents stale results and any later request', () async {
      final response = Completer<http.Response>();
      final client = _liveClient((_) => response.future);
      final service = FlightEnrichmentService(
        client: client,
        now: () => _now,
        enableLiveAircraft: true,
        enableAdsbLolRouteset: true,
      );
      final pending = service.lookup(
        airline: '国航',
        flightNumber: 'CA123',
        flightDate: _now,
      );
      service.dispose();
      response.complete(_liveResponse([_plane()]));
      expect(await pending, isNull);
      final requests = client.requests.length;
      expect(
        await service.lookup(
          airline: '国航',
          flightNumber: 'CA123',
          flightDate: _now,
        ),
        isNull,
      );
      expect(client.requests.length, requests);
    });
  });

  test('defaults respect build-time experimental feed flags', () {
    final service = FlightEnrichmentService(
      client: _FakeClient((_) => http.Response('{}', 404)),
    );
    expect(
      service.enableLiveAircraft,
      const bool.fromEnvironment(
        'FLIGHT_FOOTPRINT_ENABLE_LIVE_AIRCRAFT',
        defaultValue: true,
      ),
    );
    expect(
      service.enableAdsbLolRouteset,
      const bool.fromEnvironment(
        'FLIGHT_FOOTPRINT_ENABLE_ADSB_LOL_ROUTESET',
        defaultValue: true,
      ),
    );
  });

  test(
    'disabled experimental feeds preserve ADSBdb without live hints',
    () async {
      final client = _liveClient(
        (_) => _liveResponse([_plane()]),
        route: _routeResponse(),
      );
      final service = FlightEnrichmentService(
        client: client,
        now: () => _now,
        enableLiveAircraft: false,
        enableAdsbLolRouteset: false,
      );

      final result = await service.lookup(
        airline: '国航',
        flightNumber: 'CA123',
        flightDate: _now,
      );

      expect(result?.source, 'ADSBdb');
      expect(result?.departureIata, 'PEK');
      expect(result?.arrivalIata, 'SZX');
      expect(result?.aircraftLookupAttempted, isFalse);
      expect(result?.aircraftType, isNull);
      expect(result?.aircraftSource, isNull);
      expect(result?.aircraftObservedAt, isNull);
      expect(
        client.requests.where((r) => r.url.host == 'api.adsb.lol'),
        isEmpty,
      );
      expect(
        client.requests.where((r) => r.url.path.startsWith('/v0/aircraft/')),
        isEmpty,
      );
    },
  );

  test('disabled ADSB.lol fallback never requests its routeset', () async {
    final client = _FakeClient((_) => http.Response('{}', 404));
    final service = FlightEnrichmentService(
      client: client,
      now: () => _now,
      enableLiveAircraft: false,
      enableAdsbLolRouteset: false,
    );

    expect(
      await service.lookup(
        airline: '国航',
        flightNumber: 'CA123',
        flightDate: _now,
      ),
      isNull,
    );
    expect(client.requests.where((r) => r.url.host == 'api.adsb.lol'), isEmpty);
    expect(
      client.requests.where((r) => r.url.host == 'api.adsbdb.com'),
      isNotEmpty,
    );
    expect(
      client.requests.where(
        (r) => r.url.host == 'adsb.im' && r.method == 'POST',
      ),
      isNotEmpty,
    );
  });

  test(
    'disabled experimental feeds retain the adsb.im route fallback',
    () async {
      final client = _FakeClient((request) {
        if (request.url.host == 'adsb.im') {
          return http.Response(
            jsonEncode({
              'route': {'origin': 'PEK', 'destination': 'SZX'},
            }),
            200,
          );
        }
        return http.Response('{}', 404);
      });
      final result = await FlightEnrichmentService(
        client: client,
        now: () => _now,
        enableLiveAircraft: false,
        enableAdsbLolRouteset: false,
      ).lookup(airline: '国航', flightNumber: 'CA123', flightDate: _now);
      expect(result?.source, 'FlightBoard');
      expect(result?.departureIata, 'PEK');
      expect(result?.aircraftLookupAttempted, isFalse);
      expect(
        client.requests.where((r) => r.url.host == 'api.adsb.lol'),
        isEmpty,
      );
    },
  );

  test('ADSBdb route fills airport, airline, and aircraft details', () async {
    final client = _FakeClient((request) {
      if (!request.url.path.endsWith('/CCA123')) {
        return http.Response('{}', 404);
      }
      return http.Response(
        jsonEncode({
          'response': {
            'aircraft': {'type': 'A320-200', 'registration': 'B-1234'},
            'flightroute': {
              'callsign_iata': 'CA123',
              'airline': {'name': 'Air China'},
              'origin': {'iata_code': 'PEK'},
              'destination': {'iata_code': 'SZX'},
            },
          },
        }),
        200,
      );
    });
    final service = FlightEnrichmentService(
      enableLiveAircraft: true,
      enableAdsbLolRouteset: true,
      client: client,
      now: () => _now,
    );

    final result = await service.lookup(
      airline: '中国国际航空',
      flightNumber: 'CA123',
    );

    expect(result?.source, 'ADSBdb');
    expect(result?.airline, 'Air China');
    expect(result?.flightNumber, 'CA123');
    expect(result?.departureIata, 'PEK');
    expect(result?.arrivalIata, 'SZX');
    expect(result?.aircraftType, 'A320-200');
    expect(client.requests.map((request) => request.url.path), [
      '/v0/callsign/CA123',
      '/v0/callsign/CCA123',
    ]);
  });

  test(
    'FlightBoard-compatible routeset is used when ADSBdb has no match',
    () async {
      final client = _FakeClient((request) {
        if (request.method == 'POST' && request.url.host == 'adsb.im') {
          return http.Response(
            jsonEncode({
              'route': {
                'origin': 'SZX',
                'destination': 'CTU',
                'aircraft': {'type': 'A320'},
              },
            }),
            200,
          );
        }
        return http.Response('{}', 404);
      });
      final service = FlightEnrichmentService(
        enableLiveAircraft: true,
        enableAdsbLolRouteset: true,
        client: client,
        now: () => _now,
      );

      final result = await service.lookup(airline: '深圳航空', flightNumber: '128');

      expect(result?.source, 'FlightBoard');
      expect(result?.departureIata, 'SZX');
      expect(result?.arrivalIata, 'CTU');
      expect(result?.aircraftType, 'A320');
      expect(
        client.requests.where((request) => request.method == 'POST'),
        isNotEmpty,
      );
    },
  );

  test('an empty flight number skips network requests', () async {
    final client = _FakeClient((_) => http.Response('{}', 200));
    final service = FlightEnrichmentService(
      enableLiveAircraft: true,
      enableAdsbLolRouteset: true,
      client: client,
      now: () => _now,
    );

    expect(await service.lookup(airline: '国航', flightNumber: ' '), isNull);
    expect(client.requests, isEmpty);
  });

  test('normalizes aircraft labels and common duration formats', () async {
    final client = _FakeClient((request) {
      if (!request.url.path.endsWith('/CCA128')) {
        return http.Response('{}', 404);
      }
      return http.Response(
        jsonEncode({
          'response': {
            'flightroute': {
              'callsign_iata': 'CA128',
              'origin': {'iata_code': 'PEK'},
              'destination': {'iata_code': 'SZX'},
              'filed_ete': '03:20',
              'distance': '1,700 km',
            },
            'aircraft': {'model': 'Airbus A320-200'},
          },
        }),
        200,
      );
    });
    final service = FlightEnrichmentService(
      enableLiveAircraft: true,
      enableAdsbLolRouteset: true,
      client: client,
      now: () => _now,
    );

    final result = await service.lookup(
      airline: '中国国际航空',
      flightNumber: 'CA128',
    );

    expect(result?.aircraftType, 'A320-200');
    expect(result?.durationMinutes, 200);
    expect(result?.distanceKm, 1700);
  });

  test(
    'anchors time-only schedules without proving historical aircraft type',
    () async {
      final client = _FakeClient((request) {
        if (!request.url.path.endsWith('/CCA128')) {
          return http.Response('{}', 404);
        }
        return http.Response(
          jsonEncode({
            'response': {
              'flightroute': {
                'callsign_iata': 'CA128',
                'origin': {'iata_code': 'KUL'},
                'destination': {'iata_code': 'SZX'},
                'departure_time': '22:05',
                'arrival_time': '02:15',
                'aircraft': {'iata_type': '32N'},
              },
            },
          }),
          200,
        );
      });
      final service = FlightEnrichmentService(
        enableLiveAircraft: true,
        enableAdsbLolRouteset: true,
        client: client,
        now: () => _now,
      );

      final result = await service.lookup(
        airline: '中国国际航空',
        flightNumber: 'CA128',
        flightDate: DateTime(2026, 7, 4),
      );

      // Time-only schedule values anchored to the requested date do not prove
      // that an undated aircraft belongs to that historical flight.
      expect(result?.aircraftType, isNull);
      expect(result?.departedAt, DateTime(2026, 7, 4, 22, 5));
      expect(result?.arrivedAt, DateTime(2026, 7, 5, 2, 15));
    },
  );

  group('free live aircraft lookup', () {
    test('today adds live aircraft to a successful route', () async {
      final client = _liveClient(
        (_) => _liveResponse([_plane(callsign: ' cca123 ')]),
        route: _routeResponse(),
      );
      final result = await _lookupToday(client);

      expect(result?.departureIata, 'PEK');
      expect(result?.arrivalIata, 'SZX');
      expect(result?.aircraftType, 'A320neo');
      expect(result?.registration, 'B-1234');
      expect(result?.aircraftSource, 'ADSB.lol');
      expect(result?.aircraftLookupAttempted, isTrue);
      expect(
        result?.aircraftObservedAt?.isAtSameMomentAs(
          _now.subtract(const Duration(seconds: 10)),
        ),
        isTrue,
      );
      expect(client.requests.where(_isLive), hasLength(1));
      expect(
        client.requests.where(_isLive).single.url.path,
        '/v2/callsign/CCA123',
      );
    });

    test('can return aircraft without inventing route airports', () async {
      final client = _liveClient((_) => _liveResponse([_plane()]));
      final result = await _lookupToday(client);

      expect(result?.aircraftType, 'A320neo');
      expect(result?.departureIata, isNull);
      expect(result?.arrivalIata, isNull);
      expect(result?.aircraftLookupAttempted, isTrue);
    });

    test('accepts the provider millisecond response clock', () async {
      final client = _liveClient(
        (_) => _liveResponse([_plane()], milliseconds: true),
      );
      expect((await _lookupToday(client))?.aircraftType, 'A320neo');
    });

    test(
      'never combines live equipment with another route aircraft registration',
      () async {
        final client = _liveClient(
          (_) => _liveResponse([_plane(registration: null)]),
          route: _routeResponse(
            departedAt: '2026-10-14T10:00:00',
            type: 'A330-300',
            registration: 'B-9999',
          ),
        );
        final result = await _lookupToday(client);
        expect(result?.aircraftType, 'A320neo');
        expect(result?.registration, isNull);
        expect(result?.aircraftSource, 'ADSB.lol');
      },
    );

    test(
      'airport conflict removes even explicitly dated route equipment',
      () async {
        final client = _liveClient(
          (_) => _liveResponse([_plane()]),
          route: _routeResponse(
            departedAt: '2026-10-14T10:00:00',
            type: 'A330-300',
            registration: 'B-9999',
          ),
        );
        final result = await _lookupToday(client, departureIata: 'CAN');
        expect(result?.departureIata, 'PEK');
        expect(result?.aircraftType, isNull);
        expect(result?.registration, isNull);
        expect(result?.aircraftSource, isNull);
        expect(result?.aircraftObservedAt, isNull);
      },
    );

    for (final date in <DateTime?>[
      null,
      DateTime(2026, 10, 13, 23, 59),
      DateTime(2026, 10, 15),
    ]) {
      test('does not use live aircraft for date $date', () async {
        final client = _liveClient((_) => _liveResponse([_plane()]));
        await FlightEnrichmentService(
          enableLiveAircraft: true,
          enableAdsbLolRouteset: true,
          client: client,
          now: () => _now,
        ).lookup(airline: '国航', flightNumber: 'CA123', flightDate: date);
        expect(client.requests.where(_isLive), isEmpty);
      });
    }

    for (final date in [DateTime(2026, 10, 13), DateTime(2026, 10, 15)]) {
      test('does not attach undated route equipment to $date', () async {
        final client = _liveClient(
          (_) => _liveResponse([_plane()]),
          route: _routeResponse(type: 'A330-300', registration: 'B-9999'),
        );
        final result = await FlightEnrichmentService(
          enableLiveAircraft: true,
          enableAdsbLolRouteset: true,
          client: client,
          now: () => _now,
        ).lookup(airline: '国航', flightNumber: 'CA123', flightDate: date);
        expect(result?.departureIata, 'PEK');
        expect(result?.arrivalIata, 'SZX');
        expect(result?.aircraftType, isNull);
        expect(result?.registration, isNull);
        expect(client.requests.where(_isLive), isEmpty);
      });
    }

    test('preserves aircraft from a matching explicit dated route', () async {
      final date = DateTime(2026, 10, 13);
      final client = _liveClient(
        (_) => _liveResponse([_plane()]),
        route: _routeResponse(
          departedAt: '2026-10-13T22:05:00',
          arrivedAt: '2026-10-14T02:15:00',
          type: 'A330-300',
        ),
      );
      final result = await FlightEnrichmentService(
        enableLiveAircraft: true,
        enableAdsbLolRouteset: true,
        client: client,
        now: () => _now,
      ).lookup(airline: '国航', flightNumber: 'CA123', flightDate: date);
      expect(result?.aircraftType, 'A330-300');
      expect(result?.departedAt, DateTime(2026, 10, 13, 22, 5));
      expect(result?.arrivedAt, DateTime(2026, 10, 14, 2, 15));
      expect(client.requests.where(_isLive), isEmpty);
    });

    test('rejects mismatched explicit route dates', () async {
      final client = _liveClient(
        (_) => _liveResponse([_plane()]),
        route: _routeResponse(
          departedAt: '2026-10-11T10:00:00',
          type: 'A330-300',
        ),
      );
      final result =
          await FlightEnrichmentService(
            enableLiveAircraft: true,
            enableAdsbLolRouteset: true,
            client: client,
            now: () => _now,
          ).lookup(
            airline: '国航',
            flightNumber: 'CA123',
            flightDate: DateTime(2026, 10, 13),
          );
      expect(result, isNull);
    });

    test(
      'an adjacent route day does not prove the requested day aircraft',
      () async {
        final client = _liveClient(
          (_) => _liveResponse([_plane()]),
          route: _routeResponse(
            departedAt: '2026-10-12T10:00:00',
            type: 'A330-300',
            registration: 'B-9999',
          ),
        );
        final result =
            await FlightEnrichmentService(
              enableLiveAircraft: true,
              enableAdsbLolRouteset: true,
              client: client,
              now: () => _now,
            ).lookup(
              airline: '国航',
              flightNumber: 'CA123',
              flightDate: DateTime(2026, 10, 13),
            );
        expect(result?.aircraftType, isNull);
        expect(result?.registration, isNull);
      },
    );

    for (final seen in <Object>[-1, 121, 'bad']) {
      test('rejects invalid or stale observation age $seen', () async {
        final client = _liveClient((_) => _liveResponse([_plane(seen: seen)]));
        expect((await _lookupToday(client))?.aircraftType, isNull);
      });
    }

    for (final delta in [-301, 301]) {
      test('rejects a response clock offset of $delta seconds', () async {
        final client = _liveClient(
          (_) => _liveResponse([
            _plane(),
          ], observedAt: _now.add(Duration(seconds: delta))),
        );
        expect((await _lookupToday(client))?.aircraftType, isNull);
      });
    }

    test(
      'rejects a different callsign even when only one aircraft returns',
      () async {
        final client = _liveClient(
          (_) => _liveResponse([_plane(callsign: 'CCA1234')]),
        );
        expect((await _lookupToday(client))?.aircraftType, isNull);
      },
    );

    test(
      'rejects ambiguous multiple aircraft with the same callsign',
      () async {
        final client = _liveClient(
          (_) => _liveResponse([
            _plane(),
            _plane(hex: '780456', registration: 'B-5678', type: 'B738'),
          ]),
        );
        expect((await _lookupToday(client))?.aircraftType, isNull);
      },
    );

    test('deduplicates repeated observations of the same aircraft', () async {
      final client = _liveClient(
        (_) => _liveResponse([_plane(), _plane(seen: 12)]),
      );
      expect((await _lookupToday(client))?.aircraftType, 'A320neo');
    });

    test(
      'rejects conflicting identities disguised as duplicate registration',
      () async {
        final client = _liveClient(
          (_) => _liveResponse([_plane(), _plane(hex: '780456')]),
        );
        expect((await _lookupToday(client))?.aircraftType, isNull);
      },
    );

    test(
      'does not bind an observation from yesterday across midnight',
      () async {
        final midnight = DateTime(2026, 10, 14, 0, 1);
        final client = _liveClient(
          (_) => _liveResponse([_plane(seen: 120)], observedAt: midnight),
        );
        final result = await FlightEnrichmentService(
          enableLiveAircraft: true,
          enableAdsbLolRouteset: true,
          client: client,
          now: () => midnight,
        ).lookup(airline: '国航', flightNumber: 'CA123', flightDate: midnight);
        expect(result?.aircraftType, isNull);
      },
    );

    test(
      'rejects registry details for a different physical aircraft',
      () async {
        final client = _liveClient(
          (_) => _liveResponse([_plane(type: null)]),
          aircraft: http.Response(
            jsonEncode({
              'response': {
                'aircraft': {
                  'registration': 'B-9999',
                  'mode_s': '780123',
                  'icao_type': 'B38M',
                },
              },
            }),
            200,
          ),
        );
        expect((await _lookupToday(client))?.aircraftType, isNull);
      },
    );

    test('does not use an unidentified aircraft', () async {
      final client = _liveClient(
        (_) => _liveResponse([_plane(hex: '', registration: null)]),
      );
      expect((await _lookupToday(client))?.aircraftType, isNull);
    });

    test(
      'fills a missing live type using ADSBdb registration details',
      () async {
        final client = _liveClient(
          (_) => _liveResponse([_plane(type: null)]),
          aircraft: http.Response(
            jsonEncode({
              'response': {
                'aircraft': {
                  'registration': 'B-1234',
                  'icao_type': 'B38M',
                  'type': 'Boeing 737 MAX 8',
                },
              },
            }),
            200,
          ),
        );
        final result = await _lookupToday(client);
        expect(result?.aircraftType, 'B737 MAX 8');
        expect(result?.aircraftSource, 'ADSB.lol + ADSBdb');
        expect(
          client.requests.where((r) => r.url.path.startsWith('/v0/aircraft/')),
          isNotEmpty,
        );
      },
    );

    test(
      'missing aircraft type remains empty when registry has no match',
      () async {
        final client = _liveClient(
          (_) => _liveResponse([_plane(type: null)]),
          route: _routeResponse(),
        );
        expect((await _lookupToday(client))?.aircraftType, isNull);
      },
    );

    test(
      'can resolve an aircraft by hex when registration is unavailable',
      () async {
        final client = _liveClient(
          (_) => _liveResponse([_plane(type: null, registration: null)]),
          aircraft: http.Response(
            jsonEncode({
              'response': {
                'aircraft': {'mode_s': '780123', 'icao_type': 'E290'},
              },
            }),
            200,
          ),
        );
        final result = await _lookupToday(client);
        expect(result?.aircraftType, 'E190-E2');
        expect(
          client.requests.where((r) => r.url.path == '/v0/aircraft/780123'),
          hasLength(1),
        );
      },
    );

    for (final airports in [('CAN', 'SZX'), ('PEK', 'CTU')]) {
      test(
        'rejects live merge for conflicting route airports $airports',
        () async {
          final client = _liveClient(
            (_) => _liveResponse([_plane()]),
            route: _routeResponse(),
          );
          final result = await _lookupToday(
            client,
            departureIata: airports.$1,
            arrivalIata: airports.$2,
          );
          expect(result?.aircraftType, isNull);
        },
      );
    }

    test('accepts a route consistent with the requested airports', () async {
      final client = _liveClient(
        (_) => _liveResponse([_plane()]),
        route: _routeResponse(),
      );
      final result = await _lookupToday(
        client,
        departureIata: 'pek',
        arrivalIata: 'szx',
      );
      expect(result?.aircraftType, 'A320neo');
    });

    for (final response in [
      http.Response('{}', 404),
      http.Response('not JSON', 200),
      http.Response(
        jsonEncode({
          'ac': [_plane()],
        }),
        200,
      ),
    ]) {
      test(
        'provider failures do not discard successful route (${response.body})',
        () async {
          final client = _liveClient((_) => response, route: _routeResponse());
          final result = await _lookupToday(client);
          expect(result?.departureIata, 'PEK');
          expect(result?.arrivalIata, 'SZX');
          expect(result?.aircraftType, isNull);
          expect(result?.aircraftLookupAttempted, isTrue);
        },
      );
    }

    test('live request timeout leaves route available', () async {
      final client = _liveClient((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        return _liveResponse([_plane()]);
      }, route: _routeResponse());
      final result = await FlightEnrichmentService(
        enableLiveAircraft: true,
        enableAdsbLolRouteset: true,
        client: client,
        now: () => _now,
        requestTimeout: const Duration(milliseconds: 1),
      ).lookup(airline: '国航', flightNumber: 'CA123', flightDate: _now);
      expect(result?.departureIata, 'PEK');
      expect(result?.aircraftType, isNull);
    });

    for (final model in {
      'B38M': 'B737 MAX 8',
      'B39M': 'B737 MAX 9',
      'A339': 'A330-900NEO',
      'E290': 'E190-E2',
      'B773': 'B777-300',
      'A321': 'A321',
    }.entries) {
      test(
        'normalizes ${model.key} without inventing subtype suffixes',
        () async {
          final client = _liveClient(
            (_) => _liveResponse([_plane(type: model.key)]),
          );
          expect((await _lookupToday(client))?.aircraftType, model.value);
        },
      );
    }
  });
}
