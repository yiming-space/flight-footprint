import 'package:geolocator/geolocator.dart';

/// One-shot device location access used by the map's explicit locate action.
/// No stream or background subscription is created here, so a location is not
/// collected until the user asks for it and is never persisted by this app.
class DeviceCoordinate {
  const DeviceCoordinate(this.latitude, this.longitude);

  final double latitude;
  final double longitude;
}

enum DeviceLocationFailure {
  serviceDisabled,
  permissionDenied,
  unavailable,
}

class DeviceLocationException implements Exception {
  const DeviceLocationException(this.reason);

  final DeviceLocationFailure reason;
}

class DeviceLocationService {
  const DeviceLocationService._();

  static Future<DeviceCoordinate> readOnce() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const DeviceLocationException(
        DeviceLocationFailure.serviceDisabled,
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw const DeviceLocationException(
        DeviceLocationFailure.permissionDenied,
      );
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      if (!position.latitude.isFinite ||
          !position.longitude.isFinite ||
          position.latitude.abs() > 90 ||
          position.longitude.abs() > 180) {
        throw const DeviceLocationException(
          DeviceLocationFailure.unavailable,
        );
      }
      return DeviceCoordinate(position.latitude, position.longitude);
    } on DeviceLocationException {
      rethrow;
    } catch (_) {
      throw const DeviceLocationException(
        DeviceLocationFailure.unavailable,
      );
    }
  }
}
