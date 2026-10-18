import 'dart:async';

import 'package:flight_footprint/app/app_controller.dart';
import 'package:flight_footprint/core/localization/app_strings.dart';
import 'package:flight_footprint/data/flight_draft_store.dart';
import 'package:flight_footprint/data/flight_enrichment_service.dart';
import 'package:flight_footprint/domain/airport.dart';
import 'package:flight_footprint/features/add_flight/add_flight_page.dart';
import 'package:flight_footprint/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class _LookupController extends ChangeNotifier implements AppController {
  final response = Completer<FlightEnrichment?>();
  int calls = 0;
  String? requestedNumber;
  DateTime? requestedDate;

  @override
  Future<FlightEnrichment?> lookupFlight({
    required String airline,
    required String flightNumber,
    DateTime? flightDate,
    String? departureIata,
    String? arrivalIata,
  }) {
    calls++;
    requestedNumber = flightNumber;
    requestedDate = flightDate;
    return response.future;
  }

  @override
  Airport? airportFor(String iata) => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _host(
  _LookupController controller, {
  Locale locale = const Locale('zh'),
  double textScale = 1,
}) => MaterialApp(
  theme: AppTheme.dark(),
  locale: locale,
  supportedLocales: AppStrings.supportedLocales,
  localizationsDelegates: const [
    AppStringsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context)
        .copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: AddFlightPage(
    controller: controller,
    draftStore: FlightDraftStore(
      getMeta: (_) async => null,
      setMeta: (_, _) async {},
    ),
  ),
);

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

Future<void> _open(
  WidgetTester tester,
  _LookupController controller, {
  Locale locale = const Locale('zh'),
  double textScale = 1,
  Size size = const Size(700, 1600),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    _host(controller, locale: locale, textScale: textScale),
  );
  await tester.pumpAndSettle();
}

Future<void> _query(
  WidgetTester tester, {
  String identityLabel = '航空公司 + 航班号 *',
  String buttonLabel = '自动补全航班信息',
}) async {
  final identity = _field(identityLabel);
  await tester.ensureVisible(identity);
  await tester.enterText(identity, 'CA123');
  await tester.ensureVisible(find.text(buttonLabel));
  await tester.tap(find.text(buttonLabel));
  // Do not settle the outstanding query's spinner.
  await tester.pump();
}

FlightEnrichment _live() => FlightEnrichment(
  aircraftType: 'B737 MAX 8',
  registration: 'B-1234',
  aircraftSource: 'ADSB.lol',
  aircraftObservedAt: DateTime.now(),
  aircraftLookupAttempted: true,
  source: 'ADSBdb',
);

Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('live aircraft fills empty model and opens optional fields', (
    tester,
  ) async {
    final controller = _LookupController();
    await _open(tester, controller);
    expect(_field('飞机机型'), findsNothing);
    await _query(tester);
    expect(controller.calls, 1);
    expect(controller.requestedNumber, 'CA123');
    expect(controller.requestedDate, isNotNull);
    controller.response.complete(_live());
    await tester.pumpAndSettle();

    expect(_field('飞机机型'), findsOneWidget);
    expect(
      tester.widget<TextField>(_field('飞机机型')).controller!.text,
      'B737 MAX 8',
    );
    expect(find.textContaining('机型来自实时观测：ADSB.lol'), findsOneWidget);
    expect(find.textContaining('B-1234'), findsOneWidget);
    expect(find.textContaining('观测于'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _close(tester);
  });

  for (final example in [
    (AircraftLookupStatus.unavailable, '实时机型来源暂不可用'),
    (AircraftLookupStatus.rateLimited, '实时机型来源暂时限流'),
    (AircraftLookupStatus.ambiguous, '飞机记录存在多个匹配或冲突'),
    (AircraftLookupStatus.stale, '观测记录已过期或时间异常'),
    (AircraftLookupStatus.routeConflict, '查询航线与所选机场不一致'),
    (AircraftLookupStatus.typeUnavailable, '已找到飞机，但暂无可靠机型'),
  ]) {
    testWidgets(
      'lookup explains ${example.$1} and leaves manual entry available',
      (tester) async {
        final controller = _LookupController();
        await _open(tester, controller);
        await _query(tester);
        controller.response.complete(
          FlightEnrichment(
            source: 'ADSB.lol',
            aircraftLookupAttempted: true,
            aircraftLookupStatus: example.$1,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining(example.$2), findsOneWidget);
        expect(find.textContaining('暂未匹配到实时机型'), findsNothing);
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, '自动补全航班信息'),
              )
              .onPressed,
          isNotNull,
        );
        expect(_field('飞机机型'), findsNothing);
        expect(tester.takeException(), isNull);
        await _close(tester);
      },
    );
  }

  testWidgets(
    'live lookup never overwrites an existing manually entered model',
    (tester) async {
      final controller = _LookupController();
      await _open(tester, controller);
      await tester.ensureVisible(find.text('更多信息'));
      await tester.tap(find.text('更多信息'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(_field('飞机机型'));
      await tester.enterText(_field('飞机机型'), 'A321NEO');
      await _query(tester);
      controller.response.complete(_live());
      await tester.pumpAndSettle();

      expect(
        tester.widget<TextField>(_field('飞机机型')).controller!.text,
        'A321NEO',
      );
      expect(find.text('没有可补全的新信息，已填写内容保持不变'), findsOneWidget);
      expect(find.textContaining('机型来自实时观测'), findsNothing);
      await _close(tester);
    },
  );

  testWidgets(
    'changing flight number while awaiting lookup rejects stale data',
    (tester) async {
      final controller = _LookupController();
      await _open(tester, controller);
      await _query(tester);
      await tester.enterText(_field('航空公司 + 航班号 *'), 'CA456');
      controller.response.complete(_live());
      await tester.pumpAndSettle();

      expect(find.text('航班信息已变更，请重新查询；未填入旧结果'), findsOneWidget);
      expect(_field('飞机机型'), findsNothing);
      expect(find.text('B737 MAX 8'), findsNothing);
      expect(controller.calls, 1);
      await _close(tester);
    },
  );

  testWidgets(
    'button and keyboard submissions cannot duplicate a pending lookup',
    (tester) async {
      final controller = _LookupController();
      await _open(tester, controller);
      await _query(tester);
      final pendingButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '正在查询航班…'),
      );
      expect(pendingButton.onPressed, isNull);
      await tester.tap(find.text('正在查询航班…'));
      final identity = tester.widget<TextField>(_field('航空公司 + 航班号 *'));
      identity.onSubmitted!('CA123');
      identity.onSubmitted!('CA123');
      await tester.pump();
      expect(controller.calls, 1);

      controller.response.complete(_live());
      await tester.pumpAndSettle();
      expect(controller.calls, 1);
      await _close(tester);
    },
  );

  testWidgets(
    'successful route lookup without live model explains manual entry',
    (tester) async {
      final controller = _LookupController();
      await _open(tester, controller);
      await _query(tester);
      controller.response.complete(
        const FlightEnrichment(
          departureIata: 'PEK',
          arrivalIata: 'SHA',
          distanceKm: 1000,
          aircraftLookupAttempted: true,
          source: 'ADSBdb',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('已从航班数据源补全可用信息'), findsOneWidget);
      expect(find.textContaining('暂未匹配到实时机型，可继续手动填写'), findsOneWidget);
      expect(
        tester.widget<TextField>(_field('飞机机型')).controller!.text,
        isEmpty,
      );
      expect(
        tester.widget<TextField>(_field('里程（公里）')).controller!.text,
        '1000',
      );
      await _close(tester);
    },
  );

  testWidgets(
    'disabled live lookup explains manual entry without claiming an attempt',
    (tester) async {
      final controller = _LookupController();
      await _open(tester, controller);
      await _query(tester);
      controller.response.complete(
        const FlightEnrichment(
          departureIata: 'PEK',
          arrivalIata: 'SHA',
          source: 'ADSBdb',
          distanceKm: 1000,
          aircraftLookupAttempted: false,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('飞机机型可在更多信息中手动填写'), findsOneWidget);
      expect(find.textContaining('暂未匹配到实时机型'), findsNothing);
      expect(
        tester.widget<TextField>(_field('飞机机型')).controller!.text,
        isEmpty,
      );
      await _close(tester);
    },
  );

  testWidgets('English lookup feedback itself wraps at 390px with 2x text', (
    tester,
  ) async {
    final controller = _LookupController();
    const strings = AppStrings(Locale('en'));
    await _open(tester, controller, locale: const Locale('en'));
    await _query(
      tester,
      identityLabel: '${strings.t('airlineFlight')} *',
      buttonLabel: strings.t('autoFillFlight'),
    );
    controller.response.complete(_live());
    await tester.pumpAndSettle();
    final feedbackFinder = find.textContaining('ADSB.lol');
    expect(feedbackFinder, findsOneWidget);
    expect(find.textContaining('B-1234'), findsOneWidget);
    expect(tester.takeException(), isNull);
    final feedback = tester.widget<Text>(feedbackFinder);
    // Exercise the actual new feedback content and style independently of the
    // page's existing fixed-height date/time controls at large text sizes.
    tester.view.physicalSize = const Size(390, 1200);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(feedback.data!, style: feedback.style),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(feedback.data!), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _close(tester);
  });
}
