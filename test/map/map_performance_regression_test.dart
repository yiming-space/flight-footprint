import 'dart:ui' as ui;

import 'package:flight_footprint/features/map/map.dart';
import 'package:flight_footprint/features/map/map_projection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _empty = GeoJsonMapData(polygons: []);
const _bundle = GeoJsonMapBundle(
  land: _empty,
  countries: _empty,
  provinces: _empty,
  nationalBoundary: _empty,
  internalBoundaries: _empty,
  maritimeMarks: _empty,
);

const _from = MapAirport(
  code: 'PVG',
  name: 'Shanghai',
  latitude: 31.1443,
  longitude: 121.8083,
);
const _to = MapAirport(
  code: 'LHR',
  name: 'London',
  latitude: 51.47,
  longitude: -0.4543,
);
const _route = MapRoute(from: _from, to: _to);

void main() {
  test('precomputed Miller viewport preserves projection results', () {
    const size = Size(812, 375);
    final viewport = MillerCylindricalProjection.viewportForSize(
      size,
      horizontalPadding: 20,
      verticalPadding: 18,
      minLatitude: -62,
      maxLatitude: 85,
    );
    final cached = viewport.toOffset(31.1443, 121.8083);
    final direct = MillerCylindricalProjection.toOffset(
      31.1443,
      121.8083,
      size,
      horizontalPadding: 20,
      verticalPadding: 18,
      minLatitude: -62,
      maxLatitude: 85,
    );

    expect(cached.dx, closeTo(direct.dx, 1e-10));
    expect(cached.dy, closeTo(direct.dy, 1e-10));
    expect(
      viewport.worldPixelWidth,
      closeTo(
        MillerCylindricalProjection.worldPixelWidthForSize(
          size,
          horizontalPadding: 20,
          verticalPadding: 18,
          minLatitude: -62,
          maxLatitude: 85,
        ),
        1e-10,
      ),
    );
  });

  test(
    'wrapped route painter records and draws without changing hit tests',
    () {
      final painter = FlatMapPainter(
        data: _bundle,
        airports: const [_from, _to],
        routes: const [_route],
        horizontalWrap: true,
        routeRevealProgress: 1,
      );
      const size = Size(700, 350);
      final recorder = ui.PictureRecorder();
      painter.paint(Canvas(recorder), size);
      final picture = recorder.endRecording();
      picture.dispose();

      final point = painter.project(_to.latitude, _to.longitude, size);
      final cycle = MillerCylindricalProjection.worldPixelWidthForSize(size);
      expect(
        painter
            .selectionAt(point + Offset(cycle, 0), size)
            ?.airports
            .single
            .code,
        'LHR',
      );
    },
  );

  testWidgets('fullscreen keeps one stable deduplicated route list', (
    tester,
  ) async {
    Widget app(double width) => MaterialApp(
      home: SizedBox(
        width: width,
        child: const MapFullscreenPage(
          mode: MapMode.flight,
          airports: [_from, _to],
          routes: [_route, _route],
          places: [],
          restoreWindowOnDispose: false,
        ),
      ),
    );

    await tester.pumpWidget(app(390));
    final first = tester.widget<OfflineMap>(find.byType(OfflineMap)).routes;
    expect(first, hasLength(1));

    await tester.pumpWidget(app(700));
    final rebuilt = tester.widget<OfflineMap>(find.byType(OfflineMap)).routes;
    expect(identical(first, rebuilt), isTrue);
  });
}
