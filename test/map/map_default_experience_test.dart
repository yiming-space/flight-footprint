import 'package:flight_footprint/app/app_controller.dart';
import 'package:flight_footprint/core/localization/app_strings.dart';
import 'package:flight_footprint/domain/flight.dart';
import 'package:flight_footprint/domain/visited_place.dart';
import 'package:flight_footprint/features/home/home_page.dart';
import 'package:flight_footprint/features/map/detail_map.dart';
import 'package:flight_footprint/features/map/map_explorer_controls.dart';
import 'package:flight_footprint/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class _Controller extends ChangeNotifier implements AppController {
  @override
  List<Flight> get flights => const [];
  @override
  List<VisitedPlace> get visitedPlaces => const [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app(Widget child) => MaterialApp(
  theme: AppTheme.dark(),
  locale: const Locale('zh'),
  supportedLocales: AppStrings.supportedLocales,
  localizationsDelegates: const [
    AppStringsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: Scaffold(body: child),
);

void main() {
  testWidgets('home defaults to detailed flat map without a basemap toggle', (
    tester,
  ) async {
    final controller = _Controller();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(HomePage(controller: controller)));
    await tester.pump();
    expect(find.byType(DetailMap), findsOneWidget);
    expect(find.byIcon(Icons.layers_outlined), findsNothing);
    expect(find.byIcon(Icons.layers_rounded), findsNothing);
    expect(find.byIcon(Icons.flight_rounded), findsWidgets);
    expect(find.byIcon(Icons.map_outlined), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final globe in [false, true]) {
    testWidgets(
      'fullscreen controls keep projection, reset and add place in globe=$globe',
      (tester) async {
        bool? chosen;
        var resets = 0;
        await tester.pumpWidget(
          _app(
            MapExplorerControls(
              globeMode: globe,
              landscape: false,
              onModeChanged: (value) => chosen = value,
              onOrientation: null,
              onReset: () => resets++,
              onAddPlace: () {},
            ),
          ),
        );
        expect(find.byIcon(Icons.layers_outlined), findsNothing);
        expect(find.text('离线底图'), findsNothing);
        expect(find.byIcon(Icons.add_location_alt_outlined), findsOneWidget);
        await tester.tap(find.byIcon(Icons.public_rounded));
        expect(chosen, isTrue);
        await tester.tap(find.byIcon(Icons.map_outlined));
        expect(chosen, isFalse);
        await tester.tap(find.byIcon(Icons.center_focus_strong_rounded));
        expect(resets, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
