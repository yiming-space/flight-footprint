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
