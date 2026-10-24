import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Shared spacing keeps the four memories anchored while their glass shells
/// stretch to the height of the tallest card. Content can still grow for text.
class ExplorationMemoryLayout extends StatelessWidget {
  const ExplorationMemoryLayout({
    super.key,
    required this.minHeight,
    required this.heading,
    required this.body,
    this.footer,
  });

  static const padding = EdgeInsets.fromLTRB(16, 12, 16, 20);

  final double minHeight;
  final Widget heading;
  final Widget body;
  final Widget? footer;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(
      minHeight: math.max(280, minHeight - padding.vertical),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Align(alignment: Alignment.centerLeft, child: heading),
            ),
            const SizedBox(height: 16),
            body,
          ],
        ),
        if (footer != null)
          Padding(padding: const EdgeInsets.only(top: 24), child: footer),
      ],
    ),
  );
}
