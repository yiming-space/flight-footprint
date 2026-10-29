import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ui/theme/app_theme.dart';

/// A finite, horizontally swiped set of the four exploration memories.
class ExplorationMemoryCarousel extends StatefulWidget {
  const ExplorationMemoryCarousel({
    super.key,
    required this.cards,
    required this.labels,
  }) : assert(cards.length == labels.length);

  final List<Widget> cards;
  final List<String> labels;

  @override
  State<ExplorationMemoryCarousel> createState() =>
      _ExplorationMemoryCarouselState();
}

class _ExplorationMemoryCarouselState extends State<ExplorationMemoryCarousel> {
  late final PageController _controller = PageController();
  int _index = 0;

  @override
  void didUpdateWidget(covariant ExplorationMemoryCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_index >= widget.cards.length) {
      _index = widget.cards.isEmpty ? 0 : widget.cards.length - 1;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _controller.hasClients) _controller.jumpToPage(_index);
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goTo(int index) {
    if (widget.cards.isEmpty) return;
    final target = index.clamp(0, widget.cards.length - 1);
    if (target == _index) return;
    final media = MediaQuery.of(context);
    if (media.disableAnimations || media.accessibleNavigation) {
      _controller.jumpToPage(target);
    } else {
      _controller.animateToPage(
        target,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.pageDown) {
      _goTo(_index + 1);
    } else if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.pageUp) {
      _goTo(_index - 1);
    } else if (key == LogicalKeyboardKey.home) {
      _goTo(0);
    } else if (key == LogicalKeyboardKey.end) {
      _goTo(widget.cards.length - 1);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.cards.isEmpty) return const SizedBox.shrink();
    final textScale = MediaQuery.textScalerOf(context).scale(16) / 16;
    final pageHeight = (300 * textScale).clamp(280.0, 640.0);
    final colors = context.appColors;
    return Semantics(
      key: const ValueKey('exploration-memory-deck-semantics'),
      container: true,
      label: widget.labels[_index],
      value: '${_index + 1} / ${widget.cards.length}',
      increasedValue: _index + 1 < widget.cards.length
          ? widget.labels[_index + 1]
          : null,
      decreasedValue: _index > 0 ? widget.labels[_index - 1] : null,
      onIncrease: _index + 1 < widget.cards.length
          ? () => _goTo(_index + 1)
          : null,
      onDecrease: _index > 0 ? () => _goTo(_index - 1) : null,
      child: Focus(
        onKeyEvent: _onKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: pageHeight,
              child: PageView.builder(
                key: const ValueKey('exploration-memory-deck'),
                controller: _controller,
                itemCount: widget.cards.length,
                onPageChanged: (index) => setState(() => _index = index),
                itemBuilder: (context, index) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: KeyedSubtree(
                    key: ValueKey('memory-page-card-$index'),
                    child: widget.cards[index],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var index = 0; index < widget.cards.length; index++)
                  AnimatedContainer(
                    key: ValueKey('memory-carousel-dot-$index'),
                    duration: const Duration(milliseconds: 120),
                    curve: Curves.easeOut,
                    width: _index == index ? 8 : 6,
                    height: _index == index ? 8 : 6,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: _index == index
                          ? colors.lime
                          : colors.textTertiary,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
