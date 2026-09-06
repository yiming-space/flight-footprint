import 'dart:io';

import 'package:flutter/services.dart';

/// Opens the downloaded platform installer. Android keeps the final install
/// confirmation in the system UI; macOS opens the DMG in Finder so the user
/// can review and replace the app manually. No silent install is attempted.
abstract final class AppUpdateInstaller {
  static const _channel = MethodChannel('flight_footprint/update');

  static bool get isSupported => Platform.isAndroid || Platform.isMacOS;

  static Future<void> install(File artifact) async {
    if (Platform.isMacOS) {
      final result = await Process.run('open', [artifact.path]);
      if (result.exitCode != 0) {
        throw StateError('macOS could not open the downloaded DMG.');
      }
      return;
    }
    if (!Platform.isAndroid) {
      throw UnsupportedError(
        'In-app installer updates are only available on Android and macOS.',
      );
    }
    final launched = await _channel.invokeMethod<bool>('installApk', {
      'path': artifact.path,
    });
    if (launched != true) {
      throw StateError('Android package installer could not be opened.');
    }
  }
}
