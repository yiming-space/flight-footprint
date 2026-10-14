import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/localization/app_strings.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/widgets/perspective_card_deck.dart';
import 'aircraft_artwork.dart';
import 'aircraft_artwork_motion.dart';
import 'aircraft_collection.dart';
import 'aircraft_flip_route.dart';
import 'aircraft_poster_card.dart';

class AircraftCollectionPage extends StatefulWidget {
  const AircraftCollectionPage({
    super.key,
    required this.items,
    this.onAircraftSelected,
    this.detailBuilder,
  }) : assert(onAircraftSelected != null || detailBuilder != null);

  final List<AircraftCollectionEntry> items;
  final ValueChanged<AircraftCollectionEntry>? onAircraftSelected;
  final Widget Function(BuildContext, AircraftCollectionEntry)? detailBuilder;

  @override
  State<AircraftCollectionPage> createState() => _AircraftCollectionPageState();
}

class _AircraftCollectionPageState extends State<AircraftCollectionPage> {
  AircraftManufacturer? _manufacturer;
  // Store identity, not rank: a data refresh must not select another aircraft.
  final Map<AircraftManufacturer?, String> _selectedKeys = {};
  bool _entranceShown = false;
  String? _openingEntryKey;
  bool _hideOpeningCard = false;

  Future<void> _openAircraft(
    BuildContext cardContext,
    AircraftCollectionEntry entry, {
    required bool compact,
  }) async {
    if (_openingEntryKey != null) return;
    _selectedKeys[_manufacturer] = entry.key;
    final detailBuilder = widget.detailBuilder;
    if (detailBuilder == null) {
      widget.onAircraftSelected?.call(entry);
      return;
    }
    final navigator = Navigator.of(cardContext);
    final box = cardContext.findRenderObject();
    final overlay = navigator.overlay?.context.findRenderObject();
    Rect source = Rect.zero;
    if (box is RenderBox && box.hasSize && overlay is RenderBox) {
      source = MatrixUtils.transformRect(
        box.getTransformTo(overlay),
        Offset.zero & box.size,
      );
    }
    final route = aircraftFlipRoute<void>(
      context: context,
      sourceRect: source,
      frontSize: box is RenderBox && box.hasSize ? box.size : null,
      front: _AircraftCard(
        entry: entry,
        compact: compact,
        artwork: AircraftExhibitArtwork(entry: entry, useHero: false),
        onTap: () {},
      ),
      builder: (context) => detailBuilder(context, entry),
    );
    setState(() {
      _openingEntryKey = entry.key;
      // Navigator measures the new page offstage on its first frame.
      // Keep the real card painted until the overlay can cover it.
      _hideOpeningCard = false;
    });
    final customFlip =
        route is PageRouteBuilder<void> && !_reduceArtworkMotion(context);
    Animation<double>? routeAnimation;
    void restoreBeforeLanding() {
      final animation = routeAnimation;
      if (mounted &&
          _openingEntryKey == entry.key &&
          _hideOpeningCard &&
          animation?.status == AnimationStatus.reverse &&
          animation!.value <= .12) {
        // Restore underneath the almost-flat front before the overlay leaves.
        // Waiting for route.completed can otherwise leave one empty frame.
        setState(() => _hideOpeningCard = false);
      }
    }

    try {
      final popped = navigator.push<void>(route);
      if (customFlip) {
        routeAnimation = route.animation;
        routeAnimation?.addListener(restoreBeforeLanding);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final status = routeAnimation?.status;
          if (mounted &&
              _openingEntryKey == entry.key &&
              route.isActive &&
              (status == AnimationStatus.forward ||
                  status == AnimationStatus.completed)) {
            setState(() => _hideOpeningCard = true);
          }
        });
      }
      await popped;
      // Keep duplicate-tap protection through the complete reverse transition.
      if (route is TransitionRoute<void>) await route.completed;
    } finally {
      routeAnimation?.removeListener(restoreBeforeLanding);
      if (mounted) {
        setState(() {
          _openingEntryKey = null;
          _hideOpeningCard = false;
        });
      }
    }
  }

  Widget _openableCard({
    required AircraftCollectionEntry entry,
    required Widget artwork,
    required Key cardKey,
    Key? activeKey,
    bool compact = false,
    double depth = 0,
  }) => Builder(
    builder: (cardContext) => ExcludeSemantics(
      excluding: _hideOpeningCard && _openingEntryKey == entry.key,
      child: Opacity(
        key: ValueKey('aircraft-source-${entry.key}'),
        opacity: _hideOpeningCard && _openingEntryKey == entry.key ? 0 : 1,
        child: KeyedSubtree(
          key: activeKey,
          child: _AircraftCard(
            key: cardKey,
            entry: entry,
            compact: compact,
            depth: depth,
            artwork: artwork,
            onTap: () => _openAircraft(cardContext, entry, compact: compact),
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final isZh = context.strings.isZh;
    final colors = context.appColors;
    final items = _sortedAircraft(
      widget.items.where(
        (item) => _manufacturer == null || item.manufacturer == _manufacturer,
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(isZh ? '机型图鉴' : 'Aircraft collection'),
        backgroundColor: colors.background,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final textScale =
                    MediaQuery.textScalerOf(context).scale(16) / 16;
                final cardHeight =
                    (constraints.maxWidth - 80) / 2.35 + 180 * textScale;
                final simpleList =
                    _reduceArtworkMotion(context) ||
                    MediaQuery.textScalerOf(context).scale(16) >= 20.8 ||
                    constraints.maxHeight < cardHeight + 340;
                final header = <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                    child: Text(
                      isZh
                          ? '已搭乘 ${widget.items.length} 种机型'
                          : '${widget.items.length} aircraft ${widget.items.length == 1 ? 'type' : 'types'} flown',
                      key: const ValueKey('aircraft-collection-summary'),
                      style: AppTextStyles.bodySecondary.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: SizedBox(
                      height: 48,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final manufacturer in <AircraftManufacturer?>[
                              null,
                              ...AircraftManufacturer.values,
                            ]) ...[
                              if (manufacturer != null)
                                const SizedBox(width: AppSpacing.sm),
                              _ManufacturerFilter(
                                key: ValueKey(
                                  'aircraft-filter-${manufacturer?.name ?? 'all'}',
                                ),
                                label: manufacturer == null
                                    ? (isZh ? '全部' : 'All')
                                    : aircraftManufacturerLabel(
                                        manufacturer,
                                        isZh,
                                      ),
                                selected: _manufacturer == manufacturer,
                                onTap: () => setState(
                                  () => _manufacturer = manufacturer,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ];
                final empty = Padding(
                  padding: const EdgeInsets.fromLTRB(32, 24, 32, 40),
                  child: Center(
                    child: Text(
                      widget.items.isEmpty
                          ? (isZh
                                ? '还没有机型记录\n为已完成航班添加机型后，会显示在这里。'
                                : 'No aircraft recorded yet\nAdd an aircraft type to a completed flight to start your collection.')
                          : (isZh
                                ? '还没有搭乘这一制造商的机型'
                                : 'No aircraft from this manufacturer yet'),
                      textAlign: TextAlign.center,
                      style: AppTextStyles.body.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                );
                if (!simpleList) {
                  final animateEntrance = !_entranceShown && items.isNotEmpty;
                  if (items.isNotEmpty) _entranceShown = true;
                  final savedIndex = items.indexWhere(
                    (entry) => entry.key == _selectedKeys[_manufacturer],
                  );
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ...header,
                      Expanded(
                        child: items.isEmpty
                            ? empty
                            : Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                ),
                                child: PerspectiveCardDeck(
                                  loop: true,
                                  recycleArc: false,
                                  cycleDepth: true,
                                  showControls: false,
                                  animateEntrance: animateEntrance,
                                  key: ValueKey(
                                    'aircraft-deck-${_manufacturer?.name ?? 'all'}',
                                  ),
                                  itemCount: items.length,
                                  cardHeight: cardHeight,
                                  initialIndex: savedIndex < 0 ? 0 : savedIndex,
                                  onIndexChanged: (index) =>
                                      _selectedKeys[_manufacturer] =
                                          items[index].key,
                                  itemBuilder: (context, index, relative, active) {
                                    final entry = items[index];
                                    // Rear cards keep a clean model strip. Their plane
                                    // appears as they approach the front, never as a
                                    // stretched or rotated replacement asset.
                                    // Keep the spring above the changing active
                                    // card keys so passing the half-way point
                                    // never resets the plane's presentation.
                                    return AircraftArtworkMotion(
                                      key: ValueKey(
                                        'aircraft-motion-${entry.key}',
                                      ),
                                      relativePosition: relative,
                                      child: AircraftExhibitArtwork(
                                        entry: entry,
                                        useHero: active,
                                      ),
                                      builder: (context, offset, artwork) =>
                                          _openableCard(
                                            activeKey: active
                                                ? ValueKey(
                                                    'aircraft-active-${entry.key}',
                                                  )
                                                : null,
                                            cardKey: ValueKey(
                                              active
                                                  ? 'aircraft-card-${entry.key}'
                                                  : 'aircraft-rear-${entry.key}',
                                            ),
                                            entry: entry,
                                            compact: true,
                                            depth: relative.abs().clamp(
                                              0.0,
                                              3.0,
                                            ),
                                            artwork: Transform.translate(
                                              key: ValueKey(
                                                'aircraft-parallax-${entry.key}',
                                              ),
                                              offset: offset,
                                              child: artwork,
                                            ),
                                          ),
                                    );
                                  },
                                ),
                              ),
                      ),
                    ],
                  );
                }
                if (items.isNotEmpty) _entranceShown = true;
                return CustomScrollView(
                  key: const PageStorageKey('aircraft-collection-list'),
                  primary: false,
                  slivers: [
                    for (final child in header)
                      SliverToBoxAdapter(child: child),
                    if (items.isEmpty)
                      SliverFillRemaining(hasScrollBody: false, child: empty)
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                        sliver: SliverList.separated(
                          itemCount: items.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: AppSpacing.cardGap),
                          itemBuilder: (context, index) {
                            final entry = items[index];
                            return _openableCard(
                              cardKey: ValueKey('aircraft-card-${entry.key}'),
                              entry: entry,
                              artwork: AircraftExhibitArtwork(entry: entry),
                            );
                          },
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _ManufacturerFilter extends StatelessWidget {
  const _ManufacturerFilter({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: SizedBox(
        height: 48,
        child: Material(
          color: selected ? colors.lime : colors.surface,
          shape: AppShapes.pill,
          child: InkWell(
            onTap: onTap,
            customBorder: AppShapes.pill,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
              child: Center(
                child: Text(
                  label,
                  style: AppTextStyles.label.copyWith(
                    color: selected ? colors.onPrimary : colors.textPrimary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AircraftCard extends StatefulWidget {
  const _AircraftCard({
    super.key,
    required this.entry,
    required this.artwork,
    required this.onTap,
    this.compact = false,
    this.depth = 0,
  });

  final AircraftCollectionEntry entry;
  final Widget artwork;
  final VoidCallback onTap;
  final bool compact;
  final double depth;

  @override
  State<_AircraftCard> createState() => _AircraftCardState();
}

class _AircraftCardState extends State<_AircraftCard> {
  bool _pressed = false;
  Offset? _pressOrigin;
  AircraftCollectionEntry get entry => widget.entry;
  Widget get artwork => widget.artwork;
  VoidCallback get onTap => widget.onTap;
  bool get compact => widget.compact;
  double get depth => widget.depth;

  void _setPressed(bool value) {
    // A pointer's hit-test path can outlive this face when its active/rear key
    // changes during a drag. Ignore the remaining events after replacement.
    if (!mounted) return;
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final isZh = context.strings.isZh;
    final manufacturer = aircraftManufacturerLabel(entry.manufacturer, isZh);
    final count = aircraftFlightCountLabel(entry.count, isZh);
    final distance = aircraftDistanceLabel(entry, isZh);

    return Semantics(
      button: true,
      label: '${entry.type}, $manufacturer, $count, $distance',
      onTap: onTap,
      excludeSemantics: true,
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
          key: ValueKey('aircraft-card-press-${entry.key}'),
          scale: _pressed && !_reduceArtworkMotion(context) ? .985 : 1,
          duration: const Duration(milliseconds: 80),
          curve: Curves.easeOut,
          child: AircraftPosterCard(
            model: entry.type,
            manufacturer: manufacturer,
            countLabel: count,
            distanceLabel: distance,
            artwork: artwork,
            onTap: onTap,
            compact: compact,
            depth: depth,
          ),
        ),
      ),
    );
  }
}

/// Shares complete, model-specific artwork between the collection and detail.
/// Models without artwork deliberately keep a labeled neutral icon.
class AircraftExhibitArtwork extends StatelessWidget {
  const AircraftExhibitArtwork({
    super.key,
    required this.entry,
    this.useHero = true,
    this.aspectRatio = 2.35,
  });

  final AircraftCollectionEntry entry;
  final bool useHero;
  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    final isZh = context.strings.isZh;
    final asset = aircraftArtworkAssetFor(entry.type);
    final Widget content = LayoutBuilder(
      builder: (context, constraints) {
        final artHeight = constraints.maxWidth / aspectRatio;
        return ConstrainedBox(
          constraints: BoxConstraints(minHeight: artHeight),
          child: asset == null
              ? _AircraftArtworkFallback(entryKey: entry.key)
              : Image.asset(
                  asset,
                  key: ValueKey('aircraft-art-${entry.key}'),
                  width: double.infinity,
                  height: artHeight,
                  fit: BoxFit.contain,
                  semanticLabel: isZh
                      ? '${entry.type} 机型风格示意'
                      : '${entry.type} aircraft style illustration',
                  errorBuilder: (_, _, _) => _AircraftArtworkFallback(
                    entryKey: entry.key,
                    unavailable: true,
                  ),
                ),
        );
      },
    );
    if (asset == null || !useHero || _reduceArtworkMotion(context)) {
      return content;
    }
    return Hero(
      tag: aircraftArtworkHeroTag(entry.key),
      createRectTween: (begin, end) => RectTween(begin: begin, end: end),
      child: Material(type: MaterialType.transparency, child: content),
    );
  }
}

class _AircraftArtworkFallback extends StatelessWidget {
  const _AircraftArtworkFallback({
    required this.entryKey,
    this.unavailable = false,
  });

  final String entryKey;
  final bool unavailable;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isZh = context.strings.isZh;
    final label = unavailable
        ? (isZh ? '外观图暂不可用' : 'Aircraft illustration unavailable')
        : (isZh ? '外观图待补充' : 'Aircraft illustration coming soon');
    return Center(
      key: ValueKey('aircraft-art-fallback-$entryKey'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: Transform.rotate(
                angle: math.pi / 2,
                child: Icon(
                  Icons.airplanemode_active_rounded,
                  size: 40,
                  color: colors.textSecondary,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              label,
              textAlign: TextAlign.center,
              style: AppTextStyles.label.copyWith(
                color: colors.textSecondary,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

bool _reduceArtworkMotion(BuildContext context) {
  final media = MediaQuery.of(context);
  return media.disableAnimations || media.accessibleNavigation;
}

List<AircraftCollectionEntry> _sortedAircraft(
  Iterable<AircraftCollectionEntry> entries,
) => entries.toList()
  ..sort((left, right) {
    final countOrder = right.count.compareTo(left.count);
    return countOrder != 0 ? countOrder : left.type.compareTo(right.type);
  });

String aircraftManufacturerLabel(
  AircraftManufacturer manufacturer,
  bool isZh,
) => switch (manufacturer) {
  AircraftManufacturer.airbus => isZh ? '空客' : 'Airbus',
  AircraftManufacturer.boeing => isZh ? '波音' : 'Boeing',
  AircraftManufacturer.other => isZh ? '其他' : 'Other',
};

String aircraftFlightCountLabel(int count, bool isZh) =>
    isZh ? '$count 次' : '$count ${count == 1 ? 'flight' : 'flights'}';

String aircraftDistanceLabel(AircraftCollectionEntry entry, bool isZh) {
  final recorded = entry.flights
      .where(
        (flight) =>
            flight.distanceKm != null &&
            flight.distanceKm!.isFinite &&
            flight.distanceKm! >= 0,
      )
      .length;
  if (recorded == 0) return isZh ? '里程未记录' : 'Distance not recorded';
  final distance =
      '${NumberFormat.decimalPattern(isZh ? 'zh' : 'en').format(entry.distanceKm.round())} km';
  return recorded == entry.count
      ? (isZh ? '累计 $distance' : '$distance total')
      : (isZh ? '已记录 $distance' : '$distance recorded');
}
