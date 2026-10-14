import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:flight_footprint/data/feedback_service.dart';

class _FakeClient extends http.BaseClient {
  _FakeClient(this.handler);

  final FutureOr<http.Response> Function(http.BaseRequest request) handler;
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await handler(request);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }

  @override
  void close() => closed = true;
}

const _endpoint = 'https://feedback.example.test/v1/feedback';
const _requestId = '123e4567-e89b-42d3-a456-426614174000';
const _submission = FeedbackSubmission(
  title: 'Map labels overlap',
  description: 'The airport labels overlap when zoomed in.',
  kind: FeedbackKind.bug,
  environment: 'iOS 19, app 1.2.0',
);

http.Response _success([
  String issueUrl =
      'https://github.com/yiming-space/flight-footprint/issues/42',
]) => http.Response(jsonEncode({'issueNumber': 42, 'issueUrl': issueUrl}), 201);

void main() {
  test('posts anonymous fields and returns a verified issue receipt', () async {
    final client = _FakeClient((request) {
      expect(request.method, 'POST');
      expect(request.url, Uri.parse(_endpoint));
      expect(request.headers['authorization'], isNull);
      expect(request.headers['cookie'], isNull);
      final body =
          jsonDecode((request as http.Request).body) as Map<String, dynamic>;
      expect(body, {
        'kind': 'bug',
        'title': _submission.title,
        'description': _submission.description,
        'environment': _submission.environment,
        'requestId': _requestId,
      });
      return _success();
    });
    final service = FeedbackService(
      client: client,
      endpoint: Uri.parse(_endpoint),
    );

    expect(service.isConfigured, isTrue);
    final receipt = await service.submit(_submission, requestId: _requestId);

    expect(receipt.issueNumber, 42);
    expect(receipt.issueUrl.path, '/yiming-space/flight-footprint/issues/42');
    service.dispose();
    expect(
      client.closed,
      isFalse,
      reason: 'Injected clients remain caller-owned.',
    );
  });

  test('rejects an unconfigured or unsafe endpoint before sending', () async {
    final client = _FakeClient((_) => fail('must not make a request'));
    for (final uri in <Uri?>[
      null,
      Uri.parse('http://feedback.example.test'),
      Uri.parse('https://user:pass@feedback.example.test'),
      Uri.parse('https://feedback.example.test/path?token=x'),
      Uri.parse('https://feedback.example.test/path#fragment'),
    ]) {
      final service = FeedbackService(client: client, endpoint: uri);
      await expectLater(
        service.submit(_submission, requestId: _requestId),
        throwsA(
          isA<FeedbackException>().having(
            (e) => e.code,
            'code',
            FeedbackErrorCode.notConfigured,
          ),
        ),
      );
    }
  });

  test('validates all submitted field lengths before sending', () async {
    final client = _FakeClient((_) => fail('must not make a request'));
    final service = FeedbackService(
      client: client,
      endpoint: Uri.parse(_endpoint),
    );
    final invalid = [
      _submission.copyWithForTest(title: 'tiny'),
      _submission.copyWithForTest(title: List.filled(121, 'x').join()),
      _submission.copyWithForTest(description: 'short'),
      _submission.copyWithForTest(description: List.filled(5001, 'x').join()),
      _submission.copyWithForTest(environment: List.filled(501, 'x').join()),
    ];
    for (final submission in invalid) {
      await expectLater(
        service.submit(submission, requestId: _requestId),
        throwsA(
          isA<FeedbackException>().having(
            (e) => e.code,
            'code',
            FeedbackErrorCode.invalidInput,
          ),
        ),
      );
    }
    await expectLater(
      service.submit(_submission, requestId: 'not-a-uuid'),
      throwsA(isA<FeedbackException>()),
    );
  });

  test('maps relay statuses to safe error codes', () async {
    for (final entry in <(int, FeedbackErrorCode)>[
      (400, FeedbackErrorCode.validation),
      (409, FeedbackErrorCode.pending),
      (429, FeedbackErrorCode.rateLimited),
      (503, FeedbackErrorCode.unavailable),
      (500, FeedbackErrorCode.failed),
    ]) {
      final service = FeedbackService(
        client: _FakeClient(
          (_) => http.Response('private response body', entry.$1),
        ),
        endpoint: Uri.parse(_endpoint),
      );
      await expectLater(
        service.submit(_submission, requestId: _requestId),
        throwsA(
          isA<FeedbackException>().having((e) => e.code, 'code', entry.$2),
        ),
      );
    }
  });

  test('rejects malformed and untrusted receipts', () async {
    for (final response in <http.Response>[
      http.Response('{', 201),
      http.Response('{}', 201),
      _success('https://evil.example/yiming-space/flight-footprint/issues/42'),
      _success('https://github.com/other/repo/issues/42'),
      _success('https://github.com/yiming-space/flight-footprint/issues/43'),
      _success(
        'https://github.com/yiming-space/flight-footprint/issues/42?x=1',
      ),
    ]) {
      final service = FeedbackService(
        client: _FakeClient((_) => response),
        endpoint: Uri.parse(_endpoint),
      );
      await expectLater(
        service.submit(_submission, requestId: _requestId),
        throwsA(
          isA<FeedbackException>().having(
            (e) => e.code,
            'code',
            FeedbackErrorCode.failed,
          ),
        ),
      );
    }
  });

  test(
    'maps timeouts to unavailable without exposing response or exception text',
    () async {
      final service = FeedbackService(
        client: _FakeClient((_) => Completer<http.Response>().future),
        endpoint: Uri.parse(_endpoint),
      );
      await expectLater(
        service.submit(_submission, requestId: _requestId),
        throwsA(
          isA<FeedbackException>().having(
            (e) => e.code,
            'code',
            FeedbackErrorCode.unavailable,
          ),
        ),
      );
    },
  );
}

extension on FeedbackSubmission {
  FeedbackSubmission copyWithForTest({
    String? title,
    String? description,
    String? environment,
  }) => FeedbackSubmission(
    title: title ?? this.title,
    description: description ?? this.description,
    kind: kind,
    environment: environment ?? this.environment,
  );
}
