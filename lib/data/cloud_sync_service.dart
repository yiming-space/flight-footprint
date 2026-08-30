import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'backup_codec.dart';
import 'flight_repository.dart';

/// The state of the optional, user-controlled sync connection.
enum CloudSyncStatus { disconnected, ready, syncing, synced, error }

class CloudSyncState {
  const CloudSyncState({
    this.status = CloudSyncStatus.disconnected,
    this.endpoint,
    this.vaultId,
    this.deviceId,
    this.revision = 0,
    this.lastSyncedAt,
    this.message,
    this.hasRecoveryCode = false,
  });

  final CloudSyncStatus status;
  final String? endpoint;
  final String? vaultId;
  final String? deviceId;
  final int revision;
  final DateTime? lastSyncedAt;
  final String? message;
  final bool hasRecoveryCode;

  bool get isConfigured =>
      endpoint != null && vaultId != null && deviceId != null;
  bool get isSyncing => status == CloudSyncStatus.syncing;
}

class CloudSyncException implements Exception {
  const CloudSyncException(
    this.message, {
    this.statusCode,
    this.code,
    this.currentRevision,
  });

  final String message;
  final int? statusCode;
  final String? code;
  final int? currentRevision;

  @override
  String toString() => message;
}

/// A small abstraction keeps the sync logic testable while production uses
/// Android Keystore-backed [FlutterSecureStorage].
abstract interface class CloudCredentialStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureCloudCredentialStore implements CloudCredentialStore {
  SecureCloudCredentialStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Client for the self-hosted Cloudflare Worker + D1 sync contract.
///
/// Sync is deliberately manual. The app remains useful without an endpoint,
/// and a worker never receives a token from the source tree or build config.
class CloudSyncService extends ChangeNotifier {
  CloudSyncService({
    required this.repository,
    http.Client? client,
    CloudCredentialStore? credentialStore,
    this.onLocalDataChanged,
    this.requestTimeout = const Duration(seconds: 20),
  }) : _client = client ?? http.Client(),
       _credentials = credentialStore ?? SecureCloudCredentialStore();

  static const _endpointKey = 'cloud.sync.endpoint';
  static const _vaultIdKey = 'cloud.sync.vault_id';
  static const _deviceIdKey = 'cloud.sync.device_id';
  static const _accessTokenKey = 'cloud.sync.access_token';
  static const _revisionKey = 'cloud.sync.revision';
  static const _lastSyncedAtKey = 'cloud.sync.last_synced_at';
  static const _recoveryCodeKey = 'cloud.sync.recovery_code';

  final FlightRepository repository;
  final http.Client _client;
  final CloudCredentialStore _credentials;
  final Future<void> Function()? onLocalDataChanged;
  final Duration requestTimeout;

  CloudSyncState _state = const CloudSyncState();
  String? _accessToken;
  Future<void>? _activeSync;
  bool _initialized = false;

  CloudSyncState get state => _state;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final values = await Future.wait<String?>([
        _credentials.read(_endpointKey),
        _credentials.read(_vaultIdKey),
        _credentials.read(_deviceIdKey),
        _credentials.read(_accessTokenKey),
        _credentials.read(_revisionKey),
        _credentials.read(_lastSyncedAtKey),
        _credentials.read(_recoveryCodeKey),
      ]);
      final endpoint = _nonEmpty(values[0]);
      final vaultId = _nonEmpty(values[1]);
      final deviceId = _nonEmpty(values[2]);
      _accessToken = _nonEmpty(values[3]);
      if (endpoint == null ||
          vaultId == null ||
          deviceId == null ||
          _accessToken == null) {
        _accessToken = null;
        return;
      }
      final lastSyncedAt = values[5] == null
          ? null
          : DateTime.tryParse(values[5]!);
      _state = CloudSyncState(
        status: lastSyncedAt == null
            ? CloudSyncStatus.ready
            : CloudSyncStatus.synced,
        endpoint: endpoint,
        vaultId: vaultId,
        deviceId: deviceId,
        revision: _parseNonNegativeInt(values[4]),
        lastSyncedAt: lastSyncedAt?.toUtc(),
        hasRecoveryCode: _nonEmpty(values[6]) != null,
      );
      notifyListeners();
    } catch (_) {
      // A broken/cleared platform keystore must never prevent local data from
      // opening. The next explicit connection can repair the state.
      _accessToken = null;
      _state = const CloudSyncState();
      notifyListeners();
    }
  }

  Future<String> createVault({
    required String endpoint,
    required String bootstrapSecret,
    String deviceName = 'Flight Footprint',
  }) async {
    await initialize();
    final base = normalizeEndpoint(endpoint);
    if (bootstrapSecret.trim().isEmpty) {
      throw const CloudSyncException('初始化密钥不能为空');
    }
    _setConnecting(base);
    try {
      final response = await _request(
        'POST',
        base,
        '/v1/vaults',
        body: {'bootstrapSecret': bootstrapSecret.trim()},
      );
      final vaultId = _requiredString(response, 'vaultId');
      final recoveryCode = _requiredString(response, 'recoveryCode');
      await _pair(
        base,
        vaultId: vaultId,
        recoveryCode: recoveryCode,
        deviceName: deviceName,
        persistRecoveryCode: true,
      );
      return recoveryCode;
    } on CloudSyncException {
      _resetConnectionState();
      rethrow;
    } catch (error) {
      _resetConnectionState();
      throw CloudSyncException('连接云端失败：$error');
    }
  }

  Future<void> restoreCloud({
    required String endpoint,
    required String recoveryCode,
    String deviceName = 'Flight Footprint',
  }) async {
    await initialize();
    final base = normalizeEndpoint(endpoint);
    if (recoveryCode.trim().isEmpty) {
      throw const CloudSyncException('恢复码不能为空');
    }
    _setConnecting(base);
    try {
      final parsedVaultId = _vaultIdFromRecoveryCode(recoveryCode.trim());
      await _pair(
        base,
        vaultId: parsedVaultId,
        recoveryCode: recoveryCode.trim(),
        deviceName: deviceName,
        persistRecoveryCode: false,
      );
    } on CloudSyncException {
      _resetConnectionState();
      rethrow;
    } catch (error) {
      _resetConnectionState();
      throw CloudSyncException('连接云端失败：$error');
    }
  }

  Future<void> _pair(
    String endpoint, {
    required String vaultId,
    required String recoveryCode,
    required String deviceName,
    required bool persistRecoveryCode,
  }) async {
    final response = await _request(
      'POST',
      endpoint,
      '/v1/pair',
      body: {'recoveryCode': recoveryCode, 'deviceName': deviceName.trim()},
    );
    final responseVaultId = _requiredString(response, 'vaultId');
    if (responseVaultId != vaultId) {
      throw const CloudSyncException('恢复码与云端资料库不匹配');
    }
    final deviceId = _requiredString(response, 'deviceId');
    final accessToken = _requiredString(response, 'accessToken');
    _accessToken = accessToken;
    await _credentials.write(_endpointKey, endpoint);
    await _credentials.write(_vaultIdKey, vaultId);
    await _credentials.write(_deviceIdKey, deviceId);
    await _credentials.write(_accessTokenKey, accessToken);
    await _credentials.write(_revisionKey, '0');
    await _credentials.delete(_lastSyncedAtKey);
    if (persistRecoveryCode) {
      await _credentials.write(_recoveryCodeKey, recoveryCode);
    } else {
      await _credentials.delete(_recoveryCodeKey);
    }
    _state = CloudSyncState(
      status: CloudSyncStatus.ready,
      endpoint: endpoint,
      vaultId: vaultId,
      deviceId: deviceId,
      hasRecoveryCode: persistRecoveryCode,
    );
    notifyListeners();
  }

  /// Uses this device as the source of truth and overwrites the cloud
  /// snapshot. Nothing is imported locally, so local edits can never be
  /// duplicated by a sync operation.
  Future<void> syncLocalToCloud() => _runExclusive(_syncLocalToCloudInternal);

  /// Replaces local data with the current cloud snapshot. This is intentionally
  /// separate from [syncLocalToCloud] so restoring a new device can never
  /// silently merge with stale local rows.
  Future<void> restoreCloudToLocal() =>
      _runExclusive(_restoreCloudToLocalInternal);

  /// Backwards-compatible alias for callers from older builds. The old
  /// bidirectional merge behaviour is gone; a regular sync is now explicitly
  /// local-authoritative.
  Future<void> syncNow() => syncLocalToCloud();

  Future<void> _runExclusive(Future<void> Function() action) {
    final active = _activeSync;
    if (active != null) return active;
    late final Future<void> operation;
    operation = action().whenComplete(() {
      if (identical(_activeSync, operation)) _activeSync = null;
    });
    _activeSync = operation;
    return operation;
  }

  Future<void> _syncLocalToCloudInternal({bool retryOnConflict = true}) async {
    await initialize();
    final endpoint = _state.endpoint;
    final token = _accessToken;
    if (endpoint == null || token == null || !_state.isConfigured) {
      throw const CloudSyncException('请先连接云端同步');
    }
    _state = CloudSyncState(
      status: CloudSyncStatus.syncing,
      endpoint: _state.endpoint,
      vaultId: _state.vaultId,
      deviceId: _state.deviceId,
      revision: _state.revision,
      lastSyncedAt: _state.lastSyncedAt,
      hasRecoveryCode: _state.hasRecoveryCode,
    );
    notifyListeners();
    try {
      final remote = await _request(
        'GET',
        endpoint,
        '/v1/snapshot',
        accessToken: token,
      );
      final remoteRevision = _nonNegativeInt(remote['revision']);
      // Export only the local database. Do not pull the remote snapshot here:
      // importBackup is a merge API and would re-introduce the duplicate-row
      // bug this action is designed to avoid.
      // Re-encode through the portable codec so a cloud write can contain only
      // the two user-owned datasets: flights (including their track points)
      // and visited places. Derived statistics and UI cache fields never enter
      // the cloud snapshot.
      final localBackup = BackupCodec.decode(await repository.exportBackup());
      final localSnapshot = jsonDecode(BackupCodec.encode(localBackup));
      final result = await _request(
        'PUT',
        endpoint,
        '/v1/snapshot',
        accessToken: token,
        body: {'expectedRevision': remoteRevision, 'snapshot': localSnapshot},
      );
      await _markSynced(_nonNegativeInt(result['revision']));
    } on CloudSyncException catch (error) {
      if (error.statusCode == 409 && retryOnConflict) {
        // A second read obtains the latest compare-and-swap revision, while
        // the payload remains the unchanged local snapshot.
        await _syncLocalToCloudInternal(retryOnConflict: false);
        return;
      }
      _markError(error);
      rethrow;
    } catch (error) {
      final failure = CloudSyncException('同步失败：$error');
      _markError(failure);
      throw failure;
    }
  }

  Future<void> _restoreCloudToLocalInternal() async {
    await initialize();
    final endpoint = _state.endpoint;
    final token = _accessToken;
    if (endpoint == null || token == null || !_state.isConfigured) {
      throw const CloudSyncException('请先连接云端同步');
    }
    _setSyncing();
    try {
      final remote = await _request(
        'GET',
        endpoint,
        '/v1/snapshot',
        accessToken: token,
      );
      final remoteSnapshot = _snapshotFromResponse(remote);
      if (remoteSnapshot == null) {
        throw const CloudSyncException('云端暂无可恢复记录，请先在其他设备同步一次。');
      }
      try {
        // Accept both the current Worker envelope and the older Pages
        // `/api/device-sync` response. The codec fully validates and
        // normalizes the payload before the repository opens its transaction.
        final backup = BackupCodec.decodeCloudSnapshot(remoteSnapshot);
        // replaceBackup validates before the transaction and clears both
        // tables inside it, so this operation cannot leave a half-merged DB.
        await repository.replaceBackup(BackupCodec.encode(backup));
      } on FormatException catch (error) {
        throw CloudSyncException('云端快照格式不兼容：${error.message}');
      }
      await onLocalDataChanged?.call();
      await _markSynced(_nonNegativeInt(remote['revision']));
    } on CloudSyncException catch (error) {
      _markError(error);
      rethrow;
    } catch (error) {
      final failure = CloudSyncException('恢复失败：$error');
      _markError(failure);
      throw failure;
    }
  }

  void _setSyncing() {
    _state = CloudSyncState(
      status: CloudSyncStatus.syncing,
      endpoint: _state.endpoint,
      vaultId: _state.vaultId,
      deviceId: _state.deviceId,
      revision: _state.revision,
      lastSyncedAt: _state.lastSyncedAt,
      hasRecoveryCode: _state.hasRecoveryCode,
    );
    notifyListeners();
  }

  Future<void> _markSynced(int revision) async {
    final syncedAt = DateTime.now().toUtc();
    await _credentials.write(_revisionKey, '$revision');
    await _credentials.write(_lastSyncedAtKey, syncedAt.toIso8601String());
    _state = CloudSyncState(
      status: CloudSyncStatus.synced,
      endpoint: _state.endpoint,
      vaultId: _state.vaultId,
      deviceId: _state.deviceId,
      revision: revision,
      lastSyncedAt: syncedAt,
      hasRecoveryCode: _state.hasRecoveryCode,
    );
    notifyListeners();
  }

  void _markError(CloudSyncException error) {
    _state = CloudSyncState(
      status: CloudSyncStatus.error,
      endpoint: _state.endpoint,
      vaultId: _state.vaultId,
      deviceId: _state.deviceId,
      revision: _state.revision,
      lastSyncedAt: _state.lastSyncedAt,
      message: error.message,
      hasRecoveryCode: _state.hasRecoveryCode,
    );
    notifyListeners();
  }

  Future<String?> recoveryCode() async {
    await initialize();
    return _credentials.read(_recoveryCodeKey);
  }

  Future<void> disconnect() async {
    await initialize();
    for (final key in const [
      _endpointKey,
      _vaultIdKey,
      _deviceIdKey,
      _accessTokenKey,
      _revisionKey,
      _lastSyncedAtKey,
      _recoveryCodeKey,
    ]) {
      await _credentials.delete(key);
    }
    _accessToken = null;
    _resetConnectionState();
  }

  /// Changes only the API entry point while keeping the current device token.
  /// This is useful when the same vault is exposed through a second Cloudflare
  /// Pages/Worker hostname. The endpoint is verified before it is persisted.
  Future<void> changeEndpoint(String endpoint) async {
    await initialize();
    final token = _accessToken;
    final vaultId = _state.vaultId;
    if (token == null || vaultId == null || !_state.isConfigured) {
      throw const CloudSyncException('请先连接云端同步');
    }
    final base = normalizeEndpoint(endpoint);
    if (base == _state.endpoint) return;
    final remote = await _request(
      'GET',
      base,
      '/v1/snapshot',
      accessToken: token,
    );
    final remoteVaultId = _requiredString(remote, 'vaultId');
    if (remoteVaultId != vaultId) {
      throw const CloudSyncException('新地址不是当前资料库，不能直接切换');
    }
    await _credentials.write(_endpointKey, base);
    _state = CloudSyncState(
      status: CloudSyncStatus.ready,
      endpoint: base,
      vaultId: _state.vaultId,
      deviceId: _state.deviceId,
      revision: _state.revision,
      lastSyncedAt: _state.lastSyncedAt,
      hasRecoveryCode: _state.hasRecoveryCode,
    );
    notifyListeners();
  }

  static String normalizeEndpoint(String raw) {
    var value = raw.trim();
    if (value.isEmpty) throw const CloudSyncException('请输入 Worker 地址');
    if (!value.startsWith('http://') && !value.startsWith('https://')) {
      value = 'https://$value';
    }
    final uri = Uri.tryParse(value);
    if (uri == null || uri.host.isEmpty) {
      throw const CloudSyncException('Worker 地址格式不正确');
    }
    final localHttp =
        uri.scheme == 'http' &&
        (uri.host == 'localhost' ||
            uri.host == '127.0.0.1' ||
            uri.host == '10.0.2.2');
    if (uri.scheme != 'https' && !localHttp) {
      throw const CloudSyncException('云端地址必须使用 HTTPS');
    }
    final path = uri.path.replaceFirst(RegExp(r'/+$'), '');
    return uri.replace(path: path, query: null, fragment: null).toString();
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String endpoint,
    String path, {
    String? accessToken,
    Map<String, Object?>? body,
  }) async {
    final uri = Uri.parse('$endpoint$path');
    final headers = <String, String>{'accept': 'application/json'};
    if (body != null) headers['content-type'] = 'application/json';
    if (accessToken != null) headers['authorization'] = 'Bearer $accessToken';
    late final http.Response response;
    try {
      switch (method) {
        case 'GET':
          response = await _client
              .get(uri, headers: headers)
              .timeout(requestTimeout);
        case 'POST':
          response = await _client
              .post(uri, headers: headers, body: jsonEncode(body ?? const {}))
              .timeout(requestTimeout);
        case 'PUT':
          response = await _client
              .put(uri, headers: headers, body: jsonEncode(body ?? const {}))
              .timeout(requestTimeout);
        default:
          throw StateError('Unsupported HTTP method: $method');
      }
    } on CloudSyncException {
      rethrow;
    } on TimeoutException {
      throw const CloudSyncException(
        '连接超时：当前手机网络无法访问该 Worker。请切换 Wi‑Fi/移动网络，或为 Worker 绑定可访问的自定义域名后重试。',
      );
    } catch (error) {
      throw CloudSyncException('无法连接云端：$error');
    }
    dynamic decoded;
    try {
      decoded = response.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(response.body);
    } catch (_) {
      decoded = <String, dynamic>{};
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final map = decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : const <String, dynamic>{};
      throw CloudSyncException(
        map['error'] is String
            ? map['error'] as String
            : '云端请求失败（${response.statusCode}）',
        statusCode: response.statusCode,
        code: map['code'] is String ? map['code'] as String : null,
        currentRevision: _optionalNonNegativeInt(map['currentRevision']),
      );
    }
    if (decoded is! Map) throw const CloudSyncException('云端响应格式无效');
    return Map<String, dynamic>.from(decoded);
  }

  void _setConnecting(String endpoint) {
    _state = CloudSyncState(
      status: CloudSyncStatus.syncing,
      endpoint: endpoint,
    );
    notifyListeners();
  }

  void _resetConnectionState() {
    _state = const CloudSyncState();
    notifyListeners();
  }

  static String _requiredString(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value is! String || value.trim().isEmpty) {
      throw CloudSyncException('云端响应缺少 $key');
    }
    return value.trim();
  }

  static String? _nonEmpty(String? value) =>
      value == null || value.trim().isEmpty ? null : value.trim();

  static int _parseNonNegativeInt(String? value) {
    final parsed = int.tryParse(value ?? '');
    return parsed == null || parsed < 0 ? 0 : parsed;
  }

  static int _nonNegativeInt(Object? value) => value is int && value >= 0
      ? value
      : int.tryParse('$value')?.clamp(0, 1 << 31) ?? 0;

  static int? _optionalNonNegativeInt(Object? value) {
    if (value == null) return null;
    final parsed = int.tryParse('$value');
    return parsed == null || parsed < 0 ? null : parsed;
  }

  /// Returns the stored snapshot, with a compatibility fallback for the
  /// original Pages/device-sync endpoint that returned `{flights, places}`
  /// directly instead of nesting it under `snapshot`.
  static Object? _snapshotFromResponse(Map<String, dynamic> response) {
    final snapshot = response['snapshot'];
    if (snapshot != null) return snapshot;
    if (response['flights'] is List ||
        response['visitedPlaces'] is List ||
        response['places'] is List ||
        response['visited_places'] is List) {
      return response;
    }
    final data = response['data'];
    return data is Map || data is List || data is String ? data : null;
  }

  static String _vaultIdFromRecoveryCode(String code) {
    final parts = code.trim().split('.');
    if (parts.length != 3 || parts[0] != 'ffr1' || parts[1].length != 36) {
      throw const CloudSyncException('恢复码格式不正确');
    }
    return parts[1];
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }
}
