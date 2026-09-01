import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../app/app_links.dart';

enum UpdateCheckStatus { available, upToDate, notConfigured, unavailable }

class AppUpdateResult {
  const AppUpdateResult._({
    required this.status,
    this.currentVersion,
    this.latestVersion,
    this.releaseUrl,
    this.downloadUrl,
    this.downloadSize,
    this.releaseNotes,
    this.errorMessage,
  });

  const AppUpdateResult.available({
    required String currentVersion,
    required String latestVersion,
    required Uri releaseUrl,
    Uri? downloadUrl,
    int? downloadSize,
    String? releaseNotes,
  }) : this._(
         status: UpdateCheckStatus.available,
         currentVersion: currentVersion,
         latestVersion: latestVersion,
         releaseUrl: releaseUrl,
         downloadUrl: downloadUrl,
         downloadSize: downloadSize,
         releaseNotes: releaseNotes,
       );

  const AppUpdateResult.upToDate({required String currentVersion})
    : this._(
        status: UpdateCheckStatus.upToDate,
        currentVersion: currentVersion,
        latestVersion: currentVersion,
      );

  const AppUpdateResult.notConfigured()
    : this._(status: UpdateCheckStatus.notConfigured);

  const AppUpdateResult.unavailable({String? errorMessage})
    : this._(status: UpdateCheckStatus.unavailable, errorMessage: errorMessage);

  final UpdateCheckStatus status;
  final String? currentVersion;
  final String? latestVersion;
  final Uri? releaseUrl;
  final Uri? downloadUrl;
  final int? downloadSize;
  final String? releaseNotes;
  final String? errorMessage;

  bool get hasUpdate => status == UpdateCheckStatus.available;

  bool get canDownloadInApp => downloadUrl != null;
}

/// Checks the latest public GitHub release without making update checks
/// mandatory for the app. The app remains fully usable offline; a failed
/// check is surfaced as a quiet message in the About page.
class AppUpdateService {
  AppUpdateService({
    http.Client? client,
    PackageInfoProvider? packageInfo,
    this.repositoryUrl,
  }) : _client = client ?? http.Client(),
       _packageInfo = packageInfo ?? _platformPackageInfo;

  final http.Client _client;
  final PackageInfoProvider _packageInfo;
  final Uri? repositoryUrl;

  void dispose() => _client.close();

  Future<AppUpdateResult> checkForUpdates() async {
    final repository = _repositoryParts(
      repositoryUrl ?? AppLinks.githubRepository,
    );
    if (repository == null) return const AppUpdateResult.notConfigured();

    try {
      final packageInfo = await _packageInfo();
      final currentVersion = _displayVersion(packageInfo);
      final manifestUri = _manifestUri(repository);
      if (manifestUri != null) {
        final manifestResponse = await _get(manifestUri);
        if (manifestResponse.statusCode == 200) {
          final manifest = _decodeMap(manifestResponse.body);
          final result = _resultFromManifest(manifest, currentVersion);
          if (result != null) {
            if (!result.hasUpdate || result.canDownloadInApp) return result;
            // Older manifests only carried the release page. Enrich them with
            // the APK asset exposed by GitHub so existing installations can
            // still use the in-app updater without a manifest migration.
            final asset = await _latestApkAsset(repository);
            if (asset != null) {
              return AppUpdateResult.available(
                currentVersion: result.currentVersion!,
                latestVersion: result.latestVersion!,
                releaseUrl: result.releaseUrl!,
                downloadUrl: asset.uri,
                downloadSize: asset.size,
                releaseNotes: result.releaseNotes,
              );
            }
            return result;
          }
        }
      }

      // Keep a releases API fallback so the checker remains useful if a fork
      // has not committed update.json yet.
      return await _checkLatestRelease(repository, currentVersion);
    } catch (error) {
      return AppUpdateResult.unavailable(errorMessage: error.toString());
    }
  }

  /// Downloads the APK into the app cache and reports byte progress. The
  /// returned file is handed to Android's package installer by the UI layer;
  /// no browser or external download page is involved.
  Future<File> downloadApk(
    AppUpdateResult update, {
    void Function(int received, int? total)? onProgress,
  }) async {
    final uri = update.downloadUrl;
    if (uri == null) {
      throw StateError('This release does not provide an APK asset.');
    }
    if (uri.scheme != 'https') {
      throw StateError('APK download must use HTTPS.');
    }

    final request = http.Request('GET', uri)
      ..headers['Accept'] = 'application/vnd.android.package-archive';
    final response = await _client
        .send(request)
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw StateError('APK download failed: HTTP ${response.statusCode}.');
    }

    final cache = await getTemporaryDirectory();
    final directory = Directory('${cache.path}/flight-footprint-updates');
    await directory.create(recursive: true);
    final version = _safeFilePart(update.latestVersion ?? 'latest');
    final file = File('${directory.path}/flight-footprint-$version.apk');
    if (await file.exists()) await file.delete();

    var received = 0;
    final sink = file.openWrite();
    try {
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 30),
      )) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, response.contentLength);
      }
      await sink.flush();
    } catch (_) {
      if (await file.exists()) await file.delete();
      rethrow;
    } finally {
      await sink.close();
    }

    if (received == 0 || !await file.exists()) {
      if (await file.exists()) await file.delete();
      throw StateError('Downloaded APK is empty.');
    }
    return file;
  }

  Future<http.Response> _get(Uri endpoint) => _client
      .get(
        endpoint,
        headers: const {
          'Accept': 'application/vnd.github+json',
          'X-GitHub-Api-Version': '2022-11-28',
        },
      )
      .timeout(const Duration(seconds: 8));

  Future<AppUpdateResult> _checkLatestRelease(
    ({String owner, String repository}) repository,
    String currentVersion,
  ) async {
    final endpoint = Uri.https(
      'api.github.com',
      '/repos/${repository.owner}/${repository.repository}/releases/latest',
    );
    final response = await _get(endpoint);
    if (response.statusCode != 200) {
      return AppUpdateResult.unavailable(
        errorMessage: 'GitHub HTTP ${response.statusCode}',
      );
    }
    final payload = _decodeMap(response.body);
    final tag = _text(payload?['tag_name']);
    final version = _normalizeVersion(tag ?? _text(payload?['name']));
    final releaseUrl = Uri.tryParse(_text(payload?['html_url']) ?? '');
    if (version == null || releaseUrl == null || !releaseUrl.hasScheme) {
      return const AppUpdateResult.unavailable(
        errorMessage: 'Release version is missing',
      );
    }

    final asset = _apkAsset(payload?['assets']);
    final notes = _text(payload?['body']);
    if (_compareVersions(version, currentVersion) > 0) {
      return AppUpdateResult.available(
        currentVersion: currentVersion,
        latestVersion: version,
        releaseUrl: releaseUrl,
        downloadUrl: asset?.uri,
        downloadSize: asset?.size,
        releaseNotes: notes,
      );
    }
    return AppUpdateResult.upToDate(currentVersion: currentVersion);
  }

  Future<({Uri uri, int? size})?> _latestApkAsset(
    ({String owner, String repository}) repository,
  ) async {
    final endpoint = Uri.https(
      'api.github.com',
      '/repos/${repository.owner}/${repository.repository}/releases/latest',
    );
    final response = await _get(endpoint);
    if (response.statusCode != 200) return null;
    final payload = _decodeMap(response.body);
    return _apkAsset(payload?['assets']);
  }

  static ({Uri uri, int? size})? _apkAsset(Object? rawAssets) {
    if (rawAssets is! List) return null;
    final candidates = <({Uri uri, int? size, String name})>[];
    for (final raw in rawAssets) {
      if (raw is! Map) continue;
      final name = _text(raw['name'])?.toLowerCase();
      final uri = _safeDownloadUrl(_text(raw['browser_download_url']));
      if (name == null || !name.endsWith('.apk') || uri == null) continue;
      final size = int.tryParse(_text(raw['size']) ?? '');
      candidates.add((uri: uri, size: size, name: name));
    }
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) {
      final aScore = a.name.contains('universal') || a.name.contains('release')
          ? 1
          : 0;
      final bScore = b.name.contains('universal') || b.name.contains('release')
          ? 1
          : 0;
      return bScore.compareTo(aScore);
    });
    final selected = candidates.first;
    return (uri: selected.uri, size: selected.size);
  }

  static Uri? _safeDownloadUrl(String? raw) {
    if (raw == null) return null;
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.scheme != 'https') return null;
    final allowedHosts = {
      'github.com',
      'objects.githubusercontent.com',
      'github-releases.githubusercontent.com',
    };
    if (!allowedHosts.contains(uri.host.toLowerCase())) return null;
    return uri;
  }

  static String _safeFilePart(String value) =>
      value.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');

  static Uri? _manifestUri(({String owner, String repository}) repository) {
    return Uri.https(
      'raw.githubusercontent.com',
      '/${repository.owner}/${repository.repository}/main/update.json',
    );
  }

  static Map<String, dynamic>? _decodeMap(String body) {
    try {
      final payload = jsonDecode(body);
      return payload is Map<String, dynamic> ? payload : null;
    } on FormatException {
      return null;
    }
  }

  static AppUpdateResult? _resultFromManifest(
    Map<String, dynamic>? manifest,
    String currentVersion,
  ) {
    if (manifest == null) return null;
    final version = _normalizeVersion(_text(manifest['version']));
    final releaseUrl = Uri.tryParse(_text(manifest['releaseUrl']) ?? '');
    if (version == null || releaseUrl == null || !releaseUrl.hasScheme) {
      return null;
    }
    final build = int.tryParse(_text(manifest['build']) ?? '');
    final downloadUrl = _safeDownloadUrl(
      _text(manifest['apkUrl']) ?? _text(manifest['downloadUrl']),
    );
    final downloadSize = int.tryParse(_text(manifest['apkSize']) ?? '');
    final currentBuild = int.tryParse(currentVersion.split('+').last) ?? 0;
    final isNewer =
        _compareVersions(version, currentVersion) > 0 ||
        (_compareVersions(version, currentVersion) == 0 &&
            build != null &&
            build > currentBuild);
    final notes = _text(manifest['notes']);
    if (!isNewer) {
      return AppUpdateResult.upToDate(currentVersion: currentVersion);
    }
    return AppUpdateResult.available(
      currentVersion: currentVersion,
      latestVersion: version,
      releaseUrl: releaseUrl,
      downloadUrl: downloadUrl,
      downloadSize: downloadSize,
      releaseNotes: notes,
    );
  }

  static String _displayVersion(PackageInfo packageInfo) {
    final version = packageInfo.version.trim();
    final build = packageInfo.buildNumber.trim();
    if (build.isEmpty) return version;
    return '$version+$build';
  }

  static String? _text(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static ({String owner, String repository})? _repositoryParts(Uri? uri) {
    if (uri == null || uri.host != 'github.com') return null;
    final parts = uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    if (parts.length < 2) return null;
    return (owner: parts[0], repository: parts[1]);
  }

  static String? _normalizeVersion(String? raw) {
    if (raw == null) return null;
    final match = RegExp(r'(?<!\d)(\d+)(?:\.(\d+))?(?:\.(\d+))?')
        .firstMatch(raw);
    if (match == null) return null;
    return [
      match.group(1)!,
      match.group(2) ?? '0',
      match.group(3) ?? '0',
    ].join('.');
  }

  static int _compareVersions(String left, String right) {
    final a = _normalizeVersion(left)!.split('.').map(int.parse).toList();
    final b = _normalizeVersion(right)!.split('.').map(int.parse).toList();
    for (var index = 0; index < 3; index++) {
      final result = a[index].compareTo(b[index]);
      if (result != 0) return result;
    }
    return 0;
  }
}

typedef PackageInfoProvider = Future<PackageInfo> Function();

Future<PackageInfo> _platformPackageInfo() => PackageInfo.fromPlatform();
