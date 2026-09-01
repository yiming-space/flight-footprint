import 'package:flutter_test/flutter_test.dart';
import 'package:flight_footprint/features/map/map_models.dart';
import 'package:flight_footprint/features/stats/route_viewport_policy.dart';

void main() {
  MapAirport airport(String code, double latitude, double longitude) =>
      MapAirport(
        code: code,
        name: code,
        latitude: latitude,
        longitude: longitude,
      );

  MapRoute route(MapAirport from, MapAirport to) =>
      MapRoute(from: from, to: to);

  test('intercontinental routes use a complete north-up world view', () {
    final policy = RouteViewportPolicy.fromRoutes([
      route(airport('HKG', 22.3, 114.2), airport('JFK', 40.6, -73.8)),
    ]);

    expect(policy.usesWorldView, isTrue);
    expect(policy.fitToData, isFalse);
    expect(policy.angle, 0);
    expect(policy.fitZoomMultiplier, 1);
  });

  test('regional routes keep data fitting available', () {
    final policy = RouteViewportPolicy.fromRoutes([
      route(airport('HKG', 22.3, 114.2), airport('NRT', 35.8, 140.4)),
      route(airport('NRT', 35.8, 140.4), airport('ICN', 37.5, 126.4)),
    ]);

    expect(policy.usesWorldView, isFalse);
    expect(policy.fitToData, isTrue);
    expect(policy.angle.abs(), lessThanOrEqualTo(3.141592653589793 / 10));
  });
}
