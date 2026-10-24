import 'dart:io';
import 'dart:ui' as ui;

import 'package:flight_footprint/core/localization/app_strings.dart';
import 'package:flight_footprint/features/stats/flight_passport_card.dart';
import 'package:flight_footprint/features/map/geojson_map_data.dart';
import 'package:flight_footprint/ui/theme/app_theme.dart';
import 'package:flight_footprint/ui/widgets/app_page_background.dart';
import 'package:flight_footprint/ui/widgets/frosted_glass_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host({bool light = true, bool highContrast = false}) => MaterialApp(
  theme: light ? AppTheme.light() : AppTheme.dark(),
  locale: const Locale('zh'),
  supportedLocales: AppStrings.supportedLocales,
  localizationsDelegates: const [
    AppStringsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(highContrast: highContrast),
    child: child!,
  ),
  home: AppPageBackground(
    child: Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.only(left: 20, top: 60),
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 320,
            child: FlightPassportCard(
              year: 2026,
              travellerName: 'TRAVELER',
              distanceKm: 12000,
              flightTimeMinutes: 600,
              flightCount: 4,
              airportCount: 3,
              routeCount: 2,
              countryCodes: const [],
              airports: const [],
              routes: const [],
            ),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => const GeoJsonMapLoader().loadBundle());
  testWidgets('both passport themes use the shared card glass treatment', (
    tester,
  ) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    final glass = tester.widget<FrostedGlassSurface>(
      find.byKey(const ValueKey('passport-frosted-glass')),
    );
    expect(glass.refractionRadius, AppRadii.large.topLeft.x);
    expect(find.textContaining('12,000', findRichText: true), findsOneWidget);
    final filter = find.descendant(
      of: find.byType(FrostedGlassSurface),
      matching: find.byType(BackdropFilter),
    );
    expect(tester.widget<BackdropFilter>(filter).enabled, isTrue);
    await tester.pumpWidget(_host(light: false));
    await tester.pumpAndSettle();
    expect(find.byType(FrostedGlassSurface), findsOneWidget);
    expect(find.textContaining('12,000', findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('high contrast keeps readable content without backdrop blur', (
    tester,
  ) async {
    await tester.pumpWidget(_host(highContrast: true));
    await tester.pumpAndSettle();
    final filter = tester.widget<BackdropFilter>(find.byType(BackdropFilter));
    expect(filter.enabled, isFalse);
    expect(find.textContaining('12,000', findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final light in [true, false]) {
    testWidgets(
      'sharing ${light ? "light" : "dark"} glass captures an opaque interior and rounded corners',
      (tester) async {
        final temporary = Directory.systemTemp.createTempSync(
          'passport-glass-',
        );
        const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
        const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        String? sharedPath;
        messenger.setMockMethodCallHandler(
          pathChannel,
          (_) async => temporary.path,
        );
        messenger.setMockMethodCallHandler(shareChannel, (call) async {
          sharedPath =
              ((call.arguments as Map)['paths'] as List).single as String;
          return '';
        });
        addTearDown(() async {
          messenger.setMockMethodCallHandler(pathChannel, null);
          messenger.setMockMethodCallHandler(shareChannel, null);
          temporary.deleteSync(recursive: true);
        });
        await tester.pumpWidget(_host(light: light));
        await tester.pumpAndSettle();
        await tester.longPress(find.byType(FlightPassportCard));
        await tester.pumpAndSettle();
        await tester.tap(find.text('分享图片'));
        await tester.pumpAndSettle();
        for (var i = 0; i < 30 && sharedPath == null; i++) {
          await tester.pump();
          await tester.runAsync(() async {
            await Future<void>.delayed(const Duration(milliseconds: 20));
          });
        }
        await tester.pumpAndSettle();
        expect(
          sharedPath,
          isNotNull,
          reason: tester
              .widgetList<Text>(find.byType(Text))
              .map((text) => text.data)
              .join(' | '),
        );
        await tester.runAsync(() async {
          final bytes = await File(sharedPath!).readAsBytes();
          final codec = await ui.instantiateImageCodec(bytes);
          final image = (await codec.getNextFrame()).image;
          try {
            expect(image.width, 960);
            expect(image.height, 1280);
            final rgba = (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!;
            final interiorAlpha = rgba.getUint8(
              (image.width * 800 + 30) * 4 + 3,
            );
            expect(interiorAlpha, 255);
            expect(rgba.getUint8(3), 0);
          } finally {
            image.dispose();
            codec.dispose();
          }
        });
        expect(tester.takeException(), isNull);
      },
    );
  }
}
