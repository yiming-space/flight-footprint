import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../ui/theme/app_theme.dart';

/// Shared four-column rhythm for the four exploration memories.
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
  Widget build(BuildContext context) {
    final height = math.max(260.0, minHeight - padding.vertical);
    final textScale = MediaQuery.textScalerOf(context).scale(16) / 16;
    final headerHeight = textScale <= 1.15 ? 48.0 : 80 * textScale;
    final footerHeight = math.max(48.0, 60 * textScale);
    if (minHeight <= 0) {
      return ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 260),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: headerHeight,
              child: Align(alignment: Alignment.centerLeft, child: heading),
            ),
            const SizedBox(height: 8),
            body,
            if (footer != null) ...[
              const SizedBox(height: 12),
              SizedBox(height: footerHeight, child: footer),
            ],
          ],
        ),
      );
    }
    return SizedBox(
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            key: const ValueKey('exploration-memory-header'),
            height: headerHeight,
            child: Align(alignment: Alignment.centerLeft, child: heading),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                key: const ValueKey('exploration-memory-body-scroll'),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Align(alignment: Alignment.center, child: body),
                ),
              ),
            ),
          ),
          if (footer != null) ...[
            const SizedBox(height: 8),
            SizedBox(
              key: const ValueKey('exploration-memory-footer'),
              height: footerHeight,
              child: footer,
            ),
          ],
        ],
      ),
    );
  }
}

/// Two equal-width footer cells align labels and values on a shared baseline.
class ExplorationMemoryFooter extends StatelessWidget {
  const ExplorationMemoryFooter({
    super.key,
    required this.leftLabel,
    required this.leftValue,
    required this.rightLabel,
    required this.rightValue,
    this.inline = false,
  });

  final String leftLabel;
  final Widget leftValue;
  final String rightLabel;
  final Widget rightValue;
  final bool inline;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    if (inline) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            key: const ValueKey('exploration-memory-footer-left'),
            child: Text(
              leftLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.label.copyWith(
                color: colors.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            key: const ValueKey('exploration-memory-footer-right'),
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: rightValue,
            ),
          ),
        ],
      );
    }
    Widget cell(String label, Widget value, {bool end = false}) => Column(
      crossAxisAlignment: end
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: end ? TextAlign.end : TextAlign.start,
          style: AppTextStyles.label.copyWith(
            color: colors.textSecondary,
            fontSize: 12,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: end
              ? AlignmentDirectional.centerEnd
              : AlignmentDirectional.centerStart,
          child: value,
        ),
      ],
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          key: const ValueKey('exploration-memory-footer-left'),
          child: cell(leftLabel, leftValue),
        ),
        const SizedBox(width: 8),
        Expanded(
          key: const ValueKey('exploration-memory-footer-right'),
          child: cell(rightLabel, rightValue, end: true),
        ),
      ],
    );
  }
}
