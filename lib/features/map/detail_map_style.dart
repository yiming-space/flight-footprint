import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../ui/theme/app_theme.dart';
import 'detail_map_footprint.dart';

/// Only the public style is requested here. Personal records stay on-device.
class DetailMapStyleLoader {
  static Map<String, dynamic>? _cached;

  Future<Map<String, dynamic>> load() async {
    if (_cached case final cached?) {
      return jsonDecode(jsonEncode(cached)) as Map<String, dynamic>;
    }
    final response = await http
        .get(Uri.parse('https://tiles.openfreemap.org/styles/positron'))
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) throw StateError('Map style unavailable');
    final style = jsonDecode(response.body) as Map<String, dynamic>;
    if (style['version'] != 8 || style['layers'] is! List) {
      throw const FormatException('Invalid map style');
    }
    _cached = style;
    return jsonDecode(jsonEncode(style)) as Map<String, dynamic>;
  }
}

String detailMapColor(Color color) =>
    '#${(color.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0')}';

/// Positron geometry, styled to match the app rather than a navigation app.
Map<String, dynamic> buildDetailMapStyle(
  Map<String, dynamic> base, {
  required bool light,
  required bool chinese,
  required Map<String, dynamic> points,
  required Map<String, dynamic> routes,
  required Map<String, dynamic> location,
  bool showRouteArrows = false,
  Map<String, dynamic> regions = emptyDetailFootprint,
  Map<String, dynamic> selectedRoute = emptyDetailFootprint,
}) {
  final colors = light ? AppThemeColors.light : AppThemeColors.dark;
  const lightLand = Color(0xfff3f8fc);
  const lightLandcover = Color(0xffe3eef6);
  const lightLabel = Color(0xff1b3346);
  const lightBoundary = Color(0xffb7cad9);
  const lightRoad = Color(0xffa9cfe8);
  final lightNode = AppColors.mapMarkerLight;
  final land = detailMapColor(light ? lightLand : AppColors.detailMapNightLand);
  final water = detailMapColor(
    light ? AppColors.detailMapLightWater : AppColors.detailMapNightWater,
  );
  final landcover = detailMapColor(
    light ? lightLandcover : AppColors.detailMapNightLandcover,
  );
  final muted = detailMapColor(
    light ? lightLabel : AppColors.detailMapNightLabel,
  );
  final edge = detailMapColor(
    light ? lightBoundary : AppColors.detailMapNightBoundary,
  );
  final layers = <Map<String, dynamic>>[];
  for (final raw in base['layers'] as List) {
    final layer = Map<String, dynamic>.from(raw as Map);
    final id = '${layer['id']}';
    final source = '${layer['source-layer']}';
    // No terrain raster or POI/shield clutter in a flight journal.
    if (layer['type'] == 'raster' || source == 'poi' || id.contains('shield')) {
      continue;
    }
    final paint = Map<String, dynamic>.from(layer['paint'] as Map? ?? {});
    if (layer['type'] == 'background') paint['background-color'] = land;
    if (layer['type'] == 'fill') {
      paint['fill-color'] = source == 'water' ? water : landcover;
      if (paint.containsKey('fill-outline-color')) {
        paint['fill-outline-color'] = edge;
      }
    }
    if (layer['type'] == 'line') {
      paint['line-color'] = source == 'waterway' && light
          ? detailMapColor(lightRoad)
          : source == 'waterway'
          ? water
          : edge;
      if (source == 'transportation') {
        layer['minzoom'] = ((layer['minzoom'] as num?) ?? 0).clamp(7, 24);
        paint['line-color'] = light
            ? detailMapColor(lightRoad)
            : detailMapColor(AppColors.detailMapNightRoad);
        paint['line-opacity'] = light ? .65 : .75;
      } else if (!light && source == 'boundary') {
        paint['line-opacity'] = .7;
      }
    }
    if (layer['type'] == 'symbol') {
      final layout = Map<String, dynamic>.from(layer['layout'] as Map? ?? {});
      if (layout.containsKey('text-field')) {
        final name = [
          'coalesce',
          if (chinese) ['get', 'name:zh-Hans'],
          ['get', chinese ? 'name:zh' : 'name:en'],
          ['get', 'name_en'],
          ['get', 'name'],
        ];
        // Some OSM names contain semicolon-separated writing variants.
        // Display one compact name rather than wrapping duplicate variants.
        layout['text-field'] = [
          'case',
          [
            '>=',
            ['index-of', ';', name],
            0,
          ],
          [
            'slice',
            name,
            0,
            ['index-of', ';', name],
          ],
          name,
        ];
      }
      layer['layout'] = layout;
      paint['text-color'] = !light && source.startsWith('water')
          ? detailMapColor(AppColors.detailMapNightWaterLabel)
          : muted;
      if (!light) paint['text-opacity'] = 1;
      paint['text-halo-color'] = land;
      paint['text-halo-width'] = light ? 1 : 1.5;
    }
    layer['paint'] = paint;
    layers.add(layer);
  }
  // Place visited fills above landcover but below water, boundaries, roads
  // and all labels. Do not rebuild the basemap or camera when records change.
  final regionLayer = <String, dynamic>{
    'id': 'ff-regions',
    'type': 'fill',
    'source': 'ff-regions',
    'maxzoom': 8,
    'paint': {
      'fill-color': detailMapColor(
        light ? AppColors.detailFootprintLight : AppColors.detailFootprintDark,
      ),
      'fill-antialias': true,
      // Bundled country geometry is overview-resolution. Fade out before
      // street scale, where coastline simplification would become apparent.
      'fill-opacity': [
        'interpolate',
        ['linear'],
        ['zoom'],
        0,
        light ? .5 : .72,
        4,
        light ? .5 : .72,
        6,
        light ? .2 : .28,
        8,
        0,
      ],
    },
  };
  final insertion = layers.indexWhere(
    (layer) => layer['type'] == 'line' || layer['type'] == 'symbol',
  );
  final waterMasks = [
    for (final layer in layers)
      if (layer['type'] == 'fill' && layer['source-layer'] == 'water')
        <String, dynamic>{...layer, 'id': 'ff-region-water-${layer['id']}'},
  ];
  layers.insertAll(insertion < 0 ? layers.length : insertion, [
    regionLayer,
    // Redraw detailed coastlines/lakes over the overview-resolution fill.
    // Native water masks keep the tint off water without raster compositing.
    ...waterMasks,
  ]);
  base['sources'] = {
    ...base['sources'] as Map,
    'ff-points': {'type': 'geojson', 'data': points},
    'ff-routes': {'type': 'geojson', 'data': routes},
    'ff-route-selection': {'type': 'geojson', 'data': selectedRoute},
    'ff-location': {'type': 'geojson', 'data': location},
    'ff-regions': {'type': 'geojson', 'data': regions},
  };
  layers.addAll([
    {
      'id': 'ff-routes',
      'type': 'line',
      'source': 'ff-routes',
      'layout': {'line-cap': 'round', 'line-join': 'round'},
      'paint': {
        'line-color': detailMapColor(
          light ? colors.displaySecondary : AppColors.routePurple,
        ),
        'line-width': [
          'interpolate',
          ['linear'],
          ['zoom'],
          0,
          1.0,
          2,
          1.15,
          5,
          1.4,
          12,
          1.65,
        ],
        'line-offset': [
          'coalesce',
          ['get', 'offset'],
          0,
        ],
        'line-opacity': light ? .9 : .62,
      },
    },
    if (showRouteArrows)
      {
        'id': 'ff-route-arrows',
        'type': 'symbol',
        'source': 'ff-routes',
        'layout': {
          'symbol-placement': 'line-center',
          'icon-image': 'ff-route-arrow',
          'icon-size': [
            'interpolate',
            ['linear'],
            ['zoom'],
            0,
            .207,
            2,
            .253,
            5,
            .345,
            12,
            .437,
          ],
          'icon-rotation-alignment': 'map',
          'icon-keep-upright': false,
          'icon-allow-overlap': true,
          'icon-ignore-placement': true,
          'icon-padding': 0,
        },
        'paint': {'icon-opacity': 1},
      },
    {
      'id': 'ff-route-selection',
      'type': 'line',
      'source': 'ff-route-selection',
      'layout': {'line-cap': 'round', 'line-join': 'round'},
      'paint': {
        'line-color': detailMapColor(
          light ? colors.displaySecondary : AppColors.routePurple,
        ),
        'line-width': 2.05,
        'line-offset': [
          'coalesce',
          ['get', 'offset'],
          0,
        ],
        'line-opacity': 1,
      },
    },
    {
      'id': 'ff-points',
      'type': 'circle',
      'source': 'ff-points',
      'paint': {
        'circle-color': light
            ? detailMapColor(lightNode)
            : detailMapColor(colors.lime),
        'circle-radius': [
          'interpolate',
          ['linear'],
          ['zoom'],
          0,
          3.4,
          2,
          3.8,
          5,
          4.5,
        ],
        'circle-stroke-width': [
          'interpolate',
          ['linear'],
          ['zoom'],
          0,
          1.0,
          5,
          1.5,
        ],
        'circle-stroke-color': land,
      },
    },
    {
      'id': 'ff-labels',
      'type': 'symbol',
      'source': 'ff-points',
      'minzoom': 4,
      'layout': {
        'text-field': ['get', 'label'],
        'text-font': ['Noto Sans Regular'],
        'text-size': 12,
        'text-offset': [0, 1.1],
        'text-anchor': 'top',
      },
      'paint': {
        'text-color': light
            ? detailMapColor(lightLabel)
            : detailMapColor(colors.textPrimary),
        'text-halo-color': land,
        'text-halo-width': 1.5,
      },
    },
    {
      'id': 'ff-location',
      'type': 'circle',
      'source': 'ff-location',
      'paint': {
        'circle-color': light ? '#347CA7' : '#B69CFF',
        'circle-radius': 6,
        'circle-stroke-width': 2.5,
        'circle-stroke-color': '#FFFFFF',
        'circle-opacity': 1,
        'circle-stroke-opacity': 1,
      },
    },
  ]);
  base['layers'] = layers;
  return base;
}
