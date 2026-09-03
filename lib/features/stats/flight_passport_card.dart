import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart' as photo_manager;
import 'package:share_plus/share_plus.dart';

import '../../core/localization/app_strings.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/widgets/country_flag.dart';
import '../map/map_models.dart';
import '../map/offline_map.dart';
import 'route_viewport_policy.dart';

/// A shareable 3:4 summary of the traveller's completed flights.
///
/// The card deliberately has no app chrome in its repaint boundary. A long
/// press on the card therefore exports exactly the same portrait that the
/// user sees in the statistics page.
class FlightPassportCard extends StatefulWidget {
  const FlightPassportCard({
    super.key,
    required this.year,
    this.yearLabel,
    required this.travellerName,
    required this.distanceKm,
    required this.flightTimeMinutes,
    required this.flightCount,
    required this.airportCount,
    required this.routeCount,
    required this.countryCodes,
    required this.airports,
    required this.routes,
  });

  final int year;

  /// Optional display label for aggregate cards (for example, “ALL”). The
  /// numeric year remains available for backwards-compatible exports.
  final String? yearLabel;
  final String travellerName;
  final double distanceKm;
  final int flightTimeMinutes;
  final int flightCount;
  final int airportCount;
  final int routeCount;
  final List<String> countryCodes;
  final List<MapAirport> airports;
  final List<MapRoute> routes;

  @override
  State<FlightPassportCard> createState() => _FlightPassportCardState();
}

enum _PassportAction { save, share }

class _FlightPassportCardState extends State<FlightPassportCard> {
  final _captureKey = GlobalKey();
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final hint = context.strings.isZh
        ? '长按保存或分享'
        : 'Long press to save or share';
    return Column(
      children: [
        Semantics(
          button: true,
          label: hint,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onLongPress: _showActions,
            child: RepaintBoundary(
              key: _captureKey,
              child: ClipPath(
                clipper: ShapeBorderClipper(shape: AppShapes.large),
                child: _PassportArtwork(
                  year: widget.year,
                  yearLabel: widget.yearLabel,
                  travellerName: widget.travellerName,
                  distanceKm: widget.distanceKm,
                  flightTimeMinutes: widget.flightTimeMinutes,
                  flightCount: widget.flightCount,
                  airportCount: widget.airportCount,
                  routeCount: widget.routeCount,
                  countryCodes: widget.countryCodes,
                  airports: widget.airports,
                  routes: widget.routes,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          hint,
          style: AppTextStyles.label.copyWith(
            fontSize: 12,
            fontWeight: FontWeight.w400,
            color: AppColors.textTertiary,
          ),
        ),
      ],
    );
  }

  Future<void> _showActions() async {
    if (_busy) return;
    HapticFeedback.mediumImpact();
    final action = await showModalBottomSheet<_PassportAction>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      shape: AppShapes.sheet,
      builder: (context) {
        final isZh = context.strings.isZh;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.save_alt_rounded),
                title: Text(isZh ? '保存图片' : 'Save image'),
                onTap: () => Navigator.pop(context, _PassportAction.save),
              ),
              ListTile(
                leading: const Icon(Icons.ios_share_rounded),
                title: Text(isZh ? '分享图片' : 'Share image'),
                onTap: () => Navigator.pop(context, _PassportAction.share),
              ),
              ListTile(
                leading: const Icon(Icons.close_rounded),
                title: Text(isZh ? '取消' : 'Cancel'),
                onTap: () => Navigator.pop(context),
              ),
            ],
          ),
        );
      },
    );
    if (!mounted || action == null) return;
    setState(() => _busy = true);
    try {
      final bytes = await _capturePng();
      if (action == _PassportAction.save) {
        await _saveToGallery(bytes);
      } else {
        await _shareImage(bytes);
      }
    } catch (error) {
      if (mounted) _message('${context.strings.t('operationFailed')}: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<Uint8List> _capturePng() async {
    await WidgetsBinding.instance.endOfFrame;
    final renderObject = _captureKey.currentContext?.findRenderObject();
    final boundary = renderObject is RenderRepaintBoundary
        ? renderObject
        : null;
    if (boundary == null) throw StateError('Passport card is not ready');
    final image = await boundary.toImage(pixelRatio: 3);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('Unable to encode passport card');
      return data.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  Future<void> _saveToGallery(Uint8List bytes) async {
    await photo_manager.PhotoManager.editor.saveImage(
      bytes,
      filename: 'flight-passport-${_exportLabel()}.png',
      title: 'Flight Passport',
      relativePath: 'Pictures/Flight Footprint',
    );
    if (mounted) {
      _message(context.strings.isZh ? '已保存到相册' : 'Saved to Photos');
    }
  }

  Future<void> _shareImage(Uint8List bytes) async {
    final directory = await getTemporaryDirectory();
    final file = File(
      '${directory.path}/flight-passport-${_exportLabel()}.png',
    );
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'image/png')],
        title: 'Flight Passport',
      ),
    );
  }

  void _message(String message) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _exportLabel() {
    final raw = (widget.yearLabel ?? '${widget.year}').trim().toLowerCase();
    final normalized = raw.replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    return normalized.replaceAll(RegExp(r'^-+|-+$'), '').isEmpty
        ? '${widget.year}'
        : normalized.replaceAll(RegExp(r'^-+|-+$'), '');
  }
}

class _PassportArtwork extends StatelessWidget {
  const _PassportArtwork({
    required this.year,
    this.yearLabel,
    required this.travellerName,
    required this.distanceKm,
    required this.flightTimeMinutes,
    required this.flightCount,
    required this.airportCount,
    required this.routeCount,
    required this.countryCodes,
    required this.airports,
    required this.routes,
  });

  final int year;
  final String? yearLabel;
  final String travellerName;
  final double distanceKm;
  final int flightTimeMinutes;
  final int flightCount;
  final int airportCount;
  final int routeCount;
  final List<String> countryCodes;
  final List<MapAirport> airports;
  final List<MapRoute> routes;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth.isFinite
          ? constraints.maxWidth
          : 320.0;
      final horizontal = (width * .06).clamp(18.0, 26.0).toDouble();
      final routeViewport = RouteViewportPolicy.fromRoutes(routes);
      return AspectRatio(
        aspectRatio: 3 / 4,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Color(0xff060b11)),
            Positioned.fill(
              child: IgnorePointer(
                child: ClipRect(
                  child: AnimatedRotation(
                    turns: routeViewport.angle / (2 * math.pi),
                    duration: const Duration(milliseconds: 420),
                    curve: Curves.easeOutCubic,
                    child: OfflineMap(
                      mode: MapMode.flight,
                      airports: airports,
                      routes: routes,
                      enableInteraction: false,
                      fitToData: routeViewport.fitToData,
                      showGrid: false,
                      minimalWorldStyle: false,
                      transparentBackground: true,
                      bottomFade: routeViewport.usesWorldView,
                      excludePolarShelf: true,
                      animateRouteReveal: true,
                      showPassportTexture: false,
                      compactWorldViewport: true,
                      useLightPalette: false,
                      horizontalPadding: 0,
                      verticalPadding: 0,
                      // Keep route endpoints in the upper artwork area; the
                      // lower area is reserved for the distance and metrics.
                      fitDataHeightFactor: .5,
                      fitDataCenterY: routeViewport.usesWorldView ? .31 : .34,
                      fitZoomMultiplier: routeViewport.fitZoomMultiplier,
                    ),
                  ),
                ),
              ),
            ),
            _PassportDataFadeOverlay(isWorldView: routeViewport.usesWorldView),
            Padding(
              padding: EdgeInsets.fromLTRB(horizontal, 16, horizontal, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.topLeft,
                    child: _PassportHeader(
                      yearLabel: yearLabel ?? '$year',
                      travellerName: travellerName,
                    ),
                  ),
                  const Spacer(),
                  _PassportMetricRows(
                    cardWidth: width,
                    distanceKm: distanceKm,
                    flightTimeMinutes: flightTimeMinutes,
                    flightCount: flightCount,
                    airportCount: airportCount,
                    routeCount: routeCount,
                  ),
                  SizedBox(height: (width * .045).clamp(12.0, 18.0)),
                  _OverlappingFlags(countryCodes: countryCodes),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// A card-fixed lower fade that restores the quiet depth behind the data
/// block. It stays transparent through the route area, then settles into the
/// card surface underneath the metrics and flags.
class _PassportDataFadeOverlay extends StatelessWidget {
  const _PassportDataFadeOverlay({required this.isWorldView});

  final bool isWorldView;

  @override
  Widget build(BuildContext context) {
    // Match the earlier passport treatment: a restrained top vignette, a
    // clear middle map window, and a longer, denser fade behind the data.
    final stops = isWorldView
        ? const [0.0, .45, .58, .7, .84, 1.0]
        : const [0.0, .12, .36, .5, .64, .78, .92, 1.0];
    final colors = isWorldView
        ? const [
            Color(0x00060b11),
            Color(0x00060b11),
            Color(0x12060b11),
            Color(0x40060b11),
            Color(0xb0060b11),
            Color(0xff060b11),
          ]
        : const [
            Color(0xb8060b11),
            Color(0x16060b11),
            Color(0x00060b11),
            Color(0x08060b11),
            Color(0x40060b11),
            Color(0x9a060b11),
            Color(0xfc060b11),
            Color(0xff060b11),
          ];
    return Positioned.fill(
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: colors,
              stops: stops,
            ),
          ),
        ),
      ),
    );
  }
}

class _PassportHeader extends StatelessWidget {
  const _PassportHeader({required this.yearLabel, required this.travellerName});

  final String yearLabel;
  final String travellerName;

  @override
  Widget build(BuildContext context) {
    final name = travellerName.trim().isEmpty
        ? 'TRAVELER'
        : travellerName.trim();
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 210),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$yearLabel FLIGHT RECORD CARD',
            maxLines: 1,
            textAlign: TextAlign.left,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 8.5,
              fontWeight: FontWeight.w500,
              letterSpacing: 1.05,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.left,
            style: const TextStyle(
              color: AppColors.lime,
              fontSize: 18,
              height: 1,
              fontWeight: FontWeight.w600,
              letterSpacing: -.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _PassportMetricRows extends StatelessWidget {
  const _PassportMetricRows({
    required this.cardWidth,
    required this.distanceKm,
    required this.flightTimeMinutes,
    required this.flightCount,
    required this.airportCount,
    required this.routeCount,
  });

  final double cardWidth;
  final double distanceKm;
  final int flightTimeMinutes;
  final int flightCount;
  final int airportCount;
  final int routeCount;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'FLIGHT DISTANCE',
        style: TextStyle(
          color: AppColors.textSecondary,
          fontSize: 9,
          fontWeight: FontWeight.w500,
          letterSpacing: 1.15,
        ),
      ),
      const SizedBox(height: 3),
      SizedBox(
        height: (cardWidth * .14).clamp(42.0, 58.0),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: _number(distanceKm.round())),
                const TextSpan(
                  text: '  KM',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
            maxLines: 1,
            style: TextStyle(
              color: AppColors.lime,
              fontSize: (cardWidth * .145).clamp(44.0, 60.0),
              height: .95,
              fontWeight: FontWeight.w700,
              letterSpacing: -1.8,
              fontFeatures: const [ui.FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
      SizedBox(height: (cardWidth * .045).clamp(12.0, 18.0)),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _CompactPassportMetric(
              label: 'FLIGHT TIME',
              value: _number(_hours(flightTimeMinutes)),
              unit: 'h',
            ),
          ),
          Expanded(
            child: _CompactPassportMetric(
              label: 'FLIGHTS',
              value: _number(flightCount),
              alignment: CrossAxisAlignment.center,
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: _CompactPassportMetric(
              label: 'AIRPORTS',
              value: _number(airportCount),
              alignment: CrossAxisAlignment.center,
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: _CompactPassportMetric(
              label: 'ROUTES',
              value: _number(routeCount),
              alignment: CrossAxisAlignment.end,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    ],
  );

  static int _hours(int minutes) => minutes <= 0 ? 0 : (minutes / 60).round();

  static String _number(int value) => value.toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
}

class _CompactPassportMetric extends StatelessWidget {
  const _CompactPassportMetric({
    required this.label,
    required this.value,
    this.unit,
    this.alignment = CrossAxisAlignment.start,
    this.textAlign = TextAlign.left,
  });

  final String label;
  final String value;
  final String? unit;
  final CrossAxisAlignment alignment;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: alignment,
    children: [
      Text(
        label,
        textAlign: textAlign,
        maxLines: 1,
        overflow: TextOverflow.fade,
        softWrap: false,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 7.2,
          fontWeight: FontWeight.w500,
          letterSpacing: .65,
        ),
      ),
      const SizedBox(height: 4),
      Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            value,
            textAlign: textAlign,
            style: const TextStyle(
              color: AppColors.lime,
              fontSize: 20,
              height: .98,
              fontWeight: FontWeight.w600,
              letterSpacing: -.55,
              fontFeatures: [ui.FontFeature.tabularFigures()],
            ),
          ),
          if (unit != null) ...[
            const SizedBox(width: 4),
            Text(
              unit!,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    ],
  );
}

class _OverlappingFlags extends StatelessWidget {
  const _OverlappingFlags({required this.countryCodes});

  final List<String> countryCodes;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (countryCodes.isEmpty) return const SizedBox(height: 34);
      const size = 28.0;
      const step = 18.0;
      final maxVisible = mathMax(
        1,
        ((constraints.maxWidth - size) / step).floor() + 1,
      );
      final hasMore = countryCodes.length > maxVisible;
      final visibleCount = hasMore
          ? mathMax(1, maxVisible - 1)
          : countryCodes.length;
      final shown = countryCodes.take(visibleCount).toList(growable: false);
      final extra = countryCodes.length - shown.length;
      final itemCount = shown.length + (hasMore ? 1 : 0);
      final rowWidth = size + (itemCount - 1) * step;
      return SizedBox(
        height: size,
        child: Align(
          alignment: Alignment.center,
          child: SizedBox(
            width: rowWidth,
            height: size,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                for (var index = 0; index < shown.length; index++)
                  Positioned(
                    left: index * step,
                    child: _FlagCircle(code: shown[index]),
                  ),
                if (hasMore)
                  Positioned(
                    left: (itemCount - 1) * step,
                    child: _FlagCircle(flag: '+$extra', compact: true),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );

  static int mathMax(int a, int b) => a > b ? a : b;
}

class _FlagCircle extends StatelessWidget {
  const _FlagCircle({this.code, this.flag, this.compact = false})
    : assert(code != null || flag != null);

  final String? code;
  final String? flag;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (!compact && code != null) {
      return CountryFlag(code: code!, size: 28);
    }
    return Container(
      width: 28,
      height: 28,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: compact ? AppColors.surfaceElevated : Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.textSecondary, width: .8),
      ),
      alignment: Alignment.center,
      child: compact
          ? Text(
              flag!,
              maxLines: 1,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            )
          : const Icon(
              Icons.public_rounded,
              size: 18,
              color: AppColors.textSecondary,
            ),
    );
  }
}

// Kept as a lightweight fallback for future non-emoji export modes.
// ignore: unused_element
class _CountryFlagPainter extends CustomPainter {
  const _CountryFlagPainter(this.code);

  final String code;

  static const _navy = Color(0xff142d55);
  static const _red = Color(0xffd83b45);
  static const _gold = Color(0xffffd447);
  static const _green = Color(0xff2f9b67);
  static const _blue = Color(0xff3d6fd3);
  static const _white = Color(0xfff5f5f2);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.save();
    canvas.clipPath(Path()..addOval(rect));
    _paintBase(canvas, rect);
    canvas.restore();
  }

  void _paintBase(Canvas canvas, Rect rect) {
    final code = this.code.trim().toUpperCase();
    switch (code) {
      case 'CN':
        _fill(canvas, rect, _red);
        _star(
          canvas,
          rect.centerLeft.translate(rect.width * .12, -rect.height * .16),
          rect.width * .11,
          _gold,
        );
      case 'US':
        _horizontal(canvas, rect, const [
          _red,
          _white,
          _red,
          _white,
          _red,
          _white,
          _red,
        ]);
        canvas.drawRect(
          Rect.fromLTWH(0, 0, rect.width * .48, rect.height * .52),
          Paint()..color = _navy,
        );
      case 'GB':
        _fill(canvas, rect, _navy);
        _cross(canvas, rect, _white, _red);
      case 'SG':
        _horizontal(canvas, rect, const [_red, _white]);
        canvas.drawCircle(
          rect.centerLeft.translate(rect.width * .12, -rect.height * .13),
          rect.width * .16,
          Paint()..color = _white,
        );
        canvas.drawCircle(
          rect.centerLeft.translate(rect.width * .18, -rect.height * .13),
          rect.width * .13,
          Paint()..color = _red,
        );
      case 'AU':
        _fill(canvas, rect, _navy);
        _miniUnionJack(
          canvas,
          Rect.fromLTWH(0, 0, rect.width * .48, rect.height * .52),
        );
        _star(
          canvas,
          rect.center.translate(rect.width * .16, rect.height * .16),
          rect.width * .07,
          _white,
        );
        _star(
          canvas,
          rect.center.translate(-rect.width * .02, rect.height * .22),
          rect.width * .045,
          _white,
        );
      case 'CA':
        _vertical(canvas, rect, const [_red, _white, _red]);
        _maple(canvas, rect.center, rect.width * .16, _red);
      case 'DE':
        _horizontal(canvas, rect, const [Colors.black, _red, _gold]);
      case 'JP':
        _fill(canvas, rect, _white);
        canvas.drawCircle(rect.center, rect.width * .19, Paint()..color = _red);
      case 'FR':
        _vertical(canvas, rect, const [_blue, _white, _red]);
      case 'NL':
        _horizontal(canvas, rect, const [_red, _white, _blue]);
      case 'BR':
        _fill(canvas, rect, _green);
        final diamond = Path()
          ..moveTo(rect.center.dx, rect.top + rect.height * .16)
          ..lineTo(rect.right - rect.width * .16, rect.center.dy)
          ..lineTo(rect.center.dx, rect.bottom - rect.height * .16)
          ..lineTo(rect.left + rect.width * .16, rect.center.dy)
          ..close();
        canvas.drawPath(diamond, Paint()..color = _gold);
        canvas.drawCircle(
          rect.center,
          rect.width * .17,
          Paint()..color = _blue,
        );
      case 'KR':
        _fill(canvas, rect, _white);
        canvas.drawCircle(
          rect.center.translate(-rect.width * .035, 0),
          rect.width * .15,
          Paint()..color = _red,
        );
        canvas.drawCircle(
          rect.center.translate(rect.width * .035, 0),
          rect.width * .15,
          Paint()..color = _blue,
        );
      case 'HK':
        _fill(canvas, rect, _red);
        canvas.drawCircle(
          rect.center,
          rect.width * .17,
          Paint()..color = _white,
        );
        canvas.drawCircle(rect.center, rect.width * .09, Paint()..color = _red);
      case 'ID':
        _horizontal(canvas, rect, const [_red, _white]);
      case 'TH':
        _horizontal(canvas, rect, const [_red, _white, _blue, _white, _red]);
      case 'MY':
        _horizontal(canvas, rect, const [
          _red,
          _white,
          _red,
          _white,
          _red,
          _white,
          _red,
        ]);
        canvas.drawRect(
          Rect.fromLTWH(0, 0, rect.width * .5, rect.height * .5),
          Paint()..color = _navy,
        );
        _star(
          canvas,
          rect.centerLeft.translate(rect.width * .2, -rect.height * .1),
          rect.width * .09,
          _gold,
        );
      case 'IN':
        _horizontal(canvas, rect, const [Color(0xffffa83d), _white, _green]);
        canvas.drawCircle(
          rect.center,
          rect.width * .08,
          Paint()..color = _navy,
        );
      case 'AE':
        _vertical(canvas, rect, const [_red, _green, _white]);
        canvas.drawRect(
          Rect.fromLTWH(
            rect.width * .33,
            rect.height * .66,
            rect.width * .67,
            rect.height * .34,
          ),
          Paint()..color = Colors.black,
        );
      case 'QA':
        _vertical(canvas, rect, const [Color(0xff7d1748), _white]);
      case 'VN':
        _fill(canvas, rect, _red);
        _star(canvas, rect.center, rect.width * .17, _gold);
      case 'PH':
        _horizontal(canvas, rect, const [_blue, _red]);
        final triangle = Path()
          ..moveTo(rect.left, rect.top)
          ..lineTo(rect.left, rect.bottom)
          ..lineTo(rect.left + rect.width * .5, rect.center.dy)
          ..close();
        canvas.drawPath(triangle, Paint()..color = _white);
        _star(
          canvas,
          Offset(rect.left + rect.width * .18, rect.center.dy),
          rect.width * .07,
          _gold,
        );
      default:
        _fallback(canvas, rect, code);
    }
  }

  void _fallback(Canvas canvas, Rect rect, String code) {
    const colors = [_navy, _red, _gold, _green, _blue, Color(0xffa56de2)];
    final hash = code.codeUnits.fold<int>(
      0,
      (value, item) => value * 31 + item,
    );
    _horizontal(canvas, rect, [
      colors[hash.abs() % colors.length],
      colors[(hash ~/ 3).abs() % colors.length],
      colors[(hash ~/ 7).abs() % colors.length],
    ]);
  }

  void _fill(Canvas canvas, Rect rect, Color color) =>
      canvas.drawRect(rect, Paint()..color = color);

  void _horizontal(Canvas canvas, Rect rect, List<Color> colors) {
    final height = rect.height / colors.length;
    for (var index = 0; index < colors.length; index++) {
      canvas.drawRect(
        Rect.fromLTWH(
          rect.left,
          rect.top + height * index,
          rect.width,
          height + .5,
        ),
        Paint()..color = colors[index],
      );
    }
  }

  void _vertical(Canvas canvas, Rect rect, List<Color> colors) {
    final width = rect.width / colors.length;
    for (var index = 0; index < colors.length; index++) {
      canvas.drawRect(
        Rect.fromLTWH(
          rect.left + width * index,
          rect.top,
          width + .5,
          rect.height,
        ),
        Paint()..color = colors[index],
      );
    }
  }

  void _cross(Canvas canvas, Rect rect, Color under, Color over) {
    canvas.drawRect(
      Rect.fromLTWH(
        rect.left,
        rect.center.dy - rect.height * .12,
        rect.width,
        rect.height * .24,
      ),
      Paint()..color = under,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        rect.center.dx - rect.width * .12,
        rect.top,
        rect.width * .24,
        rect.height,
      ),
      Paint()..color = under,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        rect.left,
        rect.center.dy - rect.height * .055,
        rect.width,
        rect.height * .11,
      ),
      Paint()..color = over,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        rect.center.dx - rect.width * .055,
        rect.top,
        rect.width * .11,
        rect.height,
      ),
      Paint()..color = over,
    );
  }

  void _miniUnionJack(Canvas canvas, Rect rect) {
    _fill(canvas, rect, _navy);
    _cross(canvas, rect, _white, _red);
  }

  void _star(Canvas canvas, Offset center, double radius, Color color) {
    final path = Path();
    for (var index = 0; index < 10; index++) {
      final angle = -math.pi / 2 + index * math.pi / 5;
      final currentRadius = index.isEven ? radius : radius * .42;
      final point =
          center + Offset(math.cos(angle), math.sin(angle)) * currentRadius;
      if (index == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color);
  }

  void _maple(Canvas canvas, Offset center, double radius, Color color) {
    final path = Path()
      ..moveTo(center.dx, center.dy - radius)
      ..lineTo(center.dx + radius * .2, center.dy - radius * .35)
      ..lineTo(center.dx + radius * .7, center.dy - radius * .55)
      ..lineTo(center.dx + radius * .38, center.dy)
      ..lineTo(center.dx + radius * .7, center.dy + radius * .55)
      ..lineTo(center.dx + radius * .2, center.dy + radius * .35)
      ..lineTo(center.dx, center.dy + radius)
      ..lineTo(center.dx - radius * .2, center.dy + radius * .35)
      ..lineTo(center.dx - radius * .7, center.dy + radius * .55)
      ..lineTo(center.dx - radius * .38, center.dy)
      ..lineTo(center.dx - radius * .7, center.dy - radius * .55)
      ..lineTo(center.dx - radius * .2, center.dy - radius * .35)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _CountryFlagPainter oldDelegate) =>
      oldDelegate.code != code;
}

const _dotGlyphs = <String, List<String>>{
  'A': ['01110', '10001', '10001', '11111', '10001', '10001', '10001'],
  'B': ['11110', '10001', '10001', '11110', '10001', '10001', '11110'],
  'C': ['01111', '10000', '10000', '10000', '10000', '10000', '01111'],
  'D': ['11110', '10001', '10001', '10001', '10001', '10001', '11110'],
  'E': ['11111', '10000', '10000', '11110', '10000', '10000', '11111'],
  'F': ['11111', '10000', '10000', '11110', '10000', '10000', '10000'],
  'G': ['01111', '10000', '10000', '10111', '10001', '10001', '01111'],
  'H': ['10001', '10001', '10001', '11111', '10001', '10001', '10001'],
  'I': ['11111', '00100', '00100', '00100', '00100', '00100', '11111'],
  'J': ['00111', '00010', '00010', '00010', '10010', '10010', '01100'],
  'K': ['10001', '10010', '10100', '11000', '10100', '10010', '10001'],
  'L': ['10000', '10000', '10000', '10000', '10000', '10000', '11111'],
  'M': ['10001', '11011', '10101', '10101', '10001', '10001', '10001'],
  'N': ['10001', '11001', '11001', '10101', '10011', '10011', '10001'],
  'O': ['01110', '10001', '10001', '10001', '10001', '10001', '01110'],
  'P': ['11110', '10001', '10001', '11110', '10000', '10000', '10000'],
  'Q': ['01110', '10001', '10001', '10001', '10101', '10010', '01101'],
  'R': ['11110', '10001', '10001', '11110', '10100', '10010', '10001'],
  'S': ['01111', '10000', '10000', '01110', '00001', '00001', '11110'],
  'T': ['11111', '00100', '00100', '00100', '00100', '00100', '00100'],
  'U': ['10001', '10001', '10001', '10001', '10001', '10001', '01110'],
  'V': ['10001', '10001', '10001', '10001', '10001', '01010', '00100'],
  'W': ['10001', '10001', '10001', '10101', '10101', '11011', '10001'],
  'X': ['10001', '10001', '01010', '00100', '01010', '10001', '10001'],
  'Y': ['10001', '10001', '01010', '00100', '00100', '00100', '00100'],
  'Z': ['11111', '00001', '00010', '00100', '01000', '10000', '11111'],
};

class _DotMatrixTextPainter extends CustomPainter {
  const _DotMatrixTextPainter(this.text);

  final String text;

  @override
  void paint(Canvas canvas, Size size) {
    final chars = text.toUpperCase().split('');
    final columns = chars.fold<int>(0, (total, char) {
      final glyphWidth = char == ' ' ? 3 : 5;
      return total + glyphWidth + 1;
    });
    if (columns <= 0 || size.width <= 0 || size.height <= 0) return;
    final cell = math.min(size.width / columns, size.height / 7);
    final totalWidth = columns * cell;
    final left = (size.width - totalWidth) / 2;
    final top = (size.height - 7 * cell) / 2;
    final paint = Paint()
      ..color = AppColors.textSecondary.withValues(alpha: .86);
    var x = left;
    for (final char in chars) {
      final glyph = _dotGlyphs[char];
      if (glyph == null) {
        x += 4 * cell;
        continue;
      }
      for (var row = 0; row < glyph.length; row++) {
        for (var col = 0; col < glyph[row].length; col++) {
          if (glyph[row][col] != '1') continue;
          canvas.drawCircle(
            Offset(x + (col + .5) * cell, top + (row + .5) * cell),
            cell * .22,
            paint,
          );
        }
      }
      x += 6 * cell;
    }
  }

  @override
  bool shouldRepaint(covariant _DotMatrixTextPainter oldDelegate) =>
      oldDelegate.text != text;
}
