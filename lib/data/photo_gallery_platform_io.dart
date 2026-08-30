import 'package:photo_manager/photo_manager.dart' as pm;

import 'photo_gallery_models.dart';

Future<PhotoGalleryResult> loadPhotoGallery({
  int? limit = 120,
  void Function(int scanned, int? total)? onProgress,
}) async {
  try {
    final permission = await pm.PhotoManager.requestPermissionExtend(
      requestOption: pm.PermissionRequestOption(
        androidPermission: pm.AndroidPermission(
          type: pm.RequestType.image,
          mediaLocation: true,
        ),
        iosAccessLevel: pm.IosAccessLevel.readWrite,
      ),
    );
    if (!permission.hasAccess) {
      return PhotoGalleryResult(
        status: PhotoGalleryStatus.denied,
        message: permission.name,
      );
    }

    final paths = await pm.PhotoManager.getAssetPathList(
      onlyAll: true,
      type: pm.RequestType.image,
      filterOption: pm.FilterOptionGroup(
        imageOption: pm.FilterOption(
          sizeConstraint: pm.SizeConstraint(ignoreSize: true),
        ),
      ),
    );
    if (paths.isEmpty) {
      return const PhotoGalleryResult(status: PhotoGalleryStatus.empty);
    }

    final path = paths.first;
    final total = await path.assetCountAsync;
    final safeLimit = limit?.clamp(1, 20000).toInt();
    const pageSize = 200;
    final assets = <PhotoGalleryAsset>[];
    var page = 0;
    while (safeLimit == null || assets.length < safeLimit) {
      final remaining = safeLimit == null
          ? pageSize
          : safeLimit - assets.length;
      final requestSize = remaining < pageSize ? remaining : pageSize;
      if (requestSize <= 0) break;
      final entities = await path.getAssetListPaged(
        page: page,
        size: requestSize,
        type: pm.RequestType.image,
      );
      if (entities.isEmpty) break;
      assets.addAll(
        entities.map(
          (entity) => PhotoGalleryAsset(
            id: entity.id,
            createdAt: entity.createDateSecond == null
                ? null
                : entity.createDateTime,
            loadThumbnail: () => entity.thumbnailDataWithSize(
              const pm.ThumbnailSize.square(320),
            ),
            loadLocation: () async {
              try {
                // On Android 10+, the synchronous field is intentionally
                // empty; latlngAsync reads the original EXIF metadata after
                // ACCESS_MEDIA_LOCATION has been granted.
                final location = entity.latLng ?? await entity.latlngAsync();
                if (location == null ||
                    !location.latitude.isFinite ||
                    !location.longitude.isFinite ||
                    location.latitude.abs() > 90 ||
                    location.longitude.abs() > 180) {
                  return null;
                }
                return PhotoCoordinates(
                  latitude: location.latitude,
                  longitude: location.longitude,
                );
              } catch (_) {
                return null;
              }
            },
          ),
        ),
      );
      onProgress?.call(assets.length, total > 0 ? total : null);
      if (entities.length < requestSize) break;
      page++;
    }
    if (assets.isEmpty) {
      return const PhotoGalleryResult(status: PhotoGalleryStatus.empty);
    }

    return PhotoGalleryResult(status: PhotoGalleryStatus.ready, assets: assets);
  } catch (error) {
    return PhotoGalleryResult(
      status: PhotoGalleryStatus.failed,
      message: error.toString(),
    );
  }
}

Future<void> openPhotoGallerySettings() => pm.PhotoManager.openSetting();
