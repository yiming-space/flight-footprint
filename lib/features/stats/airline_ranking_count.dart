import 'package:flutter/material.dart';

/// A paint-only count-up driven by the capsule's existing entrance animation.
/// No second controller, delayed ticker, or layout changes between numbers.
class AirlineRankingCount extends StatelessWidget {
  const AirlineRankingCount({
    super.key,
    required this.count,
    required this.reveal,
    required this.labelForCount,
    required this.style,
  });

  final int count;
  final double reveal;
  final String Function(int) labelForCount;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.maybeOf(context);
    final reduced =
        (media?.disableAnimations ?? false) ||
        (media?.accessibleNavigation ?? false);
    final progress = reduced ? 1.0 : reveal.clamp(0.0, 1.0);
    final finalLabel = labelForCount(count);
    if (progress >= 1 || count <= 0) {
      return Text(finalLabel, textAlign: TextAlign.end, style: style);
    }
    final value = count * progress;
    final current = value.floor();
    final fraction = value - current;
    Widget label(int value) =>
        Text(labelForCount(value), textAlign: TextAlign.end, style: style);
    return ClipRect(
      child: Stack(
        alignment: AlignmentDirectional.centerEnd,
        children: [
          // Reserve the final text height even at digit/plural boundaries.
          Opacity(opacity: 0, child: label(count)),
          Positioned.fill(
            child: Opacity(
              key: const ValueKey('airline-count-outgoing'),
              opacity: 1 - fraction,
              child: Transform.translate(
                offset: Offset(0, -4 * fraction),
                child: label(current),
              ),
            ),
          ),
          if (fraction > 0)
            Positioned.fill(
              child: Opacity(
                key: const ValueKey('airline-count-incoming'),
                opacity: fraction,
                child: Transform.translate(
                  offset: Offset(0, 4 * (1 - fraction)),
                  child: label(current + 1),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
