import 'package:flutter/material.dart';

import '../../core/localization/app_strings.dart';
import '../../data/airport_localization.dart';
import '../../data/city_catalog.dart';
import '../../domain/airport.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/widgets/country_flag.dart';
import 'continent_exploration_card.dart';
import 'farthest_footprint_card.dart';
import 'exploration_memory_carousel.dart';
import 'personal_travel_card.dart';
import 'personal_travel_summary.dart';
import 'world_exploration.dart';

/// Read-only passport presentation; its host owns the saved home-city setting.
class ExplorationPassport extends StatefulWidget {
  const ExplorationPassport({
    super.key,
    required this.places,
    required this.worldCount,
    required this.home,
    required this.homeLoaded,
    required this.onChooseHome,
    this.cityCatalog,
    this.memorySummary,
    this.onMemorySelected,
  });

  final List<ExplorationPlace> places;
  final int worldCount;
  final Airport? home;
  final bool homeLoaded;
  final VoidCallback onChooseHome;
  final CityCatalog? cityCatalog;
  final PersonalTravelSummary? memorySummary;
  final ValueChanged<PersonalTravelKind>? onMemorySelected;

  @override
  State<ExplorationPassport> createState() => _ExplorationPassportState();
}

class _ExplorationPassportState extends State<ExplorationPassport> {
  TravelContinent? _selected;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final colors = context.appColors;
    final visits = buildContinentVisits(
      widget.places,
      cityCatalog: widget.cityCatalog,
    );
    final unlocked = visits.where((item) => item.isUnlocked).length;
    final home = widget.home;
    final farthest = home == null
        ? null
        : farthestFromHome(
            places: widget.places,
            homeLatitude: home.latitude,
            homeLongitude: home.longitude,
          );
    return ListView(
      key: const PageStorageKey('exploration-passport-scroll'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        20,
        AppSpacing.page,
        AppSpacing.lg,
      ),
      children: [
        if (widget.memorySummary case final summary?)
          ExplorationMemoryCarousel(
            cards: [
              FarthestFootprintCard(
                home: home,
                farthest: farthest,
                homeLoaded: widget.homeLoaded,
                onChooseHome: widget.onChooseHome,
              ),
              for (final kind in PersonalTravelKind.values)
                PersonalTravelMomentCard(
                  summary: summary,
                  kind: kind,
                  onOpen: () => widget.onMemorySelected?.call(kind),
                ),
            ],
            labels: [
              strings.t('farthestFootprint'),
              strings.isZh ? '新抵达城市' : 'New cities',
              strings.isZh ? '最常飞航线' : 'Most-flown route',
              strings.isZh ? '首次记录机型' : 'New aircraft types',
            ],
          )
        else
          FarthestFootprintCard(
            home: home,
            farthest: farthest,
            homeLoaded: widget.homeLoaded,
            onChooseHome: widget.onChooseHome,
          ),
        const SizedBox(height: AppSpacing.lg),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.xs,
          children: [
            Text(
              strings.t('continents'),
              style: AppTextStyles.sectionTitle.copyWith(
                color: colors.textPrimary,
                fontSize: 20,
              ),
            ),
            Text(
              strings
                  .t('continentsUnlocked')
                  .replaceFirst('{count}', '$unlocked'),
              key: const ValueKey('exploration-unlocked-summary'),
              style: AppTextStyles.label.copyWith(
                color: colors.textSecondary,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        LayoutBuilder(
          builder: (context, constraints) {
            final textScale = MediaQuery.textScalerOf(context).scale(16) / 16;
            final columns = constraints.maxWidth < 280 || textScale >= 1.8
                ? 1
                : constraints.maxWidth < 360 || textScale >= 1.35
                ? 2
                : 3;
            final mainContinents = visits
                .where((item) => item.continent != TravelContinent.antarctica)
                .toList(growable: false);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (
                  var row = 0;
                  row < mainContinents.length;
                  row += columns
                ) ...[
                  if (row > 0) const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var column = 0; column < columns; column++) ...[
                        if (column > 0) const SizedBox(width: 12),
                        Expanded(
                          child: row + column >= mainContinents.length
                              ? const SizedBox.shrink()
                              : _card(
                                  mainContinents[row + column],
                                  row + column,
                                ),
                        ),
                      ],
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                _card(visits.last, 6, wide: true),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _card(ContinentVisits visits, int index, {bool wide = false}) =>
      ContinentExplorationCard(
        key: ValueKey('exploration-continent-${visits.continent.name}'),
        visits: visits,
        selected: visits.continent == _selected,
        entranceIndex: index,
        wide: wide,
        onTap: () => _showContinent(visits),
      );

  Future<void> _showContinent(ContinentVisits visits) async {
    setState(() => _selected = visits.continent);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: context.appColors.cardSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      clipBehavior: Clip.antiAlias,
      builder: (context) => _ContinentDetail(
        key: ValueKey('exploration-detail-${visits.continent.name}'),
        visits: visits,
      ),
    );
    if (mounted) setState(() => _selected = null);
  }
}

class _ContinentDetail extends StatelessWidget {
  const _ContinentDetail({super.key, required this.visits});

  final ContinentVisits visits;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final strings = context.strings;
    final title = strings.isZh
        ? visits.continent.nameZh
        : visits.continent.nameEn;
    final count = strings
        .t('continentCountries')
        .replaceFirst('{count}', '${visits.countryCount}');
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .78,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AppTextStyles.sectionTitle.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        count,
                        style: AppTextStyles.bodySecondary.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: strings.t('close'),
                  icon: const Icon(Icons.close_rounded),
                  color: colors.textSecondary,
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (visits.places.isEmpty) ...[
              Text(
                strings.isZh ? '未解锁' : 'Locked',
                style: AppTextStyles.label.copyWith(
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                strings.t('noContinentLocations'),
                style: AppTextStyles.bodySecondary.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ] else ...[
              for (final place in visits.places)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ExcludeSemantics(
                        child: CountryFlag(code: place.countryCode, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              place.name,
                              style: AppTextStyles.body.copyWith(
                                color: colors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              [
                                strings.isZh
                                    ? localizedCountryName(place.countryCode)
                                    : localizedCountryEnglishName(
                                        place.countryCode,
                                      ),
                                if (place.visitedAt != null)
                                  MaterialLocalizations.of(context)
                                      .formatMediumDate(
                                        place.visitedAt!.toLocal(),
                                      ),
                              ].join(' · '),
                              style: AppTextStyles.label.copyWith(
                                color: colors.textSecondary,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
