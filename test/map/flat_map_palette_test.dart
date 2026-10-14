import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flight_footprint/features/map/map.dart';
import 'package:flight_footprint/ui/theme/app_theme.dart';

const _empty = GeoJsonMapData(polygons: []);
const _bundle = GeoJsonMapBundle(
  land: GeoJsonMapData(
    polygons: [
      MapPolygon([
        [
          [-30, -20],
          [30, -20],
          [30, 20],
          [-30, 20],
          [-30, -20],
        ],
      ]),
    ],
  ),
  countries: _empty,
  provinces: _empty,
  nationalBoundary: _empty,
  internalBoundaries: _empty,
  maritimeMarks: _empty,
);

void main() {
  testWidgets('offline light and dark land and sea share detailed-map colors', (
    tester,
  ) async {
    await tester.runAsync(() async {
      for (final light in [false, true]) {
        final painter = FlatMapPainter(
          data: _bundle,
          lightPalette: light,
          showGrid: false,
        );
        const size = Size(400, 240);
        final recorder = ui.PictureRecorder();
        painter.paint(Canvas(recorder), size);
        final picture = recorder.endRecording();
        final image = await picture.toImage(400, 240);
        final pixels = (await image.toByteData())!;
        Color colorAt(double longitude) {
          final point = painter.project(0, longitude, size);
          final offset = (point.dy.floor() * 400 + point.dx.floor()) * 4;
          return Color.fromARGB(
            pixels.getUint8(offset + 3),
            pixels.getUint8(offset),
            pixels.getUint8(offset + 1),
            pixels.getUint8(offset + 2),
          );
        }

        expect(
          colorAt(0),
          light ? AppThemeColors.light.surface : AppColors.detailMapNightLand,
        );
        expect(
          colorAt(100),
          light ? AppThemeColors.light.iceTint : AppColors.detailMapNightWater,
        );
        image.dispose();
        picture.dispose();
      }
    });
  });

  testWidgets('visited countries and provinces share one solid theme fill', (
    tester,
  ) async {
    const country = MapPolygon([
      [
        [-80, -20],
        [-40, -20],
        [-40, 20],
        [-80, 20],
        [-80, -20],
      ],
    ]);
    const province = MapPolygon([
      [
        [80, -20],
        [120, -20],
        [120, 20],
        [80, 20],
        [80, -20],
      ],
    ]);
    const unvisited = MapPolygon([
      [
        [-20, -20],
        [20, -20],
        [20, 20],
        [-20, 20],
        [-20, -20],
      ],
    ]);
    const bundle = GeoJsonMapBundle(
      land: GeoJsonMapData(polygons: [country, province, unvisited]),
      countries: GeoJsonMapData(polygons: [country, province, unvisited]),
      // Deliberate overlap checks that repeated geometry cannot darken a fill.
      provinces: GeoJsonMapData(polygons: [province, province]),
      nationalBoundary: _empty,
      internalBoundaries: _empty,
      maritimeMarks: _empty,
    );
    const places = [
      MapPlace(
        name: 'Visited country',
        latitude: 0,
        longitude: -60,
        countryCode: 'US',
      ),
      MapPlace(
        name: 'Visited province',
        latitude: 0,
        longitude: 100,
        countryCode: 'CN',
      ),
    ];
    await tester.runAsync(() async {
      for (final light in [false, true]) {
        for (final mode in [MapMode.travelFootprint, MapMode.flight]) {
          final painter = FlatMapPainter(
            data: bundle,
            places: places,
            mode: mode,
            lightPalette: light,
            showGrid: false,
          );
          const size = Size(800, 480);
          final recorder = ui.PictureRecorder();
          painter.paint(Canvas(recorder), size);
          final picture = recorder.endRecording();
          final image = await picture.toImage(800, 480);
          final pixels = (await image.toByteData())!;
          Color colorAt(double latitude, double longitude) {
            final point = painter.project(latitude, longitude, size);
            final offset = (point.dy.floor() * 800 + point.dx.floor()) * 4;
            return Color.fromARGB(
              pixels.getUint8(offset + 3),
              pixels.getUint8(offset),
              pixels.getUint8(offset + 1),
              pixels.getUint8(offset + 2),
            );
          }

          final land = light
              ? AppThemeColors.light.surface
              : AppColors.detailMapNightLand;
          final region = light
              ? const Color(0xFFCDD3F0)
              : const Color(0xFF65734F);
          final expected = mode == MapMode.travelFootprint ? region : land;
          expect(colorAt(10, -70), expected);
          expect(colorAt(10, 90), expected);
          expect(
            colorAt(10, 0),
            land,
            reason: 'Unvisited land must not change.',
          );
          if (mode == MapMode.travelFootprint) {
            expect(
              colorAt(0, -60),
              light ? const Color(0xFF78A2D2) : AppColors.lime,
              reason: 'Keep the existing city marker color.',
            );
          }
          image.dispose();
          picture.dispose();
        }
      }
    });
  });
}
