import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../app/app_links.dart';

enum FeedbackKind { bug, suggestion }

class FeedbackSubmission {
  const FeedbackSubmission({
    required this.title,
    required this.description,
    required this.kind,
    this.environment,
  });

  final String title;
  final String description;
  final FeedbackKind kind;
  final String? environment;
}

class FeedbackReceipt {
  const FeedbackReceipt({required this.issueNumber, required this.issueUrl});

  final int issueNumber;
  final Uri issueUrl;
}

enum FeedbackErrorCode {
  invalidInput,
  notConfigured,
  validation,
  pending,
  rateLimited,
  unavailable,
  failed,
}

class FeedbackException implements Exception {
  const FeedbackException(this.code);

  final FeedbackErrorCode code;

  @override
  String toString() => 'FeedbackException($code)';
}

/// Submits anonymous feedback through the project's HTTPS relay. No GitHub
/// credentials are stored in or sent by the app.
class FeedbackService {
  FeedbackService({http.Client? client, Uri? endpoint})
    : _client = client ?? http.Client(),
      _ownsClient = client == null,
      endpoint =
          endpoint ??
          (_configuredEndpoint.isEmpty
              ? null
              : Uri.tryParse(_configuredEndpoint));

  static const _configuredEndpoint = String.fromEnvironment(
    'FLIGHT_FOOTPRINT_FEEDBACK_URL',
  );
  final http.Client _client;
  final bool _ownsClient;
  final Uri? endpoint;

  bool get isConfigured => _isValidEndpoint(endpoint);

  void dispose() {
    if (_ownsClient) _client.close();
  }

  Future<FeedbackReceipt> submit(
    FeedbackSubmission submission, {
    required String requestId,
  }) async {
    _validateSubmission(submission);
    if (!_isUuid(requestId)) {
      throw const FeedbackException(FeedbackErrorCode.invalidInput);
    }
    final target = endpoint;
    if (!_isValidEndpoint(target)) {
      throw const FeedbackException(FeedbackErrorCode.notConfigured);
    }

    final body = <String, Object?>{
      'kind': submission.kind.name,
      'title': submission.title.trim(),
      'description': submission.description.trim(),
      'environment': submission.environment?.trim() ?? '',
      'requestId': requestId,
    };
    try {
      final response = await _client
          .post(
            target!,
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode == 400) {
        throw const FeedbackException(FeedbackErrorCode.validation);
      }
      if (response.statusCode == 429) {
        throw const FeedbackException(FeedbackErrorCode.rateLimited);
      }
      if (response.statusCode == 409) {
        throw const FeedbackException(FeedbackErrorCode.pending);
      }
      if (response.statusCode == 503) {
        throw const FeedbackException(FeedbackErrorCode.unavailable);
      }
      if (response.statusCode != 201) {
        throw const FeedbackException(FeedbackErrorCode.failed);
      }
      return _decodeReceipt(response.body);
    } on FeedbackException {
      rethrow;
    } on TimeoutException {
      throw const FeedbackException(FeedbackErrorCode.unavailable);
    } on http.ClientException {
      throw const FeedbackException(FeedbackErrorCode.unavailable);
    } catch (_) {
      throw const FeedbackException(FeedbackErrorCode.failed);
    }
  }

  static void _validateSubmission(FeedbackSubmission submission) {
    final title = submission.title.trim();
    final description = submission.description.trim();
    final environment = submission.environment?.trim() ?? '';
    if (title.length < 5 ||
        title.length > 120 ||
        description.length < 10 ||
        description.length > 5000 ||
        environment.length > 500) {
      throw const FeedbackException(FeedbackErrorCode.invalidInput);
    }
  }

  static bool _isValidEndpoint(Uri? uri) =>
      uri != null &&
      uri.scheme == 'https' &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty &&
      !uri.hasQuery &&
      !uri.hasFragment;

  static bool _isUuid(String value) => RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  ).hasMatch(value);

  static FeedbackReceipt _decodeReceipt(String body) {
    try {
      final value = jsonDecode(body);
      if (value is! Map<String, dynamic>) {
        throw const FeedbackException(FeedbackErrorCode.failed);
      }
      final number = value['issueNumber'];
      final url = value['issueUrl'];
      if (number is! int || number < 1 || url is! String) {
        throw const FeedbackException(FeedbackErrorCode.failed);
      }
      final uri = Uri.tryParse(url);
      final repository = AppLinks.githubRepositoryParts;
      if (uri == null ||
          repository == null ||
          uri.scheme != 'https' ||
          uri.host != 'github.com' ||
          uri.userInfo.isNotEmpty ||
          uri.hasQuery ||
          uri.hasFragment ||
          uri.pathSegments.length != 4 ||
          uri.pathSegments[0] != repository.owner ||
          uri.pathSegments[1] != repository.repository ||
          uri.pathSegments[2] != 'issues' ||
          uri.pathSegments[3] != '$number') {
        throw const FeedbackException(FeedbackErrorCode.failed);
      }
      return FeedbackReceipt(issueNumber: number, issueUrl: uri);
    } on FeedbackException {
      rethrow;
    } catch (_) {
      throw const FeedbackException(FeedbackErrorCode.failed);
    }
  }
}
