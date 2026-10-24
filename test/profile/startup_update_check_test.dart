import 'dart:async';

import 'package:flight_footprint/app/app_controller.dart';
import 'package:flight_footprint/app/app_shell.dart';
import 'package:flight_footprint/core/localization/app_strings.dart';
import 'package:flight_footprint/data/airport_catalog.dart';
import 'package:flight_footprint/data/app_update_service.dart';
import 'package:flight_footprint/data/cloud_sync_service.dart';
import 'package:flight_footprint/domain/airport.dart';
import 'package:flight_footprint/domain/flight.dart';
import 'package:flight_footprint/domain/visited_place.dart';
import 'package:flight_footprint/features/home/home_page.dart';
import 'package:flight_footprint/features/profile/profile_page.dart';
import 'package:flight_footprint/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

class _Cloud extends ChangeNotifier implements CloudSyncService {
  @override
  CloudSyncState get state => const CloudSyncState();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Controller extends ChangeNotifier implements AppController {
  @override
  bool get isLoading => false;
  @override
  final CloudSyncService cloudSync = _Cloud();
  @override
  final AirportCatalog airports = AirportCatalog({});
  @override
  List<Flight> get flights => const [];
  @override
  List<VisitedPlace> get visitedPlaces => const [];
  @override
  ThemeMode get themeMode => ThemeMode.dark;
  @override
  Locale get locale => const Locale('zh');
  @override
  String get travellerName => 'TRAVELER';
  @override
  Airport? airportFor(String iata) => null;
  @override
  void dispose() {
    cloudSync.dispose();
    super.dispose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Updates extends AppUpdateService {
  _Updates(this.respond);
  final Future<AppUpdateResult> Function(int call) respond;
  int calls = 0;
  @override
  Future<AppUpdateResult> checkForUpdates() => respond(++calls);
}

final _available = AppUpdateResult.available(
  currentVersion: '1.3.0+16',
  latestVersion: '1.3.1',
  releaseUrl: Uri.parse('https://github.com/example/app/releases/tag/v1.3.1'),
  releaseNotes: 'Startup check fixture.',
);
const _current = AppUpdateResult.upToDate(currentVersion: '1.3.0+16');

Widget _app(
  Widget child,
  GlobalKey<NavigatorState> navigator, {
  bool highContrast = false,
}) => MaterialApp(
  navigatorKey: navigator,
  theme: AppTheme.dark(),
  locale: const Locale('zh'),
  supportedLocales: AppStrings.supportedLocales,
  localizationsDelegates: const [
    AppStringsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(context).copyWith(highContrast: highContrast),
      child: child,
    ),
  ),
);

class _Fixture {
  _Fixture(this.updates);
  final _Updates updates;
  final controller = _Controller();
  final tab = ValueNotifier(0);
  final navigator = GlobalKey<NavigatorState>();

  Future<void> mount(
    WidgetTester tester, {
    bool realShell = false,
    bool highContrast = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 1100);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      tab.dispose();
      controller.dispose();
      updates.dispose();
    });
    await tester.pumpWidget(
      _app(
        realShell
            ? AppShell(controller: controller, updateService: updates)
            : Scaffold(
                body: ValueListenableBuilder<int>(
                  valueListenable: tab,
                  builder: (context, index, _) => IndexedStack(
                    index: index,
                    children: [
                      const Center(child: Text('Home fixture')),
                      const Center(child: Text('Flights fixture')),
                      const Center(child: Text('Stats fixture')),
                      ProfilePage(
                        controller: controller,
                        isHomeActive: index == 0,
                        isActive: index == 3,
                        updateService: updates,
                      ),
                    ],
                  ),
                ),
              ),
        navigator,
        highContrast: highContrast,
      ),
    );
    await tester.pump();
  }

  Future<void> changeTab(WidgetTester tester, int index) async {
    tab.value = index;
    await tester.pumpAndSettle();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Flight Footprint',
      packageName: 'com.example.flight_footprint',
      version: '1.3.0',
      buildNumber: '16',
      buildSignature: '',
    );
  });

  testWidgets('real shell checks on home without opening Profile', (
    tester,
  ) async {
    final fixture = _Fixture(_Updates((_) async => _current));
    await fixture.mount(tester, realShell: true);
    await tester.pump();
    expect(find.byType(HomePage), findsOneWidget);
    expect(find.byType(ProfilePage), findsNothing);
    final profile = tester.widget<ProfilePage>(
      find.byType(ProfilePage, skipOffstage: false),
    );
    expect(profile.isHomeActive, isTrue);
    expect(profile.isActive, isFalse);
    expect(fixture.updates.calls, 1);
    expect(find.byType(Dialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('high contrast removes the bottom bar backdrop filter', (
    tester,
  ) async {
    final fixture = _Fixture(_Updates((_) async => _current));
    await fixture.mount(tester, realShell: true, highContrast: true);
    final navFilter = find.ancestor(
      of: find.text('首页'),
      matching: find.byType(BackdropFilter),
    );
    expect(navFilter, findsOneWidget);
    final backdrop = tester.widget<BackdropFilter>(navFilter);
    expect(backdrop.enabled, isFalse);
    final decoration =
        (backdrop.child! as DecoratedBox).decoration as ShapeDecoration;
    expect(decoration.color!.a, greaterThanOrEqualTo(.98));
    expect(find.text('航迹'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home prompts once and tab changes do not repeat it', (
    tester,
  ) async {
    final fixture = _Fixture(_Updates((_) async => _available));
    await fixture.mount(tester);
    await tester.pumpAndSettle();
    expect(find.text('Home fixture'), findsOneWidget);
    expect(find.text('发现新版本'), findsOneWidget);
    expect(fixture.updates.calls, 1);
    await tester.tap(find.text('稍后再说'));
    await tester.pumpAndSettle();
    await fixture.changeTab(tester, 3);
    await fixture.changeTab(tester, 0);
    expect(fixture.updates.calls, 1);
    expect(find.byType(Dialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final result in [
    _current,
    const AppUpdateResult.unavailable(),
    const AppUpdateResult.notConfigured(),
  ]) {
    testWidgets('automatic ${result.status.name} stays quiet', (tester) async {
      final fixture = _Fixture(_Updates((_) async => result));
      await fixture.mount(tester);
      await tester.pumpAndSettle();
      expect(fixture.updates.calls, 1);
      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('Home fixture'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('late result stays off other tabs and retries on home', (
    tester,
  ) async {
    final pending = Completer<AppUpdateResult>();
    final fixture = _Fixture(
      _Updates((call) => call == 1 ? pending.future : Future.value(_available)),
    );
    await fixture.mount(tester);
    await fixture.changeTab(tester, 1);
    pending.complete(_available);
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('Flights fixture'), findsOneWidget);
    await fixture.changeTab(tester, 0);
    expect(fixture.updates.calls, 2);
    expect(find.text('发现新版本'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching home to Profile shares the pending request', (
    tester,
  ) async {
    final pending = Completer<AppUpdateResult>();
    final fixture = _Fixture(_Updates((_) => pending.future));
    await fixture.mount(tester);
    await fixture.changeTab(tester, 3);
    expect(fixture.updates.calls, 1);
    pending.complete(_available);
    await tester.pumpAndSettle();
    expect(find.text('发现新版本'), findsOneWidget);
    expect(fixture.updates.calls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('late result never covers a pushed route', (tester) async {
    final pending = Completer<AppUpdateResult>();
    final fixture = _Fixture(_Updates((_) => pending.future));
    await fixture.mount(tester);
    unawaited(
      fixture.navigator.currentState!.push<void>(
        MaterialPageRoute(
          builder: (_) => const Scaffold(body: Text('Editing fixture')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    pending.complete(_available);
    await tester.pumpAndSettle();
    expect(find.text('Editing fixture'), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposing during a check never prompts or calls setState', (
    tester,
  ) async {
    final pending = Completer<AppUpdateResult>();
    final fixture = _Fixture(_Updates((_) => pending.future));
    await fixture.mount(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete(_available);
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Profile manual check still runs after automatic check', (
    tester,
  ) async {
    final fixture = _Fixture(
      _Updates((call) async => call == 1 ? _current : _available),
    );
    await fixture.mount(tester);
    await tester.pumpAndSettle();
    await fixture.changeTab(tester, 3);
    await tester.ensureVisible(find.text('检查更新'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('检查更新'));
    await tester.pumpAndSettle();
    expect(fixture.updates.calls, 2);
    expect(find.text('发现新版本'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
