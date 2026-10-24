import 'package:flutter/material.dart';

import '../../core/localization/app_strings.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/widgets/app_page_background.dart';
import 'airline_ranking.dart';
import 'airline_ranking_tile.dart';

class AirlineRankingPage extends StatefulWidget {
  const AirlineRankingPage({
    super.key,
    required this.items,
    required this.onAirlineSelected,
    this.animateEntrance = false,
  });
  final List<AirlineRankingEntry> items;
  final ValueChanged<AirlineRankingEntry> onAirlineSelected;
  final bool animateEntrance;
  @override
  State<AirlineRankingPage> createState() => _AirlineRankingPageState();
}

class _AirlineRankingPageState extends State<AirlineRankingPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fill;
  Animation<double>? _routeAnimation;
  ModalRoute<dynamic>? _route;
  bool _started = false;
  bool get _reduced {
    final media = MediaQuery.of(context);
    return media.disableAnimations || media.accessibleNavigation;
  }

  @override
  void initState() {
    super.initState();
    _fill = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
      value: widget.animateEntrance ? 0 : 1,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    final animation = _route?.animation;
    if (animation != _routeAnimation) {
      _routeAnimation?.removeStatusListener(_routeStatus);
      _routeAnimation = animation;
      animation?.addStatusListener(_routeStatus);
    }
    if (_reduced || !widget.animateEntrance) {
      _started = true;
      _fill.stop();
      _fill.value = 1;
    } else if (animation == null ||
        animation.status == AnimationStatus.completed) {
      _startFill();
    }
  }

  void _routeStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) _startFill();
  }

  void _startFill() {
    // Navigator reports a completed proxy animation during offstage layout.
    // That is measurement, not the end of the visible opening transition.
    if (!mounted || _started || (_route?.offstage ?? false)) return;
    _started = true;
    if (_reduced || !widget.animateEntrance || widget.items.isEmpty) {
      _fill.value = 1;
    } else {
      _fill.forward();
    }
  }

  @override
  void dispose() {
    _routeAnimation?.removeStatusListener(_routeStatus);
    _fill.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    final colors = context.appColors;
    final maxCount = widget.items.isEmpty ? 0 : widget.items.first.count;
    return AppPageBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(
            s.t('airlineRanking'),
            style: AppTextStyles.sectionTitle.copyWith(
              color: colors.textPrimary,
            ),
          ),
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
        ),
        body: SafeArea(
          top: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),
              child: CustomScrollView(
                key: const PageStorageKey('airline-ranking-list'),
                primary: false,
                slivers: [
                  if (widget.items.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Text(
                          s.t('rankingEmpty'),
                          style: TextStyle(color: colors.textSecondary),
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      sliver: SliverList.separated(
                        itemCount: widget.items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final entry = widget.items[index];
                          final count = entry.count;
                          Widget tile(double reveal) => AirlineRankingTile(
                            key: ValueKey(entry.iataCode ?? entry.name),
                            name: entry.name,
                            iataCode: entry.iataCode,
                            count: count,
                            maxCount: maxCount,
                            rank: index + 1,
                            countLabel: s.isZh
                                ? '$count 次'
                                : '$count ${count == 1 ? 'flight' : 'flights'}',
                            fillReveal: reveal,
                            animatedCountLabel:
                                widget.animateEntrance && !_reduced
                                ? (value) => s.isZh
                                      ? '$value 次'
                                      : '$value ${count == 1 ? 'flight' : 'flights'}'
                                : null,
                            onTap: () => widget.onAirlineSelected(entry),
                          );
                          if (!widget.animateEntrance || _reduced) {
                            return tile(1);
                          }
                          final delay = index.clamp(0, 3) * .04;
                          return AnimatedBuilder(
                            key: ValueKey('airline-ranking-fill-$index'),
                            animation: _fill,
                            builder: (context, _) => tile(
                              Interval(
                                delay,
                                .76 + delay,
                                curve: Curves.easeOutCubic,
                              ).transform(_fill.value),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
