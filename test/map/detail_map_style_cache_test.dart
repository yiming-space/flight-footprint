import 'dart:convert';
import 'dart:io';

import 'package:flight_footprint/features/map/detail_map_style.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late Directory directory;
  const filename = 'detail-map-style-v1.json';
  final style = {'version': 8, 'layers': <Object>[]};

  setUp(() async {
    DetailMapStyleLoader.clearMemoryCacheForTesting();
    directory = await Directory.systemTemp.createTemp('detail-map-cache-test-');
  });
  tearDown(() async {
    DetailMapStyleLoader.clearMemoryCacheForTesting();
    await directory.delete(recursive: true);
  });

  test(
    'loads validated local style without network after a fresh process',
    () async {
      await File('${directory.path}/$filename')
          .writeAsString(jsonEncode(style));
      var requests = 0;
      final loader = DetailMapStyleLoader(
        cacheDirectory: () async => directory,
        client: MockClient((_) async {
          requests++;
          return http.Response('', 500);
        }),
      );
      expect(await loader.load(), style);
      expect(requests, 0);
    },
  );

  test('invalid cache falls back to a network style', () async {
    await File('${directory.path}/$filename').writeAsString('{invalid');
    var requests = 0;
    final loader = DetailMapStyleLoader(
      cacheDirectory: () async => directory,
      client: MockClient((_) async {
        requests++;
        return http.Response(jsonEncode(style), 200);
      }),
    );
    expect(await loader.load(), style);
    expect(requests, 1);
    // Wait for the asynchronous cache write before removing the directory.
    for (var i = 0; i < 30; i++) {
      if (await File('${directory.path}/$filename').readAsString() ==
          jsonEncode(style)) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  });
}
