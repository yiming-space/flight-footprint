import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A projected point in the Equal Earth coordinate space.
///
/// The values are deliberately kept independent of pixels. This lets the
/// painter, the interaction hit-test, and the initial viewport fit use the
/// exact same projection at every device size.
class MapProjectionPoint {
  const MapProjectionPoint(this.x, this.y);

  final double x;
  final double y;
}

/// The finite projected extent of a complete world in a pseudocylindrical
/// projection.
class MapProjectionBounds {
  const MapProjectionBounds({
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
  });

  final double minX;
  final double maxX;
  final double minY;
  final double maxY;

  double get width => maxX - minX;
  double get height => maxY - minY;
  double get centerX => (minX + maxX) / 2;
  double get centerY => (minY + maxY) / 2;
}

/// Equal Earth projection for the offline world map.
///
/// Equal Earth is an equal-area, pseudocylindrical world projection. It is a
/// better global composition for this app than a sphere-like projection: the
/// whole world remains planar, high latitudes keep a natural visual weight,
/// and the continents do not get squeezed into a narrow horizontal strip.
/// The coefficients below are the standard Equal Earth constants from the
/// original projection definition.
class EqualEarthProjection {
  EqualEarthProjection._();

  static const double _a1 = 1.340264;
  static const double _a2 = -0.081106;
  static const double _a3 = 0.000893;
  static const double _a4 = 0.003796;
  static const double _m = 0.8660254037844386; // sqrt(3) / 2
  static const double _degreesToRadians = math.pi / 180;

  static final double _maxTheta = math.asin(_m);
  static final double _maxY = _y(_maxTheta);
  static final double _maxX = math.pi / (_m * _a1);

  /// Complete-world projected bounds. Longitude ±180° and latitude ±90° are
  /// included, so this is also the interaction floor for a full-screen map.
  static final MapProjectionBounds worldBounds = MapProjectionBounds(
    minX: -_maxX,
    maxX: _maxX,
    minY: -_maxY,
    maxY: _maxY,
  );

  /// Projects geographic coordinates to Equal Earth coordinates.
  ///
  /// Longitude is intentionally not normalized. Great-circle route samples
  /// are unwrapped before projection so a date-line crossing remains one
  /// continuous route rather than jumping across the map.
  static MapProjectionPoint project(double latitude, double longitude) {
    final phi = latitude.clamp(-90.0, 90.0).toDouble() * _degreesToRadians;
    final lambda = longitude * _degreesToRadians;
    final theta = math.asin(_m * math.sin(phi));
    final theta2 = theta * theta;
    final denominator =
        _m *
        (_a1 +
            3 * _a2 * theta2 +
            math.pow(theta, 6) * (7 * _a3 + 9 * _a4 * theta2));
    final x = lambda * math.cos(theta) / denominator;
    final y = _y(theta);
    return MapProjectionPoint(x, y);
  }

  /// Projects directly to a canvas-sized offset with a small breathing room
  /// around the complete world. North is up, matching Flutter's y-axis.
  static Offset toOffset(
    double latitude,
    double longitude,
    Size size, {
    double horizontalPadding = 16,
    double verticalPadding = 14,
  }) {
    final scale = scaleForSize(
      size,
      horizontalPadding: horizontalPadding,
      verticalPadding: verticalPadding,
    );
    final point = project(latitude, longitude);
    return Offset(
      size.width / 2 + (point.x - worldBounds.centerX) * scale,
      size.height / 2 - (point.y - worldBounds.centerY) * scale,
    );
  }

  /// Returns the pixels per projected unit while keeping the complete world
  /// visible. A portrait viewport therefore keeps intentional side gutters
  /// instead of distorting or cropping the continents.
  static double scaleForSize(
    Size size, {
    double horizontalPadding = 16,
    double verticalPadding = 14,
  }) {
    final width = math.max(1.0, size.width - horizontalPadding);
    final height = math.max(1.0, size.height - verticalPadding);
    return math.min(width / worldBounds.width, height / worldBounds.height);
  }

  static double _y(double theta) =>
      _a1 * theta +
      _a2 * math.pow(theta, 3) +
      _a3 * math.pow(theta, 7) +
      _a4 * math.pow(theta, 9);
}

/// Robinson projection for the global map composition.
///
/// Robinson is a visually balanced compromise projection: it avoids the
/// polar squeeze of equirectangular maps without the bowl-shaped edges that a
/// regional conic projection creates when it is applied to the whole world.
/// The standard 5-degree tabulation is interpolated with a smooth
/// Catmull–Rom curve so polygon edges and the graticule do not kink at table
/// rows. Longitude remains unwrapped for continuous date-line flight routes.
class RobinsonProjection {
  RobinsonProjection._();

  static const double _xScale = 0.8487;
  static const double _yScale = 1.3523;
  static const double _degreesToRadians = math.pi / 180;

  // Robinson's standard normalized x/y ordinates, sampled every 5 degrees
  // from the equator to a pole.
  static const List<double> _xTable = [
    1.0000,
    0.9986,
    0.9954,
    0.9900,
    0.9822,
    0.9730,
    0.9600,
    0.9427,
    0.9216,
    0.8962,
    0.8679,
    0.8350,
    0.7986,
    0.7597,
    0.7186,
    0.6732,
    0.6213,
    0.5722,
    0.5322,
  ];

  static const List<double> _yTable = [
    0.0000,
    0.0620,
    0.1240,
    0.1860,
    0.2480,
    0.3100,
    0.3720,
    0.4340,
    0.4958,
    0.5571,
    0.6176,
    0.6769,
    0.7346,
    0.7903,
    0.8435,
    0.8936,
    0.9394,
    0.9761,
    1.0000,
  ];

  static final MapProjectionBounds worldBounds = MapProjectionBounds(
    minX: -_xScale * math.pi,
    maxX: _xScale * math.pi,
    minY: -_yScale,
    maxY: _yScale,
  );

  static MapProjectionPoint project(double latitude, double longitude) {
    final clampedLatitude = latitude.clamp(-90.0, 90.0).toDouble();
    final normalizedLatitude = clampedLatitude.abs() / 5;
    final xOrdinate = _interpolate(_xTable, normalizedLatitude);
    final yOrdinate = _interpolate(_yTable, normalizedLatitude);
    final sign = clampedLatitude < 0 ? -1.0 : 1.0;
    return MapProjectionPoint(
      longitude * _degreesToRadians * _xScale * xOrdinate,
      sign * _yScale * yOrdinate,
    );
  }

  static Offset toOffset(
    double latitude,
    double longitude,
    Size size, {
    double horizontalPadding = 16,
    double verticalPadding = 14,
  }) {
    final scale = scaleForSize(
      size,
      horizontalPadding: horizontalPadding,
      verticalPadding: verticalPadding,
    );
    final point = project(latitude, longitude);
    return Offset(
      size.width / 2 + (point.x - worldBounds.centerX) * scale,
      size.height / 2 - (point.y - worldBounds.centerY) * scale,
    );
  }

  static double scaleForSize(
    Size size, {
    double horizontalPadding = 16,
    double verticalPadding = 14,
  }) {
    final width = math.max(1.0, size.width - horizontalPadding);
    final height = math.max(1.0, size.height - verticalPadding);
    return math.min(width / worldBounds.width, height / worldBounds.height);
  }

  static double _interpolate(List<double> table, double index) {
    if (index <= 0) return table.first;
    if (index >= table.length - 1) return table.last;
    final lower = index.floor();
    final t = index - lower;
    final p0 = table[lower == 0 ? lower : lower - 1];
    final p1 = table[lower];
    final p2 = table[lower + 1];
    final p3 = table[lower + 2 < table.length ? lower + 2 : lower + 1];
    // Catmull–Rom interpolation (centripetal spacing is unnecessary here
    // because every tabulated latitude interval is exactly five degrees).
    return .5 *
        (2 * p1 +
            (-p0 + p2) * t +
            (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t +
            (-p0 + 3 * p1 - 3 * p2 + p3) * t * t * t);
  }
}

/// Miller cylindrical projection for the app's flat world map.
///
/// Miller keeps every meridian vertical and every parallel horizontal, like
/// the reference map the user selected, while easing the severe polar stretch
/// of Mercator. Its finite pole extent also makes the complete world fit
/// predictably in both portrait and landscape full-screen views.
class MillerCylindricalProjection {
  MillerCylindricalProjection._();

  static const double _yFactor = 1.25;
  static const double _latitudeFactor = .8;
  static const double _degreesToRadians = math.pi / 180;

  /// Latitude window used by the passport artwork. The card intentionally
  /// leaves Antarctica out of its silhouette, so retaining the unused polar
  /// band would make every other continent look vertically compressed. This
  /// window keeps the whole non-Antarctic world visible while giving the map
  /// the compact, editorial proportions of the reference card.
  static const double passportMinLatitude = -62;
  static const double passportMaxLatitude = 85;

  static final double _maxY = _y(math.pi / 2);
  static final MapProjectionBounds worldBounds = MapProjectionBounds(
    minX: -math.pi,
    maxX: math.pi,
    minY: -_maxY,
    maxY: _maxY,
  );

  static MapProjectionPoint project(double latitude, double longitude) {
    final phi = latitude.clamp(-90.0, 90.0).toDouble() * _degreesToRadians;
    return MapProjectionPoint(longitude * _degreesToRadians, _y(phi));
  }

  /// Returns the projected bounds for a latitude window while preserving the
  /// complete longitude range. This is useful for compositions that omit an
  /// intentionally empty polar region without changing the projection or
  /// clipping any land at the eastern and western edges.
  static MapProjectionBounds boundsForLatitudeRange({
    required double minLatitude,
    required double maxLatitude,
  }) {
    final low = minLatitude.clamp(-90.0, 90.0).toDouble();
    final high = maxLatitude.clamp(-90.0, 90.0).toDouble();
    final south = math.min(low, high);
    final north = math.max(low, high);
    final southY = project(south, 0).y;
    final northY = project(north, 0).y;
    return MapProjectionBounds(
      minX: -math.pi,
      maxX: math.pi,
      minY: math.min(southY, northY),
      maxY: math.max(southY, northY),
    );
  }

  static Offset toOffset(
    double latitude,
    double longitude,
    Size size, {
    double horizontalPadding = 16,
    double verticalPadding = 14,
    double minLatitude = -90,
    double maxLatitude = 90,
  }) {
    final bounds = boundsForLatitudeRange(
      minLatitude: minLatitude,
      maxLatitude: maxLatitude,
    );
    final scale = scaleForSize(
      size,
      horizontalPadding: horizontalPadding,
      verticalPadding: verticalPadding,
      minLatitude: minLatitude,
      maxLatitude: maxLatitude,
    );
    final point = project(latitude, longitude);
    return Offset(
      size.width / 2 + (point.x - bounds.centerX) * scale,
      size.height / 2 - (point.y - bounds.centerY) * scale,
    );
  }

  static double scaleForSize(
    Size size, {
      double horizontalPadding = 16,
      double verticalPadding = 14,
      double minLatitude = -90,
    double maxLatitude = 90,
  }) {
    final bounds = boundsForLatitudeRange(
      minLatitude: minLatitude,
      maxLatitude: maxLatitude,
    );
    final width = math.max(1.0, size.width - horizontalPadding);
    final height = math.max(1.0, size.height - verticalPadding);
    return math.min(width / bounds.width, height / bounds.height);
  }

  /// Returns the projected width of one complete world copy in logical
  /// pixels.  Keeping this calculation next to [scaleForSize] means the
  /// painter and the interactive map use the exact same seam when wrapping a
  /// world horizontally or splitting a route at the date-line boundary.
  static double worldPixelWidthForSize(
    Size size, {
    double horizontalPadding = 16,
    double verticalPadding = 14,
    double minLatitude = -90,
    double maxLatitude = 90,
  }) {
    return boundsForLatitudeRange(
          minLatitude: minLatitude,
          maxLatitude: maxLatitude,
        ).width *
        scaleForSize(
          size,
          horizontalPadding: horizontalPadding,
          verticalPadding: verticalPadding,
          minLatitude: minLatitude,
          maxLatitude: maxLatitude,
        );
  }

  static double _y(double latitudeRadians) {
    final argument = math.pi / 4 + _latitudeFactor * latitudeRadians / 2;
    return _yFactor * math.log(math.tan(argument));
  }
}
