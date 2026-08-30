import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import 'package:flight_footprint/data/app_update_service.dart';

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

PackageInfo _package(String version) => PackageInfo(
  appName: 'Flight Footprint',
  packageName: 'com.hjmingg.flight_footprint',
  version: version,
  buildNumber: '6',
);

void main() {
  const repository = 'https://github.com/example/flight-footprint';

  test('reports a newer GitHub release', () async {
    final service = AppUpdateService(
      repositoryUrl: Uri.parse(repository),
      client: _FakeClient((request) {
        expect(request.url.path, '/example/flight-footprint/main/update.json');
        return http.Response(
          jsonEncode({
            'version': '1.0.1',
            'build': 7,
            'releaseUrl': '$repository/releases/tag/v1.0.1',
            'notes': 'Fixes map rendering.',
          }),
          200,
        );
      }),
      packageInfo: () async => _package('1.0.0'),
    );

    final result = await service.checkForUpdates();
    service.dispose();

    expect(result.status, UpdateCheckStatus.available);
    expect(result.currentVersion, '1.0.0+6');
    expect(result.latestVersion, '1.0.1');
    expect(result.releaseNotes, 'Fixes map rendering.');
  });

  test('reports up to date when the release is not newer', () async {
    final service = AppUpdateService(
      repositoryUrl: Uri.parse(repository),
      client: _FakeClient(
        (_) => http.Response(
          jsonEncode({
            'version': '1.0.0',
            'build': 6,
            'releaseUrl': '$repository/releases/tag/1.0.0',
          }),
          200,
        ),
      ),
      packageInfo: () async => _package('1.0.0'),
    );

    final result = await service.checkForUpdates();
    service.dispose();

    expect(result.status, UpdateCheckStatus.upToDate);
  });

  test(
    'does not make a network request before a repository is configured',
    () async {
      var requests = 0;
      final service = AppUpdateService(
        repositoryUrl: Uri.parse('https://example.com/not-a-github-repository'),
        client: _FakeClient((_) {
          requests += 1;
          return http.Response('{}', 200);
        }),
        packageInfo: () async => _package('1.0.0'),
      );

      final result = await service.checkForUpdates();
      service.dispose();

      expect(result.status, UpdateCheckStatus.notConfigured);
      expect(requests, 0);
    },
  );
}
