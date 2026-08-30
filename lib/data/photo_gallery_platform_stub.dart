import 'photo_gallery_models.dart';

Future<PhotoGalleryResult> loadPhotoGallery({
  int? limit = 120,
  void Function(int scanned, int? total)? onProgress,
}) async => const PhotoGalleryResult(status: PhotoGalleryStatus.unavailable);

Future<void> openPhotoGallerySettings() async {}
