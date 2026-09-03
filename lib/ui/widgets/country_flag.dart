import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/app_theme.dart';

/// A small, local ISO 3166-1 alpha-2 flag badge.
///
/// The source SVGs are bundled with the app so the badge works offline and
/// stays crisp in both the UI and the passport PNG export. The circular
/// treatment is applied here instead of baking a separate bitmap for each
/// country, which keeps the assets compact and consistent.
class CountryFlag extends StatelessWidget {
  const CountryFlag({
    super.key,
    required this.code,
    this.size = 28,
    this.showBorder = true,
  });

  final String code;
  final double size;
  final bool showBorder;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final normalized = code.trim().toLowerCase();
    final valid = RegExp(r'^[a-z]{2}$').hasMatch(normalized);
    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Colors.white),
            if (valid)
              SvgPicture.asset(
                'assets/flags/1x1/$normalized.svg',
                fit: BoxFit.fill,
                semanticsLabel: 'Country flag ${normalized.toUpperCase()}',
                placeholderBuilder: (context) => const _UnknownCountryFlag(),
                errorBuilder: (context, error, stackTrace) =>
                    const _UnknownCountryFlag(),
              )
            else
              const _UnknownCountryFlag(),
            if (normalized == 'us')
              const CustomPaint(painter: _UsStarOverlay()),
            if (showBorder)
              IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: colors.textSecondary, width: .8),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _UnknownCountryFlag extends StatelessWidget {
  const _UnknownCountryFlag();

  @override
  Widget build(BuildContext context) => Icon(
    Icons.public_rounded,
    size: 18,
    color: context.appColors.textSecondary,
  );
}

/// flutter_svg intentionally does not implement SVG markers. The upstream
/// US flag uses a marker for its stars, so keep the source flag for the
/// stripes/canton and paint the 50 stars as a tiny vector overlay.
class _UsStarOverlay extends CustomPainter {
  const _UsStarOverlay();

  // Five rows of six stars plus four rows of five stars = 50 total.
  static const _oddRows = <double>[25, 75, 125, 175];
  static const _evenRows = <double>[50, 100, 150, 200, 250];

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white;
    for (final y in _oddRows) {
      for (final x in const <double>[48, 122, 196, 270, 344]) {
        _star(canvas, size, x, y, paint);
      }
    }
    for (final y in _evenRows) {
      for (final x in const <double>[28, 95, 162, 229, 296, 363]) {
        _star(canvas, size, x, y, paint);
      }
    }
  }

  void _star(Canvas canvas, Size size, double x, double y, Paint paint) {
    final center = Offset(size.width * x / 512, size.height * y / 512);
    final outer = size.width * 11 / 512;
    final inner = outer * .42;
    final path = Path();
    for (var index = 0; index < 10; index++) {
      final angle = -math.pi / 2 + index * math.pi / 5;
      final radius = index.isEven ? outer : inner;
      final point = Offset(
        center.dx + math.cos(angle) * radius,
        center.dy + math.sin(angle) * radius,
      );
      if (index == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _UsStarOverlay oldDelegate) => false;
}
