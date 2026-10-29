import 'package:flight_footprint/app/app_controller.dart';
import 'package:flight_footprint/data/airport_catalog.dart';
import 'package:flight_footprint/domain/airport.dart';
import 'package:flight_footprint/domain/flight.dart';
import 'package:flight_footprint/domain/transfer_decision.dart';
import 'package:flight_footprint/domain/visited_place.dart';
import 'package:flight_footprint/features/flights/suspected_transit_panel.dart';
import 'package:flight_footprint/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

final _base = DateTime.utc(2026, 1, 1);
Flight _flight(
  String id,
  String from,
  String to,
  int dep,
  int arr, {
  bool transit = false,
}) => Flight(
  id: id,
  departureIata: from,
  arrivalIata: to,
  departedAt: _base.add(Duration(hours: dep)),
  arrivedAt: _base.add(Duration(hours: arr)),
  createdAt: _base,
  updatedAt: _base,
  isTransitArrival: transit,
);

class _Controller extends ChangeNotifier implements AppController {
  _Controller(this.flights, {Map<String, Airport> airportData = const {}})
    : airports = AirportCatalog(airportData);
  @override
  List<Flight> flights;
  @override
  List<VisitedPlace> visitedPlaces = [];
  @override
  final AirportCatalog airports;
  @override
  List<TransferDecision> transferDecisions = [];
  @override
  bool countTransitArrivals = true;

  @override
  TransferDecision? transferDecisionFor(Flight inbound, Flight outbound) {
    for (final decision in transferDecisions) {
      if (decision.matchesFlights(inbound, outbound)) return decision;
    }
    return null;
  }

  @override
  Future<void> decideTransfer(
    Flight inbound,
    Flight outbound,
    TransferDecisionStatus status,
  ) async {
    final decision = TransferDecision.fromFlights(
      inbound: inbound,
      outbound: outbound,
      status: status,
      decidedAt: _base,
    );
    transferDecisions = [
      ...transferDecisions.where((item) => item.id != decision.id),
      decision,
    ];
    notifyListeners();
  }

  @override
  Airport? airportFor(String iata) => airports.findByIata(iata);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _host(_Controller controller) => MaterialApp(
  theme: AppTheme.dark(),
  locale: const Locale('zh'),
  supportedLocales: const [Locale('zh'), Locale('en')],
  localizationsDelegates: const [
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: Scaffold(
    body: ListView(children: [SuspectedTransitPanel(controller: controller)]),
  ),
);

void main() {
  testWidgets(
    'each connection requires a decision and a saved choice can change',
    (tester) async {
      final controller = _Controller([
        _flight('in', 'AAA', 'BBB', 0, 2),
        _flight('out', 'BBB', 'CCC', 3, 5),
      ]);
      addTearDown(controller.dispose);
      await tester.pumpWidget(_host(controller));
      await tester.pumpAndSettle();

      expect(find.text('待核对'), findsOneWidget);
      await tester.tap(find.text('确认中转'));
      await tester.pumpAndSettle();
      expect(
        controller
            .transferDecisionFor(controller.flights[0], controller.flights[1])
            ?.status,
        TransferDecisionStatus.confirmed,
      );
      expect(find.text('中转记录 · 1 个已处理'), findsOneWidget);
      expect(find.text('已确认 / 已拒绝 · 1 条'), findsOneWidget);
      expect(find.text('已确认 · 可更改'), findsNothing);
      await tester.tap(find.text('已确认 / 已拒绝 · 1 条'));
      await tester.pumpAndSettle();
      expect(find.text('已确认 · 可更改'), findsOneWidget);

      await tester.tap(find.text('不是中转'));
      await tester.pumpAndSettle();
      expect(
        controller
            .transferDecisionFor(controller.flights[0], controller.flights[1])
            ?.status,
        TransferDecisionStatus.rejected,
      );
      expect(find.text('已拒绝 · 可更改'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reviewed-only candidates stay collapsed but remain editable', (
    tester,
  ) async {
    final inbound = _flight('in', 'AAA', 'BBB', 0, 2);
    final outbound = _flight('out', 'BBB', 'CCC', 3, 5);
    final controller = _Controller([inbound, outbound]);
    controller.transferDecisions = [
      TransferDecision.fromFlights(
        inbound: inbound,
        outbound: outbound,
        status: TransferDecisionStatus.confirmed,
        decidedAt: _base,
      ),
    ];
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(controller));
    await tester.pumpAndSettle();

    expect(find.text('中转记录 · 1 个已处理'), findsOneWidget);
    expect(find.text('已确认 / 已拒绝 · 1 条'), findsNothing);
    expect(find.text('确认中转'), findsNothing);
    await tester.tap(find.text('中转记录 · 1 个已处理'));
    await tester.pumpAndSettle();
    expect(find.text('已确认 / 已拒绝 · 1 条'), findsOneWidget);
    expect(find.text('已确认 · 可更改'), findsNothing);
    await tester.tap(find.text('已确认 / 已拒绝 · 1 条'));
    await tester.pumpAndSettle();
    expect(find.text('已确认 · 可更改'), findsOneWidget);
    expect(find.text('不是中转'), findsOneWidget);
  });

  testWidgets('ambiguous options and legacy manual marks stay explicit', (
    tester,
  ) async {
    final controller = _Controller([
      _flight('in', 'AAA', 'BBB', 0, 2, transit: true),
      _flight('out1', 'BBB', 'CCC', 3, 5),
      _flight('out2', 'BBB', 'DDD', 4, 6),
    ]);
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(controller));
    await tester.pumpAndSettle();

    expect(find.text('存在冲突 · 请手动选择'), findsNWidgets(2));
    expect(find.text('抵达航班有旧手动中转标记'), findsNWidgets(2));
    expect(find.text('待核对'), findsNWidgets(2));
    expect(controller.transferDecisions, isEmpty);

    final firstPair = find.byKey(const ValueKey('suspected-transit-in-out1'));
    final secondPair = find.byKey(const ValueKey('suspected-transit-in-out2'));
    await tester.tap(
      find.descendant(of: firstPair, matching: find.text('确认中转')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: secondPair, matching: find.text('确认中转')),
    );
    await tester.pumpAndSettle();
    expect(
      controller
          .transferDecisionFor(controller.flights[0], controller.flights[1])
          ?.status,
      TransferDecisionStatus.confirmed,
    );
    expect(
      controller.transferDecisionFor(
        controller.flights[0],
        controller.flights[2],
      ),
      isNull,
    );
    expect(find.textContaining('该航班端点已确认另一衔接'), findsOneWidget);

    await tester.tap(find.text('已确认 / 已拒绝 · 1 条'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: firstPair, matching: find.text('不是中转')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: secondPair, matching: find.text('确认中转')),
    );
    await tester.pumpAndSettle();
    expect(
      controller
          .transferDecisionFor(controller.flights[0], controller.flights[2])
          ?.status,
      TransferDecisionStatus.confirmed,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('rejecting a pair explains that its old manual mark remains', (
    tester,
  ) async {
    final inbound = _flight('in', 'AAA', 'BBB', 0, 2, transit: true);
    final outbound = _flight('out', 'BBB', 'CCC', 3, 5);
    final controller = _Controller([inbound, outbound])
      ..countTransitArrivals = false
      ..transferDecisions = [
        TransferDecision.fromFlights(
          inbound: inbound,
          outbound: outbound,
          status: TransferDecisionStatus.rejected,
          decidedAt: _base,
        ),
      ];
    addTearDown(controller.dispose);

    await tester.pumpWidget(_host(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('中转记录 · 1 个已处理'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('已确认 / 已拒绝 · 1 条'));
    await tester.pumpAndSettle();

    expect(find.text('原手动标记仍保留'), findsOneWidget);
    expect(find.textContaining('不会清除抵达航班原有的手动标记'), findsOneWidget);
    expect(find.textContaining('该抵达仍不计入足迹'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('conflicting imported confirmations are shown for review', (
    tester,
  ) async {
    final inbound = _flight('in', 'AAA', 'BBB', 0, 2);
    final outboundOne = _flight('out1', 'BBB', 'CCC', 3, 5);
    final outboundTwo = _flight('out2', 'BBB', 'DDD', 4, 6);
    final controller = _Controller([inbound, outboundOne, outboundTwo])
      ..transferDecisions = [
        TransferDecision.fromFlights(
          inbound: inbound,
          outbound: outboundOne,
          status: TransferDecisionStatus.confirmed,
          decidedAt: _base,
        ),
        TransferDecision.fromFlights(
          inbound: inbound,
          outbound: outboundTwo,
          status: TransferDecisionStatus.confirmed,
          decidedAt: _base.add(const Duration(minutes: 1)),
        ),
      ];
    addTearDown(controller.dispose);

    await tester.pumpWidget(_host(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('中转记录 · 2 个已处理'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('已确认 / 已拒绝 · 2 条'));
    await tester.pumpAndSettle();

    expect(find.text('确认冲突 · 需重新核对'), findsNWidgets(2));
    expect(find.textContaining('统计暂不排除任一冲突衔接'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('different airports in the same city get a manual review note', (
    tester,
  ) async {
    Airport airport(String code) => Airport(
      iataCode: code,
      longitude: 0,
      latitude: 0,
      name: code,
      city: 'Same City',
      countryCode: 'XX',
    );
    final controller = _Controller(
      [_flight('in', 'AAA', 'BBB', 0, 2), _flight('out', 'CCC', 'DDD', 3, 5)],
      airportData: {'BBB': airport('BBB'), 'CCC': airport('CCC')},
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('中转记录说明'));
    await tester.pumpAndSettle();
    expect(find.textContaining('时间接近但机场代码不同'), findsOneWidget);
    expect(find.textContaining('疑似中转 · 0'), findsNothing);
    expect(controller.transferDecisions, isEmpty);
  });

  testWidgets('connection timestamps use the airport wall time', (
    tester,
  ) async {
    Airport airport(String code) => Airport(
      iataCode: code,
      longitude: 0,
      latitude: 0,
      name: code,
      city: code,
      countryCode: 'XX',
      timeZoneId: 'Asia/Shanghai',
    );
    final controller = _Controller(
      [_flight('in', 'AAA', 'BBB', 0, 2), _flight('out', 'BBB', 'CCC', 3, 5)],
      airportData: {'BBB': airport('BBB')},
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(controller));
    await tester.pumpAndSettle();

    expect(find.textContaining('抵达 BBB 2026-01-01 10:00'), findsOneWidget);
    expect(find.textContaining('出发 BBB 2026-01-01 11:00'), findsOneWidget);
    expect(find.textContaining('设备时间'), findsNothing);
  });
}
