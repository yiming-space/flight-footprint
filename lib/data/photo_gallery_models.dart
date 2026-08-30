import 'dart:typed_data';

enum PhotoGalleryStatus { ready, denied, empty, unavailable, failed }

class PhotoCoordinates {
  const PhotoCoordinates({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;
}

class PhotoGalleryAsset {
  const PhotoGalleryAsset({
    required this.id,
    required this.createdAt,
    required this.loadThumbnail,
    required this.loadLocation,
  });

  final String id;
  final DateTime? createdAt;
  final Future<Uint8List?> Function() loadThumbnail;
  final Future<PhotoCoordinates?> Function() loadLocation;
}

class PhotoGalleryResult {
  const PhotoGalleryResult({
    required this.status,
    this.assets = const [],
    this.message,
  });

  final PhotoGalleryStatus status;
  final List<PhotoGalleryAsset> assets;
  final String? message;
}
