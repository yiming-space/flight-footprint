import 'dart:math' as math;

import '../map/map_models.dart';

/// Chooses the initial camera treatment for the passport map.
///
/// A regional route network benefits from a small, data-led rotation and a
/// tighter fit. Once the data becomes intercontinental, a local fit is no
/// longer a reliable composition: it can push another continent off the card
/// and makes north-up geography harder to read. In that case the policy keeps
/// the complete world in view and disables rotation.
class RouteViewportPolicy {
  const RouteViewportPolicy({
    required this.angle,
    required this.fitZoomMultiplier,
    required this.fitToData,
  });

  static const _defaultFitZoomMultiplier = .94;
  static const _worldFitZoomMultiplier = 1.0;
  static const _maxAngle = math.pi / 10; // 18 degrees

  // A route around this length is a useful data-only proxy for a
  // transcontinental or transoceanic flight. It catches cases such as
  // Europe–Asia and North America–Europe without requiring a second geography
  // dataset in the share-card renderer.
  static const _intercontinentalDistanceKm = 4000.0;

  // These two fallbacks cover a broad network made from many shorter routes.
  // Longitude uses the smallest circular envelope, so routes near the date
  // line are measured as a compact group rather than as a false world span.
  static const _worldLongitudeSpan = 150.0;
  static const _worldLatitudeSpan = 65.0;

  final double angle;
  final double fitZoomMultiplier;
  final bool fitToData;

  /// Whether the complete world viewport should be used instead of a local
  /// airport fit.
  bool get usesWorldView => !fitToData;

  factory RouteViewportPolicy.fromRoutes(List<MapRoute> routes) {
    if (_needsWorldView(routes)) {
      return const RouteViewportPolicy(
        angle: 0,
        fitZoomMultiplier: _worldFitZoomMultiplier,
        fitToData: false,
      );
    }

    final points = <_RoutePoint>[];
    for (final route in routes) {
      final fromLatitude = route.from.latitude * math.pi / 180;
      final toLatitude = route.to.latitude * math.pi / 180;
      points.add(
        _RoutePoint(
          route.from.longitude * math.cos(fromLatitude),
          -route.from.latitude,
        ),
      );
      points.add(
        _RoutePoint(
          route.to.longitude * math.cos(toLatitude),
          -route.to.latitude,
        ),
      );
    }
    if (points.length < 4) return _default();

    final center =
        points.fold<_RoutePoint>(
          const _RoutePoint(0, 0),
          (sum, point) => sum + point,
        ) /
        points.length.toDouble();
    var xx = 0.0;
    var yy = 0.0;
    var xy = 0.0;
    for (final point in points) {
      final dx = point.x - center.x;
      final dy = point.y - center.y;
      xx += dx * dx;
      yy += dy * dy;
      xy += dx * dy;
    }
    final covarianceScale = 1 / points.length;
    xx *= covarianceScale;
    yy *= covarianceScale;
    xy *= covarianceScale;
    final spread = xx + yy;
    if (spread < .0001) return _default();

    final discriminant = math.sqrt(math.pow(xx - yy, 2) + 4 * xy * xy);
    final major = (spread + discriminant) / 2;
    final minor = math.max(.0001, (spread - discriminant) / 2);
    final anisotropy = major / minor;
    if (anisotropy < 1.45) return _default();

    var angle = -.5 * math.atan2(2 * xy, xx - yy);
    while (angle > math.pi / 2) {
      angle -= math.pi;
    }
    while (angle < -math.pi / 2) {
      angle += math.pi;
    }
    if (angle.abs() > _maxAngle) return _default();

    final confidence = ((anisotropy - 1.45) / 2.2).clamp(0.0, 1.0);
    angle *= confidence;
    return RouteViewportPolicy(
      angle: angle,
      // Rotating a fitted viewport exposes the corners sooner. The extra
      // margin keeps route endpoints and decorative arcs inside the map.
      fitZoomMultiplier: _defaultFitZoomMultiplier - confidence * .04,
      fitToData: true,
    );
  }

  static RouteViewportPolicy _default() => const RouteViewportPolicy(
    angle: 0,
    fitZoomMultiplier: _defaultFitZoomMultiplier,
    fitToData: true,
  );

  static bool _needsWorldView(List<MapRoute> routes) {
    if (routes.isEmpty) return false;

    final longitudes = <double>[];
    final latitudes = <double>[];
    var longestRouteKm = 0.0;
    for (final route in routes) {
      longitudes
        ..add(route.from.longitude)
        ..add(route.to.longitude);
      latitudes
        ..add(route.from.latitude)
        ..add(route.to.latitude);
      longestRouteKm = math.max(
        longestRouteKm,
        _greatCircleDistanceKm(route.from, route.to),
      );
    }

    if (longestRouteKm >= _intercontinentalDistanceKm) return true;

    final latitudeSpan =
        latitudes.reduce(math.max) - latitudes.reduce(math.min);
    if (latitudeSpan >= _worldLatitudeSpan) return true;

    return _minimalLongitudeSpan(longitudes) >= _worldLongitudeSpan;
  }

  static double _minimalLongitudeSpan(List<double> longitudes) {
    if (longitudes.length < 2) return 0;
    final normalized =
        longitudes.map((longitude) => ((longitude % 360) + 360) % 360).toList()
          ..sort();
    var largestGap = 0.0;
    for (var index = 0; index < normalized.length; index++) {
      final next = index == normalized.length - 1
          ? normalized.first + 360
          : normalized[index + 1];
      largestGap = math.max(largestGap, next - normalized[index]);
    }
    return 360 - largestGap;
  }

  static double _greatCircleDistanceKm(MapAirport from, MapAirport to) {
    double radians(double value) => value * math.pi / 180;

    final lat1 = radians(from.latitude);
    final lat2 = radians(to.latitude);
    final deltaLatitude = lat2 - lat1;
    final deltaLongitude = radians(to.longitude - from.longitude);
    final haversine =
        math.pow(math.sin(deltaLatitude / 2), 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.pow(math.sin(deltaLongitude / 2), 2);
    final angularDistance =
        2 * math.asin(math.sqrt(haversine.clamp(0.0, 1.0).toDouble()));
    return 6371.0088 * angularDistance;
  }
}

class _RoutePoint {
  const _RoutePoint(this.x, this.y);

  final double x;
  final double y;

  _RoutePoint operator +(_RoutePoint other) =>
      _RoutePoint(x + other.x, y + other.y);

  _RoutePoint operator /(double value) => _RoutePoint(x / value, y / value);
}
