import 'dart:async';

import 'package:flight_footprint/app/app_controller.dart';
import 'package:flight_footprint/core/localization/app_strings.dart';
import 'package:flight_footprint/data/calendar_import_service.dart';
import 'package:flight_footprint/data/flight_repository.dart';
import 'package:flight_footprint/domain/airport.dart';
import 'package:flight_footprint/domain/flight.dart';
import 'package:flight_footprint/features/add_flight/flight_entry_sheet.dart';
import 'package:flight_footprint/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class _Controller extends ChangeNotifier implements AppController {
  CalendarImportResult result = const CalendarImportResult(
    status: CalendarScanStatus.available,
    eventsRead: 0,
    flights: [],
  );
  Completer<CalendarImportResult>? pendingScan;
  Completer<FlightImportSummary>? pendingImport;
  bool failImport = false;
  int scans = 0;
  int previews = 0;
  int writes = 0;

  @override
  Future<CalendarImportResult> scanCalendarFlights({
    DateTime? start,
    DateTime? end,
  }) async {
    scans++;
    return pendingScan?.future ?? result;
  }

  @override
  Future<FlightImportPreview> previewCalendarFlights(
    Iterable<CalendarFlightDraft> drafts,
  ) async {
    previews++;
    return FlightImportPreview(
      summary: const FlightImportSummary(added: 1),
      addedFlights: drafts.map((draft) => draft.toFlight()).toList(),
      conflictingFlights: const [],
      unchangedFlights: const [],
    );
  }

  @override
  Future<FlightImportSummary> importCalendarFlights(
    Iterable<CalendarFlightDraft> drafts, {
    bool overwriteExisting = false,
    void Function(int completed, int total)? onProgress,
  }) async {
    writes++;
    if (failImport) throw StateError('test import failed');
    return pendingImport?.future ?? const FlightImportSummary(added: 1);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

CalendarImportResult _oneFlight() => CalendarImportResult(
  status: CalendarScanStatus.available,
  eventsRead: 1,
  flights: [
    CalendarFlightDraft(
      eventId: 'event-1',
      title: 'CA123 PEK to SHA',
      departureText: 'PEK',
      arrivalText: 'SHA',
      departureAirport: const Airport(
        iataCode: 'PEK',
        longitude: 116,
        latitude: 40,
        name: 'Capital',
        city: 'Beijing',
        countryCode: 'CN',
      ),
      arrivalAirport: const Airport(
        iataCode: 'SHA',
        longitude: 121,
        latitude: 31,
        name: 'Hongqiao',
        city: 'Shanghai',
        countryCode: 'CN',
      ),
      airline: 'Air China',
      flightNumber: 'CA123',
      departedAt: DateTime.utc(2025, 1, 1, 8),
      arrivedAt: DateTime.utc(2025, 1, 1, 10),
      status: FlightStatus.completed,
      distanceKm: 1000,
      durationMinutes: 120,
    ),
  ],
);

Future<void> _open(
  WidgetTester tester,
  _Controller controller, {
  ValueChanged<FlightEntryResult?>? onResult,
  Locale locale = const Locale('zh'),
  Size size = const Size(430, 950),
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
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
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              final result = await showModalBottomSheet<FlightEntryResult>(
                context: context,
                isScrollControlled: true,
                builder: (_) => FlightEntrySheet(controller: controller),
              );
              onResult?.call(result);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> _scan(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('flight-entry-calendar')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets(
    'entry choices remain reachable in English at 320px with 2x text',
    (tester) async {
      final controller = _Controller();
      await _open(
        tester,
        controller,
        locale: const Locale('en'),
        size: const Size(320, 900),
        textScale: 2,
      );
      for (final method in FlightEntryMethod.values) {
        final option = find.byKey(ValueKey('flight-entry-${method.name}'));
        await tester.ensureVisible(option);
        await tester.pump();
        expect(option, findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('entry offers all three methods and returns manual choice', (
    tester,
  ) async {
    final controller = _Controller();
    FlightEntryResult? result;
    await _open(tester, controller, onResult: (value) => result = value);
    for (final method in FlightEntryMethod.values) {
      expect(
        find.byKey(ValueKey('flight-entry-${method.name}')),
        findsOneWidget,
      );
    }
    await tester.tap(find.byKey(const ValueKey('flight-entry-manual')));
    await tester.pumpAndSettle();
    expect(result, FlightEntryResult.manual);
    expect(controller.scans, 0);
    expect(controller.writes, 0);
  });

  for (final example in [
    (CalendarScanStatus.permissionDenied, '需要日历读取权限才能导入航班日程'),
    (CalendarScanStatus.available, '没有找到可识别的航班日程'),
  ]) {
    testWidgets('calendar ${example.$1} keeps entry open without writes', (
      tester,
    ) async {
      final controller = _Controller()
        ..result = CalendarImportResult(
          status: example.$1,
          eventsRead: 0,
          flights: const [],
        );
      await _open(tester, controller);
      await _scan(tester);
      expect(find.text(example.$2), findsWidgets);
      expect(find.byType(FlightEntrySheet), findsOneWidget);
      expect(controller.writes, 0);
      expect(controller.previews, 0);
      expect(
        tester
            .widget<ListTile>(
              find.byKey(const ValueKey('flight-entry-calendar')),
            )
            .onTap,
        isNotNull,
      );
    });
  }

  testWidgets(
    'canceling calendar preview never writes and allows manual entry',
    (tester) async {
      final controller = _Controller()..result = _oneFlight();
      await _open(tester, controller);
      await _scan(tester);
      expect(find.text('日历航程预览'), findsOneWidget);
      expect(controller.writes, 0);
      await tester.tap(find.byTooltip('取消'));
      await tester.pumpAndSettle();
      expect(controller.previews, 0);
      expect(controller.writes, 0);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('flight-entry-manual')),
            )
            .onPressed,
        isNotNull,
      );
    },
  );

  testWidgets('pending scan blocks duplicate submissions until completion', (
    tester,
  ) async {
    final controller = _Controller()
      ..pendingScan = Completer<CalendarImportResult>();
    await _open(tester, controller);
    final calendar = find.byKey(const ValueKey('flight-entry-calendar'));
    // Two callbacks before a rebuild exercise the guard as well as disabled UI.
    final callback = tester.widget<ListTile>(calendar).onTap!;
    callback();
    callback();
    await tester.pump();
    expect(controller.scans, 1);
    expect(tester.widget<ListTile>(calendar).onTap, isNull);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('flight-entry-manual')),
          )
          .onPressed,
      isNull,
    );
    controller.pendingScan!.complete(controller.result);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(tester.widget<ListTile>(calendar).onTap, isNotNull);
    expect(controller.writes, 0);
  });

  testWidgets('confirmed calendar import completes once and returns imported', (
    tester,
  ) async {
    final controller = _Controller()
      ..result = _oneFlight()
      ..pendingImport = Completer<FlightImportSummary>();
    FlightEntryResult? result;
    await _open(tester, controller, onResult: (value) => result = value);
    await _scan(tester);
    await tester.tap(find.text('导入选中的航程'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(controller.writes, 1);
    expect(result, isNull);
    expect(
      tester
          .widget<ListTile>(find.byKey(const ValueKey('flight-entry-calendar')))
          .onTap,
      isNull,
    );
    controller.pendingImport!.complete(const FlightImportSummary(added: 1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('日历航程导入完成'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '关闭'));
    await tester.pumpAndSettle();
    expect(result, FlightEntryResult.imported);
    expect(controller.writes, 1);
    expect(controller.previews, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed confirmed import can be retried successfully', (
    tester,
  ) async {
    final controller = _Controller()
      ..result = _oneFlight()
      ..failImport = true;
    await _open(tester, controller);
    await _scan(tester);
    await tester.tap(find.text('导入选中的航程'));
    await tester.pumpAndSettle();
    expect(find.textContaining('test import failed'), findsWidgets);
    expect(find.byType(FlightEntrySheet), findsOneWidget);
    controller.failImport = false;
    await _scan(tester);
    await tester.tap(find.text('导入选中的航程'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('日历航程导入完成'), findsOneWidget);
    expect(controller.writes, 2);
    await tester.tap(find.widgetWithText(FilledButton, '关闭'));
    await tester.pumpAndSettle();
    expect(find.byType(FlightEntrySheet), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
