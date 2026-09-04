import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/app_controller.dart';
import '../../core/localization/app_strings.dart';
import '../../data/airline_catalog.dart';
import '../../data/airport_catalog.dart';
import '../../data/airport_localization.dart';
import '../../domain/airport.dart';
import '../../domain/flight.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/widgets/widgets.dart';

class AddFlightPage extends StatefulWidget {
  const AddFlightPage({
    super.key,
    required this.controller,
    this.initialFlight,
  });
  final AppController controller;
  final Flight? initialFlight;
  @override
  State<AddFlightPage> createState() => _AddFlightPageState();
}

class _AddFlightPageState extends State<AddFlightPage> {
  Airport? _departure;
  Airport? _arrival;
  DateTime _date = DateTime.now();
  bool _dateTouched = false;
  DateTime? _arrivalAt;
  bool _arrivalTouched = false;
  bool _more = false;
  bool _saving = false;
  bool _lookingUp = false;
  String? _lookupMessage;
  bool _durationTouched = false;
  bool _distanceTouched = false;
  final _flightIdentity = TextEditingController();
  final _airline = TextEditingController();
  final _flightNumber = TextEditingController();
  final _aircraft = TextEditingController();
  final _duration = TextEditingController();
  final _distance = TextEditingController();
  final _seat = TextEditingController();
  final _note = TextEditingController();
  String? _cabin;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialFlight;
    if (initial == null) {
      return;
    }
    _departure = widget.controller.airportFor(initial.departureIata);
    _arrival = widget.controller.airportFor(initial.arrivalIata);
    _date = initial.departedAt.toLocal();
    _dateTouched = true;
    final storedArrival = initial.arrivedAt?.toLocal();
    _arrivalAt = storedArrival;
    _arrivalTouched = storedArrival != null;
    _airline.text = initial.airline ?? '';
    _flightNumber.text = initial.flightNumber ?? '';
    _flightIdentity.text = [
      initial.airline,
      initial.flightNumber,
    ].whereType<String>().where((value) => value.trim().isNotEmpty).join(' ');
    _aircraft.text = initial.aircraftType ?? '';
    _duration.text = initial.durationMinutes?.toString() ?? '';
    _distance.text = initial.distanceKm == null
        ? ''
        : _formatDistance(initial.distanceKm!);
    _durationTouched = initial.durationMinutes != null;
    _distanceTouched = initial.distanceKm != null;
    if (!_durationTouched) {
      final inferred = _durationFromTimes(_date, _arrivalAt);
      if (inferred != null) _duration.text = inferred.toString();
    }
    _seat.text = initial.seat ?? '';
    _note.text = initial.note ?? '';
    _cabin = _normalizeCabinValue(initial.cabinClass);
    _more = [
      initial.aircraftType,
      initial.durationMinutes?.toString(),
      initial.seat,
      initial.cabinClass,
      initial.note,
    ].any((value) => value != null && value.trim().isNotEmpty);
    _applyCalculatedFields();
  }

  @override
  void dispose() {
    for (final controller in [
      _flightIdentity,
      _airline,
      _flightNumber,
      _aircraft,
      _duration,
      _distance,
      _seat,
      _note,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    final colors = context.appColors;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final identityCardColor = isLight
        ? Color.alphaBlend(
            colors.cardMint.withValues(alpha: .52),
            colors.surface,
          )
        : colors.surfaceElevated;
    return Material(
      color: colors.background,
      child: SafeArea(
        top: true,
        child: _ImeAwareFlightForm(
          children: [
            PageHeader(
              title: s.t(
                widget.initialFlight == null ? 'addFlight' : 'editFlight',
              ),
              onBack: () => Navigator.maybePop(context),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RepaintBoundary(
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
                      decoration: ShapeDecoration(
                        color: colors.surface,
                        shape: AppShapes.large,
                        shadows: _surfaceShadow(),
                      ),
                      child: DefaultTextStyle(
                        style: TextStyle(color: colors.textPrimary),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: _AirportSelector(
                                    label: s.t('departure'),
                                    airport: _departure,
                                    onTap: () => _pickAirport(true),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                  ),
                                  child: SizedBox(
                                    width: 48,
                                    height: 72,
                                    child: Center(
                                      child: Icon(
                                        Icons.flight_takeoff_rounded,
                                        color: colors.lime,
                                        size: 28,
                                      ),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: _AirportSelector(
                                    label: s.t('arrival'),
                                    airport: _arrival,
                                    alignEnd: true,
                                    onTap: () => _pickAirport(false),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: _DateTimeSelector(
                                    label: s.t('takeoff'),
                                    value: _date,
                                    onDateTap: _pickDate,
                                    onTimeTap: _pickDepartureTime,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _DateTimeSelector(
                                    label: s.t('landing'),
                                    // Older imported records may only contain a
                                    // duration. Show its calculated arrival in
                                    // the editor instead of an empty field; it
                                    // remains an automatic value until touched.
                                    value: _arrivalAt ?? _estimatedArrival,
                                    onDateTap: _pickArrivalDate,
                                    onTimeTap: _pickArrivalTime,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  RepaintBoundary(
                    child: SurfaceCard(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                      color: identityCardColor,
                      borderRadius: AppRadii.large,
                      showBorder: false,
                      boxShadow: _surfaceShadow(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _field(
                            s.t('airlineFlight'),
                            _flightIdentity,
                            required: true,
                            prefixIcon: Icons.confirmation_number_outlined,
                            hintText: s.t('airlineFlightHint'),
                            onChanged: _onFlightIdentityChanged,
                            onSubmitted: (_) => _lookupFlight(),
                          ),
                          if (_lookupMessage == null) ...[
                            const SizedBox(height: 8),
                            Text(
                              s.t('requiredHint'),
                              style: AppTextStyles.label.copyWith(
                                color: colors.textTertiary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _lookingUp ? null : _lookupFlight,
                              icon: _lookingUp
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.auto_awesome_rounded),
                              label: Text(
                                _lookingUp
                                    ? s.t('lookingUpFlight')
                                    : s.t('autoFillFlight'),
                              ),
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(44, 56),
                                backgroundColor: colors.lime.withValues(
                                  alpha: isLight ? .22 : .14,
                                ),
                                foregroundColor: isLight
                                    ? Color.lerp(
                                        colors.lime,
                                        colors.textPrimary,
                                        .10,
                                      )
                                    : colors.lime,
                                disabledBackgroundColor: colors.surface,
                                disabledForegroundColor: colors.textTertiary,
                                shape: AppShapes.large,
                                textStyle: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                          if (_lookupMessage != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              _lookupMessage!,
                              style: AppTextStyles.label.copyWith(
                                color: colors.textSecondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  RepaintBoundary(
                    child: SurfaceCard(
                      padding: EdgeInsets.zero,
                      color: colors.surfaceElevated,
                      borderRadius: AppRadii.large,
                      showBorder: false,
                      boxShadow: _surfaceShadow(),
                      child: Column(
                        children: [
                          DisclosureRow(
                            title: s.t('moreDetails'),
                            subtitle: s.t('optionalInfo'),
                            showChevron: false,
                            value: _more ? '−' : '+',
                            onTap: () => setState(() => _more = !_more),
                          ),
                          if (_more)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                              child: Column(
                                children: [
                                  _field(s.t('aircraft'), _aircraft),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _field(
                                          s.t('duration'),
                                          _duration,
                                          number: true,
                                          onChanged: (_) =>
                                              _durationTouched = true,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: _field(
                                          s.t('distance'),
                                          _distance,
                                          number: true,
                                          decimal: true,
                                          onChanged: (_) =>
                                              _distanceTouched = true,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _field(s.t('seat'), _seat),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: DropdownButtonFormField<String>(
                                          initialValue: _cabin,
                                          isExpanded: true,
                                          decoration: _decoration(s.t('cabin')),
                                          items: _cabinOptions(s),
                                          onChanged: (value) {
                                            setState(() => _cabin = value);
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  _field(s.t('note'), _note, lines: 3),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  PrimaryButton(
                    label: _saving
                        ? '…'
                        : s.t(
                            widget.initialFlight == null
                                ? 'save'
                                : 'saveChanges',
                          ),
                    icon: Icons.check_rounded,
                    onPressed: _saving ? null : _save,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    bool number = false,
    bool decimal = false,
    int lines = 1,
    bool required = false,
    IconData? prefixIcon,
    ValueChanged<String>? onSubmitted,
    ValueChanged<String>? onChanged,
    String? hintText,
  }) => TextField(
    controller: controller,
    keyboardType: number
        ? TextInputType.numberWithOptions(decimal: decimal)
        : TextInputType.text,
    minLines: lines,
    maxLines: lines,
    onSubmitted: onSubmitted,
    onChanged: onChanged,
    decoration: _decoration(required ? '$label *' : label).copyWith(
      hintText: hintText,
      prefixIcon: prefixIcon == null
          ? null
          : Icon(prefixIcon, color: context.appColors.textTertiary),
    ),
  );

  InputDecoration _decoration(String label) {
    final colors = context.appColors;
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: colors.surface,
      labelStyle: AppTextStyles.label.copyWith(color: colors.textSecondary),
      floatingLabelStyle: TextStyle(
        color: colors.lime,
        backgroundColor: colors.surface,
        fontSize: 12,
        height: 1,
        fontWeight: FontWeight.w600,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      border: ShapedInputBorder(
        shape: AppShapes.medium,
        borderSide: BorderSide(color: colors.border),
        gapPadding: 8,
      ),
      enabledBorder: ShapedInputBorder(
        shape: AppShapes.medium,
        borderSide: BorderSide(color: colors.border),
        gapPadding: 8,
      ),
      focusedBorder: ShapedInputBorder(
        shape: AppShapes.medium,
        borderSide: BorderSide(color: colors.lime, width: 1.5),
        gapPadding: 8,
      ),
    );
  }

  List<BoxShadow> _surfaceShadow() => [
    BoxShadow(
      color: Colors.black.withValues(alpha: .16),
      blurRadius: 18,
      offset: const Offset(0, 8),
    ),
  ];

  String? _normalizeCabinValue(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) return null;
    return switch (normalized.toLowerCase()) {
      '经济舱' || 'economy' => 'Economy',
      '超级经济舱' || 'premium economy' || 'premium' => 'Premium Economy',
      '商务舱' || 'business' => 'Business',
      '头等舱' || 'first' => 'First',
      // Legacy placeholder values are not useful data and should not make
      // the dropdown assert when an older record is opened.
      '未记录' || '未填写' || 'unknown' || 'n/a' => null,
      _ => normalized,
    };
  }

  List<DropdownMenuItem<String>> _cabinOptions(AppStrings strings) {
    final options = <String>['Economy', 'Premium Economy', 'Business', 'First'];
    if (_cabin != null && !options.contains(_cabin)) {
      options.insert(0, _cabin!);
    }
    return options
        .map(
          (value) => DropdownMenuItem<String>(
            value: value,
            child: Text(
              value == 'Economy' ? strings.t('economy') : value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        )
        .toList();
  }

  Future<void> _lookupFlight() async {
    final parsed = _syncFlightIdentity();
    final airline = parsed?.$1 ?? '';
    final flightNumber = parsed?.$2 ?? '';
    final strings = context.strings;
    if (airline.isEmpty || flightNumber.isEmpty) {
      setState(() => _lookupMessage = strings.t('requiredHint'));
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _lookingUp = true;
      _lookupMessage = null;
    });
    try {
      final result = await widget.controller.lookupFlight(
        airline: airline,
        flightNumber: flightNumber,
        flightDate: _date,
      );
      if (!mounted) return;
      if (result == null) {
        setState(() => _lookupMessage = strings.t('flightLookupNoResult'));
        return;
      }
      final filled = <String>[];
      setState(() {
        if (_airline.text.trim().isEmpty && result.airline != null) {
          _airline.text = result.airline!;
          filled.add(strings.t('airline'));
        }
        if (!_dateTouched && result.departedAt != null) {
          _date = result.departedAt!.toLocal();
          _dateTouched = true;
          filled.add(strings.t('date'));
        }
        if (_departure == null && result.departureIata != null) {
          final airport = widget.controller.airportFor(result.departureIata!);
          if (airport != null) {
            _departure = airport;
            filled.add(strings.t('departure'));
          }
        }
        if (_arrival == null && result.arrivalIata != null) {
          final airport = widget.controller.airportFor(result.arrivalIata!);
          if (airport != null) {
            _arrival = airport;
            filled.add(strings.t('arrival'));
          }
        }
        if (!_arrivalTouched && result.arrivedAt != null) {
          _arrivalAt = result.arrivedAt!.toLocal();
          _arrivalTouched = true;
          filled.add(strings.t('landing'));
        }
        if (_aircraft.text.trim().isEmpty &&
            result.aircraftType != null &&
            result.aircraftType!.trim().isNotEmpty) {
          _aircraft.text = result.aircraftType!;
          filled.add(strings.t('aircraft'));
        }
        if (!_distanceTouched && result.distanceKm != null) {
          _distance.text = _formatDistance(result.distanceKm!);
          filled.add(strings.t('distance'));
        }
        if (!_durationTouched) {
          final duration =
              result.durationMinutes ??
              _durationFromTimes(_date, _arrivalAt) ??
              _estimatedDurationForAirports(
                _departure,
                _arrival,
                distanceKm: result.distanceKm,
              );
          if (duration != null && duration > 0) {
            _duration.text = duration.toString();
            filled.add(strings.t('duration'));
          }
        }
        _applyCalculatedFields(
          calculateDistance: result.distanceKm == null,
          calculateDuration: result.durationMinutes == null,
        );
        if (filled.contains(strings.t('aircraft')) ||
            filled.contains(strings.t('distance')) ||
            filled.contains(strings.t('duration'))) {
          _more = true;
        }
        _lookupMessage = filled.isEmpty
            ? strings.t('flightLookupSuccess')
            : '${strings.t('flightLookupSuccess')} · ${filled.join('、')}';
      });
    } catch (_) {
      if (mounted) {
        setState(() => _lookupMessage = strings.t('flightLookupFailed'));
      }
    } finally {
      if (mounted) setState(() => _lookingUp = false);
    }
  }

  void _onFlightIdentityChanged(String _) {
    // Keep the internal values from a previous edit/query from being reused
    // when the user starts typing a new combined airline + flight number.
    _airline.clear();
    _flightNumber.clear();
  }

  (String airline, String flightNumber)? _syncFlightIdentity() {
    final parsed = _parseFlightIdentity(_flightIdentity.text);
    if (parsed == null) return null;
    _airline.text = parsed.$1;
    _flightNumber.text = parsed.$2;
    return parsed;
  }

  (String airline, String flightNumber)? _parseFlightIdentity(String value) {
    final text = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (text.isEmpty) return null;

    // Prefer the two/three-letter IATA/ICAO prefix when it is present. The
    // negative look-behind intentionally allows Chinese names directly next
    // to the code, e.g. “南方航空CZ679”.
    final codeMatch = RegExp(
      r'(?<![A-Za-z0-9])([A-Za-z]{2,3})\s*(\d{1,4}[A-Za-z]?)(?![A-Za-z0-9])',
      caseSensitive: false,
    ).firstMatch(text);
    late String prefix;
    late String number;
    String airlineText;
    if (codeMatch != null) {
      prefix = codeMatch.group(1)!.toUpperCase();
      number = codeMatch.group(2)!.toUpperCase();
      airlineText = text
          .replaceRange(codeMatch.start, codeMatch.end, ' ')
          .trim();
    } else {
      // Also accept “南方航空679” when the airline name itself identifies
      // the IATA prefix in the offline catalog.
      final numberMatch = RegExp(r'(\d{1,4}[A-Za-z]?)\s*$').firstMatch(text);
      if (numberMatch == null) return null;
      number = numberMatch.group(1)!.toUpperCase();
      airlineText = text.substring(0, numberMatch.start).trim();
      final detectedPrefix = airlineIataFromText(airlineText);
      if (detectedPrefix == null) return null;
      prefix = detectedPrefix;
    }

    final resolvedAirline = resolveAirlineName(
      prefix,
      text: airlineText,
    ).trim();
    if (resolvedAirline.isEmpty || number.isEmpty) return null;
    return (resolvedAirline, '$prefix$number');
  }

  Future<void> _pickAirport(bool departure) async {
    final airport = await showModalBottomSheet<Airport>(
      context: context,
      isScrollControlled: true,
      requestFocus: false,
      backgroundColor: context.appColors.background,
      builder: (_) => _AirportPicker(controller: widget.controller),
    );
    if (airport == null) return;
    setState(() {
      if (departure) {
        _departure = airport;
      } else {
        _arrival = airport;
      }
      _applyCalculatedFields();
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(1900),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        _date = DateTime(
          picked.year,
          picked.month,
          picked.day,
          _date.hour,
          _date.minute,
        );
        _dateTouched = true;
        _applyCalculatedFields();
      });
    }
  }

  Future<void> _pickDepartureTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_date),
    );
    if (picked == null) return;
    setState(() {
      _date = DateTime(
        _date.year,
        _date.month,
        _date.day,
        picked.hour,
        picked.minute,
      );
      _dateTouched = true;
      _applyCalculatedFields();
    });
  }

  Future<void> _pickArrivalDate() async {
    final fallback = _arrivalAt ?? _estimatedArrival ?? _date;
    final picked = await showDatePicker(
      context: context,
      initialDate: fallback,
      firstDate: DateTime(1900),
      lastDate: DateTime.now().add(const Duration(days: 3660)),
    );
    if (picked == null) return;
    final current = _arrivalAt ?? fallback;
    setState(() {
      _arrivalAt = DateTime(
        picked.year,
        picked.month,
        picked.day,
        current.hour,
        current.minute,
      );
      _arrivalTouched = true;
      _applyCalculatedFields();
    });
  }

  Future<void> _pickArrivalTime() async {
    final fallback = _arrivalAt ?? _estimatedArrival ?? _date;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(fallback),
    );
    if (picked == null) return;
    setState(() {
      _arrivalAt = DateTime(
        fallback.year,
        fallback.month,
        fallback.day,
        picked.hour,
        picked.minute,
      );
      _arrivalTouched = true;
      _applyCalculatedFields();
    });
  }

  void _applyCalculatedFields({
    bool calculateDistance = true,
    bool calculateDuration = true,
  }) {
    final distanceKm = _calculatedDistanceKm;
    if (calculateDistance && !_distanceTouched && distanceKm != null) {
      _distance.text = _formatDistance(distanceKm);
    }

    if (calculateDuration && !_durationTouched) {
      final duration =
          _durationFromTimes(_date, _arrivalAt) ??
          _estimatedDurationForAirports(
            _departure,
            _arrival,
            distanceKm: distanceKm,
          );
      if (duration != null) _duration.text = duration.toString();
    }
  }

  double? get _calculatedDistanceKm {
    if (_departure == null || _arrival == null) return null;
    return AirportCatalog.greatCircleDistanceKm(_departure!, _arrival!);
  }

  static String _formatDistance(double value) {
    if (!value.isFinite || value <= 0) return '';
    final rounded = value.round();
    return rounded.toString();
  }

  static double? _parseDistance(String value) {
    final normalized = value.trim().replaceAll(',', '');
    final parsed = double.tryParse(normalized);
    return parsed == null || !parsed.isFinite || parsed <= 0 ? null : parsed;
  }

  static int? _durationFromTimes(DateTime departure, DateTime? arrival) {
    if (arrival == null) return null;
    final minutes = arrival.difference(departure).inMinutes;
    return minutes > 0 && minutes <= 48 * 60 ? minutes : null;
  }

  static int? _estimatedDurationForAirports(
    Airport? departure,
    Airport? arrival, {
    double? distanceKm,
  }) {
    final distance =
        distanceKm ??
        (departure == null || arrival == null
            ? null
            : AirportCatalog.greatCircleDistanceKm(departure, arrival));
    if (distance == null || !distance.isFinite || distance <= 0) return null;
    // Gate-to-gate estimate: cruise speed plus climb, taxi and routing time.
    // It is explicitly a fallback; a provider duration or edited value wins.
    final estimate = (distance / 780 * 60 + 35).round();
    return math.max(45, math.min(960, estimate));
  }

  DateTime? get _estimatedArrival {
    final minutes = int.tryParse(_duration.text);
    if (minutes == null || minutes <= 0) return null;
    return _date.add(Duration(minutes: minutes));
  }

  FlightStatus _statusForDate(DateTime date) {
    final today = DateTime.now();
    final selectedDay = DateTime(date.year, date.month, date.day);
    final currentDay = DateTime(today.year, today.month, today.day);
    return selectedDay.isAfter(currentDay)
        ? FlightStatus.upcoming
        : FlightStatus.completed;
  }

  Future<void> _save() async {
    final strings = context.strings;
    final parsed = _syncFlightIdentity();
    if (parsed == null ||
        parsed.$1.trim().isEmpty ||
        parsed.$2.trim().isEmpty ||
        _departure == null ||
        _arrival == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(strings.t('missingRequired'))));
      return;
    }
    setState(() => _saving = true);
    try {
      final initial = widget.initialFlight;
      final durationMinutes = int.tryParse(_duration.text);
      final distanceKm = _parseDistance(_distance.text);
      final arrivedAt = _arrivalTouched
          ? _arrivalAt
          : (durationMinutes != null && durationMinutes > 0
                ? _date.add(Duration(minutes: durationMinutes))
                : null);
      final status = _statusForDate(_date);
      if (initial == null) {
        await widget.controller.addFlight(
          departure: _departure!,
          arrival: _arrival!,
          date: _date,
          arrivedAt: arrivedAt,
          distanceKm: distanceKm,
          airline: _airline.text,
          flightNumber: _flightNumber.text,
          aircraftType: _aircraft.text,
          durationMinutes: durationMinutes,
          seat: _seat.text,
          cabinClass: _cabin,
          note: _note.text,
          status: status,
        );
      } else {
        await widget.controller.updateFlight(
          existing: initial,
          departure: _departure!,
          arrival: _arrival!,
          date: _date,
          arrivedAt: arrivedAt,
          distanceKm: distanceKm,
          airline: _airline.text,
          flightNumber: _flightNumber.text,
          aircraftType: _aircraft.text,
          durationMinutes: durationMinutes,
          seat: _seat.text,
          cabinClass: _cabin,
          note: _note.text,
          status: status,
        );
      }
      if (mounted) Navigator.pop(context);
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

class _ImeAwareFlightForm extends StatelessWidget {
  const _ImeAwareFlightForm({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      // Keep IME relayout local to the form's viewport. The old nested
      // Scaffold resized its whole sheet and repainted every decorated card
      // on each Android keyboard animation frame.
      padding: EdgeInsets.only(bottom: bottomInset),
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.only(bottom: AppSpacing.xl),
        children: children,
      ),
    );
  }
}

class _AirportSelector extends StatelessWidget {
  const _AirportSelector({
    required this.label,
    required this.airport,
    required this.onTap,
    this.alignEnd = false,
  });
  final String label;
  final Airport? airport;
  final VoidCallback onTap;
  final bool alignEnd;
  @override
  Widget build(BuildContext context) {
    final selectedAirport = airport;
    final colors = context.appColors;
    return InkWell(
      onTap: onTap,
      customBorder: AppShapes.small,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          crossAxisAlignment: alignEnd
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w800,
                letterSpacing: -.1,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              airport?.iataCode ?? '—',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 40,
                height: 1,
                fontWeight: FontWeight.w700,
                letterSpacing: -1.5,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              selectedAirport == null
                  ? context.strings.t('tapToChoose')
                  : localizedAirportCardName(selectedAirport),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                height: 1.15,
                fontWeight: FontWeight.w600,
                color: airport == null ? colors.lime : colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateTimeSelector extends StatelessWidget {
  const _DateTimeSelector({
    required this.label,
    required this.value,
    required this.onDateTap,
    required this.onTimeTap,
  });

  final String label;
  final DateTime? value;
  final VoidCallback onDateTap;
  final VoidCallback onTimeTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final date = value == null
        ? context.strings.t('unknown')
        : DateFormat('yyyy-MM-dd').format(value!);
    final time = value == null ? '--:--' : DateFormat('HH:mm').format(value!);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      decoration: ShapeDecoration(
        color: colors.surfaceElevated,
        shape: AppShapes.medium,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: .1,
            ),
          ),
          const SizedBox(height: 4),
          InkWell(
            onTap: onDateTap,
            customBorder: AppShapes.small,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Icon(
                    Icons.calendar_today_rounded,
                    color: colors.textSecondary,
                    size: 15,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      date,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          InkWell(
            onTap: onTimeTap,
            customBorder: AppShapes.small,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(
                    Icons.schedule_rounded,
                    color: colors.textSecondary,
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    time,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 22,
                      height: 1,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AirportPicker extends StatefulWidget {
  const _AirportPicker({required this.controller});
  final AppController controller;
  @override
  State<_AirportPicker> createState() => _AirportPickerState();
}

class _AirportPickerState extends State<_AirportPicker> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _searchDebounce;
  var _shouldFocusSearch = true;
  List<Airport> _results = const [];
  List<AirportCountry> _countryResults = const [];
  AirportCountry? _selectedCountry;

  @override
  void initState() {
    super.initState();
    _search.addListener(_onSearchChanged);
    // Let the picker sheet settle before starting the IME animation. This is
    // especially important on physical Android devices, where the sheet
    // transition and keyboard resize otherwise jank together.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 360), () {
        if (!mounted || !_shouldFocusSearch || _searchFocus.hasFocus) return;
        _searchFocus.requestFocus();
      });
    });
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
    if (query.isEmpty) {
      _applySearchResults(const [], null, const []);
      return;
    }
    // Do not run the full catalogue search in the same frame as an IME
    // keystroke. Coalescing rapid input keeps the keyboard responsive while
    // the pre-indexed catalogue still returns results almost immediately.
    _searchDebounce = Timer(const Duration(milliseconds: 80), () {
      if (!mounted || query != _search.text.trim()) return;
      _searchDebounce = null;
      _updateSearchResults(query);
    });
  }

  void _updateSearchResults(String query) {
    final countries = widget.controller.airports
        .searchCountries(query, limit: 8)
        .toList(growable: false);
    final exactCountry = widget.controller.airports.findCountry(query);
    final airports = exactCountry == null
        ? (query.isEmpty
              ? const <Airport>[]
              : widget.controller.airports.search(query, limit: 40).toList())
        : widget.controller.airports.airportsForCountry(exactCountry.code);
    _applySearchResults(countries, exactCountry, airports);
  }

  void _applySearchResults(
    List<AirportCountry> countries,
    AirportCountry? exactCountry,
    List<Airport> airports,
  ) {
    if (!mounted) return;
    setState(() {
      _countryResults = countries;
      _selectedCountry = exactCountry;
      _results = airports;
    });
  }

  void _selectCountry(AirportCountry country) {
    _shouldFocusSearch = false;
    _search.value = TextEditingValue(
      text: country.name,
      selection: TextSelection.collapsed(offset: country.name.length),
    );
    _searchFocus.unfocus();
  }

  void _clearCountry() {
    _shouldFocusSearch = false;
    _search.clear();
    _searchFocus.requestFocus();
  }

  Widget _countryResult(BuildContext context, AirportCountry country) =>
      ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        leading: SizedBox(
          width: 44,
          child: Text(
            localizedCountryFlag(country.code),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 25),
          ),
        ),
        title: Text(
          '${country.name}  ${country.code}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          context.strings
              .t('countryAirportCount')
              .replaceAll('{count}', country.airportCount.toString()),
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => _selectCountry(country),
      );

  Widget _countryHeader(BuildContext context, AirportCountry country) {
    final colors = context.appColors;
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: ShapeDecoration(
        color: colors.lime.withValues(alpha: .12),
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colors.lime.withValues(alpha: .42)),
        ),
      ),
      child: Row(
        children: [
          Text(
            localizedCountryFlag(country.code),
            style: const TextStyle(fontSize: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              context.strings
                  .t('countryAirports')
                  .replaceAll('{country}', country.name)
                  .replaceAll('{count}', country.airportCount.toString()),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            tooltip: context.strings.t('clear'),
            onPressed: _clearCountry,
            icon: const Icon(Icons.close_rounded),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _airportResult(Airport airport) {
    final colors = context.appColors;
    final city = localizedAirportCity(airport);
    final title = city.isEmpty
        ? (airport.city.trim().isEmpty ? airport.iataCode : airport.city)
        : city;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      leading: Container(
        width: 54,
        height: 42,
        alignment: Alignment.center,
        decoration: ShapeDecoration(
          color: colors.lime,
          shape: RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Text(
          airport.iataCode,
          style: const TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      title: Text(title),
      subtitle: Text(
        localizedAirportName(airport),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () => Navigator.pop(context, airport),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final selectedCountry = _selectedCountry;
    final countryRows = selectedCountry == null ? _countryResults.length : 1;
    final totalRows = countryRows + _results.length;
    return SafeArea(
      top: true,
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 24,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .76,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.strings.t('selectAirport'),
                style: AppTextStyles.sectionTitle.copyWith(
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _search,
                focusNode: _searchFocus,
                autofocus: false,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded),
                  hintText: context.strings.t('searchAirport'),
                  filled: true,
                  fillColor: colors.surface,
                  border: ShapedInputBorder(
                    shape: AppShapes.medium,
                    borderSide: BorderSide(color: colors.border),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: totalRows == 0
                    ? Center(child: Text(context.strings.t('searchAirport')))
                    : ListView.separated(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        itemCount: totalRows,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          if (selectedCountry != null) {
                            if (index == 0) {
                              return _countryHeader(context, selectedCountry);
                            }
                            return _airportResult(_results[index - 1]);
                          }
                          if (index < _countryResults.length) {
                            return _countryResult(
                              context,
                              _countryResults[index],
                            );
                          }
                          return _airportResult(
                            _results[index - _countryResults.length],
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
