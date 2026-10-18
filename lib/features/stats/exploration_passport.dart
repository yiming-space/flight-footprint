import 'package:flutter/material.dart';

import '../../core/localization/app_strings.dart';
import '../../data/airport_localization.dart';
import '../../domain/airport.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/widgets/country_flag.dart';
import 'continent_exploration_card.dart';
import 'farthest_footprint_card.dart';
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
  });

  final List<ExplorationPlace> places;
  final int worldCount;
  final Airport? home;
  final bool homeLoaded;
  final VoidCallback onChooseHome;

  @override
  State<ExplorationPassport> createState() => _ExplorationPassportState();
}

class _ExplorationPassportState extends State<ExplorationPassport> {
  TravelContinent? _selected;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final colors = context.appColors;
    final visits = buildContinentVisits(widget.places);
    final unlocked = visits.where((item) => item.isUnlocked).length;
    final home = widget.home;
    final farthest = home == null
        ? null
        : farthestFromHome(
            places: widget.places,
            homeLatitude: home.latitude,
            homeLongitude: home.longitude,
          );
    final reduced =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);

    return ListView(
      key: const PageStorageKey('exploration-passport-scroll'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        8,
        AppSpacing.page,
        AppSpacing.lg,
      ),
      children: [
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
                  _detailsBelow(
                    mainContinents.skip(row).take(columns),
                    reduced: reduced,
                  ),
                ],
                const SizedBox(height: 12),
                _card(visits.last, 6, wide: true),
                _detailsBelow([visits.last], reduced: reduced),
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
        onTap: () => setState(() {
          _selected = _selected == visits.continent ? null : visits.continent;
        }),
      );

  Widget _detailsBelow(Iterable<ContinentVisits> row, {required bool reduced}) {
    final selected = row
        .where((item) => item.continent == _selected)
        .firstOrNull;
    return AnimatedSize(
      duration: reduced ? Duration.zero : const Duration(milliseconds: 260),
      reverseDuration: reduced
          ? Duration.zero
          : const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: selected == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(top: 12),
              child: _ContinentDetail(
                key: ValueKey('exploration-detail-${selected.continent.name}'),
                visits: selected,
              ),
            ),
    );
  }
}

class _ContinentDetail extends StatelessWidget {
  const _ContinentDetail({super.key, required this.visits});

  final ContinentVisits visits;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final strings = context.strings;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: AppRadii.small,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${strings.isZh ? visits.continent.nameZh : visits.continent.nameEn} · ${strings.t('continentLocations')}',
            style: AppTextStyles.body.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (visits.places.isEmpty)
            Text(
              strings.t('noContinentLocations'),
              style: AppTextStyles.bodySecondary.copyWith(
                color: colors.textSecondary,
              ),
            ),
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
                                  .formatMediumDate(place.visitedAt!.toLocal()),
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
      ),
    );
  }
}
