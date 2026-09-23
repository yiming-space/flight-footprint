import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

/// Static backdrop kept in its own repaint boundary by [GlobeMap].
///
/// The galaxy and vignette do not depend on camera movement, so rasterizing
/// this layer once prevents the full-screen background from being replayed on
/// every drag, momentum, and idle-rotation frame.
class GlobeBackdropPainter extends CustomPainter {
  const GlobeBackdropPainter({this.lightPalette = false});

  final bool lightPalette;

  @override
  void paint(Canvas canvas, Size size) {
    GalaxyBackgroundPainter(lightPalette: lightPalette).paint(canvas, size);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          colors: lightPalette
              ? const [Color(0xB8FFFDF5), Color(0xEAF6F1ED)]
              : const [Color(0x52070D16), Color(0xF8000000)],
          radius: .92,
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(covariant GlobeBackdropPainter oldDelegate) =>
      oldDelegate.lightPalette != lightPalette;
}

/// Quiet, offline starlight for painting underneath an opaque globe.
///
/// Call `const GalaxyBackgroundPainter().paint(canvas, size)` in the parent's
/// local coordinates, before painting the globe. Pictures use logical pixels;
/// stars therefore stay fine on both phones and tablets without bitmap scaling.
class GalaxyBackgroundPainter extends CustomPainter {
  const GalaxyBackgroundPainter({this.lightPalette = false});

  final bool lightPalette;

  // Retain portrait/landscape (or inline/fullscreen) without an unbounded cache.
  static final Map<bool, Map<Size, ui.Picture>> _pictures = <bool, Map<Size, ui.Picture>>{
    false: <Size, ui.Picture>{},
    true: <Size, ui.Picture>{},
  };

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || !size.width.isFinite || !size.height.isFinite) return;

    final cache = _pictures[lightPalette]!;
    var picture = cache.remove(size);
    if (picture == null) {
      final recorder = ui.PictureRecorder();
      final background = Canvas(recorder);
      background.clipRect(Offset.zero & size);
      _paintDust(background, size, lightPalette: lightPalette);
      _paintStars(background, size, lightPalette: lightPalette);
      picture = recorder.endRecording();
    }
    cache[size] = picture;
    if (cache.length > 2) {
      cache.remove(cache.keys.first)!.dispose();
    }
    canvas.drawPicture(picture);
  }

  static double _hash(int x, int y) {
    // Products stay below 2^53; bit mixing stays within 32 bits on native/web.
    var value =
        (((x & 0xffff) * 374761393) ^ ((y & 0xffff) * 668265263)) & 0x7fffffff;
    value = ((value ^ (value >> 13)) * 65599) & 0x7fffffff;
    return (value ^ (value >> 16)) / 0x7fffffff;
  }

  static double _noise(double x, double y) {
    final ix = x.floor();
    final iy = y.floor();
    final fx = x - ix;
    final fy = y - iy;
    final sx = fx * fx * (3 - 2 * fx);
    final sy = fy * fy * (3 - 2 * fy);
    final top = _hash(ix, iy) * (1 - sx) + _hash(ix + 1, iy) * sx;
    final bottom = _hash(ix, iy + 1) * (1 - sx) + _hash(ix + 1, iy + 1) * sx;
    return top * (1 - sy) + bottom * sy;
  }

  static double _texture(double x, double y) =>
      _noise(x, y) * 0.55 +
      _noise(x * 2.07 + 31, y * 2.07 + 17) * 0.29 +
      _noise(x * 4.13 + 73, y * 4.13 + 49) * 0.16;

  // The diagonal is defined in isotropic coordinates, not stretched UV space.
  static double _across(double x, double y) =>
      x * 0.57 + y * 0.82 + 0.09 * math.sin((x * 0.82 - y * 0.57) * 3);

  static double _bell(double distance, double width) {
    final normalized = distance / width;
    return math.exp(-normalized * normalized);
  }

  static void _paintDust(
    Canvas canvas,
    Size size, {
    required bool lightPalette,
  }) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..color = lightPalette
            ? const Color(0xfff6f1ed)
            : const Color(0xff000000),
    );

    // One opaque, interpolated mesh: soft detail without layers, blur, or seams.
    // Bounded at 16,641 vertices, with more samples on larger logical canvases.
    final columns = (size.width / 8).ceil().clamp(2, 128);
    final rows = (size.height / 8).ceil().clamp(2, 128);
    final count = (columns + 1) * (rows + 1);
    final positions = Float32List(count * 2);
    final colors = Int32List(count);
    final indices = Uint16List(columns * rows * 6);
    final unit = size.shortestSide;

    for (var row = 0; row <= rows; row++) {
      for (var column = 0; column <= columns; column++) {
        final index = row * (columns + 1) + column;
        final px = size.width * column / columns;
        final py = size.height * row / rows;
        positions[index * 2] = px;
        positions[index * 2 + 1] = py;
        final x = (px - size.width * 0.5) / unit;
        final y = (py - size.height * 0.5) / unit;
        final along = x * 0.82 - y * 0.57;
        final across = _across(x, y);
        final clouds = _texture(along * 4 + 51, across * 11 + 29);
        final grain = _texture(along * 13 + 11, across * 27 + 83);
        final width = 0.15 + 0.075 * _noise(along * 3 + 19, 7);
        final veil = _bell(across, width * 1.8);
        final band = _bell(across + (clouds - 0.5) * 0.12, width);
        final laneCenter = 0.026 + (clouds - 0.5) * 0.10;
        final lane = _bell(across - laneCenter, 0.025 + clouds * 0.018);
        final light =
            band *
            (0.18 + clouds * 0.82) *
            (0.58 + grain * 0.42) *
            (1 - lane * 0.76);
        final lilac = _noise(along * 2 + 103, across * 5 + 41);
        final red = lightPalette
            ? (227 + veil * 4 + light * (12 + lilac * 5)).round()
            : (4 + veil * 2 + light * (20 + lilac * 10)).round();
        final green = lightPalette
            ? (233 + veil * 4 + light * (13 - lilac * 3)).round()
            : (10 + veil * 3 + light * (31 - lilac * 5)).round();
        final blue = lightPalette
            ? (237 + veil * 5 + light * (14 + lilac * 5)).round()
            : (12 + veil * 5 + light * (31 + lilac * 7)).round();
        colors[index] = (0xff << 24) | (red << 16) | (green << 8) | blue;
      }
    }

    var cursor = 0;
    for (var row = 0; row < rows; row++) {
      for (var column = 0; column < columns; column++) {
        final top = row * (columns + 1) + column;
        final bottom = top + columns + 1;
        indices[cursor++] = top;
        indices[cursor++] = bottom;
        indices[cursor++] = top + 1;
        indices[cursor++] = top + 1;
        indices[cursor++] = bottom;
        indices[cursor++] = bottom + 1;
      }
    }
    canvas.drawVertices(
      ui.Vertices.raw(
        ui.VertexMode.triangles,
        positions,
        colors: colors,
        indices: indices,
      ),
      BlendMode.srcOver,
      Paint(),
    );
  }

  static void _paintStars(
    Canvas canvas,
    Size size, {
    required bool lightPalette,
  }) {
    final random = math.Random(0x47a1a9);
    final unit = size.shortestSide;
    final area = size.width * size.height;
    // Keep the field visibly populated outside the Milky Way band as well.
    // This is recorded once per viewport size, so the denser sky stays cheap
    // during globe rotation and gestures.
    final count = (area / 56).round().clamp(1600, 14000);
    final groups = List<List<Offset>>.generate(4, (_) => <Offset>[]);

    // Rejection sampling leaves a dense, irregular band and quiet outer space.
    // All random work happens once when recording a new size.
    for (var index = 0; index < count; index++) {
      final point = Offset(
        random.nextDouble() * size.width,
        random.nextDouble() * size.height,
      );
      final x = (point.dx - size.width * 0.5) / unit;
      final y = (point.dy - size.height * 0.5) / unit;
      final across = _across(x, y);
      final density =
          0.22 +
          0.78 *
              _bell(across, 0.22) *
              (0.58 + 0.42 * _noise(x * 9 + 47, y * 9 + 13));
      if (random.nextDouble() > density) continue;
      final brightness = random.nextDouble();
      final group = brightness < 0.65
          ? 0
          : brightness < 0.90
          ? 1
          : brightness < 0.97
          ? 2
          : 3;
      groups[group].add(point);
    }

    final colors = lightPalette
        ? const <Color>[
            Color(0x24929db1),
            Color(0x3a7f8aa0),
            Color(0x4d68758d),
            Color(0x5f596680),
          ]
        : const <Color>[
            Color(0x6d7d8799),
            Color(0x9b9aa8bb),
            Color(0xbfc0cede),
            Color(0xdceaf2fb),
          ];
    const widths = <double>[0.50, 0.65, 0.85, 1.05];
    final paint = Paint()..strokeCap = StrokeCap.round;
    for (var group = 0; group < groups.length; group++) {
      paint
        ..color = colors[group]
        ..strokeWidth = widths[group];
      canvas.drawPoints(ui.PointMode.points, groups[group], paint);
    }

    // A handful of brighter suns, with minute soft shoulders and no starbursts.
    final brightCount = (area / 25000).round().clamp(8, 38);
    for (var index = 0; index < brightCount; index++) {
      final point = Offset(
        random.nextDouble() * size.width,
        random.nextDouble() * size.height,
      );
      final warm = random.nextDouble() < 0.35;
      final tint = lightPalette
          ? const Color(0xff6f7d9a)
          : warm
          ? const Color(0xffecd8b9)
          : const Color(0xffb6a9e8);
      final radius = 0.45 + random.nextDouble() * 0.25;
      canvas.drawCircle(
        point,
        radius * 2.4,
        Paint()..color = tint.withAlpha(lightPalette ? 7 : 12),
      );
      canvas.drawCircle(
        point,
        radius * 1.5,
        Paint()..color = tint.withAlpha(lightPalette ? 16 : 30),
      );
      canvas.drawCircle(
        point,
        radius,
        Paint()..color = tint.withAlpha(lightPalette ? 90 : 190),
      );
    }
  }

  @override
  bool shouldRepaint(covariant GalaxyBackgroundPainter oldDelegate) =>
      oldDelegate.lightPalette != lightPalette;
}
