import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app/app_controller.dart';
import 'app/app_shell.dart';
import 'core/localization/app_strings.dart';
import 'ui/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isAndroid || Platform.isIOS) {
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
  }
  runApp(const AppStartup());
}

/// Draw a loading surface before beginning potentially expensive local setup.
class AppStartup extends StatefulWidget {
  const AppStartup({super.key, this.createController});
  final Future<AppController> Function()? createController;
  @override
  State<AppStartup> createState() => _AppStartupState();
}

class _AppStartupState extends State<AppStartup> {
  Completer<AppController> _controller = Completer<AppController>();

  void _start() {
    final current = _controller;
    Future.sync(widget.createController ?? AppController.create)
        .then(current.complete, onError: current.completeError);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _start();
    });
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<AppController>(
    future: _controller.future,
    builder: (context, snapshot) {
      if (snapshot.hasData)
        return FlightFootprintApp(controller: snapshot.requireData);
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.system,
        home: Scaffold(
          // Match the Android launch window until saved app preferences load.
          backgroundColor: const Color(0xFF0B0E12),
          body: snapshot.hasError
              ? Center(
                  child: TextButton(
                    onPressed: () => setState(() {
                      _controller = Completer<AppController>();
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) _start();
                      });
                    }),
                    child: const Text('加载失败，重试 / Retry'),
                  ),
                )
              : const SizedBox.expand(),
        ),
      );
    },
  );
}

class FlightFootprintApp extends StatelessWidget {
  const FlightFootprintApp({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Flight Footprint',
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: controller.themeMode,
        locale: controller.locale,
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: const [
          AppStringsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) {
          final theme = Theme.of(context);
          final isDark = theme.brightness == Brightness.dark;
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle(
              statusBarColor: theme.scaffoldBackgroundColor,
              statusBarIconBrightness: isDark
                  ? Brightness.light
                  : Brightness.dark,
              statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
              // Keep the gesture/navigation area transparent so the floating
              // bottom menu can reveal the page content around its rounded
              // surface.
              systemNavigationBarColor: Colors.transparent,
              systemNavigationBarIconBrightness: isDark
                  ? Brightness.light
                  : Brightness.dark,
              systemNavigationBarDividerColor: Colors.transparent,
              systemNavigationBarContrastEnforced: false,
            ),
            child: child ?? const SizedBox.shrink(),
          );
        },
        home: AppShell(controller: controller),
      ),
    );
  }
}
