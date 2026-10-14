import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:flight_footprint/core/localization/app_strings.dart';
import 'package:flight_footprint/data/feedback_service.dart';
import 'package:flight_footprint/features/profile/feedback_page.dart';
import 'package:flight_footprint/ui/theme/app_theme.dart';

const _endpoint = 'https://feedback.test/v1/feedback';
const _receipt = {
  'issueNumber': 42,
  'issueUrl': 'https://github.com/yiming-space/flight-footprint/issues/42',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  PackageInfo.setMockInitialValues(
    appName: 'Flight Footprint',
    packageName: 'com.example.flight_footprint',
    version: '1.2.0',
    buildNumber: '15',
    buildSignature: '',
  );

  testWidgets('selects either feedback kind and posts the selected value', (
    tester,
  ) async {
    final kinds = <String>[];
    final client = MockClient((request) async {
      kinds.add(
        (jsonDecode(request.body) as Map<String, dynamic>)['kind'] as String,
      );
      return http.Response(jsonEncode(_receipt), 201);
    });
    await tester.pumpWidget(_app(client: client));

    await _fillValidForm(tester);
    await tester.tap(find.text('提交反馈'));
    await tester.pumpAndSettle();
    expect(kinds, ['bug']);
    expect(find.text('感谢你的反馈'), findsOneWidget);

    final nextClient = MockClient((request) async {
      kinds.add(
        (jsonDecode(request.body) as Map<String, dynamic>)['kind'] as String,
      );
      return http.Response(jsonEncode(_receipt), 201);
    });
    await tester.pumpWidget(_app(client: nextClient));
    await tester.tap(find.text('功能建议'));
    await _fillValidForm(tester);
    await tester.tap(find.text('提交反馈'));
    await tester.pumpAndSettle();
    expect(kinds, ['bug', 'suggestion']);
  });

  testWidgets('invalid fields and missing public consent do not send', (
    tester,
  ) async {
    var requests = 0;
    final client = MockClient((_) async {
      requests++;
      return http.Response(jsonEncode(_receipt), 201);
    });
    await tester.pumpWidget(_app(client: client));

    await _enterFormText(tester);
    await _scrollTo(tester, find.text('提交反馈'));
    await tester.tap(find.text('提交反馈'));
    await tester.pumpAndSettle();
    expect(requests, 0, reason: 'Consent is required before sending.');

    await _scrollTo(tester, find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await _scrollTo(tester, find.byType(TextFormField).first);
    await tester.enterText(find.byType(TextFormField).first, '短');
    await _scrollTo(tester, find.text('提交反馈'));
    await tester.tap(find.text('提交反馈'));
    await tester.pumpAndSettle();
    expect(requests, 0);
    await _scrollTo(tester, find.text('标题请填写 5–120 个字'));
    expect(find.text('标题请填写 5–120 个字'), findsOneWidget);
  });

  testWidgets('environment opt-out sends no device or platform metadata', (
    tester,
  ) async {
    Map<String, dynamic>? submitted;
    final client = MockClient((request) async {
      submitted = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(jsonEncode(_receipt), 201);
    });
    await tester.pumpWidget(_app(client: client));
    await _scrollTo(tester, find.byType(SwitchListTile));
    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    await _fillValidForm(tester);
    await tester.tap(find.text('提交反馈'));
    await tester.pumpAndSettle();

    expect(submitted, isNotNull);
    expect(submitted!.containsKey('environment'), isTrue);
    expect(submitted!['environment'], isEmpty);
    expect(submitted!.keys, isNot(contains('deviceId')));
    expect(submitted!.keys, isNot(contains('systemLogs')));
  });

  testWidgets('shows receipt in place without external navigation', (
    tester,
  ) async {
    final client = MockClient(
      (_) async => http.Response(jsonEncode(_receipt), 201),
    );
    await tester.pumpWidget(_app(client: client));
    await _fillValidForm(tester);
    await tester.tap(find.text('提交反馈'));
    await tester.pumpAndSettle();

    expect(find.text('感谢你的反馈'), findsOneWidget);
    expect(find.text('已同步到 GitHub · #42'), findsOneWidget);
    expect(find.byType(FeedbackPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'preserves text and reuses request UUID after a failed submission',
    (tester) async {
      final ids = <String>[];
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        ids.add(
          (jsonDecode(request.body) as Map<String, dynamic>)['requestId']
              as String,
        );
        return calls == 1
            ? http.Response('{}', 503)
            : http.Response(jsonEncode(_receipt), 201);
      });
      await tester.pumpWidget(_app(client: client));
      await _fillValidForm(tester);
      await tester.tap(find.text('提交反馈'));
      await tester.pumpAndSettle();

      expect(find.text('暂时无法连接，请稍后重试。内容已保留。'), findsOneWidget);
      expect(
        (tester.widgetList<TextFormField>(find.byType(TextFormField)).first)
            .controller!
            .text,
        '地图标题重叠',
      );
      await tester.tap(find.text('提交反馈'));
      await tester.pumpAndSettle();
      expect(ids, hasLength(2));
      expect(ids.first, isNotEmpty);
      expect(ids[1], ids.first);
      expect(find.text('感谢你的反馈'), findsOneWidget);
    },
  );

  testWidgets('ignores a second submit while the first request is pending', (
    tester,
  ) async {
    final response = Completer<http.Response>();
    var requests = 0;
    final client = MockClient((_) {
      requests++;
      return response.future;
    });
    await tester.pumpWidget(_app(client: client));
    await _fillValidForm(tester);

    await tester.tap(find.text('提交反馈'));
    await tester.pump();
    expect(find.text('正在提交…'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton).first).onPressed,
      isNull,
    );
    expect(requests, 1);

    response.complete(http.Response(jsonEncode(_receipt), 201));
    await tester.pumpAndSettle();
    expect(find.text('感谢你的反馈'), findsOneWidget);
    expect(requests, 1);
  });

  testWidgets('fits narrow screens with keyboard insets in both themes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);

    for (final theme in [AppTheme.light(), AppTheme.dark()]) {
      await tester.pumpWidget(
        _app(
          client: MockClient((_) async => http.Response('', 500)),
          theme: theme,
        ),
      );
      await tester.tap(find.byType(TextFormField).first);
      await tester.pump();
      await tester.enterText(find.byType(TextFormField).first, '窄屏表单标题');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });
}

Widget _app({required http.Client client, ThemeData? theme}) => MaterialApp(
  theme: theme ?? AppTheme.dark(),
  locale: const Locale('zh'),
  supportedLocales: AppStrings.supportedLocales,
  localizationsDelegates: const [
    AppStringsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: FeedbackPage(
    key: UniqueKey(),
    service: FeedbackService(client: client, endpoint: Uri.parse(_endpoint)),
  ),
);

Future<void> _enterFormText(WidgetTester tester) async {
  final fields = find.byType(TextFormField);
  await tester.enterText(fields.at(0), '地图标题重叠');
  await tester.enterText(fields.at(1), '放大地图后，机场名称会互相遮挡。');
}

Future<void> _fillValidForm(WidgetTester tester) async {
  await _enterFormText(tester);
  await _scrollTo(tester, find.byType(CheckboxListTile));
  if (tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value !=
      true) {
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
  }
  expect(
    tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
    isTrue,
  );
  await _scrollTo(tester, find.text('提交反馈'));
}

Future<void> _scrollTo(WidgetTester tester, Finder target) async {
  final scrollable = find.byType(Scrollable).first;
  await tester.scrollUntilVisible(target, 200, scrollable: scrollable);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  for (var attempt = 0; attempt < 4; attempt++) {
    final targetRect = tester.getRect(target);
    final viewportRect = tester.getRect(scrollable);
    if (targetRect.top >= viewportRect.top &&
        targetRect.bottom <= viewportRect.bottom) {
      break;
    }
    final delta = targetRect.bottom > viewportRect.bottom ? -120.0 : 120.0;
    await tester.drag(scrollable, Offset(0, delta));
    await tester.pumpAndSettle();
  }
}
