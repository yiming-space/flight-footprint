import 'dart:convert';

import 'package:flight_footprint/data/backup_codec.dart';
import 'package:flight_footprint/data/cloud_sync_service.dart';
import 'package:flight_footprint/data/flight_repository.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_test/flutter_test.dart';

class _MemoryCredentials implements CloudCredentialStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

class _FakeClient extends http.BaseClient {
  _FakeClient(this.handler);

  final http.Response Function(http.BaseRequest request) handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
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

class _FakeRepository extends FlightRepository {
  _FakeRepository() : super(databaseProvider: () => throw StateError('unused'));

  String? replacedSource;

  @override
  Future<ImportResult> replaceBackup(String source) async {
    replacedSource = source;
    final backup = BackupCodec.decode(source);
    return ImportResult(
      flightsMerged: backup.flights.length,
      placesMerged: backup.visitedPlaces.length,
    );
  }
}

void main() {
  test(
    'restores flights and footprints from a legacy cloud response',
    () async {
      const vaultId = '00000000-0000-4000-8000-000000000001';
      const recoveryCode =
          'ffr1.$vaultId.abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJ';
      final repository = _FakeRepository();
      final credentials = _MemoryCredentials();
      final client = _FakeClient((request) {
        if (request.method == 'POST' && request.url.path == '/v1/pair') {
          return http.Response(
            jsonEncode({
              'vaultId': vaultId,
              'deviceId': 'device-1',
              'accessToken': 'ffd1.test-token',
            }),
            201,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        if (request.method == 'GET' && request.url.path == '/v1/snapshot') {
          return http.Response(
            jsonEncode({
              'vaultId': vaultId,
              'revision': 4,
              'flights': [
                {
                  'id': 12,
                  'flightNumber': 'UO123',
                  'airline': '香港快运航空',
                  'flightDate': '2026-08-20',
                  'originCode': 'HKG',
                  'originCity': '香港',
                  'destinationCode': 'SZX',
                  'destinationCity': '深圳',
                  'departureTime': '22:30',
                  'arrivalTime': '23:35',
                  'durationMinutes': 65,
                  'distanceKm': 40,
                  'createdAt': '2026-08-20T14:30:00Z',
                },
              ],
              'places': [
                {
                  'id': 9,
                  'cityName': '深圳',
                  'countryCode': 'CN',
                  'latitude': 22.54,
                  'longitude': 114.06,
                  'visitedAt': '2026-08-21',
                  'createdAt': '2026-08-21',
                },
              ],
              'stats': {'countryCount': 99},
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response('{}', 404);
      });
      var refreshed = false;
      final service = CloudSyncService(
        repository: repository,
        client: client,
        credentialStore: credentials,
        onLocalDataChanged: () async => refreshed = true,
      );

      await service.restoreCloud(
        endpoint: 'https://sync.example.com/',
        recoveryCode: recoveryCode,
      );
      await service.restoreCloudToLocal();

      expect(refreshed, isTrue);
      final restored = BackupCodec.decode(repository.replacedSource!);
      expect(restored.flights, hasLength(1));
      expect(restored.flights.single.flightNumber, 'UO123');
      expect(restored.visitedPlaces, hasLength(1));
      expect(restored.visitedPlaces.single.name, '深圳');
      final payload =
          jsonDecode(repository.replacedSource!) as Map<String, dynamic>;
      expect(payload.containsKey('stats'), isFalse);
    },
  );
}
