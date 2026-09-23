import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flight_footprint/features/map/geojson_map_data.dart';
import 'package:flight_footprint/features/map/globe_map.dart';
import 'package:flight_footprint/features/map/map_models.dart';

const _emptyMapData = GeoJsonMapData(polygons: []);
const _emptyMapBundle = GeoJsonMapBundle(
  land: _emptyMapData,
  countries: _emptyMapData,
  provinces: _emptyMapData,
  nationalBoundary: _emptyMapData,
  internalBoundaries: _emptyMapData,
  maritimeMarks: _emptyMapData,
);

void main() {
  test('globe camera repaints only when a rendered value changes', () {
    final camera = GlobeCamera(
      yaw: -.35,
      pitch: .12,
      entryScale: .86,
      entryYawOffset: .2,
      entryArtworkOpacity: .4,
    );
    var notifications = 0;
    camera.addListener(() => notifications++);

    camera.update(
      yaw: -.35,
      pitch: .12,
      scale: 1,
      entryScale: .86,
      entryYawOffset: .2,
      entryArtworkOpacity: .4,
    );
    expect(notifications, 0);

    camera.update(yaw: -.2);
    expect(notifications, 1);

    camera.update(
      pitch: .2,
      entryYawOffset: .3,
      entryArtworkOpacity: .5,
      notify: false,
    );
    expect(notifications, 1);
    expect(camera.pitch, .2);
    expect(camera.entryYawOffset, .3);
    expect(camera.entryArtworkOpacity, .5);

    camera.dispose();
  });

  test('route-follow camera preserves great-circle endpoints', () {
    const from = MapAirport(code: 'AAA', name: 'A', latitude: 0, longitude: 0);
    const to = MapAirport(code: 'BBB', name: 'B', latitude: 0, longitude: 90);
    const routes = [MapRoute(from: from, to: to)];

    final start = GlobePainter.animationCameraForProgress(routes, 0);
    final end = GlobePainter.animationCameraForProgress(routes, 1);

    expect(start.yaw, closeTo(0, 1e-9));
    expect(start.pitch, closeTo(0, 1e-9));
    expect(end.yaw, closeTo(-3.141592653589793 / 2, 1e-9));
    expect(end.pitch, closeTo(0, 1e-9));
  });

  test('globe selects a visible airport and exposes its compact label', () {
    const airport = MapAirport(
      code: 'CPT',
      name: '开\n普\n敦',
      latitude: 0,
      longitude: 0,
    );
    const destination = MapAirport(
      code: 'JNB',
      name: '约翰内斯堡',
      latitude: -26,
      longitude: 28,
    );
    final painter = GlobePainter(
      data: _emptyMapBundle,
      airports: const [airport, destination],
      routes: const [MapRoute(from: airport, to: destination)],
    );

    final selection = painter.selectionAt(
      const Offset(200, 200),
      const Size(400, 400),
    );

    expect(selection?.airports.single.code, 'CPT');
    expect(painter.labelForSelection(selection!), '开普敦');
  });

  test('globe hit testing follows the temporary hero rotation', () {
    const airport = MapAirport(
      code: 'AAA',
      name: 'A',
      latitude: 0,
      longitude: 0,
    );
    const destination = MapAirport(
      code: 'BBB',
      name: 'B',
      latitude: 0,
      longitude: 90,
    );
    final camera = GlobeCamera(entryYawOffset: 1.0471975512);
    final painter = GlobePainter(
      data: _emptyMapBundle,
      airports: const [airport, destination],
      routes: const [MapRoute(from: airport, to: destination)],
      camera: camera,
    );

    final selection = painter.selectionAt(
      const Offset(335, 200),
      const Size(400, 400),
    );

    expect(selection?.airports.single.code, 'AAA');
    camera.dispose();
  });

  test('travel globe selects a visited place and exposes its name', () {
    const place = MapPlace(
      name: '东京',
      latitude: 0,
      longitude: 0,
      isVisited: true,
    );
    final painter = GlobePainter(
      data: _emptyMapBundle,
      mode: MapMode.travelFootprint,
      places: const [place],
    );

    final selection = painter.selectionAt(
      const Offset(200, 200),
      const Size(400, 400),
    );

    expect(selection?.places.single.name, '东京');
    expect(painter.labelForSelection(selection!), '东京');
  });
}
