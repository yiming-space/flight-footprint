import 'dart:typed_data';

import 'package:flight_footprint/ui/widgets/airline_logo_palette.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Color? dominant(List<List<int>> pixels) => airlineLogoDominantColor(
    Uint8List.fromList(pixels.expand((pixel) => pixel).toList()),
    width: pixels.length,
    height: 1,
  );

  test('rejects white, gray, very dark and transparent pixels', () {
    expect(
      dominant([
        [255, 255, 255, 255],
        [120, 120, 120, 255],
        [15, 0, 0, 255],
        [0, 0, 255, 0],
      ]),
      isNull,
    );
  });

  test('extracts colored logo pixels instead of white background', () {
    expect(
      dominant([
        for (var i = 0; i < 20; i++) [255, 255, 255, 255],
        [220, 30, 40, 255],
        [220, 30, 40, 255],
      ]),
      const Color(0xFFDC1E28),
    );
  });

  test('selects dominant hue group rather than blending unrelated hues', () {
    final result = dominant([
      [230, 20, 25, 255],
      [220, 30, 30, 255],
      [210, 20, 25, 255],
      [10, 50, 240, 255],
    ]);
    expect(result, isNotNull);
    expect(
      HSVColor.fromColor(result!).hue,
      anyOf(lessThan(10), greaterThan(350)),
    );
  });

  test('handles malformed buffers and bounded sampling of large images', () {
    expect(airlineLogoDominantColor(Uint8List(2), width: 1, height: 1), isNull);
    expect(airlineLogoDominantColor(Uint8List(0), width: 0, height: 5), isNull);
    final rgba = Uint8List.fromList([
      for (var i = 0; i < 10000; i++) ...[20, 80, 220, 255],
    ]);
    expect(
      airlineLogoDominantColor(rgba, width: 10000, height: 1),
      const Color(0xFF1450DC),
    );
  });
}
