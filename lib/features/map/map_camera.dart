import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'map_models.dart';
import 'map_projection.dart';

/// A geographic camera shared by the offline Miller and online Mercator maps.
/// Zoom uses MapLibre's 512-logical-pixel world at zoom zero. Matching longitude
/// scale keeps the same horizontal extent without accumulating conversion drift.
@immutable
class MapCamera {
  const MapCamera(this.center, this.zoom);

  final MapCoordinate center;
  final double zoom;

  factory MapCamera.fromOffline(
    MillerProjectionViewport projection,
    Matrix4 transform,
  ) {
    // The unused Z axis stays at 1, so getMaxScaleOnAxis is incorrect when
    // the two-dimensional world is zoomed below scale 1.
    final scale = transform.storage[0].abs();
    final scene = MatrixUtils.transformPoint(
      Matrix4.inverted(transform),
      projection.size.center(Offset.zero),
    );
    final x =
        projection.bounds.centerX +
        (scene.dx - projection.size.width / 2) / projection.scale;
    final y =
        projection.bounds.centerY -
        (scene.dy - projection.size.height / 2) / projection.scale;
    final latitude =
        (2 * math.atan(math.exp(y / 1.25)) - math.pi / 2) / .8 * 180 / math.pi;
    final longitude = (x * 180 / math.pi + 180) % 360 - 180;
    return MapCamera(
      MapCoordinate(latitude.clamp(-85.051129, 85.051129), longitude),
      math.log(projection.worldPixelWidth * scale / 512) / math.ln2,
    );
  }

  double offlineScale(MillerProjectionViewport projection) =>
      512 * math.pow(2, zoom) / projection.worldPixelWidth;

  Matrix4 toOffline(MillerProjectionViewport projection) {
    final point = projection.toOffset(center.latitude, center.longitude);
    final scale = offlineScale(projection);
    return Matrix4.identity()
      ..translateByDouble(
        projection.size.width / 2,
        projection.size.height / 2,
        0,
        1,
      )
      ..scaleByDouble(scale, scale, 1, 1)
      ..translateByDouble(-point.dx, -point.dy, 0, 1);
  }

  bool matches(MapCamera? other) =>
      other != null &&
      (center.latitude - other.center.latitude).abs() < 1e-7 &&
      ((center.longitude - other.center.longitude + 180) % 360 - 180).abs() <
          1e-7 &&
      (zoom - other.zoom).abs() < 1e-7;
}

typedef DetailMapCamera = MapCamera;
