import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flight_footprint/features/map/map.dart';
import 'package:flight_footprint/features/map/map_projection.dart';

void main() {
  test('switching projections retains center and horizontal extent', () {
    for (final size in [const Size(390, 800), const Size(780, 400)]) {
      final projection = MillerCylindricalProjection.viewportForSize(size);
      for (final center in [
        const MapCoordinate(0, 0),
        const MapCoordinate(35.6, 139.7),
        const MapCoordinate(78, -179.5),
        const MapCoordinate(-70, 179.5),
      ]) {
        for (final zoom in [0.0, 3.0, 8.0, 17.0]) {
          final original = MapCamera(center, zoom);
          var camera = original;
          for (var i = 0; i < 25; i++) {
            camera = MapCamera.fromOffline(
              projection,
              camera.toOffline(projection),
            );
          }
          expect(camera.matches(original), isTrue);
          final scale = camera.toOffline(projection).storage[0];
          expect(
            projection.worldPixelWidth * scale,
            closeTo(512 * (1 << zoom.toInt()), 1e-7),
          );
        }
      }
    }
  });

  test('orientation changes retain the geographic camera', () {
    const camera = MapCamera(MapCoordinate(31.2, 121.5), 7);
    final portrait = MillerCylindricalProjection.viewportForSize(
      const Size(390, 800),
    );
    final landscape = MillerCylindricalProjection.viewportForSize(
      const Size(800, 390),
    );
    final restored = MapCamera.fromOffline(
      landscape,
      MapCamera.fromOffline(
        portrait,
        camera.toOffline(portrait),
      ).toOffline(landscape),
    );
    expect(restored.matches(camera), isTrue);
  });
}
