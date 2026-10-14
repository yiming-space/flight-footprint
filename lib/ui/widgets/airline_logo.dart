import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../data/airline_catalog.dart';
import '../theme/app_theme.dart';
import 'airline_logo_palette.dart';

/// A decorative airline badge. The enclosing row supplies the airline name.
///
/// Logos are fetched on demand from the endpoint documented by Travelpayouts;
/// they are not bundled or persisted to disk. Unknown codes and unavailable
/// images retain a same-size code badge so offline rankings stay readable.
class AirlineLogo extends StatefulWidget {
  const AirlineLogo({
    super.key,
    this.iataCode,
    this.size = 36,
    this.imageProvider,
    this.onColorResolved,
  }) : assert(size > 0);

  final String? iataCode;
  final double size;

  /// Delivered after a frame when the loaded logo has a useful colored hue.
  /// Neutral or unavailable logos leave the enclosing row's fallback unchanged.
  final ValueChanged<Color>? onColorResolved;

  /// Overrides remote loading in tests. Only a recognized IATA code can render
  /// an image, even when this is supplied.
  @visibleForTesting
  final ImageProvider<Object>? imageProvider;

  @override
  State<AirlineLogo> createState() => _AirlineLogoState();
}

class _AirlineLogoState extends State<AirlineLogo> {
  // Decoded colors only: no second fetch, image dataset or disk persistence.
  // In-flight work is shared between the preview and complete ranking list.
  static final _paletteCache = <String, Future<Color?>>{};

  static final _iataPattern = RegExp(r'^[A-Z0-9]{2}$');

  ImageProvider<Object>? _provider;
  ImageStream? _paletteStream;
  ImageStreamListener? _paletteListener;
  String _code = '';
  bool _recognized = false;
  bool _paletteStarted = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _configureProvider();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _startPalette();
  }

  @override
  void didUpdateWidget(covariant AirlineLogo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.iataCode?.trim().toUpperCase() !=
            widget.iataCode?.trim().toUpperCase() ||
        oldWidget.imageProvider != widget.imageProvider ||
        (oldWidget.onColorResolved == null) !=
            (widget.onColorResolved == null)) {
      _generation++;
      _detachPaletteListener();
      _paletteStarted = false;
      _configureProvider();
      _startPalette();
    }
  }

  void _configureProvider() {
    _code = widget.iataCode?.trim().toUpperCase() ?? '';
    _recognized =
        _iataPattern.hasMatch(_code) && airlineNameForPrefix(_code) != null;
    _provider = _recognized
        ? widget.imageProvider ??
              NetworkImage('https://pics.avs.io/144/144/$_code.png')
        : null;
  }

  void _startPalette() {
    if (_paletteStarted || !_recognized || widget.onColorResolved == null) {
      return;
    }
    _paletteStarted = true;
    final generation = _generation;
    // Test providers deliberately bypass this code-keyed production cache.
    final cacheKey = widget.imageProvider == null ? _code : null;
    final cached = cacheKey == null ? null : _paletteCache[cacheKey];
    if (cached != null) {
      _deliverColor(cached, generation);
      return;
    }

    var consumedFrame = false;
    final listener = ImageStreamListener(
      (info, synchronousCall) {
        if (consumedFrame || !mounted || generation != _generation) {
          info.dispose();
          return;
        }
        consumedFrame = true;
        _detachPaletteListener();
        final pending = cacheKey == null ? null : _paletteCache[cacheKey];
        final Future<Color?> palette;
        if (pending != null) {
          info.dispose();
          palette = pending;
        } else {
          palette = _extractColor(info);
          if (cacheKey != null) _paletteCache[cacheKey] = palette;
        }
        _deliverColor(palette, generation);
      },
      onError: (Object error, StackTrace? stackTrace) {
        _detachPaletteListener();
      },
    );
    _paletteListener = listener;
    _paletteStream = _provider!.resolve(createLocalImageConfiguration(context));
    _paletteStream!.addListener(listener);
  }

  static Future<Color?> _extractColor(ImageInfo info) async {
    try {
      final pixels = await info.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (pixels == null) return null;
      return airlineLogoDominantColor(
        pixels.buffer.asUint8List(pixels.offsetInBytes, pixels.lengthInBytes),
        width: info.image.width,
        height: info.image.height,
      );
    } catch (_) {
      return null;
    } finally {
      // ImageStream delivers a handle owned by this listener, distinct from
      // the Image widget's handle. Release it after asynchronous pixel access.
      info.dispose();
    }
  }

  void _deliverColor(Future<Color?> palette, int generation) {
    unawaited(
      palette.then((color) {
        if (color == null || !mounted || generation != _generation) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && generation == _generation) {
            widget.onColorResolved?.call(color);
          }
        });
        WidgetsBinding.instance.ensureVisualUpdate();
      }),
    );
  }

  void _detachPaletteListener() {
    final listener = _paletteListener;
    if (listener != null) _paletteStream?.removeListener(listener);
    _paletteStream = null;
    _paletteListener = null;
  }

  @override
  void dispose() {
    _generation++;
    _detachPaletteListener();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final code = _code;
    final validCode = _iataPattern.hasMatch(code);
    final size = widget.size;
    final fallback = _AirlineCodeBadge(
      code: validCode ? code : null,
      size: size,
    );

    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: ClipOval(
          child: DecoratedBox(
            decoration: const BoxDecoration(
              // The circular light plate preserves brand colors in both themes.
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: Padding(
              // The inner square fits fully within the circle, preserving
              // complete wide logos rather than clipping their outer corners.
              padding: EdgeInsets.all(size * .16),
              child: _recognized
                  ? Image(
                      image: _provider!,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.medium,
                      frameBuilder:
                          (context, child, frame, synchronouslyLoaded) =>
                              synchronouslyLoaded || frame != null
                              ? child
                              : fallback,
                      errorBuilder: (context, error, stackTrace) => fallback,
                    )
                  : fallback,
            ),
          ),
        ),
      ),
    );
  }
}

class _AirlineCodeBadge extends StatelessWidget {
  const _AirlineCodeBadge({required this.code, required this.size});

  final String? code;
  final double size;

  @override
  Widget build(BuildContext context) {
    // Use the light-theme ink on the always-light brand plate.
    final ink = AppThemeColors.light.textSecondary;
    return Center(
      child: code == null
          ? Icon(Icons.flight_rounded, size: size * .5, color: ink)
          : FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                code!,
                style: TextStyle(
                  color: ink,
                  fontSize: size * .34,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .3,
                ),
              ),
            ),
    );
  }
}
