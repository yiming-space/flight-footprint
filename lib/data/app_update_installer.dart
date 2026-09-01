import 'dart:io';

import 'package:flutter/services.dart';

/// Bridges the downloaded APK to Android's package installer. Android keeps
/// the final install confirmation in the system UI; the app never attempts a
/// silent or privileged install.
abstract final class AppUpdateInstaller {
  static const _channel = MethodChannel('flight_footprint/update');

  static bool get isSupported => Platform.isAndroid;

  static Future<void> install(File apk) async {
    if (!isSupported) {
      throw UnsupportedError(
        'In-app APK updates are only available on Android.',
      );
    }
    final launched = await _channel.invokeMethod<bool>('installApk', {
      'path': apk.path,
    });
    if (launched != true) {
      throw StateError('Android package installer could not be opened.');
    }
  }
}
