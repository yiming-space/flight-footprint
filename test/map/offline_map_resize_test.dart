import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flight_footprint/features/map/map.dart';
import 'package:flight_footprint/features/map/map_projection.dart';

const _land = GeoJsonMapData(
  polygons: [
    MapPolygon([
      [
        [-160, -60],
        [160, -60],
        [160, 75],
        [-160, 75],
        [-160, -60],
      ],
    ]),
  ],
);
const _empty = GeoJsonMapData(polygons: []);
const _bundle = GeoJsonMapBundle(
  land: _land,
  countries: _land,
  provinces: _empty,
  nationalBoundary: _empty,
  internalBoundaries: _empty,
  maritimeMarks: _empty,
);

class _Loader extends GeoJsonMapLoader {
  const _Loader();
  @override
  Future<GeoJsonMapBundle> loadBundle() async => _bundle;
}

const _airports = [
  MapAirport(code: 'LHR', name: 'London', latitude: 51, longitude: 0),
  MapAirport(code: 'HND', name: 'Tokyo', latitude: 35, longitude: 140),
];

void main() {
  testWidgets('restores an online camera instead of fitting all records', (
    tester,
  ) async {
    MapCamera? reported;
    const desired = MapCamera(MapCoordinate(35.6, 139.7), 9);
    Future<void> show(MapCamera camera, {Key? key}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 390,
            height: 300,
            child: OfflineMap(
              key: key,
              loader: const _Loader(),
              airports: _airports,
              initialCamera: camera,
              onCameraChanged: (value) => reported = value,
              coverViewport: true,
              horizontalWrap: true,
              enableInteraction: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    await show(desired);
    expect(reported?.matches(desired), isTrue);
    // A newly mounted offline map must also restore after returning online.
    await show(desired, key: const ValueKey('remounted'));
    expect(reported?.matches(desired), isTrue);
    const moved = MapCamera(MapCoordinate(-33.8, 151.2), 5);
    await show(moved, key: const ValueKey('remounted'));
    expect(reported?.matches(moved), isTrue);
    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    await tester.drag(find.byType(InteractiveViewer), const Offset(40, 10));
    await tester.pumpAndSettle();
    expect(reported?.matches(moved), isFalse);
    final panned = reported!;
    final matrix = Matrix4.copy(viewer.transformationController!.value);
    // Echoing the current camera on an unrelated parent rebuild must not refit.
    await show(panned, key: const ValueKey('remounted'));
    expect(viewer.transformationController!.value.storage, matrix.storage);
  });

  testWidgets(
    'preview applies fit and returns to the same camera after resize',
    (tester) async {
      Future<void> show(double width, {Key? key}) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                height: 300,
                child: OfflineMap(
                  key: key,
                  loader: const _Loader(),
                  airports: _airports,
                  coverViewport: true,
                  fillViewportHeight: true,
                  horizontalWrap: width >= 600,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }

      Matrix4 camera() => tester
          .widget<Transform>(
            find
                .descendant(
                  of: find.byType(OfflineMap),
                  matching: find.byType(Transform),
                )
                .first,
          )
          .transform;
      await show(390);
      final narrow = Matrix4.copy(camera());
      expect(
        narrow,
        isNot(Matrix4.identity()),
        reason: 'First fit must reach the displayed Transform',
      );
      await show(780);
      expect(camera(), isNot(narrow));
      await show(390);
      expect(
        camera().storage,
        orderedEquals(narrow.storage),
        reason:
            'Returning from fullscreen must not retain the wide preview matrix',
      );
      await show(780);
      final wide = Matrix4.copy(camera());
      await show(780, key: const ValueKey('fresh'));
      expect(
        camera().storage,
        orderedEquals(wide.storage),
        reason: 'A resized map must agree with a fresh map at the same bounds',
      );
    },
  );

  testWidgets('tap on a transformed airport selects the visible marker', (
    tester,
  ) async {
    MapSelection? selection;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 390,
            height: 300,
            child: OfflineMap(
              loader: const _Loader(),
              airports: _airports,
              coverViewport: true,
              onSelection: (s) => selection = s,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final painting = find.descendant(
      of: find.byType(OfflineMap),
      matching: find.byWidgetPredicate(
        (w) =>
            w is CustomPaint &&
            w.painter is FlatMapPainter &&
            (w.painter! as FlatMapPainter).paintLayer ==
                FlatMapPaintLayer.overlay,
      ),
    );
    final painter =
        tester.widget<CustomPaint>(painting).painter! as FlatMapPainter;
    final box = tester.renderObject<RenderBox>(painting);
    final point = painter.project(35, 140, box.size);
    await tester.tapAt(box.localToGlobal(point));
    await tester.pump();
    expect(selection?.airports.first.code, 'HND');
    expect(tester.takeException(), isNull);
  });

  test(
    'wrapped airport hits match across the date line; empty space stays empty',
    () {
      final painter = FlatMapPainter(
        data: _bundle,
        airports: _airports,
        horizontalWrap: true,
      );
      const size = Size(700, 350);
      final point = painter.project(35, 140, size);
      final cycle = MillerCylindricalProjection.worldPixelWidthForSize(
        size,
        horizontalPadding: 16,
        verticalPadding: 14,
      );
      expect(
        painter
            .selectionAt(point + Offset(cycle, 0), size)
            ?.airports
            .first
            .code,
        'HND',
      );
      expect(painter.selectionAt(const Offset(350, -300), size), isNull);
    },
  );
}
