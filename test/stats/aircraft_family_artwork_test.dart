import 'dart:io';
import 'dart:ui' as ui;

import 'package:flight_footprint/core/localization/app_strings.dart';
import 'package:flight_footprint/features/stats/aircraft_artwork.dart';
import 'package:flight_footprint/features/stats/aircraft_collection.dart';
import 'package:flight_footprint/features/stats/aircraft_collection_page.dart';
import 'package:flight_footprint/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final review in [
    (
      name: 'eight mainstream family assets load on light and dark surfaces',
      types: const [
        'A320NEO',
        'A220-300',
        'B747-400',
        'B757-200',
        'B767-300ER',
        'C919',
        'C909',
        'E190',
      ],
      height: 2360.0,
      capturePath: '.impeccable/review/aircraft-family-mainstream-20261016.png',
    ),
    (
      name: 'four core family assets load on light and dark surfaces',
      types: const ['A330', 'A321', 'A320', 'B737'],
      height: 1220.0,
      capturePath: '.impeccable/review/aircraft-family-core-20261018.png',
    ),
  ]) {
    testWidgets(review.name, (tester) async {
      const capture = bool.fromEnvironment('AIRCRAFT_CAPTURE_REVIEW');
      if (capture) {
        await tester.runAsync(() async {
          final bytes = await File(
            '/System/Library/Fonts/Supplemental/Arial.ttf',
          ).readAsBytes();
          final font = FontLoader('AircraftReview')
            ..addFont(Future.value(ByteData.sublistView(bytes)));
          await font.load();
        });
      }
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(1200, review.height);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final types = review.types;
      final entries = [
        for (final type in types)
          AircraftCollectionEntry(
            key: type,
            type: type,
            manufacturer: AircraftManufacturer.other,
            flights: const [],
          ),
      ];
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('en'),
          supportedLocales: AppStrings.supportedLocales,
          localizationsDelegates: const [
            AppStringsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: RepaintBoundary(
            key: boundaryKey,
            child: Scaffold(
              backgroundColor: const Color(0xff10161a),
              body: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Mainstream families | pure side profile',
                      style: TextStyle(
                        fontFamily: capture ? 'AircraftReview' : null,
                        fontSize: 28,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 12),
                    for (final entry in entries) ...[
                      Text(
                        entry.type,
                        style: const TextStyle(
                          fontFamily: capture ? 'AircraftReview' : null,
                          fontSize: 20,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 213,
                        child: Row(
                          children: [
                            for (final light in [false, true]) ...[
                              Expanded(
                                child: ColoredBox(
                                  color: light
                                      ? const Color(0xfff4f4f0)
                                      : const Color(0xff161d23),
                                  child: Theme(
                                    data: light
                                        ? AppTheme.light()
                                        : AppTheme.dark(),
                                    child: AircraftExhibitArtwork(
                                      entry: entry,
                                      useHero: false,
                                      aspectRatio: 2.7,
                                    ),
                                  ),
                                ),
                              ),
                              if (!light) const SizedBox(width: 12),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      Object? imageLoadError;
      await tester.runAsync(() async {
        await Future.wait([
          for (final type in types)
            precacheImage(
              AssetImage(aircraftArtworkAssetFor(type)!),
              boundaryKey.currentContext!,
              onError: (error, stack) => imageLoadError = error,
            ),
        ]);
      });
      await tester.pumpAndSettle();
      expect(imageLoadError, isNull);
      expect(find.byType(Image), findsNWidgets(types.length * 2));
      expect(
        tester
            .widgetList<RawImage>(find.byType(RawImage))
            .where((image) => image.image != null),
        hasLength(types.length * 2),
        reason: 'Verify decoded frames, not only Image widget declarations',
      );
      for (final type in types) {
        final asset = aircraftArtworkAssetFor(type);
        expect(asset, isNotNull);
        final images = tester.widgetList<Image>(
          find.byKey(ValueKey('aircraft-art-$type')),
        );
        expect(images, hasLength(2));
        expect(
          images.every(
            (image) =>
                image.image is AssetImage &&
                (image.image as AssetImage).assetName == asset,
          ),
          isTrue,
        );
        expect(
          find.byKey(ValueKey('aircraft-art-fallback-$type')),
          findsNothing,
        );
      }
      expect(tester.takeException(), isNull);
      if (capture) {
        await tester.runAsync(() async {
          final boundary =
              boundaryKey.currentContext!.findRenderObject()
                  as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(review.capturePath)
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    });
  }
}
