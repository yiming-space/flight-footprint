import 'package:flight_footprint/core/localization/app_strings.dart';
import 'package:flight_footprint/features/stats/exploration_map_artwork.dart';
import 'package:flight_footprint/features/stats/exploration_overview_card.dart';
import 'package:flight_footprint/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class _PaintProbe extends CustomPainter {
  _PaintProbe(this.onPaint, {super.repaint});
  final VoidCallback onPaint;
  @override
  void paint(Canvas canvas, Size size) {
    onPaint();
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.blue);
  }

  @override
  bool shouldRepaint(covariant _PaintProbe oldDelegate) => false;
}

void main() {
  testWidgets('covered stats page stops painting after exploration opens', (
    tester,
  ) async {
    final changes = ValueNotifier(0);
    addTearDown(changes.dispose);
    var sourcePaints = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: const [AppStringsDelegate()],
        home: Scaffold(
          body: CustomPaint(
            painter: _PaintProbe(() => sourcePaints++, repaint: changes),
            child: Center(
              child: SizedBox(
                width: 350,
                child: ExplorationOverviewCard(
                  worldCount: 24,
                  chinaCount: 20,
                  pageBuilder: (_) => const Scaffold(body: Text('Details')),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('world-exploration-source')));
    await tester.pumpAndSettle();
    final coveredPaints = sourcePaints;
    changes.value++;
    await tester.pump();
    expect(sourcePaints, coveredPaints);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(sourcePaints, greaterThan(coveredPaints));
  });

  testWidgets('flip caches changing detail paint then restores live content', (
    tester,
  ) async {
    final changes = ValueNotifier(0);
    addTearDown(changes.dispose);
    var detailPaints = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: const [AppStringsDelegate()],
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 350,
              child: ExplorationOverviewCard(
                worldCount: 24,
                chinaCount: 20,
                pageBuilder: (_) => CustomPaint(
                  painter: _PaintProbe(() => detailPaints++, repaint: changes),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('world-exploration-source')));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));
    final cachedPaints = detailPaints;
    expect(cachedPaints, greaterThan(0));
    for (var i = 0; i < 8; i++) {
      changes.value++;
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(detailPaints, cachedPaints);
    await tester.pumpAndSettle();
    final livePaints = detailPaints;
    changes.value++;
    await tester.pump();
    expect(detailPaints, greaterThan(livePaints));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('flip reuses the static destination paint during movement', (
    tester,
  ) async {
    var paints = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        locale: const Locale('zh'),
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: const [
          AppStringsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 350,
              child: ExplorationOverviewCard(
                worldCount: 24,
                chinaCount: 20,
                pageBuilder: (_) => CustomPaint(
                  painter: _PaintProbe(() => paints++),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('world-exploration-source')));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 230));
    final before = paints;
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final extra = paints - before;
    // A static detail page must be composited, rather than repainted each frame.
    // ignore: avoid_print
    print('DETAIL_PAINTS_DURING_10_FLIP_FRAMES=$extra');
    expect(extra, lessThanOrEqualTo(1));
    await tester.pumpAndSettle();
  });

  test('cold exploration geometry load measurement', () async {
    final watch = Stopwatch()..start();
    await ExplorationMapArtwork.preload();
    watch.stop();
    // Host debug timing is diagnostic, never a real-device frame-rate claim.
    // ignore: avoid_print
    print('COLD_EXPLORATION_GEOMETRY_MS=${watch.elapsedMilliseconds}');
  });
}
