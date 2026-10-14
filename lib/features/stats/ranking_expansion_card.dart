import 'package:flutter/material.dart';

import 'ranking_expansion_route.dart';
import 'ranking_overview_card.dart';

/// A statistics entry with one reversible, source-anchored page transition.
/// The overview face stays shared; only navigation and press feedback live here.
class RankingExpansionCard extends StatefulWidget {
  const RankingExpansionCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.keyPrefix,
    this.onTap,
    this.pageBuilder,
  }) : assert(onTap != null || pageBuilder != null);

  final String title;
  final String subtitle;
  final IconData icon;
  final String keyPrefix;
  final VoidCallback? onTap;
  final WidgetBuilder? pageBuilder;

  @override
  State<RankingExpansionCard> createState() => _RankingExpansionCardState();
}

class _RankingExpansionCardState extends State<RankingExpansionCard> {
  bool _pressed = false;
  bool _opening = false;
  bool _hidden = false;
  Offset? _pressOrigin;

  bool get _reduced {
    final media = MediaQuery.maybeOf(context);
    return (media?.disableAnimations ?? false) ||
        (media?.accessibleNavigation ?? false);
  }

  void _setPressed(bool value) {
    if (mounted && _pressed != value) setState(() => _pressed = value);
  }

  Future<void> _open() async {
    if (_opening || !mounted) return;
    final builder = widget.pageBuilder;
    if (builder == null) {
      widget.onTap?.call();
      return;
    }
    final navigator = Navigator.of(context);
    final box = context.findRenderObject();
    final overlay = navigator.overlay?.context.findRenderObject();
    var rect = Rect.zero;
    if (box is RenderBox && box.hasSize && overlay is RenderBox) {
      rect = MatrixUtils.transformRect(
        box.getTransformTo(overlay),
        Offset.zero & box.size,
      );
    }
    final route = rankingExpansionRoute<void>(
      context: context,
      sourceRect: rect,
      builder: builder,
    );
    final custom = route is PageRouteBuilder<void> && !_reduced;
    Animation<double>? animation;
    void restore() {
      if (mounted &&
          _hidden &&
          animation?.status == AnimationStatus.reverse &&
          animation!.value <= .12) {
        setState(() => _hidden = false);
      }
    }

    setState(() {
      _opening = true;
      _hidden = false;
      _pressed = false;
    });
    try {
      final popped = navigator.push<void>(route);
      if (custom) {
        animation = route.animation;
        animation?.addListener(restore);
        // Keep the source during Navigator's offstage measurement frame.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted &&
              _opening &&
              route.isActive &&
              (animation?.status == AnimationStatus.forward ||
                  animation?.status == AnimationStatus.completed)) {
            setState(() => _hidden = true);
          }
        });
      }
      await popped;
      if (route is TransitionRoute<void>) await route.completed;
    } finally {
      animation?.removeListener(restore);
      if (mounted) {
        setState(() {
          _opening = false;
          _hidden = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '${widget.title}, ${widget.subtitle}',
    onTap: _open,
    excludeSemantics: true,
    hidden: _hidden,
    child: Opacity(
      key: ValueKey('${widget.keyPrefix}-source'),
      opacity: _hidden ? 0 : 1,
      child: Listener(
        onPointerDown: (event) {
          _pressOrigin = event.localPosition;
          _setPressed(true);
        },
        onPointerMove: (event) {
          if (_pressOrigin != null &&
              (event.localPosition - _pressOrigin!).distance > 8) {
            _setPressed(false);
          }
        },
        onPointerUp: (_) {
          _pressOrigin = null;
          _setPressed(false);
        },
        onPointerCancel: (_) {
          _pressOrigin = null;
          _setPressed(false);
        },
        child: AnimatedScale(
          key: ValueKey('${widget.keyPrefix}-press'),
          scale: _pressed && !_reduced ? .985 : 1,
          duration: const Duration(milliseconds: 80),
          curve: Curves.easeOut,
          child: RankingOverviewCard(
            title: widget.title,
            subtitle: widget.subtitle,
            icon: widget.icon,
            onTap: _open,
          ),
        ),
      ),
    ),
  );
}
