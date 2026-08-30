import 'dart:convert';

import 'package:flight_footprint/data/backup_codec.dart';
import 'package:flight_footprint/domain/flight.dart';
import 'package:flight_footprint/domain/visited_place.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final createdAt = DateTime.utc(2026, 8, 26, 9);
  final updatedAt = DateTime.utc(2026, 8, 26, 10);
  final data = BackupData(
    flights: [
      Flight(
        id: 'flight-1',
        departureIata: 'PVG',
        arrivalIata: 'PEK',
        departedAt: DateTime.utc(2026, 8, 1),
        createdAt: createdAt,
        updatedAt: updatedAt,
        status: FlightStatus.upcoming,
        airline: 'MU',
        aircraftType: 'Airbus A330-300',
        durationMinutes: 145,
        seat: '18A',
        distanceKm: 1067.2,
      ),
    ],
    visitedPlaces: [
      VisitedPlace(
        id: 'place-1',
        name: 'The Bund',
        latitude: 31.240,
        longitude: 121.490,
        visitedAt: DateTime.utc(2026, 8, 2),
        createdAt: createdAt,
        updatedAt: updatedAt,
      ),
    ],
  );

  test('backup v1 survives a JSON round trip', () {
    final decoded = BackupCodec.decode(
      BackupCodec.encode(data, exportedAt: createdAt),
    );
    expect(decoded.flights.single.id, 'flight-1');
    expect(decoded.flights.single.distanceKm, 1067.2);
    expect(decoded.flights.single.aircraftType, 'Airbus A330-300');
    expect(decoded.flights.single.durationMinutes, 145);
    expect(decoded.flights.single.seat, '18A');
    expect(decoded.flights.single.status, FlightStatus.upcoming);
    expect(decoded.visitedPlaces.single.name, 'The Bund');
    expect(decoded.visitedPlaces.single.visitedAt, DateTime.utc(2026, 8, 2));
  });

  test('older backups without a status remain completed', () {
    final decoded = BackupCodec.decode(
      '{"format":"flight-footprint-backup","version":1,"flights":['
      '{"id":"legacy-1","departureIata":"PVG","arrivalIata":"SZX",'
      '"departedAt":"2024-01-01T08:00:00Z",'
      '"createdAt":"2024-01-01T08:00:00Z",'
      '"updatedAt":"2024-01-01T08:00:00Z"}],"visitedPlaces":[]}',
    );
    expect(decoded.flights.single.status, FlightStatus.completed);
  });

  test('backup rejects unsupported versions before import', () {
    expect(
      () => BackupCodec.decode(
        '{"format":"flight-footprint-backup","version":2,'
        '"flights":[],"visitedPlaces":[]}',
      ),
      throwsFormatException,
    );
  });

  test('imports the web app flight array and keeps sampled track points', () {
    final decoded = BackupCodec.decode(
      '[{"id":42,"flightNumber":"AK128","airline":"亚洲航空",'
      '"flightDate":"2026-07-04","departureTime":"22:05",'
      '"arrivalTime":"02:15+1","originCode":"KUL",'
      '"destinationCode":"SZX","originCity":"吉隆坡",'
      '"destinationCity":"深圳","aircraftType":"Airbus A320",'
      '"durationMinutes":250,"distanceKm":2510,"cabin":"经济舱",'
      '"track":[{"recordedAt":100,"latitude":3.1,"longitude":101.7},'
      '{"recordedAt":200,"latitude":4.0,"longitude":103.0}]}]',
    );
    expect(decoded.flights.single.id, 'web-flight-42');
    expect(decoded.flights.single.departureIata, 'KUL');
    expect(decoded.flights.single.arrivalIata, 'SZX');
    expect(decoded.flights.single.departedAt, DateTime.utc(2026, 7, 4, 22, 5));
    expect(decoded.flights.single.arrivedAt, DateTime.utc(2026, 7, 5, 2, 15));
    expect(decoded.flights.single.track, hasLength(2));
    expect(decoded.flights.single.track.last.longitude, 103.0);
  });

  test('imports a web envelope with visited places', () {
    final decoded = BackupCodec.decode(
      '{"format":"flight-footprint-web-export","version":1,'
      '"flights":[],"visitedPlaces":[{"id":9,"cityName":"深圳",'
      '"countryCode":"CN","latitude":22.54,"longitude":114.06,'
      '"visitedAt":"2026-07-05"}]}',
    );
    expect(decoded.flights, isEmpty);
    expect(decoded.visitedPlaces.single.id, 'web-place-9');
    expect(decoded.visitedPlaces.single.name, '深圳');
  });

  test('imports legacy device-sync places with snake_case fields', () {
    final decoded = BackupCodec.decode(
      '{"flights":[],"places":[{"id":12,"city_name":"厦门",'
      '"country_code":"CN","country_name":"中国",'
      '"airport_code":"XMN","latitude":24.48,"longitude":118.08,'
      '"visited_at":"2026-07-06","created_at":"2026-07-06"}]}',
    );
    expect(decoded.visitedPlaces.single.id, 'web-place-12');
    expect(decoded.visitedPlaces.single.name, '厦门');
    expect(decoded.visitedPlaces.single.countryCode, 'CN');
    expect(decoded.visitedPlaces.single.visitedAt, DateTime.utc(2026, 7, 6));
  });

  test('decodes a cloud response with a nested JSON snapshot', () {
    final cloudSnapshot = jsonDecode(BackupCodec.encode(data));
    final decoded = BackupCodec.decodeCloudSnapshot(
      jsonEncode({'revision': 7, 'snapshot': jsonEncode(cloudSnapshot)}),
    );

    expect(decoded.flights.single.id, 'flight-1');
    expect(decoded.visitedPlaces.single.name, 'The Bund');
  });

  test('decodes the legacy Pages envelope and ignores derived stats', () {
    final decoded = BackupCodec.decodeCloudSnapshot({
      'revision': 3,
      'flights': [
        {
          'id': 12,
          'flight_number': 'UO123',
          'airline': '香港快运航空',
          'flight_date': '2026-08-20',
          'origin_code': 'HKG',
          'destination_code': 'SZX',
          'departure_time': '22:30',
          'arrival_time': '23:35',
          'duration_minutes': '65',
          'distance_km': '40',
          'created_at': '2026-08-20T14:30:00Z',
        },
      ],
      'places': [
        {
          'id': 9,
          'city_name': '深圳',
          'country_code': 'CN',
          'latitude': '22.54',
          'longitude': 114.06,
          'visited_at': '2026-08-21',
          'created_at': '2026-08-21',
        },
      ],
      'stats': {'countryCount': 99},
    });

    expect(decoded.flights.single.flightNumber, 'UO123');
    expect(decoded.flights.single.durationMinutes, 65);
    expect(decoded.visitedPlaces.single.name, '深圳');
    expect(decoded.visitedPlaces.single.latitude, 22.54);
  });

  test('deduplicates legacy cloud records before restore', () {
    final first = jsonDecode(BackupCodec.encode(data)) as Map<String, dynamic>;
    final second = jsonDecode(
      BackupCodec.encode(
        BackupData(
          flights: [
            data.flights.single.copyWith(
              distanceKm: 1111,
              updatedAt: updatedAt.add(const Duration(hours: 1)),
            ),
          ],
          visitedPlaces: [data.visitedPlaces.single],
        ),
      ),
    ) as Map<String, dynamic>;
    final decoded = BackupCodec.decodeCloudSnapshot({
      'flights': [
        ...(first['flights'] as List),
        ...(second['flights'] as List),
      ],
      'places': [
        ...(first['visitedPlaces'] as List),
        ...(second['visitedPlaces'] as List),
      ],
    });

    expect(decoded.flights, hasLength(1));
    expect(decoded.flights.single.distanceKm, 1111);
    expect(decoded.visitedPlaces, hasLength(1));
  });
}
