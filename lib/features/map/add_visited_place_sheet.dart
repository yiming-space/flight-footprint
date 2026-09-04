import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/app_controller.dart';
import '../../core/localization/app_strings.dart';
import '../../data/airport_localization.dart';
import '../../data/city_catalog.dart';
import '../../domain/visited_place.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/widgets/widgets.dart';
import 'photo_footprint_picker_sheet.dart';

class AddVisitedPlaceSheet extends StatefulWidget {
  const AddVisitedPlaceSheet({super.key, required this.controller});

  final AppController controller;

  @override
  State<AddVisitedPlaceSheet> createState() => _AddVisitedPlaceSheetState();
}

class _AddVisitedPlaceSheetState extends State<AddVisitedPlaceSheet> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _searchDebounce;
  Future<CityCatalog>? _catalog;
  CityCenter? _selected;
  DateTime _visitedAt = DateTime.now();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _search.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _search.removeListener(_onSearchChanged);
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    final query = _search.text.trim();
    if (_selected != null && query != _selected!.name) {
      setState(() => _selected = null);
    } else {
      setState(() {});
    }
    if (_catalog != null || query.isEmpty) return;
    // Start the catalogue only after the user pauses briefly. The sheet opens
    // without requesting the IME, so the route entrance and keyboard never
    // compete for the same first frames, and rapid typing does not queue
    // repeated catalogue work.
    _searchDebounce = Timer(const Duration(milliseconds: 100), () {
      if (!mounted || _search.text.trim().isEmpty || _catalog != null) return;
      setState(() => _catalog = CityCatalog.load());
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    final colors = context.appColors;
    return Material(
      color: colors.background,
      child: SafeArea(
        top: true,
        bottom: true,
        child: _ImeAwareVisitedPlaceContent(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      s.t('addPlace'),
                      style: AppTextStyles.sectionTitle,
                    ),
                  ),
                  IconButton(
                    tooltip: s.t('close'),
                    onPressed: () => Navigator.maybePop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(s.t('addPlaceHint'), style: AppTextStyles.bodySecondary),
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: _saving ? null : _openPhotoImport,
                icon: const Icon(Icons.photo_library_outlined),
                label: Text(s.t('addFromPhotos')),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  foregroundColor: colors.textPrimary,
                  side: BorderSide(color: colors.border),
                  shape: AppShapes.medium,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _search,
                focusNode: _searchFocus,
                // Focus is requested after the route settles in initState;
                // autofocus here would animate the IME at the same time as
                // the modal sheet.
                autofocus: false,
                readOnly: _selected != null,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded),
                  hintText: s.t('searchCity'),
                  filled: true,
                  fillColor: colors.surface,
                  border: ShapedInputBorder(
                    shape: AppShapes.medium,
                    borderSide: BorderSide(color: colors.border),
                  ),
                  enabledBorder: ShapedInputBorder(
                    shape: AppShapes.medium,
                    borderSide: BorderSide(color: colors.border),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Flexible(
                fit: FlexFit.loose,
                child: _selected != null
                    ? SizedBox(
                        height: 88,
                        child: _selectedCity(context, _selected!),
                      )
                    : _catalog == null
                    ? Center(child: Text(s.t('searchCity')))
                    : FutureBuilder<CityCatalog>(
                        future: _catalog,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState !=
                              ConnectionState.done) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          if (snapshot.hasError || snapshot.data == null) {
                            return Center(child: Text(s.t('noCityResults')));
                          }
                          final query = _search.text.trim();
                          final suggestions = query.isEmpty
                              ? const <CityCenter>[]
                              : snapshot.data!.search(query);
                          if (query.isNotEmpty && suggestions.isEmpty) {
                            return Center(child: Text(s.t('noCityResults')));
                          }
                          return ListView.separated(
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            itemCount: suggestions.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final city = suggestions[index];
                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 2,
                                ),
                                leading: Container(
                                  width: 42,
                                  height: 42,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: colors.lime.withValues(alpha: .16),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.location_on_rounded,
                                    color: colors.lime,
                                    size: 20,
                                  ),
                                ),
                                title: Text(
                                  city.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                subtitle: Text(city.regionLabel),
                                onTap: () {
                                  // Keep the selected card and action area out
                                  // of the IME's reduced viewport. The old
                                  // focused search field left the result area
                                  // with a tight height and produced Flutter's
                                  // BOTTOM OVERFLOWED warning on smaller
                                  // devices.
                                  _searchFocus.unfocus();
                                  setState(() {
                                    _selected = city;
                                    _search.value = TextEditingValue(
                                      text: city.name,
                                      selection: TextSelection.collapsed(
                                        offset: city.name.length,
                                      ),
                                    );
                                  });
                                },
                              );
                            },
                          );
                        },
                      ),
              ),
              const SizedBox(height: 10),
              if (_selected != null)
                InkWell(
                  customBorder: AppShapes.medium,
                  onTap: _pickDate,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: ShapeDecoration(
                      color: colors.surface,
                      shape: RoundedSuperellipseBorder(
                        borderRadius: BorderRadius.all(Radius.circular(18)),
                        side: BorderSide(color: colors.border),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_month_rounded),
                        const SizedBox(width: 10),
                        Text(s.t('visitedDate')),
                        const Spacer(),
                        Text(DateFormat('yyyy-MM-dd').format(_visitedAt)),
                        const SizedBox(width: 4),
                        const Icon(Icons.chevron_right_rounded),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              PrimaryButton(
                label: _saving ? '…' : s.t('savePlace'),
                icon: Icons.add_location_alt_rounded,
                onPressed: _selected == null || _saving ? null : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _selectedCity(BuildContext context, CityCenter city) => SizedBox(
    height: 88,
    width: double.infinity,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: ShapeDecoration(
        color: context.appColors.lime.withValues(alpha: .14),
        shape: RoundedSuperellipseBorder(
          borderRadius: const BorderRadius.all(Radius.circular(18)),
          side: BorderSide(
            color: context.appColors.lime.withValues(alpha: .55),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_rounded, color: context.appColors.lime),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  city.name,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                Text(city.regionLabel, style: AppTextStyles.bodySecondary),
              ],
            ),
          ),
          TextButton(
            onPressed: () => setState(() {
              _selected = null;
              _search.clear();
            }),
            style: TextButton.styleFrom(
              minimumSize: Size.zero,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
            child: Text(context.strings.t('selectCity')),
          ),
        ],
      ),
    ),
  );

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _visitedAt,
      firstDate: DateTime(1900),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _visitedAt = picked);
  }

  Future<void> _openPhotoImport() async {
    if (_saving) return;
    final result = await showModalBottomSheet<PhotoFootprintImportResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: .68),
      builder: (_) => FractionallySizedBox(
        heightFactor: .94,
        child: PhotoFootprintPickerSheet(
          // A flight endpoint already represents a visited city. Include
          // those effective footprint points in the import exclusion set so
          // a photo from the same city cannot create a hidden duplicate that
          // the map would later have to collapse.
          existingPlaces: _existingFootprintPlaces(),
        ),
      ),
    );
    if (!mounted || result == null || result.drafts.isEmpty) return;
    setState(() => _saving = true);
    try {
      for (final draft in result.drafts) {
        await widget.controller.addVisitedPlace(
          name: draft.name,
          latitude: draft.latitude,
          longitude: draft.longitude,
          visitedAt: draft.visitedAt,
          countryCode: draft.countryCode,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${context.strings.t('operationFailed')}: $error'),
        ),
      );
      setState(() => _saving = false);
    }
  }

  List<VisitedPlace> _existingFootprintPlaces() {
    final places = <VisitedPlace>[...widget.controller.visitedPlaces];
    final seenFlightCities = <String>{};
    for (final flight in widget.controller.flights.where(
      (flight) => flight.isCompleted,
    )) {
      for (final iata in [flight.departureIata, flight.arrivalIata]) {
        final airport = widget.controller.airportFor(iata);
        if (airport == null) continue;
        final name = localizedAirportCity(airport).trim();
        if (name.isEmpty) continue;
        final country = airport.countryCode.trim().toUpperCase();
        final key = '$country|${CityCatalog.normalizeLookup(name)}';
        if (!seenFlightCities.add(key)) continue;
        final timestamp = flight.departedAt;
        places.add(
          VisitedPlace(
            id: 'flight-city:${airport.iataCode}',
            name: name,
            latitude: airport.latitude,
            longitude: airport.longitude,
            visitedAt: timestamp,
            createdAt: timestamp,
            updatedAt: timestamp,
            countryCode: airport.countryCode,
          ),
        );
      }
    }
    return List.unmodifiable(places);
  }

  Future<void> _save() async {
    final selected = _selected;
    if (selected == null) return;
    setState(() => _saving = true);
    try {
      await widget.controller.addVisitedPlace(
        name: selected.name,
        latitude: selected.latitude,
        longitude: selected.longitude,
        visitedAt: _visitedAt,
        countryCode: selected.countryCode,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${context.strings.t('operationFailed')}: $error'),
        ),
      );
      setState(() => _saving = false);
    }
  }
}

class _ImeAwareVisitedPlaceContent extends StatelessWidget {
  const _ImeAwareVisitedPlaceContent({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      // Only this sheet content follows the IME. The stateful sheet and the
      // route behind it stay out of the per-frame inset rebuild path.
      padding: EdgeInsets.fromLTRB(20, 20, 20, bottomInset + 16),
      child: child,
    );
  }
}
