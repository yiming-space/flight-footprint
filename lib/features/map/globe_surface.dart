import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/services.dart';

import 'geojson_map_data.dart';

/// Approximate subsolar point calculated from the current UTC time.
///
/// This is deliberately kept local and deterministic: the globe remains
/// useful offline while the day/night boundary follows the real sun.
class SolarPosition {
  const SolarPosition({required this.x, required this.y, required this.z});

  final double x;
  final double y;
  final double z;

  factory SolarPosition.now() => SolarPosition.fromUtc(DateTime.now().toUtc());

  factory SolarPosition.fromUtc(DateTime utc) {
    final dayOfYear = utc.difference(DateTime.utc(utc.year, 1, 1)).inDays + 1;
    final utcMinutes =
        utc.hour * 60 + utc.minute + utc.second / 60 + utc.millisecond / 60000;
    final gamma =
        2 * math.pi / 365 * (dayOfYear - 1 + (utcMinutes / 60 - 12) / 24);
    final declination =
        0.006918 -
        0.399912 * math.cos(gamma) +
        0.070257 * math.sin(gamma) -
        0.006758 * math.cos(2 * gamma) +
        0.000907 * math.sin(2 * gamma) -
        0.002697 * math.cos(3 * gamma) +
        0.001480 * math.sin(3 * gamma);
    final equationOfTime =
        229.18 *
        (0.000075 +
            0.001868 * math.cos(gamma) -
            0.032077 * math.sin(gamma) -
            0.014615 * math.cos(2 * gamma) -
            0.040849 * math.sin(2 * gamma));
    var longitude = (720 - utcMinutes - equationOfTime) / 4;
    while (longitude > 180) longitude -= 360;
    while (longitude < -180) longitude += 360;
    final cosDeclination = math.cos(declination);
    return SolarPosition(
      x: cosDeclination * math.sin(longitude * math.pi / 180),
      y: math.sin(declination),
      z: cosDeclination * math.cos(longitude * math.pi / 180),
    );
  }
}

/// One offline, equirectangular atlas shared by globe views. Rasterizing in
/// geographic space avoids horizon closure chords and polygon fill seams.
class GlobeSurface {
  GlobeSurface._(this.atlas, this.landMask, this.program);

  /// Night and day atlases are stacked vertically in one image. Keeping one
  /// color sampler for both surfaces avoids sampler-limit differences between
  /// Android GPU backends.
  final ui.Image atlas;
  final ui.Image landMask;
  final ui.FragmentProgram program;
  static const _atlasWidth = 2560;
  static const _atlasHeight = 1280;
  static final _cache = Expando<Future<GlobeSurface>>();
  static final _landMaskCache = Expando<Future<ui.Image>>();
  static Future<ui.FragmentProgram>? _programFuture;
  static Future<ui.Image>? _nightAtlasFuture;
  static Future<ui.Image>? _dayAtlasFuture;
  static Future<ui.Image>? _combinedAtlasFuture;

  static Future<GlobeSurface> load(GeoJsonMapData land) =>
      _cache[land] ??= _load(land);

  static Future<GlobeSurface> _load(GeoJsonMapData land) async {
    // Keep masks at 2K to limit GPU memory; the higher-resolution color atlas
    // carries the extra detail users see in the globe's terrain and night side.
    const width = 2048.0;
    const height = 1024.0;
    // Both atlases are resized offline. The vector mask preserves a
    // controllable ocean palette while the shader blends the day and night
    // surfaces around the real solar terminator.
    final program = await (_programFuture ??= ui.FragmentProgram.fromAsset(
      'shaders/globe_surface.frag',
    ));
    final nightAtlas = await (_nightAtlasFuture ??= _loadRasterAtlas(
      'assets/data/earth-night.jpg',
    ));
    final dayAtlas = await (_dayAtlasFuture ??= _loadRasterAtlas(
      'assets/data/natural-earth-ii.jpg',
    ));
    final atlas = await (_combinedAtlasFuture ??= _combineAtlases(
      nightAtlas,
      dayAtlas,
    ));
    final landMask = await (_landMaskCache[land] ??= _buildLandMask(
      land,
      width,
      height,
    ));
    return GlobeSurface._(atlas, landMask, program);
  }

  static Future<ui.Image> _combineAtlases(
    ui.Image nightAtlas,
    ui.Image dayAtlas,
  ) async {
    final width = math.min(nightAtlas.width, dayAtlas.width);
    final height = math.min(nightAtlas.height, dayAtlas.height);
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final target = ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
    canvas.drawImageRect(nightAtlas, target, target, ui.Paint());
    final dayTarget = ui.Rect.fromLTWH(
      0,
      height.toDouble(),
      width.toDouble(),
      height.toDouble(),
    );
    canvas.drawImageRect(dayAtlas, target, dayTarget, ui.Paint());
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(width, height * 2);
    } finally {
      picture.dispose();
    }
  }

  static Future<ui.Image> _loadRasterAtlas(String assetPath) async {
    final data = await rootBundle.load(assetPath);
    final codec = await ui.instantiateImageCodec(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      targetWidth: _atlasWidth,
      targetHeight: _atlasHeight,
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

  ui.FragmentShader createShader() => program.fragmentShader()
    ..setImageSampler(0, atlas)
    ..setImageSampler(1, landMask);

  static void paint(
    ui.Canvas canvas, {
    required ui.FragmentShader shader,
    required ui.Offset center,
    required double radius,
    required double yaw,
    required double pitch,
    required SolarPosition solarPosition,
  }) {
    final yawCos = math.cos(yaw);
    final yawSin = math.sin(yaw);
    final pitchCos = math.cos(pitch);
    final pitchSin = math.sin(pitch);
    shader
      ..setFloat(0, center.dx)
      ..setFloat(1, center.dy)
      ..setFloat(2, radius)
      ..setFloat(3, yawCos)
      ..setFloat(4, yawSin)
      ..setFloat(5, pitchCos)
      ..setFloat(6, pitchSin)
      ..setFloat(7, solarPosition.x)
      ..setFloat(8, solarPosition.y)
      ..setFloat(9, solarPosition.z);
    canvas.drawRect(
      ui.Rect.fromCircle(center: center, radius: radius),
      ui.Paint()..shader = shader,
    );
  }
}
