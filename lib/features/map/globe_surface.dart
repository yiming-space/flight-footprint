import 'dart:ui' as ui;

import 'geojson_map_data.dart';
import 'map_models.dart';

/// One offline, equirectangular atlas shared by globe views. Rasterizing in
/// geographic space avoids horizon closure chords and polygon fill seams.
class GlobeSurface {
  GlobeSurface._(this.atlas, this.visitMask, this.program);

  final ui.Image atlas;
  final ui.Image visitMask;
  final ui.FragmentProgram program;
  static final _cache = Expando<Future<GlobeSurface>>();

  static Future<GlobeSurface> load(
    GeoJsonMapData land, {
    required GeoJsonMapData countries,
    List<MapPlace> places = const [],
  }) {
    // A travel-footprint globe has a data-dependent visited-country mask, so
    // keep that surface local to the current fullscreen scene instead of
    // caching a stale set of visited regions.
    if (places.any((place) => place.isVisited)) {
      return _load(land, countries, places);
    }
    return _cache[land] ??= _load(land, countries, places);
  }

  static Future<GlobeSurface> _load(
    GeoJsonMapData land,
    GeoJsonMapData countries,
    List<MapPlace> places,
  ) async {
    final program = await ui.FragmentProgram.fromAsset(
      'shaders/globe_surface.frag',
    );
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    const width = 2048.0;
    const height = 1024.0;
    // Reuse the flat map's dark palette, but lift the globe's ocean one step
    // above the app background. The sphere needs a readable blue atmosphere
    // around its coastlines instead of collapsing into near-black.
    canvas.drawColor(const ui.Color(0xff132b43), ui.BlendMode.src);
    final fill = ui.Paint()..color = const ui.Color(0xff233b52);
    final coast = ui.Paint()
      ..color = const ui.Color(0xff7e9fba)
      ..style = ui.PaintingStyle.stroke
      // Keep coastlines and country boundaries subordinate to the routes.
      ..strokeWidth = .45;
    final countryBoundary = ui.Paint()
      ..color = const ui.Color(0x996d8da4)
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = .35;
    // The bundled Natural Earth land is already split at the date line.
    // Keep those geographic rings intact, including holes and polar edges.
    for (final polygon in land.polygons) {
      final path = ui.Path()..fillType = ui.PathFillType.evenOdd;
      for (final ring in polygon.rings) {
        if (ring.length < 3) continue;
        for (var i = 0; i < ring.length; i++) {
          final x = (ring[i][0] + 180) / 360 * width;
          final y = (90 - ring[i][1]) / 180 * height;
          if (i == 0) {
            path.moveTo(x, y);
          } else {
            path.lineTo(x, y);
          }
        }
        path.close();
      }
      canvas.drawPath(path, fill);
    }
    // Country polygons are rendered into the same equirectangular atlas as
    // the land fill, so the shader applies the globe projection to both
    // layers together. Draw coastlines afterwards to keep the outer edge
    // crisp where a country boundary meets the ocean.
    for (final polygon in countries.polygons) {
      final path = ui.Path()..fillType = ui.PathFillType.evenOdd;
      for (final ring in polygon.rings) {
        if (ring.length < 3) continue;
        for (var i = 0; i < ring.length; i++) {
          final x = (ring[i][0] + 180) / 360 * width;
          final y = (90 - ring[i][1]) / 180 * height;
          if (i == 0) {
            path.moveTo(x, y);
          } else {
            path.lineTo(x, y);
          }
        }
        path.close();
      }
      canvas.drawPath(path, countryBoundary);
    }
    for (final polygon in land.polygons) {
      final path = ui.Path()..fillType = ui.PathFillType.evenOdd;
      for (final ring in polygon.rings) {
        if (ring.length < 3) continue;
        for (var i = 0; i < ring.length; i++) {
          final x = (ring[i][0] + 180) / 360 * width;
          final y = (90 - ring[i][1]) / 180 * height;
          if (i == 0) {
            path.moveTo(x, y);
          } else {
            path.lineTo(x, y);
          }
        }
        path.close();
      }
      canvas.drawPath(path, coast);
    }
    final picture = recorder.endRecording();
    try {
      final atlas = await picture.toImage(width.toInt(), height.toInt());
      final visitMask = await _buildVisitMask(
        countries,
        places,
        width,
        height,
      );
      return GlobeSurface._(atlas, visitMask, program);
    } finally {
      picture.dispose();
    }
  }

  static Future<ui.Image> _buildVisitMask(
    GeoJsonMapData countries,
    List<MapPlace> places,
    double width,
    double height,
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawColor(const ui.Color(0x00000000), ui.BlendMode.src);
    final visitedPaint = ui.Paint()..color = const ui.Color(0xffffffff);
    for (final polygon in countries.polygons) {
      if (!_containsVisitedPlace(polygon, places)) continue;
      canvas.drawPath(_atlasPath(polygon, width, height), visitedPaint);
    }
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(width.toInt(), height.toInt());
    } finally {
      picture.dispose();
    }
  }

  static ui.Path _atlasPath(
    MapPolygon polygon,
    double width,
    double height,
  ) {
    final path = ui.Path()..fillType = ui.PathFillType.evenOdd;
    for (final ring in polygon.rings) {
      if (ring.length < 3) continue;
      for (var i = 0; i < ring.length; i++) {
        final x = (ring[i][0] + 180) / 360 * width;
        final y = (90 - ring[i][1]) / 180 * height;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      path.close();
    }
    return path;
  }

  static bool _containsVisitedPlace(
    MapPolygon polygon,
    List<MapPlace> places,
  ) => places.any(
    (place) =>
        place.isVisited &&
        _containsPolygonPoint(polygon, place.longitude, place.latitude),
  );

  static bool _containsPolygonPoint(
    MapPolygon polygon,
    double longitude,
    double latitude,
  ) {
    var inside = false;
    for (final ring in polygon.rings) {
      for (var index = 0, previous = ring.length - 1;
          index < ring.length;
          previous = index++) {
        final currentPoint = ring[index];
        final previousPoint = ring[previous];
        final currentLongitude = currentPoint[0];
        final currentLatitude = currentPoint[1];
        final previousLongitude = previousPoint[0];
        final previousLatitude = previousPoint[1];
        final crossesLatitude =
            (currentLatitude > latitude) !=
            (previousLatitude > latitude);
        if (!crossesLatitude) continue;
        final crossingLongitude =
            (previousLongitude - currentLongitude) *
                (latitude - currentLatitude) /
                (previousLatitude - currentLatitude) +
            currentLongitude;
        if (longitude < crossingLongitude) inside = !inside;
      }
    }
    return inside;
  }

  ui.FragmentShader createShader() => program.fragmentShader()
    ..setImageSampler(0, atlas)
    ..setImageSampler(1, visitMask);

  static void paint(
    ui.Canvas canvas, {
    required ui.FragmentShader shader,
    required ui.Offset center,
    required double radius,
    required double yaw,
    required double pitch,
  }) {
    shader
      ..setFloat(0, center.dx)
      ..setFloat(1, center.dy)
      ..setFloat(2, radius)
      ..setFloat(3, yaw)
      ..setFloat(4, pitch);
    canvas.drawRect(
      ui.Rect.fromCircle(center: center, radius: radius),
      ui.Paint()..shader = shader,
    );
  }
}
