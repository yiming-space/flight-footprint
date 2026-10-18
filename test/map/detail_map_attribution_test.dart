import 'package:flight_footprint/core/localization/app_strings.dart';
import 'package:flight_footprint/features/map/detail_map_attribution.dart';
import 'package:flight_footprint/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final light in [false, true]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'quiet corner credit stays readable and tappable light=$light scale=$scale',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(390, 844);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          await tester.pumpWidget(
            MaterialApp(
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
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: const Scaffold(
                body: Stack(children: [DetailMapAttribution(bottomOffset: 92)]),
              ),
            ),
          );
          final credit = find.text('© OpenMapTiles · © OpenStreetMap');
          final button = tester.widget<TextButton>(find.byType(TextButton));
          expect(
            button.style!.backgroundColor!.resolve({}),
            Colors.transparent,
          );
          expect(button.style!.shape!.resolve({}), isNot(isA<StadiumBorder>()));
          expect(tester.widget<Text>(credit).style!.fontSize, 9);
          final rect = tester.getRect(find.byType(TextButton));
          expect(rect.left, 8);
          expect(rect.bottom, 752);
          expect(rect.height, greaterThanOrEqualTo(44));
          expect(tester.getRect(credit).right, lessThanOrEqualTo(382));
          expect(tester.takeException(), isNull);
          await tester.tap(credit);
          await tester.pumpAndSettle();
          expect(find.text('OpenFreeMap'), findsOneWidget);
          expect(find.text('© OpenMapTiles'), findsOneWidget);
          expect(find.text('© OpenStreetMap contributors'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
