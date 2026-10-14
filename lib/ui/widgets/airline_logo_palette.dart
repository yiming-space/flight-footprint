import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/painting.dart';

/// Finds the strongest colored hue in raw RGBA pixels, not the white plate.
/// Work is bounded to 1,024 evenly distributed samples regardless of size.
Color? airlineLogoDominantColor(
  Uint8List rgba, {
  required int width,
  required int height,
}) {
  if (width <= 0 || height <= 0 || rgba.length < width * height * 4) {
    return null;
  }
  final buckets = List.generate(24, (_) => _HueBucket());
  final pixelCount = width * height;
  final samples = math.min(pixelCount, 1024);
  for (var sample = 0; sample < samples; sample++) {
    final offset = ((sample + .5) * pixelCount / samples).floor() * 4;
    final alpha = rgba[offset + 3];
    if (alpha < 128) continue;
    final red = rgba[offset];
    final green = rgba[offset + 1];
    final blue = rgba[offset + 2];
    final color = HSVColor.fromColor(Color.fromARGB(255, red, green, blue));
    // Transparent edges, paper, black lettering and grayscale are not useful
    // brand hues. The remaining strongest hue controls the tonal row fill.
    if (color.value < .20 || color.saturation < .22) continue;
    final bucket = buckets[((color.hue + 7.5) % 360 / 15).floor()];
    final weight = color.saturation * alpha / 255;
    bucket.weight += weight;
    bucket.red += red * weight;
    bucket.green += green * weight;
    bucket.blue += blue * weight;
  }
  final strongest = buckets.reduce(
    (left, right) => left.weight >= right.weight ? left : right,
  );
  if (strongest.weight == 0) return null;
  return Color.fromARGB(
    255,
    (strongest.red / strongest.weight).round().clamp(0, 255),
    (strongest.green / strongest.weight).round().clamp(0, 255),
    (strongest.blue / strongest.weight).round().clamp(0, 255),
  );
}

class _HueBucket {
  double weight = 0;
  double red = 0;
  double green = 0;
  double blue = 0;
}
