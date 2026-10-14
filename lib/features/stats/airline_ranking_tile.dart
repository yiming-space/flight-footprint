import 'package:flutter/material.dart';

import '../../ui/widgets/airline_logo.dart';
import 'airline_ranking_row.dart';
import 'airline_ranking_count.dart';

/// Keeps a logo's sampled brand color local to its row, so resolving an image
/// never rebuilds the map or the rest of the statistics page.
class AirlineRankingTile extends StatefulWidget {
  const AirlineRankingTile({
    super.key,
    required this.name,
    required this.iataCode,
    required this.count,
    required this.maxCount,
    required this.rank,
    required this.countLabel,
    required this.onTap,
    this.fillReveal = 1,
    this.animatedCountLabel,
  });

  final String name;
  final String? iataCode;
  final int count;
  final int maxCount;
  final int rank;
  final String countLabel;
  final VoidCallback onTap;
  final double fillReveal;
  final String Function(int)? animatedCountLabel;

  @override
  State<AirlineRankingTile> createState() => _AirlineRankingTileState();
}

class _AirlineRankingTileState extends State<AirlineRankingTile> {
  Color? _brandColor;

  @override
  void didUpdateWidget(covariant AirlineRankingTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.iataCode != widget.iataCode) _brandColor = null;
  }

  @override
  Widget build(BuildContext context) => AirlineRankingRow(
    name: widget.name,
    count: widget.count,
    maxCount: widget.maxCount,
    rank: widget.rank,
    countLabel: widget.countLabel,
    accentColor: _brandColor,
    leading: AirlineLogo(
      key: ValueKey(widget.iataCode),
      iataCode: widget.iataCode,
      onColorResolved: (color) {
        if (mounted && color != _brandColor) {
          setState(() => _brandColor = color);
        }
      },
    ),
    onTap: widget.onTap,
    fillReveal: widget.fillReveal,
    followFill: widget.animatedCountLabel != null,
    countBuilder: widget.animatedCountLabel == null
        ? null
        : (style) => AirlineRankingCount(
            key: ValueKey('airline-ranking-count-${widget.rank}'),
            count: widget.count,
            reveal: widget.fillReveal,
            labelForCount: widget.animatedCountLabel!,
            style: style,
          ),
  );
}
