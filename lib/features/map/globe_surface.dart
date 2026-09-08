import 'dart:ui' as ui;

import 'package:flutter/services.dart';

import 'geojson_map_data.dart';
import 'map_models.dart';

/// One offline, equirectangular atlas shared by globe views. Rasterizing in
/// geographic space avoids horizon closure chords and polygon fill seams.
class GlobeSurface {
  GlobeSurface._(this.atlas, this.visitMask, this.landMask, this.program);

  final ui.Image atlas;
  final ui.Image visitMask;
  final ui.Image landMask;
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
    const width = 2048.0;
    const height = 1024.0;
    // NASA Black Marble is resized offline. The vector mask preserves a
    // controllable ocean palette without adding another texture sampler.
    final atlas = await _loadRasterAtlas();
    final landMask = await _buildLandMask(land, width, height);
    final visitMask = await _buildVisitMask(countries, places, width, height);
    return GlobeSurface._(atlas, visitMask, landMask, program);
  }

  static Future<ui.Image> _loadRasterAtlas() async {
    final data = await rootBundle.load('assets/data/earth-night.jpg');
    final codec = await ui.instantiateImageCodec(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      targetWidth: 2048,
      targetHeight: 1024,
    );
    try {
      final frame = await codec.getNextFrame();
      return frame.image;
    } finally {
      codec.dispose();
    }
  }

  static Future<ui.Image> _buildLandMask(
    GeoJsonMapData land,
    double width,
    double height,
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawColor(const ui.Color(0xff000000), ui.BlendMode.src);
    final fill = ui.Paint()..color = const ui.Color(0xffffffff);
    for (final polygon in land.polygons) {
      canvas.drawPath(_atlasPath(polygon, width, height), fill);
    }
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(width.toInt(), height.toInt());
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

  static ui.Path _atlasPath(MapPolygon polygon, double width, double height) {
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
      for (
        var index = 0, previous = ring.length - 1;
        index < ring.length;
        previous = index++
      ) {
        final currentPoint = ring[index];
        final previousPoint = ring[previous];
        final currentLongitude = currentPoint[0];
        final currentLatitude = currentPoint[1];
        final previousLongitude = previousPoint[0];
        final previousLatitude = previousPoint[1];
        final crossesLatitude =
            (currentLatitude > latitude) != (previousLatitude > latitude);
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
    ..setImageSampler(1, visitMask)
    ..setImageSampler(2, landMask);

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
