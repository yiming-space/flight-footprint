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
    List<MapPlace> places = const [],
  }) {
    // A travel-footprint globe has a data-dependent glow mask, so keep that
    // surface local to the current fullscreen scene instead of caching a
    // stale set of visited regions.
    if (places.any((place) => place.isVisited)) {
      return _load(land, places);
    }
    return _cache[land] ??= _load(land, places);
  }

  static Future<GlobeSurface> _load(
    GeoJsonMapData land,
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
      ..strokeWidth = .65;
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
      canvas.drawPath(path, coast);
    }
    final picture = recorder.endRecording();
    try {
      final atlas = await picture.toImage(width.toInt(), height.toInt());
      final visitMask = await _buildVisitMask(places, width, height);
      return GlobeSurface._(atlas, visitMask, program);
    } finally {
      picture.dispose();
    }
  }

  static Future<ui.Image> _buildVisitMask(
    List<MapPlace> places,
    double width,
    double height,
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawColor(const ui.Color(0x00000000), ui.BlendMode.src);
    for (final place in places) {
      if (!place.isVisited) continue;
      final x = (place.longitude + 180) / 360 * width;
      final y = (90 - place.latitude) / 180 * height;
      final radius = 28 + place.visits.clamp(1, 8) * 3.0;
      final paint = ui.Paint()
        ..shader = ui.Gradient.radial(
          ui.Offset(x, y),
          radius,
          const [
            ui.Color(0xd8ffffff),
            ui.Color(0x60ffffff),
            ui.Color(0x00ffffff),
          ],
          const [0.0, .22, 1.0],
        );
      for (final shiftedX in [x - width, x, x + width]) {
        canvas.drawCircle(ui.Offset(shiftedX, y), radius, paint);
      }
    }
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(width.toInt(), height.toInt());
    } finally {
      picture.dispose();
    }
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
