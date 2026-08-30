import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/localization/app_strings.dart';
import '../../data/city_catalog.dart';
import '../../data/photo_gallery.dart';
import '../../domain/visited_place.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/widgets/widgets.dart';
import 'map_models.dart';

class PhotoFootprintDraft {
  const PhotoFootprintDraft({
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.visitedAt,
    required this.countryCode,
  });

  final String name;
  final double latitude;
  final double longitude;
  final DateTime visitedAt;
  final String countryCode;
}

class PhotoFootprintImportResult {
  const PhotoFootprintImportResult({
    required this.drafts,
    this.skippedNoLocation = 0,
    this.skippedNoCity = 0,
    this.skippedExisting = 0,
  });

  final List<PhotoFootprintDraft> drafts;
  final int skippedNoLocation;
  final int skippedNoCity;
  final int skippedExisting;

  int get skipped => skippedNoLocation + skippedNoCity + skippedExisting;
}

class _PhotoFootprintCandidate {
  const _PhotoFootprintCandidate({required this.draft, required this.asset});

  final PhotoFootprintDraft draft;
  final PhotoGalleryAsset asset;
}

class _PhotoFootprintScan {
  const _PhotoFootprintScan({
    required this.gallery,
    this.candidates = const [],
    this.scannedCount = 0,
    this.skippedNoLocation = 0,
    this.skippedNoCity = 0,
    this.skippedExisting = 0,
  });

  final PhotoGalleryResult gallery;
  final List<_PhotoFootprintCandidate> candidates;
  final int scannedCount;
  final int skippedNoLocation;
  final int skippedNoCity;
  final int skippedExisting;

  int get skipped => skippedNoLocation + skippedNoCity + skippedExisting;
}

enum _PhotoScanPhase { scanning, locating, matching }

class PhotoFootprintPickerSheet extends StatefulWidget {
  const PhotoFootprintPickerSheet({super.key, required this.existingPlaces});

  final List<VisitedPlace> existingPlaces;

  @override
  State<PhotoFootprintPickerSheet> createState() =>
      _PhotoFootprintPickerSheetState();
}

class _PhotoFootprintPickerSheetState extends State<PhotoFootprintPickerSheet> {
  late Future<_PhotoFootprintScan> _scanFuture;
  late final Future<CityCatalog> _cityCatalogFuture = CityCatalog.load();
  final _locationFutures = <String, Future<PhotoCoordinates?>>{};
  final _thumbnailFutures = <String, Future<Uint8List?>>{};
  bool _importing = false;
  final _candidateKeys = <String>{};
  final _selectedCandidateKeys = <String>{};
  int _candidateTotal = 0;
  int _selectedCount = 0;
  int _scannedPhotos = 0;
  int? _totalPhotos;
  _PhotoScanPhase _scanPhase = _PhotoScanPhase.scanning;
  int _processedPhotos = 0;

  @override
  void initState() {
    super.initState();
    _scanFuture = _scanPhotos();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    return Material(
      color: AppColors.background,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(
                alignment: Alignment.center,
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.textTertiary,
                    borderRadius: AppRadii.pill,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      s.t('photoFootprintTitle'),
                      style: AppTextStyles.sectionTitle,
                    ),
                  ),
                  IconButton(
                    tooltip: s.t('close'),
                    onPressed: _importing ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              Text(
                s.t('photoFootprintHint'),
                style: AppTextStyles.bodySecondary,
              ),
              const SizedBox(height: 14),
              Expanded(
                child: FutureBuilder<_PhotoFootprintScan>(
                  future: _scanFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return _PhotoScanLoading(
                        phase: _scanPhase,
                        scanned: _scannedPhotos,
                        processed: _processedPhotos,
                        total: _totalPhotos,
                        onCancel: _importing
                            ? null
                            : () => Navigator.maybePop(context),
                      );
                    }
                    final scan = snapshot.data;
                    final result = scan?.gallery;
                    if (scan == null ||
                        result == null ||
                        result.status == PhotoGalleryStatus.failed) {
                      return _PhotoGalleryMessage(
                        icon: Icons.cloud_off_rounded,
                        message: s.t('photoFootprintLoadFailed'),
                        action: _retry,
                        actionLabel: s.t('retry'),
                      );
                    }
                    if (result.status == PhotoGalleryStatus.denied) {
                      return _PhotoGalleryMessage(
                        icon: Icons.lock_outline_rounded,
                        message: s.t('photoFootprintPermissionHint'),
                        action: _openSettings,
                        actionLabel: s.t('photoFootprintOpenSettings'),
                      );
                    }
                    if (result.status == PhotoGalleryStatus.unavailable) {
                      return _PhotoGalleryMessage(
                        icon: Icons.phone_android_rounded,
                        message: s.t('photoFootprintUnsupported'),
                      );
                    }
                    if (result.assets.isEmpty) {
                      return _PhotoGalleryMessage(
                        icon: Icons.photo_library_outlined,
                        message: s.t('photoFootprintNoPhotos'),
                      );
                    }
                    if (scan.candidates.isEmpty) {
                      return _PhotoGalleryMessage(
                        icon: Icons.location_off_outlined,
                        message: s.t('photoFootprintNoImportable'),
                        action: _retry,
                        actionLabel: s.t('retry'),
                      );
                    }
                    return _buildResults(context, scan);
                  },
                ),
              ),
              if (_candidateTotal > 0) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        s
                            .t('photoFootprintSelectionSummary')
                            .replaceFirst('{selected}', '$_selectedCount')
                            .replaceFirst('{total}', '$_candidateTotal'),
                        style: AppTextStyles.label,
                      ),
                    ),
                    if (!_importing) ...[
                      TextButton(
                        onPressed: _selectedCount == _candidateTotal
                            ? _clearSelection
                            : _selectAll,
                        child: Text(
                          s.t(
                            _selectedCount == _candidateTotal
                                ? 'deselectAll'
                                : 'selectAll',
                          ),
                        ),
                      ),
                      TextButton(onPressed: _retry, child: Text(s.t('retry'))),
                    ],
                  ],
                ),
                PrimaryButton(
                  label: s
                      .t('photoFootprintAddAll')
                      .replaceFirst('{count}', '$_selectedCount'),
                  icon: Icons.add_location_alt_rounded,
                  onPressed: _importing || _selectedCount == 0 ? null : _import,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResults(BuildContext context, _PhotoFootprintScan scan) {
    final s = context.strings;
    final selectedCount = _selectedCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.lime.withValues(alpha: .10),
            borderRadius: AppRadii.medium,
            border: Border.all(color: AppColors.lime.withValues(alpha: .34)),
          ),
          child: Row(
            children: [
              const Icon(Icons.auto_awesome_rounded, color: AppColors.lime),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  s
                      .t('photoFootprintSelectionSummary')
                      .replaceFirst('{selected}', '$selectedCount')
                      .replaceFirst('{total}', '${scan.candidates.length}'),
                  style: AppTextStyles.body,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.only(bottom: 4),
            itemCount: scan.candidates.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: .92,
            ),
            itemBuilder: (context, index) =>
                _buildCandidateTile(context, scan.candidates[index]),
          ),
        ),
      ],
    );
  }

  Widget _buildCandidateTile(
    BuildContext context,
    _PhotoFootprintCandidate candidate,
  ) {
    final asset = candidate.asset;
    final selected = _isSelected(candidate);
    return Semantics(
      button: true,
      checked: selected,
      label:
          '${candidate.draft.name}, ${formatPhotoFootprintDate(context, asset.createdAt)}',
      child: InkWell(
        onTap: _importing ? null : () => _toggleCandidate(candidate),
        borderRadius: AppRadii.medium,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadii.medium,
            border: Border.all(
              color: selected ? AppColors.lime : AppColors.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 180),
            opacity: selected ? 1 : .46,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: FutureBuilder<Uint8List?>(
                    future: _thumbnailFor(asset),
                    builder: (context, snapshot) {
                      final bytes = snapshot.data;
                      if (bytes == null) {
                        return Center(
                          child:
                              snapshot.connectionState == ConnectionState.done
                              ? const Icon(
                                  Icons.broken_image_outlined,
                                  color: AppColors.textTertiary,
                                )
                              : const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.lime,
                                  ),
                                ),
                        );
                      }
                      return Image.memory(
                        bytes,
                        fit: BoxFit.cover,
                        width: double.infinity,
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.location_on_rounded,
                        size: 15,
                        color: AppColors.lime,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              candidate.draft.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              formatPhotoFootprintDate(
                                context,
                                asset.createdAt,
                              ),
                              style: AppTextStyles.label,
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        selected
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        size: 19,
                        color: selected
                            ? AppColors.lime
                            : AppColors.textTertiary,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<_PhotoFootprintScan> _scanPhotos() async {
    _scannedPhotos = 0;
    _totalPhotos = null;
    _scanPhase = _PhotoScanPhase.scanning;
    _processedPhotos = 0;
    final gallery = await loadPhotoGallery(
      // null means all image assets in the system's “all photos” album.
      limit: null,
      onProgress: (scanned, total) {
        if (!mounted) return;
        setState(() {
          _scannedPhotos = scanned;
          _totalPhotos = total;
          _scanPhase = _PhotoScanPhase.scanning;
        });
      },
    );
    if (gallery.status != PhotoGalleryStatus.ready || gallery.assets.isEmpty) {
      if (mounted) {
        setState(() {
          _candidateKeys.clear();
          _selectedCandidateKeys.clear();
          _candidateTotal = 0;
          _selectedCount = 0;
        });
      }
      return _PhotoFootprintScan(gallery: gallery);
    }

    try {
      if (mounted) {
        setState(() {
          _scanPhase = _PhotoScanPhase.locating;
          _processedPhotos = 0;
          _totalPhotos = gallery.assets.length;
        });
      }
      final catalog = await _cityCatalogFuture;
      final candidates = <String, _PhotoFootprintCandidate>{};
      final existingCityKeys = <String>{
        for (final place in widget.existingPlaces)
          if (!isProvinceMapLabel(place.name))
            catalog.canonicalCityKey(
              place.name,
              countryCode: place.countryCode,
              latitude: place.latitude,
              longitude: place.longitude,
            ),
      };
      var skippedNoLocation = 0;
      var skippedNoCity = 0;
      var skippedExisting = 0;
      const batchSize = 24;
      for (var start = 0; start < gallery.assets.length; start += batchSize) {
        final end = (start + batchSize).clamp(0, gallery.assets.length).toInt();
        final batch = gallery.assets.sublist(start, end);
        if (mounted) {
          setState(() => _scanPhase = _PhotoScanPhase.locating);
        }
        final locations = await Future.wait(batch.map(_locationFor));
        if (mounted) {
          setState(() => _scanPhase = _PhotoScanPhase.matching);
        }
        for (var index = 0; index < batch.length; index++) {
          final asset = batch[index];
          final location = locations[index];
          if (location == null) {
            skippedNoLocation++;
            continue;
          }
          final city = catalog.nearest(
            location.latitude,
            location.longitude,
            countryCode: null,
          );
          if (city == null) {
            skippedNoCity++;
            continue;
          }
          final cityName = catalog.canonicalCityName(
            city.name,
            countryCode: city.countryCode,
            latitude: location.latitude,
            longitude: location.longitude,
          );
          final cityCountry = city.countryCode.trim().toUpperCase();
          final cityKey = catalog.canonicalCityKey(
            cityName,
            countryCode: cityCountry,
            latitude: location.latitude,
            longitude: location.longitude,
          );
          final duplicate =
              existingCityKeys.contains(cityKey) ||
              widget.existingPlaces.any((place) {
                // A province row from an older version should not block the
                // real city that the same photo resolves to.
                if (isProvinceMapLabel(place.name)) return false;
                final placeCountry = place.countryCode?.trim().toUpperCase();
                if (placeCountry != null &&
                    placeCountry.isNotEmpty &&
                    placeCountry != cityCountry) {
                  return false;
                }
                return CityCatalog.distanceKm(
                      fromLatitude: place.latitude,
                      fromLongitude: place.longitude,
                      toLatitude: location.latitude,
                      toLongitude: location.longitude,
                    ) <=
                    25;
              });
          if (duplicate) {
            skippedExisting++;
            continue;
          }
          final key = cityKey;
          candidates.putIfAbsent(
            key,
            () => _PhotoFootprintCandidate(
              asset: asset,
              draft: PhotoFootprintDraft(
                name: cityName,
                latitude: location.latitude,
                longitude: location.longitude,
                visitedAt: asset.createdAt ?? DateTime.now(),
                countryCode: city.countryCode,
              ),
            ),
          );
        }
        if (mounted) {
          setState(() => _processedPhotos = end);
        }
      }
      final scan = _PhotoFootprintScan(
        gallery: gallery,
        candidates: List.unmodifiable(candidates.values),
        scannedCount: gallery.assets.length,
        skippedNoLocation: skippedNoLocation,
        skippedNoCity: skippedNoCity,
        skippedExisting: skippedExisting,
      );
      if (mounted) {
        final keys = {
          for (final candidate in scan.candidates) _candidateKey(candidate),
        };
        setState(() {
          _candidateKeys
            ..clear()
            ..addAll(keys);
          _selectedCandidateKeys
            ..clear()
            ..addAll(keys);
          _candidateTotal = scan.candidates.length;
          _selectedCount = keys.length;
        });
      }
      return scan;
    } catch (_) {
      if (mounted) {
        setState(() {
          _candidateKeys.clear();
          _selectedCandidateKeys.clear();
          _candidateTotal = 0;
          _selectedCount = 0;
        });
      }
      return _PhotoFootprintScan(
        gallery: PhotoGalleryResult(
          status: PhotoGalleryStatus.failed,
          message: 'scan failed',
        ),
      );
    }
  }

  Future<PhotoCoordinates?> _locationFor(PhotoGalleryAsset asset) =>
      _locationFutures.putIfAbsent(asset.id, asset.loadLocation);

  Future<Uint8List?> _thumbnailFor(PhotoGalleryAsset asset) =>
      _thumbnailFutures.putIfAbsent(asset.id, asset.loadThumbnail);

  String _candidateKey(_PhotoFootprintCandidate candidate) {
    final draft = candidate.draft;
    return '${draft.countryCode.trim().toUpperCase()}|${draft.name.trim().toLowerCase()}';
  }

  bool _isSelected(_PhotoFootprintCandidate candidate) =>
      _selectedCandidateKeys.contains(_candidateKey(candidate));

  void _toggleCandidate(_PhotoFootprintCandidate candidate) {
    final key = _candidateKey(candidate);
    setState(() {
      if (_selectedCandidateKeys.contains(key)) {
        _selectedCandidateKeys.remove(key);
      } else {
        _selectedCandidateKeys.add(key);
      }
      _selectedCount = _selectedCandidateKeys.length;
    });
  }

  void _selectAll() {
    setState(() {
      _selectedCandidateKeys
        ..clear()
        ..addAll(_candidateKeys);
      _selectedCount = _selectedCandidateKeys.length;
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedCandidateKeys.clear();
      _selectedCount = 0;
    });
  }

  Future<void> _import() async {
    if (_selectedCount == 0 || _importing) return;
    setState(() => _importing = true);
    try {
      final scan = await _scanFuture;
      if (!mounted) return;
      final selected = scan.candidates
          .where(_isSelected)
          .toList(growable: false);
      if (selected.isEmpty) {
        setState(() => _importing = false);
        _message(context, context.strings.t('photoFootprintNoImportable'));
        return;
      }
      Navigator.pop(
        context,
        PhotoFootprintImportResult(
          drafts: [for (final candidate in selected) candidate.draft],
          skippedNoLocation: scan.skippedNoLocation,
          skippedNoCity: scan.skippedNoCity,
          skippedExisting: scan.skippedExisting,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _importing = false);
      _message(context, context.strings.t('photoFootprintLoadFailed'));
    }
  }

  void _retry() {
    if (_importing) return;
    setState(() {
      _candidateKeys.clear();
      _selectedCandidateKeys.clear();
      _candidateTotal = 0;
      _selectedCount = 0;
      _scannedPhotos = 0;
      _totalPhotos = null;
      _scanPhase = _PhotoScanPhase.scanning;
      _processedPhotos = 0;
      _locationFutures.clear();
      _thumbnailFutures.clear();
      _scanFuture = _scanPhotos();
    });
  }

  Future<void> _openSettings() async {
    await openPhotoGallerySettings();
    if (!mounted) return;
    _retry();
  }

  void _message(BuildContext context, String message) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _PhotoScanLoading extends StatefulWidget {
  const _PhotoScanLoading({
    required this.phase,
    required this.scanned,
    required this.processed,
    required this.total,
    this.onCancel,
  });

  final _PhotoScanPhase phase;
  final int scanned;
  final int processed;
  final int? total;
  final VoidCallback? onCancel;

  @override
  State<_PhotoScanLoading> createState() => _PhotoScanLoadingState();
}

class _PhotoScanLoadingState extends State<_PhotoScanLoading>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    final total = widget.total;
    final count = widget.phase == _PhotoScanPhase.scanning
        ? widget.scanned
        : widget.processed;
    final countText = total == null || total <= 0
        ? '…'
        : s
              .t('photoFootprintPhotoProgress')
              .replaceFirst('{processed}', '$count')
              .replaceFirst('{total}', '$total');
    final progress = total == null || total <= 0
        ? null
        : (widget.phase == _PhotoScanPhase.scanning
                  ? count / total
                  : .45 + count / total * .55)
              .clamp(0.0, .98)
              .toDouble();

    return Center(
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                liveRegion: true,
                label: s.t('photoFootprintScanTitle'),
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) => CustomPaint(
                    size: Size(240, 190),
                    painter: _PhotoScanIllustrationPainter(
                      progress: _controller.value,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                countText,
                textAlign: TextAlign.center,
                style: AppTextStyles.body.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (progress != null) ...[
                const SizedBox(height: 14),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: progress),
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOut,
                  builder: (context, value, child) => SizedBox(
                    width: 240,
                    height: 6,
                    child: ClipRRect(
                      borderRadius: AppRadii.pill,
                      child: LinearProgressIndicator(
                        value: value,
                        backgroundColor: AppColors.surfaceElevated,
                        valueColor: const AlwaysStoppedAnimation(
                          AppColors.lime,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              if (widget.onCancel != null) ...[
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: widget.onCancel,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.lime,
                    foregroundColor: Colors.black,
                    minimumSize: const Size(112, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 30),
                    shape: const RoundedRectangleBorder(
                      borderRadius: AppRadii.pill,
                    ),
                  ),
                  child: Text(s.t('cancel')),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoScanIllustrationPainter extends CustomPainter {
  const _PhotoScanIllustrationPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    const designWidth = 240.0;
    const designHeight = 190.0;
    final scale = math.min(
      size.width / designWidth,
      size.height / designHeight,
    );
    canvas.save();
    canvas.translate(
      (size.width - designWidth * scale) / 2,
      (size.height - designHeight * scale) / 2,
    );
    canvas.scale(scale);

    final ink = Paint()
      ..color = AppColors.textSecondary.withValues(alpha: .88)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final softInk = Paint()
      ..color = AppColors.textTertiary.withValues(alpha: .76)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final routeInk = Paint()
      ..color = AppColors.textTertiary.withValues(alpha: .62)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    final purple = Paint()
      ..color = AppColors.purple
      ..style = PaintingStyle.fill;
    final cardRect = Rect.fromLTWH(28, 18, 138, 106);
    canvas.drawRRect(
      RRect.fromRectAndRadius(cardRect, const Radius.circular(18)),
      ink,
    );
    final mountain = Path()
      ..moveTo(48, 91)
      ..lineTo(73, 61)
      ..lineTo(96, 82)
      ..lineTo(121, 54)
      ..lineTo(153, 91);
    canvas.drawPath(mountain, softInk);
    canvas.drawCircle(const Offset(130, 43), 10, softInk);

    final route = Path()
      ..moveTo(60, 150)
      ..cubicTo(94, 161, 145, 165, 190, 150);
    final routeMetric = route.computeMetrics().first;
    const dotGap = 12.0;
    _drawDashedInterval(
      canvas,
      routeMetric,
      dotGap,
      routeMetric.length / 2 - dotGap,
      routeInk,
    );
    _drawDashedInterval(
      canvas,
      routeMetric,
      routeMetric.length / 2 + dotGap,
      routeMetric.length - dotGap,
      routeInk,
    );
    const dotPositions = <Offset>[
      Offset(60, 150),
      Offset(125, 160),
      Offset(190, 150),
    ];
    for (var index = 0; index < dotPositions.length; index++) {
      final phase = (progress + index / dotPositions.length) % 1;
      final bob = math.sin(phase * math.pi * 2) * 1.8;
      final opacity = .84 + math.sin(phase * math.pi * 2) * .10;
      final lime = Paint()
        ..color = AppColors.lime.withValues(alpha: opacity)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(dotPositions[index] + Offset(0, bob), 8.5, lime);
    }

    final pin = Path()
      ..moveTo(173, 65)
      ..cubicTo(157, 65, 148, 76, 150, 90)
      ..cubicTo(152, 102, 164, 115, 173, 126)
      ..cubicTo(182, 115, 194, 102, 196, 90)
      ..cubicTo(198, 76, 189, 65, 173, 65)
      ..close();
    final pinFill = Paint()
      ..color = AppColors.background
      ..style = PaintingStyle.fill;
    canvas.drawPath(pin, pinFill);
    canvas.drawPath(pin, ink);
    canvas.drawCircle(const Offset(173, 84), 8.5, purple);
    canvas.restore();
  }

  void _drawDashedInterval(
    Canvas canvas,
    PathMetric metric,
    double start,
    double end,
    Paint paint,
  ) {
    if (end <= start) return;

    const dashLength = 6.0;
    const gapLength = 5.0;
    final dashed = Path();
    var distance = start;
    while (distance < end) {
      final dashEnd = math.min(distance + dashLength, end);
      if (dashEnd > distance) {
        dashed.addPath(metric.extractPath(distance, dashEnd), Offset.zero);
      }
      distance += dashLength + gapLength;
    }
    canvas.drawPath(dashed, paint);
  }

  @override
  bool shouldRepaint(covariant _PhotoScanIllustrationPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _PhotoGalleryMessage extends StatelessWidget {
  const _PhotoGalleryMessage({
    required this.icon,
    required this.message,
    this.action,
    this.actionLabel,
  });

  final IconData icon;
  final String message;
  final VoidCallback? action;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 42, color: AppColors.textTertiary),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySecondary,
          ),
          if (action != null) ...[
            const SizedBox(height: 16),
            OutlinedButton(onPressed: action, child: Text(actionLabel!)),
          ],
        ],
      ),
    ),
  );
}

String formatPhotoFootprintDate(BuildContext context, DateTime? value) {
  if (value == null) return context.strings.t('photoFootprintDateUnknown');
  return DateFormat('yyyy-MM-dd').format(value.toLocal());
}
