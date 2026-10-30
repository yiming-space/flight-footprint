import 'dart:async';

import 'package:flight_footprint/app/app_controller.dart';
import 'package:flight_footprint/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('draws startup screen before local initialization completes', (
    tester,
  ) async {
    final pending = Completer<AppController>();
    var calls = 0;
    await tester.pumpWidget(
      AppStartup(
        createController: () {
          calls++;
          return pending.future;
        },
      ),
    );
    expect(find.text('Flight Footprint'), findsNothing);
    expect(find.byIcon(Icons.flight_takeoff_rounded), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      const Color(0xFF0B0E12),
    );
    expect(calls, 1);
    await tester.pump();
    pending.completeError(StateError('initialization failed'));
    await tester.pump();
    await tester.pump();
    expect(find.text('加载失败，重试 / Retry'), findsOneWidget);
  });
}
