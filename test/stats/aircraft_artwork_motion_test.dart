import 'package:flight_footprint/features/stats/aircraft_artwork_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host({
  double relative = 0,
  bool enabled = true,
  bool disableAnimations = false,
  bool accessibleNavigation = false,
}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(
      disableAnimations: disableAnimations,
      accessibleNavigation: accessibleNavigation,
    ),
    child: AircraftArtworkMotion(
      relativePosition: relative,
      enabled: enabled,
      child: const SizedBox(width: 120, height: 60),
    ),
  ),
);

Transform _transform(WidgetTester tester) => tester.widget<Transform>(
  find.byKey(const ValueKey('aircraft-artwork-motion-transform')),
);

Offset _offset(WidgetTester tester) {
  final translation = _transform(tester).transform.getTranslation();
  return Offset(translation.x, translation.y);
}

void main() {
  testWidgets(
    'retargeting is continuous and settles exactly with no idle tick',
    (tester) async {
      await tester.pumpWidget(_host());
      expect(_offset(tester), Offset.zero);
      await tester.pumpWidget(_host(relative: 1));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      final moving = _offset(tester);
      expect(moving.dx, inExclusiveRange(0, 10));
      expect(moving.dy, closeTo(-moving.dx / 2, .000001));
      await tester.pumpWidget(_host(relative: -1));
      expect(
        _offset(tester).dx,
        closeTo(moving.dx, 1e-8),
        reason: 'Retargeting must not jump horizontally',
      );
      expect(
        _offset(tester).dy,
        closeTo(moving.dy, 1e-8),
        reason: 'Retargeting must not jump vertically',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 8));
      expect(
        _offset(tester).dx,
        greaterThan(moving.dx),
        reason: 'Reversal retains incoming velocity before changing direction',
      );
      await tester.pumpAndSettle();
      expect(_offset(tester), const Offset(-10, 5));
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();
      expect(_transform(tester).transform.storage, Matrix4.identity().storage);
      await tester.pump(const Duration(seconds: 2));
      expect(_offset(tester), Offset.zero);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.binding.hasScheduledFrame, isFalse);
    },
  );

  testWidgets(
    'disabled and accessibility settings snap midflight to identity',
    (tester) async {
      for (var mode = 0; mode < 3; mode++) {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(_host());
        await tester.pumpWidget(_host(relative: 1));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 80));
        expect(_offset(tester).dx, greaterThan(0));
        await tester.pumpWidget(
          _host(
            relative: 1,
            enabled: mode != 0,
            disableAnimations: mode == 1,
            accessibleNavigation: mode == 2,
          ),
        );
        expect(
          _transform(tester).transform.storage,
          Matrix4.identity().storage,
        );
        await tester.pump(const Duration(seconds: 1));
        expect(_offset(tester), Offset.zero);
        expect(tester.binding.transientCallbackCount, 0);
        expect(tester.binding.hasScheduledFrame, isFalse);
      }
    },
  );

  testWidgets('initial offsets clamp and disposal cancels an active spring', (
    tester,
  ) async {
    await tester.pumpWidget(_host(relative: 3));
    expect(_offset(tester), const Offset(10, -5));
    await tester.pumpWidget(_host(relative: -3));
    await tester.pumpAndSettle();
    expect(_offset(tester), const Offset(-10, 5));
    await tester.pumpWidget(_host(relative: 1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });
}
