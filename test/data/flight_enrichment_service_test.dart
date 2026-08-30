import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:flight_footprint/data/flight_enrichment_service.dart';

class _FakeClient extends http.BaseClient {
  _FakeClient(this.handler);

  final http.Response Function(http.BaseRequest request) handler;
  final requests = <http.BaseRequest>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    final response = handler(request);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      reasonPhrase: response.reasonPhrase,
      request: request,
    );
  }
}

void main() {
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
    final service = FlightEnrichmentService(client: client);

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
      final service = FlightEnrichmentService(client: client);

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
    final service = FlightEnrichmentService(client: client);

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
    final service = FlightEnrichmentService(client: client);

    final result = await service.lookup(
      airline: '中国国际航空',
      flightNumber: 'CA128',
    );

    expect(result?.aircraftType, 'A320-200');
    expect(result?.durationMinutes, 200);
    expect(result?.distanceKm, 1700);
  });

  test(
    'uses the flight date for time-only schedules and normalizes IATA type',
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
      final service = FlightEnrichmentService(client: client);

      final result = await service.lookup(
        airline: '中国国际航空',
        flightNumber: 'CA128',
        flightDate: DateTime(2026, 7, 4),
      );

      expect(result?.aircraftType, 'A320neo');
      expect(result?.departedAt, DateTime(2026, 7, 4, 22, 5));
      expect(result?.arrivedAt, DateTime(2026, 7, 5, 2, 15));
    },
  );
}
