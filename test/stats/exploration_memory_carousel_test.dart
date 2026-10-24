import 'package:flight_footprint/core/localization/app_strings.dart';
import 'package:flight_footprint/features/stats/exploration_memory_carousel.dart';
import 'package:flight_footprint/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Finder get _deck => find.byKey(const ValueKey('exploration-memory-deck'));
Finder get _semantics =>
    find.byKey(const ValueKey('exploration-memory-deck-semantics'));

void _expectCard(WidgetTester tester, int index) {
  final semantics = tester.widget<Semantics>(_semantics);
  expect(semantics.properties.label, 'Memory ${index + 1}');
  expect(semantics.properties.value, '${index + 1} / 4');
  expect(find.text('Memory ${index + 1}').hitTestable(), findsOneWidget);
}

Widget _host({
  bool reduced = false,
  bool counters = false,
  double scale = 1,
  bool highContrast = false,
}) => MaterialApp(
  theme: AppTheme.light(),
  locale: const Locale('en'),
  supportedLocales: AppStrings.supportedLocales,
  localizationsDelegates: const [
    AppStringsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      textScaler: TextScaler.linear(scale),
      disableAnimations: reduced,
      highContrast: highContrast,
    ),
    child: child!,
  ),
  home: Scaffold(
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExplorationMemoryCarousel(
            cards: [
              for (var i = 0; i < 4; i++)
                counters
                    ? _CountingCard(label: 'Memory ${i + 1}')
                    : SizedBox(
                        height: 180 + i * 38,
                        child: ColoredBox(
                          color: Colors.white,
                          child: Center(child: Text('Memory ${i + 1}')),
                        ),
                      ),
            ],
            labels: [for (var i = 0; i < 4; i++) 'Memory ${i + 1}'],
          ),
          const SizedBox(height: 24),
          const Text('Below the deck', key: ValueKey('below-deck')),
          const SizedBox(height: 800),
        ],
      ),
    ),
  ),
);

void _surface(WidgetTester tester, {double width = 390, double height = 900}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

void main() {
  testWidgets(
    'exposed glass backs blur distinct regions without accumulating filters',
    (tester) async {
      _surface(tester);
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();
      final filters = tester.layers.whereType<BackdropFilterLayer>().toList();
      expect(filters, hasLength(3));
      final clips = <Path>[];
      for (final filter in filters) {
        Layer? ancestor = filter.parent;
        while (ancestor != null && ancestor is! ClipPathLayer) {
          ancestor = ancestor.parent;
        }
        expect(ancestor, isA<ClipPathLayer>());
        clips.add((ancestor! as ClipPathLayer).clipPath!);
      }
      for (var i = 0; i < clips.length; i++) {
        expect(clips[i].getBounds().isEmpty, isFalse);
        for (var j = i + 1; j < clips.length; j++) {
          expect(
            Path.combine(
              PathOperation.intersect,
              clips[i],
              clips[j],
            ).getBounds().isEmpty,
            isTrue,
          );
        }
      }
      await tester.pumpWidget(_host(highContrast: true));
      await tester.pumpAndSettle();
      expect(tester.layers.whereType<BackdropFilterLayer>(), isEmpty);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('stack backs use faint cool colors in both themes', (
    tester,
  ) async {
    late List<Color> colors;
    Future<void> capture(ThemeData theme) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Builder(
            builder: (context) {
              colors = [
                for (var i = 0; i < 4; i++)
                  explorationMemoryCardColor(context, i),
              ];
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await capture(AppTheme.light());
    expect(
      colors,
      everyElement(const Color(0xFFA9DBF7).withValues(alpha: .12)),
    );
    await capture(AppTheme.dark());
    expect(colors, everyElement(Colors.white.withValues(alpha: .045)));
  });

  testWidgets('cuts forward and backward in a continuous circular deck', (
    tester,
  ) async {
    _surface(tester);
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    _expectCard(tester, 0);

    await tester.drag(_deck, const Offset(-150, 0));
    await tester.pumpAndSettle();
    _expectCard(tester, 1);
    await tester.drag(_deck, const Offset(150, 0));
    await tester.pumpAndSettle();
    _expectCard(tester, 0);

    await tester.drag(_deck, const Offset(150, 0));
    await tester.pumpAndSettle();
    _expectCard(tester, 3);
    await tester.drag(_deck, const Offset(-150, 0));
    await tester.pumpAndSettle();
    _expectCard(tester, 0);
    expect(find.byKey(const ValueKey('memory-carousel-next')), findsNothing);
    expect(
      find.byKey(const ValueKey('memory-carousel-previous')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('memory-carousel-dot-0')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reversing and cancelling an interrupted drag returns smoothly', (
    tester,
  ) async {
    _surface(tester);
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(tester.getCenter(_deck));
    await gesture.moveBy(const Offset(-35, 0));
    await tester.pump(const Duration(milliseconds: 40));
    await gesture.moveBy(const Offset(35, 0));
    await tester.pump(const Duration(milliseconds: 180));
    await gesture.up();
    await tester.pumpAndSettle();
    _expectCard(tester, 0);

    final cancelled = await tester.startGesture(tester.getCenter(_deck));
    await cancelled.moveBy(const Offset(-90, 0));
    await cancelled.cancel();
    await tester.pumpAndSettle();
    _expectCard(tester, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'animation frames repaint without rebuilding or laying out cards',
    (tester) async {
      _surface(tester);
      _CountingCard.builds = 0;
      _CountingRender.layouts = 0;
      await tester.pumpWidget(_host(counters: true));
      await tester.pumpAndSettle();
      final builds = _CountingCard.builds;
      final layouts = _CountingRender.layouts;

      final gesture = await tester.startGesture(tester.getCenter(_deck));
      await gesture.moveBy(const Offset(-150, 0));
      await gesture.up();
      for (var frame = 0; frame < 10; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(
          _CountingCard.builds,
          builds,
          reason: 'frame $frame rebuilt card content',
        );
        expect(
          _CountingRender.layouts,
          layouts,
          reason: 'frame $frame relaid out card content',
        );
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'paint geometry stays continuous when the outgoing card becomes the back',
    (tester) async {
      _surface(tester);
      final snapshots = <(int, double, List<ExplorationMemoryPose>)>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: ExplorationMemoryCarousel(
              cards: [
                for (var i = 0; i < 4; i++)
                  const SizedBox(
                    height: 220,
                    child: ColoredBox(color: Colors.white),
                  ),
              ],
              labels: [for (var i = 0; i < 4; i++) 'Memory ${i + 1}'],
              onPaintSnapshot: (index, progress, poses) =>
                  snapshots.add((index, progress, poses)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(tester.getCenter(_deck));
      await gesture.moveBy(const Offset(-500, 0));
      await tester.pump();
      final before = snapshots.lastWhere((snapshot) => snapshot.$2 > .9);
      await gesture.up();
      await tester.pumpAndSettle();
      final after = snapshots.lastWhere(
        (snapshot) => snapshot.$1 == 1 && snapshot.$2 == 0,
      );
      expect(before.$3, hasLength(4));
      expect(after.$3, hasLength(4));
      for (var card = 0; card < 4; card++) {
        expect(
          before.$3[card].translation.dx,
          closeTo(after.$3[card].translation.dx, 4),
        );
        expect(
          before.$3[card].translation.dy,
          closeTo(after.$3[card].translation.dy, 6),
        );
        expect(before.$3[card].rotation, closeTo(after.$3[card].rotation, .03));
        expect(before.$3[card].scale, closeTo(after.$3[card].scale, .02));
      }

      snapshots.clear();
      final reverse = await tester.startGesture(tester.getCenter(_deck));
      await reverse.moveBy(const Offset(500, 0));
      await tester.pump();
      final reverseBefore = snapshots.lastWhere(
        (snapshot) => snapshot.$2 < -.9,
      );
      await reverse.up();
      await tester.pumpAndSettle();
      final reverseAfter = snapshots.lastWhere(
        (snapshot) => snapshot.$1 == 0 && snapshot.$2 == 0,
      );
      for (var card = 0; card < 4; card++) {
        expect(
          reverseBefore.$3[card].translation.dx,
          closeTo(reverseAfter.$3[card].translation.dx, 4),
        );
        expect(
          reverseBefore.$3[card].translation.dy,
          closeTo(reverseAfter.$3[card].translation.dy, 6),
        );
        expect(
          reverseBefore.$3[card].rotation,
          closeTo(reverseAfter.$3[card].rotation, .03),
        );
        expect(
          reverseBefore.$3[card].scale,
          closeTo(reverseAfter.$3[card].scale, .02),
        );
      }
    },
  );

  testWidgets('vertical scroll remains independent and cards stay in bounds', (
    tester,
  ) async {
    _surface(tester, height: 560);
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    final before = tester.getTopLeft(_deck).dy;
    await tester.drag(_deck, const Offset(0, -120));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(_deck).dy, lessThan(before));
    expect(tester.getSize(_deck).width, lessThanOrEqualTo(350));
    _expectCard(tester, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion cuts immediately after a completed swipe', (
    tester,
  ) async {
    _surface(tester);
    await tester.pumpWidget(_host(reduced: true));
    await tester.pumpAndSettle();
    await tester.drag(_deck, const Offset(-120, 0));
    await tester.pumpAndSettle();
    _expectCard(tester, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('large text keeps natural card height without clipping', (
    tester,
  ) async {
    _surface(tester, width: 320);
    await tester.pumpWidget(_host(scale: 1.8));
    await tester.pumpAndSettle();
    expect(tester.getSize(_deck).width, lessThanOrEqualTo(280));
    expect(tester.getSize(_deck).height, greaterThan(180));
    expect(tester.getBottomLeft(_deck).dy, lessThanOrEqualTo(560));
    expect(tester.takeException(), isNull);
  });
}

class _CountingCard extends StatefulWidget {
  const _CountingCard({required this.label});
  final String label;
  static int builds = 0;

  @override
  State<_CountingCard> createState() => _CountingCardState();
}

class _CountingCardState extends State<_CountingCard> {
  @override
  Widget build(BuildContext context) {
    _CountingCard.builds++;
    return SizedBox(
      height: 200,
      child: _CountingLayout(child: Center(child: Text(widget.label))),
    );
  }
}

class _CountingLayout extends SingleChildRenderObjectWidget {
  const _CountingLayout({required super.child});
  @override
  _CountingRender createRenderObject(BuildContext context) => _CountingRender();
}

class _CountingRender extends RenderProxyBox {
  static int layouts = 0;
  @override
  void performLayout() {
    layouts++;
    super.performLayout();
  }
}
