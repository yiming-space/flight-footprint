import 'dart:math' as math;

import 'package:flight_footprint/ui/theme/app_theme.dart';
import 'package:flight_footprint/ui/widgets/perspective_card_deck.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host({
  int count = 12,
  int initialIndex = 0,
  bool reduceMotion = false,
  bool loop = false,
  bool animateEntrance = false,
  bool recycleArc = true,
  bool flipInPlace = false,
  bool cycleDepth = false,
  bool showControls = true,
  int maxRearCards = 3,
  int maxBottomPreviews = 0,
  double height = 600,
  ValueChanged<int>? onIndexChanged,
  Map<int, double>? positions,
}) => MaterialApp(
  theme: AppTheme.dark(),
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: 360,
        height: height,
        child: PerspectiveCardDeck(
          itemCount: count,
          initialIndex: initialIndex,
          cardHeight: 340,
          reduceMotion: reduceMotion,
          loop: loop,
          animateEntrance: animateEntrance,
          recycleArc: recycleArc,
          flipInPlace: flipInPlace,
          cycleDepth: cycleDepth,
          showControls: showControls,
          maxRearCards: maxRearCards,
          maxBottomPreviews: maxBottomPreviews,
          onIndexChanged: onIndexChanged,
          itemBuilder: (context, index, relative, active) {
            positions?[index] = relative;
            return Semantics(
              button: true,
              label: 'Aircraft $index',
              excludeSemantics: true,
              child: ColoredBox(
                color: Colors.grey,
                child: Center(
                  child: Text(
                    'Card $index',
                    key: ValueKey(active ? 'active-$index' : 'rear-$index'),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ),
  ),
);

Finder get _next => find.byKey(const ValueKey('deck-next'));
Finder get _previous => find.byKey(const ValueKey('deck-previous'));
Finder get _position => find.byKey(const ValueKey('deck-position'));
Finder get _deck => find.byKey(const ValueKey('perspective-deck'));
Finder _active(int index) => find.byKey(ValueKey('active-$index'));

Offset _dragStart(WidgetTester tester) =>
    tester.getTopLeft(_deck) + const Offset(180, 300);

List<double> _cardTransform(WidgetTester tester, int slot) => tester
    .widget<Transform>(find.byKey(ValueKey('deck-card-transform-$slot')))
    .transform
    .storage
    .toList();

void main() {
  testWidgets(
    'bottom previews use available height without shrinking the front',
    (tester) async {
      tester.view.physicalSize = const Size(400, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();
      try {
        for (final height in [600.0, 800.0]) {
          await tester.pumpWidget(
            _host(
              loop: true,
              cycleDepth: true,
              showControls: false,
              maxBottomPreviews: 2,
              height: height,
            ),
          );
          await tester.pumpAndSettle();
          final viewport = tester.getRect(
            find.byKey(const ValueKey('deck-card-stack')),
          );
          final front = tester.getRect(
            find.byKey(const ValueKey('deck-card-transform-0')),
          );
          expect(front.height, 340);
          expect(front.bottom, lessThan(viewport.bottom));
          final first = tester.getTopLeft(
            find.byKey(const ValueKey('deck-card-transform-1')),
          );
          final second = tester.getTopLeft(
            find.byKey(const ValueKey('deck-card-transform-2')),
          );
          expect(first.dy, closeTo(front.bottom + 12, .01));
          expect(first.dy, lessThan(viewport.bottom - 60));
          expect(
            second.dy,
            height == 600 ? lessThan(front.top) : closeTo(first.dy + 76, .01),
          );
          expect(find.bySemanticsLabel('Aircraft 0'), findsOneWidget);
          expect(find.bySemanticsLabel('Aircraft 1'), findsNothing);
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(
          _host(
            loop: true,
            cycleDepth: true,
            showControls: false,
            maxBottomPreviews: 2,
            reduceMotion: true,
            height: 800,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('deck-slot-1')), findsNothing);
        expect(_cardTransform(tester, 0)[0], 1);
        expect(tester.binding.transientCallbackCount, 0);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('small looping decks land continuously in the bottom preview', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final count in [2, 3]) {
      final positions = <int, double>{};
      await tester.pumpWidget(
        _host(
          count: count,
          loop: true,
          cycleDepth: true,
          showControls: false,
          maxBottomPreviews: 2,
          height: 800,
          positions: positions,
        ),
      );
      final gesture = await tester.startGesture(_dragStart(tester));
      await gesture.moveBy(const Offset(0, -24));
      await tester.pump();
      await gesture.moveBy(Offset(0, (-positions[0]! - .99999) * 176.8));
      await tester.pump();
      final outgoingTop = tester
          .widget<Positioned>(find.byKey(const ValueKey('deck-slot-0')))
          .top!;
      final outgoing = _cardTransform(tester, 0);
      await gesture.moveBy(const Offset(0, -.00002 * 176.8));
      await tester.pump();
      final returnedTop = tester
          .widget<Positioned>(find.byKey(ValueKey('deck-slot-$count')))
          .top!;
      final returned = _cardTransform(tester, count);
      expect(returnedTop, closeTo(outgoingTop, .03));
      for (var i = 0; i < 16; i++) {
        expect(returned[i], closeTo(outgoing[i], .0001));
      }
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(_active(1), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'drawn card flies up then tucks behind offscreen and reverses the same path',
    (tester) async {
      final positions = <int, double>{};
      await tester.pumpWidget(
        _host(
          count: 8,
          loop: true,
          cycleDepth: true,
          maxRearCards: 4,
          positions: positions,
        ),
      );
      final top = tester
          .widget<Positioned>(find.byKey(const ValueKey('deck-slot-0')))
          .top!;
      final gesture = await tester.startGesture(_dragStart(tester));
      await gesture.moveBy(const Offset(0, -24));
      await tester.pump();
      Future<void> seek(double progress) async {
        await gesture.moveBy(Offset(0, (-positions[0]! - progress) * 176.8));
        await tester.pump();
      }

      var previousScale = 1.0;
      var previousTop = top;
      double? sampleTop;
      List<double>? sample;
      for (final progress in [
        .01,
        .1,
        .25,
        .35,
        .49,
        .5,
        .51,
        .56,
        .6,
        .65,
        .75,
        .9,
        .99,
      ]) {
        await seek(progress);
        final outgoing = _cardTransform(tester, 0);
        final incoming = _cardTransform(tester, 1);
        for (final matrix in [outgoing, incoming]) {
          expect(matrix.every((value) => value.isFinite), isTrue);
          expect(matrix[5] / matrix[0], greaterThan(.85));
          expect(matrix[0], lessThanOrEqualTo(1));
          expect(matrix[12], 0);
        }
        final currentTop = tester
            .widget<Positioned>(find.byKey(const ValueKey('deck-slot-0')))
            .top!;
        expect(outgoing[0], lessThanOrEqualTo(previousScale));
        if (progress <= .56) {
          expect(currentTop, lessThanOrEqualTo(previousTop));
        }
        if (progress >= .56 && progress <= .65) {
          expect(
            currentTop + 340 * outgoing[0],
            lessThan(0),
            reason: 'Paint depth changes only outside the clipped deck',
          );
        }
        previousScale = outgoing[0];
        previousTop = currentTop;
        double opacity(int slot) => tester
            .widget<Opacity>(
              find.descendant(
                of: find.byKey(ValueKey('deck-slot-$slot')),
                matching: find.byType(Opacity),
              ),
            )
            .opacity;
        expect(opacity(0) + opacity(1), greaterThan(.9));
        if (progress <= .56) expect(opacity(0), 1);
        if (progress == .25) {
          sample = outgoing;
          sampleTop = currentTop;
        }
      }
      await seek(.25);
      final reversed = _cardTransform(tester, 0);
      expect(
        tester
            .widget<Positioned>(find.byKey(const ValueKey('deck-slot-0')))
            .top,
        closeTo(sampleTop!, 1e-8),
      );
      for (var i = 0; i < reversed.length; i++) {
        expect(reversed[i], closeTo(sample![i], 1e-8));
      }
      await tester.pump(const Duration(milliseconds: 500));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(_active(0), findsOneWidget);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('depth cycle loops both ways without visible paging controls', (
    tester,
  ) async {
    Future<void> key(LogicalKeyboardKey key) async {
      Focus.of(tester.element(find.byKey(const ValueKey('deck-card-stack'))))
          .requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
    }

    for (final count in [2, 3, 16]) {
      await tester.pumpWidget(
        _host(
          count: count,
          initialIndex: count - 1,
          loop: true,
          cycleDepth: true,
          showControls: false,
          maxRearCards: 4,
        ),
      );
      await tester.pumpAndSettle();
      expect(_next, findsNothing);
      expect(_previous, findsNothing);
      expect(_position, findsNothing);
      await key(LogicalKeyboardKey.arrowDown);
      expect(_active(0), findsOneWidget);
      await key(LogicalKeyboardKey.arrowUp);
      expect(_active(count - 1), findsOneWidget);
      expect(tester.binding.transientCallbackCount, 0);
    }
    await tester.pumpWidget(
      _host(
        count: 3,
        loop: true,
        cycleDepth: true,
        showControls: false,
        maxRearCards: 4,
        reduceMotion: true,
      ),
    );
    await key(LogicalKeyboardKey.arrowUp);
    expect(_active(2), findsOneWidget);
    expect(
      _cardTransform(tester, -1),
      (Matrix4.identity()..setEntry(3, 2, .0012)).storage,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('in-place flip stays centered and never exposes mirrored faces', (
    tester,
  ) async {
    final positions = <int, double>{};
    await tester.pumpWidget(
      _host(
        count: 8,
        loop: true,
        recycleArc: false,
        flipInPlace: true,
        positions: positions,
      ),
    );
    final restTop = tester
        .widget<Positioned>(find.byKey(const ValueKey('deck-slot-0')))
        .top!;
    final gesture = await tester.startGesture(_dragStart(tester));
    await gesture.moveBy(const Offset(0, -24));
    await tester.pump();
    Future<void> seek(double progress) async {
      await gesture.moveBy(Offset(0, (-positions[0]! - progress) * 176.8));
      await tester.pump();
    }

    List<double>? beforeReverse;
    for (final progress in [.1, .25, .49, .5, .51, .75, .9]) {
      await seek(progress);
      for (final slot in [0, 1]) {
        final matrix = _cardTransform(tester, slot);
        expect(matrix.every((value) => value.isFinite), isTrue);
        expect(matrix[5], greaterThanOrEqualTo(-1e-10));
        expect(matrix[12], 0);
      }
      final outgoing = tester.widget<Transform>(
        find.byKey(const ValueKey('deck-card-transform-0')),
      );
      expect(outgoing.transform.storage[0], 1);
      expect(outgoing.alignment, Alignment.center);
      expect(
        tester
            .widget<Positioned>(find.byKey(const ValueKey('deck-slot-0')))
            .top,
        restTop,
      );
      final opacity = tester.widget<Opacity>(
        find.descendant(
          of: find.byKey(const ValueKey('deck-slot-0')),
          matching: find.byType(Opacity),
        ),
      );
      if (progress != .5) {
        expect(opacity.opacity, progress < .5 ? 1 : 0);
      }
      if (progress == .25) beforeReverse = _cardTransform(tester, 1);
      if (progress > .5) {
        final incoming = tester.widget<Transform>(
          find.byKey(const ValueKey('deck-card-transform-1')),
        );
        expect(incoming.alignment, Alignment.center);
        expect(incoming.transform.storage[0], 1);
        expect(
          tester
              .widget<Positioned>(find.byKey(const ValueKey('deck-slot-1')))
              .top,
          restTop,
        );
      }
    }
    await seek(.25);
    final reversed = _cardTransform(tester, 1);
    for (var i = 0; i < reversed.length; i++) {
      expect(reversed[i], closeTo(beforeReverse![i], 1e-8));
    }
    await tester.pump(const Duration(milliseconds: 500));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(_active(0), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'in-place loop flips across either seam and skips reduced motion',
    (tester) async {
      await tester.pumpWidget(
        _host(
          count: 6,
          initialIndex: 5,
          loop: true,
          recycleArc: false,
          flipInPlace: true,
          animateEntrance: true,
        ),
      );
      await tester.pumpAndSettle();
      for (final delta in [-110.0, 110.0]) {
        final gesture = await tester.startGesture(_dragStart(tester));
        await gesture.moveBy(Offset(0, delta.sign * 24));
        await tester.pump(const Duration(milliseconds: 50));
        await gesture.moveBy(Offset(0, delta));
        await tester.pump(const Duration(milliseconds: 600));
        await gesture.up();
        await tester.pumpAndSettle();
        expect(_active(delta < 0 ? 0 : 5), findsOneWidget);
      }
      await tester.pump(const Duration(seconds: 2));
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.binding.hasScheduledFrame, isFalse);
      await tester.pumpWidget(
        _host(count: 6, loop: true, flipInPlace: true, reduceMotion: true),
      );
      await tester.tap(_previous);
      await tester.pump();
      expect(_active(5), findsOneWidget);
      expect(find.text('Card 0'), findsNothing);
      expect(_cardTransform(tester, -1)[5], 1);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('light perspective shrinks gently with stable logical layers', (
    tester,
  ) async {
    final positions = <int, double>{};
    await tester.pumpWidget(
      _host(count: 8, loop: true, recycleArc: false, positions: positions),
    );
    final restTop = tester
        .widget<Positioned>(find.byKey(const ValueKey('deck-slot-0')))
        .top!;
    final gesture = await tester.startGesture(_dragStart(tester));
    await gesture.moveBy(const Offset(0, -24));
    await tester.pump();
    Future<void> seek(double progress) async {
      await gesture.moveBy(Offset(0, (-positions[0]! - progress) * 176.8));
      await tester.pump();
    }

    var previousScale = 1.0;
    for (final progress in [.1, .2, .4, .6]) {
      await seek(progress);
      final transform = _cardTransform(tester, 0);
      expect(transform[0], lessThanOrEqualTo(previousScale));
      expect(transform[0], closeTo(1 - progress * .045, 1e-8));
      expect(
        math.atan2(transform[6], transform[5]).abs(),
        lessThanOrEqualTo(.1),
      );
      expect(transform[12], 0);
      previousScale = transform[0];
    }
    final top = tester
        .widget<Positioned>(find.byKey(const ValueKey('deck-slot-0')))
        .top!;
    expect(top, closeTo(restTop - .6 * 340 * .24, 1e-8));
    final outgoingOpacity = tester.widget<Opacity>(
      find.descendant(
        of: find.byKey(const ValueKey('deck-slot-0')),
        matching: find.byType(Opacity),
      ),
    );
    expect(outgoingOpacity.opacity, closeTo(.4, 1e-8));
    final slots = tester
        .widget<Stack>(find.byKey(const ValueKey('deck-card-stack')))
        .children
        .map((child) => child.key)
        .toList();
    expect(slots, [
      for (var slot = 4; slot >= 0; slot--) ValueKey('deck-slot-$slot'),
    ]);
    final farOpacity = tester.widget<Opacity>(
      find.descendant(
        of: find.byKey(const ValueKey('deck-slot-4')),
        matching: find.byType(Opacity),
      ),
    );
    expect(farOpacity.opacity, closeTo(.66 * .6, 1e-8));
    await seek(.2);
    expect(_cardTransform(tester, 0)[0], closeTo(1 - .2 * .045, 1e-8));
    await tester.pump(const Duration(milliseconds: 500));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(_active(0), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'light looping reverses across seams and rests with reduced motion',
    (tester) async {
      final positions = <int, double>{};
      await tester.pumpWidget(
        _host(
          count: 6,
          initialIndex: 5,
          loop: true,
          recycleArc: false,
          animateEntrance: true,
          positions: positions,
        ),
      );
      await tester.pumpAndSettle();
      for (final delta in [-110.0, 110.0]) {
        final gesture = await tester.startGesture(_dragStart(tester));
        await gesture.moveBy(Offset(0, delta.sign * 24));
        await tester.pump(const Duration(milliseconds: 50));
        await gesture.moveBy(Offset(0, delta));
        await tester.pump(const Duration(milliseconds: 600));
        await gesture.up();
        await tester.pumpAndSettle();
        expect(_active(delta < 0 ? 0 : 5), findsOneWidget);
      }
      final resting = _cardTransform(tester, 5);
      await tester.pump(const Duration(seconds: 2));
      expect(_cardTransform(tester, 5), resting);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.binding.hasScheduledFrame, isFalse);
      await tester.pumpWidget(
        _host(count: 6, loop: true, recycleArc: false, reduceMotion: true),
      );
      await tester.tap(_previous);
      await tester.pump();
      expect(_active(5), findsOneWidget);
      expect(find.text('Card 0'), findsNothing);
      await tester.tap(_next);
      await tester.pump();
      expect(_active(0), findsOneWidget);
      expect(_cardTransform(tester, 0)[0], 1);
      expect(_cardTransform(tester, 0)[5], 1);
      await tester.pump(const Duration(seconds: 1));
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.binding.hasScheduledFrame, isFalse);
      await tester.pumpWidget(_host(count: 1, loop: true, recycleArc: false));
      expect(_active(0), findsOneWidget);
      expect(tester.widget<IconButton>(_next).onPressed, isNull);
      expect(tester.widget<IconButton>(_previous).onPressed, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'loop card recedes without lifting, folds behind the next face and reverses the same arc',
    (tester) async {
      final positions = <int, double>{};
      await tester.pumpWidget(
        _host(count: 8, loop: true, positions: positions),
      );
      final restTop = tester
          .widget<Positioned>(find.byKey(const ValueKey('deck-slot-0')))
          .top!;
      final start = _dragStart(tester);
      final gesture = await tester.startGesture(start);
      await gesture.moveBy(const Offset(0, -24));
      await tester.pump();
      Future<void> seek(double progress) async {
        await gesture.moveBy(Offset(0, (-positions[0]! - progress) * 176.8));
        await tester.pump();
      }

      var previousScale = 1.0;
      for (final progress in [.05, .10, .15, .20]) {
        await seek(progress);
        final scale = _cardTransform(tester, 0)[0];
        expect(
          scale,
          lessThanOrEqualTo(previousScale),
          reason: 'No grow-before-shrink lift',
        );
        previousScale = scale;
        if (progress == .10) {
          final top = tester
              .widget<Positioned>(find.byKey(const ValueKey('deck-slot-0')))
              .top!;
          expect(
            top,
            greaterThan(restTop - 15),
            reason: 'Early fold must not jump upward',
          );
        }
      }
      final lifted = _cardTransform(tester, 0);
      final liftedTop = tester
          .widget<Positioned>(find.byKey(const ValueKey('deck-slot-0')))
          .top!;
      expect(lifted[0], lessThan(1));
      expect(lifted[12], greaterThan(0));
      expect(liftedTop, lessThan(restTop));
      await seek(.6);
      final folded = _cardTransform(tester, 0);
      expect(
        folded[5].abs(),
        lessThan(.25),
        reason: 'Card folds nearly edge-on without showing a mirrored back',
      );
      final layer = find.byKey(const ValueKey('deck-card-stack'));
      final slots = tester
          .widget<Stack>(layer)
          .children
          .map((child) => child.key)
          .toList();
      expect(
        slots.indexOf(const ValueKey('deck-slot-0')),
        lessThan(slots.indexOf(const ValueKey('deck-slot-1'))),
        reason: 'Returning card is painted behind the incoming face',
      );
      expect(slots.length, lessThanOrEqualTo(5));
      final opacity = tester.widget<Opacity>(
        find.descendant(
          of: find.byKey(const ValueKey('deck-slot-0')),
          matching: find.byType(Opacity),
        ),
      );
      expect(
        opacity.opacity,
        greaterThan(.65),
        reason: 'Occlusion, not disappearance, owns the return',
      );
      await seek(.2);
      final reversed = _cardTransform(tester, 0);
      for (var i = 0; i < 16; i++) {
        expect(reversed[i], closeTo(lifted[i], 1e-8));
      }
      await tester.pump(const Duration(milliseconds: 500));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(_active(0), findsOneWidget);
      expect(_cardTransform(tester, 0)[0], 1);
      expect(_cardTransform(tester, 0)[5], 1);
      expect(_cardTransform(tester, 0)[12], 0);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('arc remains finite and non-mirrored with two or three cards', (
    tester,
  ) async {
    for (final count in [2, 3]) {
      await tester.pumpWidget(const SizedBox.shrink());
      final positions = <int, double>{};
      await tester.pumpWidget(
        _host(count: count, loop: true, positions: positions),
      );
      final gesture = await tester.startGesture(_dragStart(tester));
      await gesture.moveBy(const Offset(0, -24));
      await tester.pump();
      for (var step = 1; step <= 9; step++) {
        await gesture.moveBy(Offset(0, (-positions[0]! - step / 10) * 176.8));
        await tester.pump();
        final matrix = _cardTransform(tester, 0);
        expect(matrix.every((value) => value.isFinite), isTrue);
        expect(matrix[0], greaterThan(0));
        expect(matrix[5], greaterThan(0));
      }
      await tester.pump(const Duration(milliseconds: 500));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(_active(1), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('entrance opens once and stays idle across rebuilds', (
    tester,
  ) async {
    await tester.pumpWidget(_host(animateEntrance: true));
    final compressed = _cardTransform(tester, 1);
    final compressedTop = tester
        .widget<Positioned>(find.byKey(const ValueKey('deck-slot-1')))
        .top!;
    await tester.pump(const Duration(milliseconds: 225));
    expect(_cardTransform(tester, 1), isNot(compressed));
    await tester.pump(const Duration(milliseconds: 225));
    final opened = _cardTransform(tester, 1);
    final openedTop = tester
        .widget<Positioned>(find.byKey(const ValueKey('deck-slot-1')))
        .top!;
    expect(openedTop, lessThan(compressedTop));
    await tester.pumpWidget(_host(animateEntrance: true));
    expect(_cardTransform(tester, 1), opened);
    await tester.pump(const Duration(seconds: 2));
    expect(_cardTransform(tester, 1), opened);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('pointer input and paging finish an interrupted entrance', (
    tester,
  ) async {
    await tester.pumpWidget(_host());
    final opened = _cardTransform(tester, 1);
    for (final step in [false, true]) {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(_host(animateEntrance: true));
      await tester.pump(const Duration(milliseconds: 100));
      expect(_cardTransform(tester, 1), isNot(opened));
      if (step) {
        await tester.tap(_next);
      } else {
        final gesture = await tester.startGesture(_dragStart(tester));
        await tester.pump();
        expect(_cardTransform(tester, 1), opened);
        await gesture.up();
      }
      await tester.pump();
      expect(_cardTransform(tester, 1), opened);
      await tester.pumpAndSettle();
      expect(_active(step ? 1 : 0), findsOneWidget);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('single and reduced decks skip entrance and remain idle', (
    tester,
  ) async {
    for (final reduced in [false, true]) {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        _host(count: reduced ? 3 : 1, reduceMotion: reduced),
      );
      final resting = _cardTransform(tester, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        _host(
          count: reduced ? 3 : 1,
          reduceMotion: reduced,
          animateEntrance: true,
        ),
      );
      expect(_cardTransform(tester, 0), resting);
      await tester.pump(const Duration(seconds: 1));
      expect(_cardTransform(tester, 0), resting);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.binding.hasScheduledFrame, isFalse);
    }
  });

  testWidgets('loop controls wrap both ways and report real item indices', (
    tester,
  ) async {
    final selections = <int>[];
    await tester.pumpWidget(
      _host(count: 3, loop: true, onIndexChanged: selections.add),
    );
    expect(tester.widget<IconButton>(_previous).onPressed, isNotNull);
    await tester.tap(_previous);
    await tester.pumpAndSettle();
    expect(_active(2), findsOneWidget);
    expect(tester.widget<Text>(_position).data, '3 / 3');
    expect(tester.widget<IconButton>(_next).onPressed, isNotNull);
    await tester.tap(_next);
    await tester.pumpAndSettle();
    expect(_active(0), findsOneWidget);
    for (var i = 0; i < 7; i++) {
      await tester.tap(_next);
      await tester.pumpAndSettle();
    }
    expect(_active(1), findsOneWidget);
    expect(selections, [2, 0, 1, 2, 0, 1, 2, 0, 1]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('drag tracks continuously across the loop seam and reverses', (
    tester,
  ) async {
    final positions = <int, double>{};
    await tester.pumpWidget(
      _host(count: 6, initialIndex: 5, loop: true, positions: positions),
    );
    final gesture = await tester.startGesture(_dragStart(tester));
    await gesture.moveBy(const Offset(0, -24));
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveBy(const Offset(0, -110));
    await tester.pump(const Duration(milliseconds: 300));
    expect(positions[5], lessThan(-.5));
    expect(positions[0], greaterThan(0));
    expect(positions[0], lessThan(.5));
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(_active(0), findsOneWidget);
    final reverse = await tester.startGesture(_dragStart(tester));
    await reverse.moveBy(const Offset(0, 24));
    await tester.pump(const Duration(milliseconds: 50));
    await reverse.moveBy(const Offset(0, 110));
    await tester.pump(const Duration(milliseconds: 600));
    await reverse.up();
    await tester.pumpAndSettle();
    expect(_active(5), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a loop flick crosses either seam but still advances at most three',
    (tester) async {
      await tester.pumpWidget(_host(count: 8, loop: true));
      await tester.flingFrom(_dragStart(tester), const Offset(0, 160), 2500);
      await tester.pumpAndSettle();
      expect(_active(5), findsOneWidget);
      await tester.flingFrom(_dragStart(tester), const Offset(0, -160), 2500);
      await tester.pumpAndSettle();
      expect(_active(0), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'loop with two items exposes one active card and reduced paging wraps',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(_host(count: 2, loop: true));
        expect(find.text('Card 0'), findsOneWidget);
        expect(find.text('Card 1'), findsOneWidget);
        await tester.tap(_previous);
        await tester.pumpAndSettle();
        expect(find.bySemanticsLabel('Aircraft 1'), findsOneWidget);
        expect(find.bySemanticsLabel('Aircraft 0'), findsNothing);
        await tester.pumpWidget(
          _host(count: 2, loop: true, reduceMotion: true),
        );
        await tester.tap(_next);
        await tester.pump();
        expect(_active(0), findsOneWidget);
        expect(find.text('Card 1'), findsNothing);
        await tester.pumpWidget(_host(count: 1, loop: true));
        expect(tester.widget<IconButton>(_next).onPressed, isNull);
        expect(tester.widget<IconButton>(_previous).onPressed, isNull);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('only nearby cards build and controls stop at both boundaries', (
    tester,
  ) async {
    final positions = <int, double>{};
    final selections = <int>[];
    await tester.pumpWidget(
      _host(count: 40, positions: positions, onIndexChanged: selections.add),
    );
    expect(_active(0), findsOneWidget);
    expect(positions.length, lessThanOrEqualTo(5));
    expect(tester.widget<IconButton>(_previous).onPressed, isNull);
    await tester.tap(_next);
    await tester.pumpAndSettle();
    expect(_active(1), findsOneWidget);
    expect(tester.widget<Text>(_position).data, '2 / 40');
    expect(selections, [1]);
    await tester.pumpWidget(_host(count: 40, initialIndex: 39));
    await tester.pumpAndSettle();
    expect(_active(39), findsOneWidget);
    expect(tester.widget<IconButton>(_next).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'drag updates presentation directly before release then settles',
    (tester) async {
      final positions = <int, double>{};
      final selections = <int>[];
      await tester.pumpWidget(
        _host(positions: positions, onIndexChanged: selections.add),
      );
      final gesture = await tester.startGesture(_dragStart(tester));
      await gesture.moveBy(const Offset(0, -24));
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.moveBy(const Offset(0, -110));
      await tester.pump(const Duration(milliseconds: 250));
      expect(positions[0], lessThan(-.5));
      expect(
        selections,
        isEmpty,
        reason: 'Selection reports only after settling',
      );
      await tester.pump(const Duration(milliseconds: 300));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(_active(1), findsOneWidget);
      expect(selections, [1]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a fast flick advances multiple cards but at most three', (
    tester,
  ) async {
    await tester.pumpWidget(_host(count: 20));
    await tester.flingFrom(_dragStart(tester), const Offset(0, -160), 2500);
    await tester.pumpAndSettle();
    expect(_active(3), findsOneWidget);
    expect(tester.widget<Text>(_position).data, '4 / 20');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a drag can interrupt a spring and reverse immediately', (
    tester,
  ) async {
    final positions = <int, double>{};
    await tester.pumpWidget(_host(initialIndex: 3, positions: positions));
    await tester.tap(_next);
    await tester.pump(const Duration(milliseconds: 80));
    final before = positions[3]!;
    final gesture = await tester.startGesture(_dragStart(tester));
    await gesture.moveBy(const Offset(0, 24));
    await tester.pump(const Duration(milliseconds: 30));
    await gesture.moveBy(const Offset(0, 130));
    await tester.pump(const Duration(milliseconds: 250));
    expect(positions[3], greaterThan(before));
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    await tester.pumpAndSettle();
    final selected = tester.widget<Text>(_position).data!;
    expect(selected, isNot('5 / 12'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('inactive cards do not duplicate accessibility actions', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(_host());
      expect(find.bySemanticsLabel('Aircraft 0'), findsOneWidget);
      expect(find.bySemanticsLabel('Aircraft 1'), findsNothing);
      await tester.tap(_next);
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Aircraft 1'), findsOneWidget);
      expect(find.bySemanticsLabel('Aircraft 0'), findsNothing);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('reduced motion changes immediately with no perspective stack', (
    tester,
  ) async {
    final positions = <int, double>{};
    await tester.pumpWidget(_host(reduceMotion: true, positions: positions));
    expect(find.text('Card 0'), findsOneWidget);
    expect(find.text('Card 1'), findsNothing);
    await tester.tap(_next);
    await tester.pump();
    expect(_active(1), findsOneWidget);
    expect(positions[1], 0);
    final before = tester.getTopLeft(_active(1));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.getTopLeft(_active(1)), before);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty and single-card decks remain safe', (tester) async {
    await tester.pumpWidget(_host(count: 0));
    expect(_deck, findsNothing);
    await tester.pumpWidget(_host(count: 1));
    expect(_active(0), findsOneWidget);
    expect(tester.widget<IconButton>(_next).onPressed, isNull);
    expect(tester.widget<IconButton>(_previous).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('enabling reduced motion mid-spring snaps and reports nearest', (
    tester,
  ) async {
    final positions = <int, double>{};
    final selections = <int>[];
    await tester.pumpWidget(
      _host(positions: positions, onIndexChanged: selections.add),
    );
    await tester.tap(_next);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(positions[0], lessThan(-.5));
    expect(positions[0], greaterThan(-1));
    expect(selections, isEmpty);
    await tester.pumpWidget(
      _host(
        reduceMotion: true,
        positions: positions,
        onIndexChanged: selections.add,
      ),
    );
    expect(_active(1), findsOneWidget);
    expect(positions[1], 0);
    expect(selections, [1]);
    await tester.pump(const Duration(seconds: 1));
    expect(tester.widget<Text>(_position).data, '2 / 12');
    expect(selections, [1]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping a card interrupts its old spring target', (
    tester,
  ) async {
    await tester.pumpWidget(_host());
    await tester.tap(_next);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(_active(0), findsOneWidget);
    await tester.tapAt(_dragStart(tester));
    await tester.pumpAndSettle();
    expect(_active(0), findsOneWidget);
    expect(tester.widget<Text>(_position).data, '1 / 12');
    await tester.pump(const Duration(seconds: 1));
    expect(tester.widget<Text>(_position).data, '1 / 12');
    expect(tester.takeException(), isNull);
  });
}
