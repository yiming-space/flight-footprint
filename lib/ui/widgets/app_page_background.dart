import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Shared page canvas for the app's non-map surfaces.
class AppPageBackground extends StatelessWidget {
  const AppPageBackground({super.key, this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: isDark ? colors.background : const Color(0xFFFCFDFE)),
        if (!isDark) ...const [
          _ColorWash(
            center: Alignment(-1.05, -1.04),
            radius: 1.04,
            color: Color(0x999EBFDC),
          ),
          _ColorWash(
            center: Alignment(0.76, -0.68),
            radius: 1.14,
            color: Color(0x80BBDDD9),
          ),
          _ColorWash(
            center: Alignment(-0.88, 0.14),
            radius: 1.08,
            color: Color(0x80E2D5DF),
          ),
          _ColorWash(
            center: Alignment(0.98, 0.70),
            radius: 1.10,
            color: Color(0x8AC6B7DE),
          ),
        ],
        if (child != null) Positioned.fill(child: child!),
      ],
    );
  }
}

class _ColorWash extends StatelessWidget {
  const _ColorWash({
    required this.center,
    required this.radius,
    required this.color,
  });

  final Alignment center;
  final double radius;
  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: RadialGradient(
        center: center,
        radius: radius,
        colors: [
          color,
          color.withValues(alpha: color.a * .82),
          color.withValues(alpha: color.a * .24),
          color.withValues(alpha: 0),
        ],
        stops: const [0, .22, .68, 1],
      ),
    ),
  );
}
