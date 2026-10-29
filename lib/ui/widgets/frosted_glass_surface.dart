import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../theme/app_theme.dart';

/// A reusable, softly frosted glass surface with a thin reflective rim.
class FrostedGlassSurface extends StatefulWidget {
  const FrostedGlassSurface({
    super.key,
    required this.shape,
    required this.child,
    this.visible = true,
    this.refractionRadius,
    this.edgeThickness = 1,
    this.adaptiveContrast = false,
    this.tintOpacity,
    this.highlightStrength = 1,
    this.liquidRefraction = false,
    this.environmentReflectionStrength = 1,
    this.backgroundResponsiveHighlights = false,
    this.useLocalRefraction = false,
    this.tintColor = Colors.white,
    this.showRim = true,
  }) : assert(edgeThickness >= 1 && edgeThickness <= 2),
       assert(tintOpacity == null || (tintOpacity >= 0 && tintOpacity <= 1)),
       assert(highlightStrength >= 0 && highlightStrength <= 2),
       assert(
         environmentReflectionStrength >= 0 &&
             environmentReflectionStrength <= 2,
       );

  final ShapeBorder shape;
  final Widget child;
  final bool visible;

  /// Override only for non-capsule shapes; controls keep their original lens.
  final double? refractionRadius;

  /// Controls retain their original rim; large cards can use a deeper bevel.
  final double edgeThickness;

  /// Separates floating navigation from bright content using backdrop luminance.
  final bool adaptiveContrast;

  /// White scattering in the glass body, independent of reflective edges.
  final double? tintOpacity;
  final Color tintColor;

  /// Printed artwork can place this same rim above its map, below its text.
  final bool showRim;

  /// Resolve the lens in filter-texture coordinates for transformed card decks.
  /// Floating controls retain their existing screen-coordinate material.
  final bool useLocalRefraction;

  /// Scales the refraction highlight and rim paint without changing the body.
  final double highlightStrength;

  /// Gently changes the refracted edge while the surface is visible.
  final bool liquidRefraction;

  /// Controls how strongly surrounding colors appear in the glass edge.
  final double environmentReflectionStrength;

  /// Attenuates edge highlights when the surrounding background is dark.
  final bool backgroundResponsiveHighlights;

  @override
  State<FrostedGlassSurface> createState() => _FrostedGlassSurfaceState();
}

class _FrostedGlassSurfaceState extends State<FrostedGlassSurface>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const bool _refractionEnabled =
      String.fromEnvironment('MENU_GLASS_REFRACTION', defaultValue: '1') != '0';

  final GlobalKey _clipKey = GlobalKey();
  ui.FragmentShader? _shader;
  ui.ImageFilter? _localFilter;
  Object? _localFilterKey;
  ScrollPosition? _scrollPosition;
  AnimationController? _liquid;
  bool _appActive = true;

  void _repaintLiquid() =>
      _clipKey.currentContext?.findRenderObject()?.markNeedsPaint();

  void _syncLiquidMotion() {
    final media = MediaQuery.maybeOf(context);
    final enabled =
        widget.liquidRefraction &&
        widget.visible &&
        _shader != null &&
        _appActive &&
        TickerMode.valuesOf(context).enabled &&
        !(media?.disableAnimations ?? false) &&
        !(media?.accessibleNavigation ?? false) &&
        !(media?.highContrast ?? false);
    if (enabled) {
      final controller = _liquid ??= AnimationController(
        vsync: this,
        duration: const Duration(seconds: 8),
      )..addListener(_repaintLiquid);
      if (!controller.isAnimating) controller.repeat();
    } else if (_liquid?.isAnimating ?? false) {
      _liquid!.stop();
      _repaintLiquid();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncLiquidMotion();
    final position = Scrollable.maybeOf(context)?.position;
    if (position == _scrollPosition) return;
    _scrollPosition?.removeListener(_repaintForScroll);
    _scrollPosition = position;
    position?.addListener(_repaintForScroll);
  }

  void _repaintForScroll() {
    // These lenses have no window-position uniforms to refresh. Their retained
    // backdrop layers already sample the new background during compositing.
    if (widget.useLocalRefraction) return;
    // Invalidate the retained card layer before painting the new scroll pose.
    // No setState/post-frame measurement, ticker, or idle repaint is needed.
    _clipKey.currentContext?.findRenderObject()?.markNeedsPaint();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadShader());
  }

  @override
  void didUpdateWidget(covariant FrostedGlassSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visible != widget.visible ||
        oldWidget.liquidRefraction != widget.liquidRefraction) {
      _syncLiquidMotion();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    if (mounted) _syncLiquidMotion();
  }

  Future<void> _loadShader() async {
    if (!_refractionEnabled || !ui.ImageFilter.isShaderFilterSupported) return;
    try {
      final program = await ui.FragmentProgram.fromAsset(
        'shaders/menu_glass.frag',
      );
      // Each surface owns its own shader because uniforms are mutable.
      final shader = program.fragmentShader();
      if (!mounted) {
        shader.dispose();
        return;
      }
      setState(() => _shader = shader);
      _syncLiquidMotion();
    } catch (_) {
      // Native BackdropFilter remains the supported fallback.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _liquid?.dispose();
    _scrollPosition?.removeListener(_repaintForScroll);
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final highContrast = MediaQuery.highContrastOf(context);
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    final glassColor = highContrast
        ? (isLight ? colors.surfaceElevated : colors.surface).withValues(
            alpha: .98,
          )
        : widget.tintColor.withValues(
            alpha: widget.tintOpacity ?? (isLight ? .14 : .10),
          );
    final shadowColor = Colors.black.withValues(alpha: isLight ? .08 : .12);
    final blur = ui.ImageFilter.blur(
      sigmaX: isLight ? 14 : 12,
      sigmaY: isLight ? 14 : 12,
    );

    return DecoratedBox(
      decoration: ShapeDecoration(
        color: Colors.transparent,
        shape: widget.shape,
        shadows: widget.edgeThickness > 1
            ? const []
            : [
                BoxShadow(
                  color: shadowColor,
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final shader = _shader;
          final useRefraction =
              widget.visible &&
              !highContrast &&
              _refractionEnabled &&
              ui.ImageFilter.isShaderFilterSupported &&
              shader != null;
          ui.ImageFilter resolveFilter() {
            if (!useRefraction) return blur;
            if (widget.useLocalRefraction && widget.refractionRadius != null) {
              // In texture coordinates, motion does not change the lens. Keep
              // its filter stable instead of allocating one for every drag or
              // scroll frame. Screen-coordinate controls retain their path.
              final key = (
                shader,
                pixelRatio,
                widget.refractionRadius,
                widget.edgeThickness,
                widget.highlightStrength,
                widget.environmentReflectionStrength,
                widget.backgroundResponsiveHighlights,
                isLight,
                widget.adaptiveContrast,
              );
              if (_localFilterKey != key) {
                shader
                  ..setFloat(2, 1)
                  ..setFloat(3, 0)
                  ..setFloat(4, 0)
                  ..setFloat(5, 0)
                  ..setFloat(6, 0)
                  ..setFloat(7, pixelRatio)
                  ..setFloat(8, widget.refractionRadius! * pixelRatio)
                  ..setFloat(9, widget.edgeThickness)
                  ..setFloat(10, (isLight ? 1 : .45) * widget.highlightStrength)
                  ..setFloat(11, isLight && widget.adaptiveContrast ? 1 : 0)
                  ..setFloat(12, 1)
                  ..setFloat(13, 0)
                  ..setFloat(14, widget.environmentReflectionStrength)
                  ..setFloat(15, widget.backgroundResponsiveHighlights ? 1 : 0);
                _localFilter = ui.ImageFilter.compose(
                  inner: blur,
                  outer: ui.ImageFilter.shader(shader),
                );
                _localFilterKey = key;
              }
              return _localFilter!;
            }
            final box = _clipKey.currentContext?.findRenderObject();
            if (!useRefraction || box is! RenderBox || !box.hasSize) {
              return blur;
            }
            final rect = widget.useLocalRefraction
                ? MatrixUtils.transformRect(
                    box.getTransformTo(null),
                    Offset.zero & box.size,
                  )
                : box.localToGlobal(Offset.zero) & box.size;
            shader
              ..setFloat(2, 1)
              ..setFloat(3, rect.left * pixelRatio)
              ..setFloat(4, rect.top * pixelRatio)
              ..setFloat(5, rect.width * pixelRatio)
              ..setFloat(6, rect.height * pixelRatio)
              ..setFloat(7, pixelRatio)
              ..setFloat(
                8,
                (widget.refractionRadius ?? rect.height / 2) * pixelRatio,
              )
              ..setFloat(9, widget.edgeThickness)
              ..setFloat(10, (isLight ? 1 : .45) * widget.highlightStrength)
              ..setFloat(11, isLight && widget.adaptiveContrast ? 1 : 0)
              ..setFloat(12, widget.useLocalRefraction ? 1 : 0)
              ..setFloat(
                13,
                widget.liquidRefraction && (_liquid?.isAnimating ?? false)
                    ? 1 + _liquid!.value * math.pi * 2
                    : 0,
              )
              ..setFloat(14, widget.environmentReflectionStrength)
              ..setFloat(15, widget.backgroundResponsiveHighlights ? 1 : 0);
            // Construct a fresh filter after updating mutable shader uniforms.
            return ui.ImageFilter.compose(
              inner: blur,
              outer: ui.ImageFilter.shader(shader),
            );
          }

          return ClipPath(
            key: _clipKey,
            clipper: ShapeBorderClipper(shape: widget.shape),
            child: BackdropFilter(
              enabled: widget.visible && !highContrast,
              filterConfig: _GlassFilterConfig(resolveFilter),
              // Keep this DecoratedBox directly under BackdropFilter for the
              // high-contrast fallback and existing shell tests.
              child: DecoratedBox(
                decoration: ShapeDecoration(
                  color: glassColor,
                  shape: widget.shape,
                ),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: ShapeDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.white.withValues(
                                  alpha: isLight
                                      ? .10
                                      : (widget.edgeThickness > 1 ? .045 : .08),
                                ),
                                Colors.white.withValues(
                                  alpha: isLight
                                      ? .035
                                      : (widget.edgeThickness > 1
                                            ? .015
                                            : .025),
                                ),
                                Colors.transparent,
                              ],
                              stops: const [0, .24, 1],
                            ),
                            shape: widget.shape,
                          ),
                        ),
                      ),
                    ),
                    if (widget.showRim)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(
                            foregroundPainter: _GlassRimPainter(
                              shape: widget.shape,
                              light: isLight,
                              highlightStrength: widget.highlightStrength,
                              backgroundResponsive:
                                  widget.backgroundResponsiveHighlights &&
                                  !highContrast,
                              depth:
                                  widget.edgeThickness *
                                  widget.highlightStrength,
                              backdropHighlights:
                                  useRefraction && widget.edgeThickness > 1,
                            ),
                          ),
                        ),
                      ),
                    widget.child,
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Resolve uniforms in the paint pass, after scroll/layout transforms settle.
class _GlassFilterConfig implements ImageFilterConfig {
  const _GlassFilterConfig(this.resolveCurrentPosition);
  final ui.ImageFilter Function() resolveCurrentPosition;

  @override
  ui.ImageFilter resolve(ImageFilterContext context) =>
      resolveCurrentPosition();
  @override
  ui.ImageFilter? get filter => null;
  @override
  String get debugShortDescription => 'positioned glass';
}

/// A continuous fine rim with a broad, low-opacity reflection band just inside.
/// Paint the same continuous bevel on lightweight glass panes without adding
/// another widget tree or a second parallel outline.
void paintFrostedGlassRim(
  Canvas canvas,
  Size size, {
  required ShapeBorder shape,
  required bool light,
  double highlightStrength = 1,
  double edgeThickness = 2,
}) => _GlassRimPainter(
  shape: shape,
  light: light,
  highlightStrength: highlightStrength,
  depth: edgeThickness * highlightStrength,
).paint(canvas, size);

class _GlassRimPainter extends CustomPainter {
  const _GlassRimPainter({
    required this.shape,
    required this.light,
    required this.highlightStrength,
    this.depth = 1,
    this.backdropHighlights = false,
    this.backgroundResponsive = false,
  });

  final ShapeBorder shape;
  final bool light;
  final double highlightStrength;
  final double depth;
  final bool backdropHighlights;
  final bool backgroundResponsive;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final path = shape.getOuterPath(rect.deflate(.5));
    if (backgroundResponsive) {
      // A quiet directional boundary follows the real clip path. The wider
      // highlight is drawn by the shader from actual backdrop light and color.
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = .8
          ..shader = ui.Gradient.sweep(
            size.center(Offset.zero),
            [
              Colors.white.withValues(alpha: light ? .08 : .10),
              Colors.white.withValues(alpha: light ? .28 : .30),
              Colors.white.withValues(alpha: light ? .16 : .18),
              Colors.white.withValues(alpha: light ? .05 : .07),
              Colors.white.withValues(alpha: light ? .03 : .05),
              Colors.white.withValues(alpha: light ? .18 : .20),
              Colors.white.withValues(alpha: light ? .08 : .10),
              Colors.white.withValues(alpha: light ? .04 : .06),
              Colors.white.withValues(alpha: light ? .08 : .10),
            ],
            const [0, .12, .25, .37, .50, .62, .75, .88, 1],
            TileMode.clamp,
            -math.pi,
            math.pi,
          ),
      );
      return;
    }
    if (backdropHighlights) {
      // Build a broken, directional reflection directly on the Flutter clip
      // path. The shader supplies the broad backdrop-responsive bevel.
      final center = size.center(Offset.zero);
      final broadReflection = ui.Gradient.sweep(
        center,
        [
          Colors.white.withValues(alpha: light ? .05 : .025),
          Colors.white.withValues(alpha: light ? .22 : .11),
          Colors.white.withValues(alpha: light ? .13 : .065),
          Colors.white.withValues(alpha: light ? .025 : .012),
          Colors.transparent,
          Colors.white.withValues(alpha: light ? .09 : .045),
          Colors.white.withValues(alpha: light ? .035 : .018),
          Colors.transparent,
          Colors.white.withValues(alpha: light ? .05 : .025),
        ],
        const [0, .12, .25, .37, .50, .62, .75, .88, 1],
        TileMode.clamp,
        -math.pi,
        math.pi,
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3 * highlightStrength
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, .7)
          ..shader = broadReflection,
      );
      final narrowReflection = ui.Gradient.sweep(
        center,
        [
          Colors.white.withValues(alpha: light ? .17 : .085),
          Colors.white.withValues(alpha: light ? .48 : .24),
          Colors.white.withValues(alpha: light ? .29 : .145),
          Colors.white.withValues(alpha: light ? .08 : .04),
          Colors.white.withValues(alpha: light ? .025 : .012),
          Colors.white.withValues(alpha: light ? .23 : .115),
          Colors.white.withValues(alpha: light ? .12 : .06),
          Colors.white.withValues(alpha: light ? .035 : .018),
          Colors.white.withValues(alpha: light ? .17 : .085),
        ],
        const [0, .12, .25, .37, .50, .62, .75, .88, 1],
        TileMode.clamp,
        -math.pi,
        math.pi,
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = highlightStrength
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, .12)
          ..shader = narrowReflection,
      );
      return;
    }
    final firstReflectionPath = shape.getOuterPath(rect.deflate(1.4 * depth));
    final deepReflectionPath = shape.getOuterPath(rect.deflate(3.9 * depth));
    final innerShadePath = shape.getOuterPath(rect.deflate(6.1 * depth));
    final center = size.center(Offset.zero);
    final rim = ui.Gradient.sweep(
      center,
      [
        Colors.white.withValues(alpha: light ? .34 : .42),
        Colors.white.withValues(alpha: light ? .58 : .64),
        Colors.white.withValues(alpha: light ? .48 : .54),
        Colors.white.withValues(alpha: light ? .34 : .40),
        Colors.white.withValues(alpha: light ? .24 : .30),
        Colors.white.withValues(alpha: light ? .36 : .42),
        Colors.white.withValues(alpha: light ? .28 : .34),
        Colors.white.withValues(alpha: light ? .20 : .25),
        Colors.white.withValues(alpha: light ? .34 : .42),
      ],
      const [0, .12, .25, .37, .50, .62, .75, .88, 1],
      TileMode.clamp,
      -math.pi,
      math.pi,
    );
    final innerReflection = ui.Gradient.sweep(
      center,
      [
        Colors.white.withValues(alpha: light ? .08 : .10),
        Colors.white.withValues(alpha: light ? .14 : .17),
        Colors.white.withValues(alpha: light ? .12 : .14),
        Colors.white.withValues(alpha: light ? .09 : .11),
        Colors.white.withValues(alpha: light ? .07 : .09),
        Colors.white.withValues(alpha: light ? .12 : .15),
        Colors.white.withValues(alpha: light ? .10 : .12),
        Colors.white.withValues(alpha: light ? .07 : .08),
        Colors.white.withValues(alpha: light ? .08 : .10),
      ],
      const [0, .12, .25, .37, .50, .62, .75, .88, 1],
      TileMode.clamp,
      -math.pi,
      math.pi,
    );
    final deepReflection = ui.Gradient.sweep(
      center,
      [
        Colors.white.withValues(alpha: light ? .025 : .035),
        Colors.white.withValues(alpha: light ? .07 : .085),
        Colors.white.withValues(alpha: light ? .06 : .07),
        Colors.white.withValues(alpha: light ? .04 : .05),
        Colors.white.withValues(alpha: light ? .025 : .035),
        Colors.white.withValues(alpha: light ? .055 : .07),
        Colors.white.withValues(alpha: light ? .045 : .055),
        Colors.white.withValues(alpha: light ? .025 : .03),
        Colors.white.withValues(alpha: light ? .025 : .035),
      ],
      const [0, .12, .25, .37, .50, .62, .75, .88, 1],
      TileMode.clamp,
      -math.pi,
      math.pi,
    );
    final innerShade = ui.Gradient.sweep(
      center,
      [
        Colors.black.withValues(alpha: light ? .018 : .026),
        Colors.black.withValues(alpha: light ? .03 : .04),
        Colors.black.withValues(alpha: light ? .025 : .035),
        Colors.black.withValues(alpha: light ? .02 : .03),
        Colors.black.withValues(alpha: light ? .018 : .026),
        Colors.black.withValues(alpha: light ? .03 : .04),
        Colors.black.withValues(alpha: light ? .026 : .035),
        Colors.black.withValues(alpha: light ? .02 : .028),
        Colors.black.withValues(alpha: light ? .018 : .026),
      ],
      const [0, .12, .25, .37, .50, .62, .75, .88, 1],
      TileMode.clamp,
      -math.pi,
      math.pi,
    );
    if (depth > 1) {
      // The passport gets one continuous bevel. Feather both depth and light
      // from the same outer path instead of tracing inset parallel rings.
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7 * depth
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.4)
          ..shader = innerShade,
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5.5 * depth
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.8)
          ..shader = ui.Gradient.linear(
            rect.topLeft,
            rect.bottomRight,
            [
              Colors.white.withValues(alpha: light ? .50 : .22),
              Colors.white.withValues(alpha: light ? .12 : .06),
              Colors.white.withValues(alpha: light ? .06 : .03),
              Colors.white.withValues(alpha: light ? .40 : .18),
            ],
            const [0, .30, .65, 1],
          ),
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.white.withValues(alpha: light ? 1 : .55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = light ? .48 : .58
          ..shader = rim,
      );
      return;
    }
    canvas.drawPath(
      innerShadePath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .8 * depth
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, .45)
        ..shader = innerShade,
    );
    canvas.drawPath(
      deepReflectionPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.8 * depth
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.15)
        ..shader = deepReflection,
    );
    canvas.drawPath(
      firstReflectionPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2 * depth
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, .9)
        ..shader = innerReflection,
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = light ? .48 : .58
        ..shader = rim,
    );
  }

  @override
  bool shouldRepaint(covariant _GlassRimPainter oldDelegate) =>
      oldDelegate.shape != shape ||
      oldDelegate.light != light ||
      oldDelegate.highlightStrength != highlightStrength ||
      oldDelegate.depth != depth ||
      oldDelegate.backdropHighlights != backdropHighlights ||
      oldDelegate.backgroundResponsive != backgroundResponsive;
}
