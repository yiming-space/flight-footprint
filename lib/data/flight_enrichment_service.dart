import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'airline_catalog.dart';

/// Best-effort flight details returned by an external provider.
///
/// The app never depends on this object to save a flight: local entry remains
/// the source of truth and an unsuccessful lookup simply leaves the manual
/// fields untouched.
class FlightEnrichment {
  const FlightEnrichment({
    this.airline,
    this.flightNumber,
    this.departureIata,
    this.arrivalIata,
    this.aircraftType,
    this.registration,
    this.aircraftSource,
    this.aircraftObservedAt,
    this.aircraftLookupAttempted = false,
    this.departedAt,
    this.arrivedAt,
    this.durationMinutes,
    this.distanceKm,
    required this.source,
  });

  final String? airline;
  final String? flightNumber;
  final String? departureIata;
  final String? arrivalIata;
  final String? aircraftType;
  final String? registration;
  final String? aircraftSource;
  final DateTime? aircraftObservedAt;
  final bool aircraftLookupAttempted;
  final DateTime? departedAt;
  final DateTime? arrivedAt;
  final int? durationMinutes;
  final double? distanceKm;
  final String source;
}

/// Small provider adapter used by the add-flight form.
///
/// ADSBdb is queried first for a callsign route. FlightBoard's open-source
/// route workflow uses the free adsb.im / adsb.lol routeset endpoints, so they
/// are tried as a compatible fallback. For an explicitly selected current
/// date, a fresh, unambiguous ADSB.lol callsign observation can additionally
/// supply equipment, with ADSBdb aircraft metadata used only for that observed
/// identity. These optional feeds never establish a historical assignment.
class FlightEnrichmentService {
  FlightEnrichmentService({
    http.Client? client,
    this.requestTimeout = const Duration(seconds: 7),
    DateTime Function()? now,
    this.enableLiveAircraft = const bool.fromEnvironment(
      'FLIGHT_FOOTPRINT_ENABLE_LIVE_AIRCRAFT',
      defaultValue: !kReleaseMode,
    ),
    this.enableAdsbLolRouteset = const bool.fromEnvironment(
      'FLIGHT_FOOTPRINT_ENABLE_ADSB_LOL_ROUTESET',
      defaultValue: !kReleaseMode,
    ),
  }) : _client = client ?? http.Client(),
       _now = now ?? DateTime.now,
       _ownsClient = client == null;

  static const _adsbdbBase = 'https://api.adsbdb.com/v0/callsign';
  static const _flightBoardEndpoints = [
    'https://adsb.im/api/0/routeset',
    'https://api.adsb.lol/api/0/routeset',
  ];

  // Providers commonly return IATA equipment codes instead of an ICAO model
  // code. Keep the compact conversion table local so the editor can still
  // show a useful model when the response contains values such as 32N or 77W.
  static const _iataAircraftTypes = <String, String>{
    '319': 'A319',
    '320': 'A320',
    '321': 'A321',
    '32A': 'A320',
    '32N': 'A320neo',
    '32Q': 'A321neo',
    '32S': 'A320',
    '332': 'A330-200',
    '333': 'A330-300',
    '338': 'A330-800',
    '339': 'A330-900',
    '350': 'A350',
    '359': 'A350-900',
    '351': 'A350-1000',
    '380': 'A380',
    '388': 'A380-800',
    '737': 'B737',
    '738': 'B737-800',
    '739': 'B737-900',
    '73H': 'B737-800',
    '73J': 'B737-900',
    '7M8': 'B737 MAX 8',
    '7M9': 'B737 MAX 9',
    '744': 'B747-400',
    '748': 'B747-8',
    '763': 'B767-300',
    '764': 'B767-400',
    '772': 'B777-200',
    '773': 'B777-300',
    '77L': 'B777-200LR',
    '77W': 'B777-300ER',
    '788': 'B787-8',
    '789': 'B787-9',
    '78X': 'B787-10',
    'E70': 'E170',
    'E75': 'E175',
    'E90': 'E190',
    'E95': 'E195',
    'CR7': 'CRJ-700',
    'CR9': 'CRJ-900',
    'CRK': 'CRJ-1000',
    'AT4': 'ATR 42',
    'AT7': 'ATR 72',
    'DH4': 'Dash 8 Q400',
    'DH8': 'Dash 8',
    'M80': 'MD-80',
    'M82': 'MD-82',
    'M83': 'MD-83',
    'M87': 'MD-87',
    'M88': 'MD-88',
    'M90': 'MD-90',
  };

  static const _iataToIcao = <String, String>{
    '3U': 'CSC',
    '8L': 'LKE',
    '9C': 'CQH',
    'CA': 'CCA',
    'CZ': 'CSN',
    'EU': 'UEA',
    'FM': 'CSH',
    'GJ': 'CDC',
    'GS': 'GCR',
    'HO': 'DKH',
    'HU': 'CHH',
    'JD': 'CBJ',
    'KN': 'CUA',
    'MF': 'CXA',
    'MU': 'CES',
    'NS': 'HBH',
    'PN': 'CHB',
    'QW': 'QDA',
    'SC': 'CDG',
    'TV': 'TBA',
    'AA': 'AAL',
    'AC': 'ACA',
    'AF': 'AFR',
    'AI': 'AIC',
    'AK': 'AXM',
    'AM': 'AMX',
    'AS': 'ASA',
    'AY': 'FIN',
    'BA': 'BAW',
    'B6': 'JBU',
    'BI': 'RBA',
    'BR': 'EVA',
    'CI': 'CAL',
    'CM': 'CMP',
    'CX': 'CPA',
    'DL': 'DAL',
    'DY': 'NAX',
    'EK': 'UAE',
    'ET': 'ETH',
    'EY': 'ETD',
    'F9': 'FFT',
    'FJ': 'FJI',
    'FR': 'RYR',
    'G3': 'GLO',
    'GA': 'GIA',
    'GF': 'GFA',
    'GK': 'JJP',
    'HA': 'HAL',
    'HX': 'CRK',
    'IB': 'IBE',
    'ID': 'BTK',
    'I5': 'AXB',
    'JL': 'JAL',
    'JQ': 'JST',
    'KE': 'KAL',
    'KL': 'KLM',
    'KQ': 'KQA',
    'KU': 'KAC',
    'LA': 'LAN',
    'LH': 'DLH',
    'LJ': 'JNA',
    'LO': 'LOT',
    'LX': 'SWR',
    'ME': 'MEA',
    'MK': 'MAU',
    'MM': 'APJ',
    'MS': 'MSR',
    'MH': 'MAS',
    'NH': 'ANA',
    'NK': 'NKS',
    'NZ': 'ANZ',
    'OZ': 'AAR',
    'PC': 'PGT',
    'PR': 'PAL',
    'QF': 'QFA',
    'QG': 'CTV',
    'QZ': 'AWQ',
    'QR': 'QTR',
    'SA': 'SAA',
    'SB': 'ACI',
    'S7': 'SBI',
    'SK': 'SAS',
    'SL': 'TLM',
    'SQ': 'SIA',
    'SU': 'AFL',
    'SV': 'SVA',
    'TG': 'THA',
    'TK': 'THY',
    'TP': 'TAP',
    'TR': 'TGW',
    'UA': 'UAL',
    'UL': 'ALK',
    'U2': 'EZY',
    'U6': 'SVR',
    'VA': 'VOZ',
    'VJ': 'VJC',
    'VN': 'HVN',
    'VS': 'VIR',
    'VY': 'VLG',
    'W6': 'WZZ',
    'WN': 'SWA',
    'WS': 'WJA',
    'WY': 'OMA',
    'ZH': 'CSZ',
  };

  final http.Client _client;
  final bool _ownsClient;
  final Duration requestTimeout;
  final DateTime Function() _now;

  /// Experimental observations are opt-in in release builds until provider
  /// access and data licensing have been confirmed. Tests can inject a value.
  final bool enableLiveAircraft;

  /// ADSB.lol's routeset fallback is separately opt-in for the same reason.
  /// ADSBdb and the existing adsb.im route fallback remain available.
  final bool enableAdsbLolRouteset;

  /// Looks up a flight without making the result a prerequisite for saving.
  Future<FlightEnrichment?> lookup({
    required String airline,
    required String flightNumber,
    DateTime? flightDate,
    String? departureIata,
    String? arrivalIata,
  }) async {
    final callsigns = _callsignCandidates(airline, flightNumber);
    if (callsigns.isEmpty) return null;

    final instant = _now();
    final liveCallsigns = callsigns
        .where((value) => RegExp(r'^[A-Z]{3}\d{1,4}[A-Z]?$').hasMatch(value))
        .take(2)
        .toList(growable: false);
    final attemptLive =
        enableLiveAircraft &&
        flightDate != null &&
        _calendarDay(flightDate) == _calendarDay(instant) &&
        liveCallsigns.isNotEmpty;
    // Start the independent, bounded live request alongside the old route
    // workflow. An early route hit must not skip the equipment lookup.
    final liveFuture = attemptLive
        ? _lookupLiveAircraft(liveCallsigns, instant)
        : Future<_ObservedAircraft?>.value(null);
    final route = await _lookupRoute(callsigns, flightDate);
    final live = await liveFuture;
    final routeMatches =
        route == null ||
        ((departureIata == null ||
                departureIata.trim().isEmpty ||
                _clean(departureIata) == route.departureIata) &&
            (arrivalIata == null ||
                arrivalIata.trim().isEmpty ||
                _clean(arrivalIata) == route.arrivalIata));
    final boundAircraft = routeMatches ? live : null;
    if (route == null && boundAircraft == null) return null;
    return FlightEnrichment(
      airline: route?.airline,
      flightNumber: route?.flightNumber ?? _clean(flightNumber),
      departureIata: route?.departureIata,
      arrivalIata: route?.arrivalIata,
      aircraftType: routeMatches
          ? boundAircraft?.type ?? route?.aircraftType
          : null,
      // A live model must not inherit an unrelated route's registration
      // when the receiver has no registration for that physical aircraft.
      registration: !routeMatches
          ? null
          : boundAircraft != null
          ? boundAircraft.registration
          : route?.registration,
      aircraftSource: routeMatches
          ? boundAircraft?.source ?? route?.aircraftSource
          : null,
      aircraftObservedAt: boundAircraft?.observedAt,
      aircraftLookupAttempted: attemptLive,
      departedAt: route?.departedAt,
      arrivedAt: route?.arrivedAt,
      durationMinutes: route?.durationMinutes,
      distanceKm: route?.distanceKm,
      source: route?.source ?? boundAircraft!.source,
    );
  }

  Future<FlightEnrichment?> _lookupRoute(
    List<String> callsigns,
    DateTime? flightDate,
  ) async {
    for (final callsign in callsigns) {
      final result = await _lookupAdsbdb(callsign, flightDate: flightDate);
      if (result != null && _matchesFlightDate(result, flightDate)) {
        return result;
      }
    }
    for (final callsign in callsigns) {
      final result = await _lookupFlightBoard(callsign, flightDate: flightDate);
      if (result != null && _matchesFlightDate(result, flightDate)) {
        return result;
      }
    }
    return null;
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }

  Future<_ObservedAircraft?> _lookupLiveAircraft(
    List<String> callsigns,
    DateTime instant,
  ) async {
    final matches = <_ObservedAircraft>[];
    final timeout = requestTimeout < const Duration(seconds: 3)
        ? requestTimeout
        : const Duration(seconds: 3);
    for (final callsign in callsigns) {
      final payload = await _getJson(
        Uri.parse('https://api.adsb.lol/v2/callsign/$callsign'),
        timeout: timeout,
      );
      if (payload == null) continue;
      // The public v2 endpoint reports `now` as Unix milliseconds. Accept
      // seconds as well, but never substitute the device clock for missing
      // provider evidence or accept a stale cache as today's assignment.
      final providerNow = _dateTime(payload['now']);
      if (providerNow == null ||
          providerNow.difference(instant.toUtc()).abs() >
              const Duration(minutes: 5)) {
        continue;
      }
      final aircraft = payload['ac'];
      if (aircraft is! List) continue;
      for (final value in aircraft) {
        final item = _asMap(value);
        if (item == null ||
            _clean(item['flight']?.toString() ?? '') != callsign) {
          continue;
        }
        final seenValue = item['seen'];
        final seen = seenValue is num
            ? seenValue.toDouble()
            : double.tryParse(seenValue?.toString() ?? '');
        if (seen == null || !seen.isFinite || seen < 0 || seen > 120) continue;
        final observedAt = providerNow.subtract(
          Duration(milliseconds: (seen * 1000).round()),
        );
        if (_calendarDay(observedAt) != _calendarDay(instant)) continue;
        final hexValue = _clean(item['hex']?.toString() ?? '');
        final hex = RegExp(r'^[0-9A-F]{6}$').hasMatch(hexValue)
            ? hexValue
            : null;
        final registration = _stringFrom(item['r'], const []);
        if (hex == null && registration == null) continue;
        final candidate = _ObservedAircraft(
          type: _aircraftModel(item['t']),
          registration: registration,
          hex: hex,
          observedAt: observedAt,
          source: 'ADSB.lol',
        );
        final sameIndex = matches.indexWhere(
          (existing) =>
              (hex != null && existing.hex == hex) ||
              (registration != null &&
                  existing.registration != null &&
                  _clean(existing.registration!) == _clean(registration)),
        );
        if (sameIndex < 0) {
          matches.add(candidate);
        } else {
          final previous = matches[sameIndex];
          // Duplicates must describe the same physical aircraft, not hide
          // conflicting assignments behind one shared identifier.
          if ((hex != null && previous.hex != null && hex != previous.hex) ||
              (registration != null &&
                  previous.registration != null &&
                  _clean(registration) != _clean(previous.registration!)) ||
              (candidate.type != null &&
                  previous.type != null &&
                  candidate.type != previous.type)) {
            return null;
          }
          if (candidate.type != null && previous.type == null) {
            matches[sameIndex] = candidate;
          }
        }
      }
    }
    // Reused callsigns / multiple aircraft are deliberately not resolved
    // using nearest coordinates or an inferred route segment.
    if (matches.length != 1) return null;
    final observed = matches.single;
    if (observed.type != null) return observed;
    final identifier = observed.registration ?? observed.hex!;
    final payload = await _getJson(
      Uri.parse(
        'https://api.adsbdb.com/v0/aircraft/${Uri.encodeComponent(identifier)}',
      ),
      timeout: timeout,
    );
    final response = _asMap(payload?['response']);
    final aircraft = _asMap(response?['aircraft']);
    if (aircraft == null) return null;
    final registration = _stringFrom(aircraft['registration'], const []);
    final hex = _stringFrom(aircraft['mode_s'], const []);
    if (observed.registration != null &&
        registration != null &&
        _clean(observed.registration!) != _clean(registration)) {
      return null;
    }
    if (observed.hex != null && hex != null && observed.hex != _clean(hex)) {
      return null;
    }
    final identityMatches =
        (observed.registration != null &&
            registration != null &&
            _clean(observed.registration!) == _clean(registration)) ||
        (observed.hex != null && hex != null && observed.hex == _clean(hex));
    if (!identityMatches) return null;
    final type =
        _aircraftModel(aircraft['icao_type']) ??
        _aircraftModel(aircraft['type']) ??
        _aircraftModel(aircraft['model']);
    if (type == null) return null;
    return _ObservedAircraft(
      type: type,
      registration: observed.registration ?? registration,
      hex: observed.hex,
      observedAt: observed.observedAt,
      source: 'ADSB.lol + ADSBdb',
    );
  }

  List<String> _callsignCandidates(String airline, String flightNumber) {
    final normalizedNumber = _clean(flightNumber);
    if (normalizedNumber.isEmpty) return const [];
    final candidates = <String>[];

    void add(String value) {
      final normalized = _clean(value);
      if (normalized.isNotEmpty && !candidates.contains(normalized)) {
        candidates.add(normalized);
      }
    }

    add(normalizedNumber);
    final numberMatch = RegExp(r'^([A-Z0-9]{2,3}?)(\d{1,4}[A-Z]?)$')
        .firstMatch(normalizedNumber);
    if (numberMatch != null) {
      final iata = numberMatch.group(1)!;
      final icao = _iataToIcao[iata] ?? airlineIcaoForCode(iata);
      if (icao != null) add('$icao${numberMatch.group(2)!}');
    } else if (RegExp(r'^\d{1,4}[A-Z]?$').hasMatch(normalizedNumber)) {
      final airlineKey = _clean(airline);
      final iata = _iataToIcao.containsKey(airlineKey)
          ? airlineKey
          : airlineIataForName(airline);
      if (iata != null) add('$iata$normalizedNumber');
      final icao = iata == null
          ? null
          : (_iataToIcao[iata] ?? airlineIcaoForCode(iata));
      if (icao != null) {
        add('$icao$normalizedNumber');
      }
    }
    return candidates.take(3).toList(growable: false);
  }

  Future<FlightEnrichment?> _lookupAdsbdb(
    String callsign, {
    DateTime? flightDate,
  }) async {
    final payload = await _getJson(
      Uri.parse('$_adsbdbBase/${Uri.encodeComponent(callsign)}'),
    );
    if (payload == null) return null;
    final response = _asMap(payload['response']);
    final route = _asMap(response?['flightroute']);
    if (route == null) return null;
    return _fromRoute(
      route,
      payload: payload,
      fallbackFlightNumber: callsign,
      source: 'ADSBdb',
      flightDate: flightDate,
    );
  }

  Future<FlightEnrichment?> _lookupFlightBoard(
    String callsign, {
    DateTime? flightDate,
  }) async {
    for (final endpoint in _flightBoardEndpoints) {
      if (!enableAdsbLolRouteset &&
          Uri.parse(endpoint).host == 'api.adsb.lol') {
        continue;
      }
      final payload = await _postJson(Uri.parse(endpoint), {
        'callsign': callsign,
        'lat': 0,
        'lng': 0,
      });
      if (payload == null) continue;
      final route = _findRouteMap(payload);
      if (route == null) continue;
      final result = _fromRoute(
        route,
        payload: payload,
        fallbackFlightNumber: callsign,
        source: 'FlightBoard',
        flightDate: flightDate,
      );
      if (result != null) return result;
    }
    return null;
  }

  Future<Map<String, dynamic>?> _getJson(Uri uri, {Duration? timeout}) async {
    try {
      final response = await _client
          .get(
            uri,
            headers: const {
              'accept': 'application/json',
              'user-agent': 'FlightFootprint/1.0 personal-flight-diary',
            },
          )
          .timeout(timeout ?? requestTimeout);
      return _decodeJson(response);
    } on Object {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _postJson(
    Uri uri,
    Map<String, Object> body,
  ) async {
    try {
      final response = await _client
          .post(
            uri,
            headers: const {
              'accept': 'application/json',
              'content-type': 'application/json',
              'user-agent': 'FlightFootprint/1.0 personal-flight-diary',
            },
            body: jsonEncode(body),
          )
          .timeout(requestTimeout);
      return _decodeJson(response);
    } on Object {
      return null;
    }
  }

  Map<String, dynamic>? _decodeJson(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) return null;
    try {
      final value = jsonDecode(response.body);
      return _asMap(value);
    } on Object {
      return null;
    }
  }

  FlightEnrichment? _fromRoute(
    Map<String, dynamic> route, {
    required Map<String, dynamic> payload,
    required String fallbackFlightNumber,
    required String source,
    DateTime? flightDate,
  }) {
    final departure = _airportCode(
      _value(route, const ['origin', 'from', 'departure', 'departureAirport']),
    );
    final arrival = _airportCode(
      _value(route, const ['destination', 'to', 'arrival', 'arrivalAirport']),
    );
    if (departure == null || arrival == null) return null;

    final airlineValue = _value(route, const [
      'airline',
      'operator',
      'carrier',
    ]);
    final aircraftType = _aircraftType(route, payload);
    final aircraft = _findMapByKey(payload, const ['aircraft', 'plane']);
    final duration = _durationMinutes(
      _firstValue(route, payload, const [
        'durationMinutes',
        'duration_minutes',
        'flightDurationMinutes',
        'flight_duration_minutes',
        'duration',
        'filed_ete',
        'filedEte',
        'estimated_enroute_time',
        'estimatedEnrouteTime',
        'ete',
        'air_time',
        'airTime',
        'flight_time',
        'flightTime',
      ]),
    );
    final distance = _number(
      _firstValue(route, payload, const [
        'distanceKm',
        'distance_km',
        'distance',
        'routeDistanceKm',
        'route_distance_km',
      ]),
    );
    final departureTimeValue = _firstValue(route, payload, const [
      'actualDepartureAt',
      'actual_departure_at',
      'scheduledDepartureAt',
      'scheduled_departure_at',
      'departureDateTime',
      'departure_datetime',
      'departureTime',
      'departure_time',
      'departedAt',
      'departed_at',
      'flightDate',
      'flight_date',
    ]);
    final arrivalTimeValue = _firstValue(route, payload, const [
      'actualArrivalAt',
      'actual_arrival_at',
      'scheduledArrivalAt',
      'scheduled_arrival_at',
      'arrivalDateTime',
      'arrival_datetime',
      'arrivalTime',
      'arrival_time',
      'arrivedAt',
      'arrived_at',
    ]);
    var departedAt = _dateTime(departureTimeValue, fallbackDate: flightDate);
    var arrivedAt = _dateTime(arrivalTimeValue, fallbackDate: flightDate);

    // A few feeds mix a complete timestamp for one side with a time-only
    // value for the other. Anchor that time-only value to the known side so
    // a result such as 22:05–02:15 remains an overnight flight instead of
    // being attached to the device's current date.
    if (departedAt != null && arrivedAt != null) {
      final departureIsTimeOnly = _isTimeOnly(departureTimeValue);
      final arrivalIsTimeOnly = _isTimeOnly(arrivalTimeValue);
      if (departureIsTimeOnly && !arrivalIsTimeOnly) {
        departedAt = _sameDateWithTime(arrivedAt, departedAt);
        if (departedAt.isAfter(arrivedAt)) {
          departedAt = departedAt.subtract(const Duration(days: 1));
        }
      } else if (arrivalIsTimeOnly && !departureIsTimeOnly) {
        arrivedAt = _sameDateWithTime(departedAt, arrivedAt);
      }
    }
    if (departedAt != null &&
        arrivedAt != null &&
        !arrivedAt.isAfter(departedAt)) {
      arrivedAt = arrivedAt.add(const Duration(days: 1));
    }
    final explicitDeparture = _isTimeOnly(departureTimeValue)
        ? null
        : _dateTime(departureTimeValue);
    final explicitFlightDay = _dateTime(
      _firstValue(route, payload, const ['flightDate', 'flight_date']),
    );
    final equipmentDay = explicitDeparture ?? explicitFlightDay;
    // Standing-data routes describe a usual route, not the aircraft that
    // operated a selected date. Time-only values anchored by fallbackDate
    // are useful for the form but do not prove a dated aircraft assignment.
    // Airport fallback tolerates an adjacent timezone day. Equipment requires
    // an exact proved departure day; an arrival date alone is ambiguous for
    // an overnight flight and must not bind an airframe.
    final keepRouteAircraft =
        flightDate == null ||
        (equipmentDay != null &&
            _calendarDay(equipmentDay) == _calendarDay(flightDate));
    return FlightEnrichment(
      airline: _stringFrom(airlineValue, const ['name', 'label']),
      flightNumber:
          _stringFrom(route, const [
            'callsign_iata',
            'callsign',
            'flightNumber',
          ]) ??
          fallbackFlightNumber,
      departureIata: departure,
      arrivalIata: arrival,
      aircraftType: keepRouteAircraft ? aircraftType : null,
      registration: keepRouteAircraft
          ? _stringFrom(aircraft, const ['registration', 'reg'])
          : null,
      aircraftSource: keepRouteAircraft && aircraftType != null ? source : null,
      departedAt: departedAt,
      arrivedAt: arrivedAt,
      durationMinutes: duration,
      distanceKm: distance,
      source: source,
    );
  }

  Object? _firstValue(
    Map<String, dynamic> route,
    Map<String, dynamic> payload,
    List<String> keys,
  ) {
    final routeValue = _value(route, keys) ?? _findValueByKey(route, keys);
    if (routeValue != null) return routeValue;
    return _value(payload, keys) ?? _findValueByKey(payload, keys);
  }

  /// Providers use several shapes for equipment: a nested `aircraft` object,
  /// an ICAO code under `t`/`icao_type`, or a human label such as
  /// `Airbus A320-200`. Normalize all of them to the compact model code the
  /// editor can display and keep editable.
  String? _aircraftType(
    Map<String, dynamic> route,
    Map<String, dynamic> payload,
  ) {
    const keys = [
      'aircraftType',
      'aircraft_type',
      'aircraftTypeCode',
      'aircraft_type_code',
      'icao_type',
      'icaoType',
      'icao_type_code',
      'icaoTypeCode',
      'iata_type',
      'iataType',
      'equipment',
      'aircraft',
      'plane',
      'model',
      't',
      'icao',
      'type',
    ];
    for (final root in [route, payload]) {
      for (final map in _mapNodes(root)) {
        for (final key in keys) {
          final model = _aircraftModel(map[key]);
          if (model != null) return model;
        }
      }
    }
    return null;
  }

  String? _aircraftModel(Object? value) {
    if (value == null) return null;
    if (value is Map || value is List) {
      for (final map in _mapNodes(value)) {
        for (final key in const [
          'aircraftType',
          'aircraft_type',
          'aircraftTypeCode',
          'aircraft_type_code',
          'icao_type',
          'icaoType',
          'icao_type_code',
          'icaoTypeCode',
          'iata_type',
          'iataType',
          'equipment',
          'model',
          'name',
          't',
          'icao',
          'type',
        ]) {
          final model = _aircraftModel(map[key]);
          if (model != null) return model;
        }
      }
      return null;
    }
    final text = value.toString().trim();
    if (text.isEmpty) return null;
    final match = RegExp(
      r'\b((?:A|B|C|E|F|G|Q|ARJ|AT|BAE|CRJ|DHC|DC|ERJ|IL|MD|SU|TU)\d{2,4}(?:[-/][A-Z0-9]{1,6}|[A-Z]{1,4})?|(?:\d{2,3}[A-Z]?|[A-Z]{1,3}\d{1,3}|[0-9][A-Z][0-9]))\b',
      caseSensitive: false,
    ).firstMatch(text);
    if (match == null) return null;
    return _normalizeAircraftCode(match.group(1)!);
  }

  String _normalizeAircraftCode(String value) {
    final code = value.trim().toUpperCase();
    final mapped = _iataAircraftTypes[code];
    if (mapped != null) return mapped;
    return switch (code) {
      'A20N' || 'A320NEO' => 'A320neo',
      'A21N' || 'A321NEO' => 'A321neo',
      'B38M' || '7M8' => 'B737 MAX 8',
      'B39M' || '7M9' => 'B737 MAX 9',
      'A332' => 'A330-200',
      'A333' => 'A330-300',
      'A338' => 'A330-800',
      'A339' => 'A330-900NEO',
      'A359' => 'A350-900',
      'A35K' => 'A350-1000',
      'A388' => 'A380-800',
      'B738' => 'B737-800',
      'B739' => 'B737-900',
      'B77W' => 'B777-300ER',
      'B77L' => 'B777-200LR',
      'B772' => 'B777-200',
      'B773' => 'B777-300',
      'B788' => 'B787-8',
      'B789' => 'B787-9',
      'B78X' => 'B787-10',
      'E290' => 'E190-E2',
      'E295' => 'E195-E2',
      _ => code,
    };
  }

  bool _matchesFlightDate(FlightEnrichment result, DateTime? flightDate) {
    if (flightDate == null) return true;
    final actual = result.departedAt ?? result.arrivedAt;
    if (actual == null) return true;
    final expectedDay = _calendarDay(flightDate);
    final actualDay = _calendarDay(actual);
    final difference = actualDay.difference(expectedDay).inDays.abs();
    // The free route feeds are not consistently timezone-aware. Allow one
    // adjacent day for UTC/local-midnight conversions, but reject a clearly
    // unrelated dated result instead of filling the wrong flight.
    return difference <= 1;
  }

  DateTime _calendarDay(DateTime value) {
    final local = value.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  Object? _findValueByKey(Object? value, List<String> keys) {
    for (final map in _mapNodes(value)) {
      for (final key in keys) {
        final candidate = map[key];
        if (candidate == null) continue;
        if (candidate is String && candidate.trim().isEmpty) continue;
        return candidate;
      }
    }
    return null;
  }

  Map<String, dynamic>? _findRouteMap(Object? value) {
    for (final map in _mapNodes(value)) {
      final hasOrigin = _value(map, const [
        'origin',
        'from',
        'departure',
        'departureAirport',
      ]);
      final hasDestination = _value(map, const [
        'destination',
        'to',
        'arrival',
        'arrivalAirport',
      ]);
      if (hasOrigin != null && hasDestination != null) return map;
    }
    return null;
  }

  Iterable<Map<String, dynamic>> _mapNodes(Object? value) sync* {
    if (value is Map) {
      final map = <String, dynamic>{
        for (final entry in value.entries) entry.key.toString(): entry.value,
      };
      yield map;
      for (final child in map.values) {
        yield* _mapNodes(child);
      }
    } else if (value is List) {
      for (final child in value) {
        yield* _mapNodes(child);
      }
    }
  }

  Map<String, dynamic>? _findMapByKey(Object? value, List<String> keys) {
    for (final map in _mapNodes(value)) {
      for (final key in keys) {
        final child = _asMap(map[key]);
        if (child != null) return child;
      }
    }
    return null;
  }

  Object? _value(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value != null && value.toString().trim().isNotEmpty) return value;
    }
    return null;
  }

  String? _airportCode(Object? value) {
    if (value is Map) {
      final map = <String, dynamic>{
        for (final entry in value.entries) entry.key.toString(): entry.value,
      };
      for (final key in const [
        'iata_code',
        'iataCode',
        'iata',
        'code',
        'airportCode',
      ]) {
        final code = _airportCode(map[key]);
        if (code != null) return code;
      }
      return null;
    }
    if (value is! String) return null;
    final upper = value.trim().toUpperCase();
    final exact = RegExp(r'^[A-Z]{3}$').firstMatch(upper)?.group(0);
    if (exact != null) return exact;
    return RegExp(r'\b([A-Z]{3})\b').firstMatch(upper)?.group(1);
  }

  String? _stringFrom(Object? value, List<String> keys) {
    if (value is String) return value.trim().isEmpty ? null : value.trim();
    final map = _asMap(value);
    if (map == null) return null;
    for (final key in keys) {
      final child = map[key];
      if (child is String && child.trim().isNotEmpty) return child.trim();
    }
    return null;
  }

  int? _durationMinutes(Object? value) {
    if (value is Map || value is List) {
      for (final map in _mapNodes(value)) {
        final nested = _findValueByKey(map, const [
          'durationMinutes',
          'duration_minutes',
          'flightDurationMinutes',
          'flight_duration_minutes',
          'duration',
          'filed_ete',
          'filedEte',
          'ete',
          'air_time',
          'airTime',
        ]);
        if (nested != null && !identical(nested, value)) {
          final parsed = _durationMinutes(nested);
          if (parsed != null) return parsed;
        }
      }
      return null;
    }
    if (value is num && value.isFinite) {
      final numeric = value.toDouble();
      if (numeric <= 0) return null;
      // A few feeds expose elapsed time in seconds. Values above 60 minutes
      // expressed as a whole number of seconds are safe to normalize here.
      return numeric >= 3600 ? (numeric / 60).round() : numeric.round();
    }
    if (value is! String) return null;
    var text = value.trim().toLowerCase();
    if (text.isEmpty) return null;
    final iso = RegExp(r'^p(?:(\d+)d)?t?(?:(\d+)h)?(?:(\d+)m)?$')
        .firstMatch(text.replaceAll(' ', ''));
    if (iso != null && (iso.group(2) != null || iso.group(3) != null)) {
      return (int.tryParse(iso.group(2) ?? '0') ?? 0) * 60 +
          (int.tryParse(iso.group(3) ?? '0') ?? 0) +
          (int.tryParse(iso.group(1) ?? '0') ?? 0) * 1440;
    }
    final clock = RegExp(r'^(\d{1,3}):(\d{2})(?::(\d{2}))?$').firstMatch(text);
    if (clock != null) {
      final hours = int.tryParse(clock.group(1)!) ?? 0;
      final minutes = int.tryParse(clock.group(2)!) ?? 0;
      return hours * 60 + minutes;
    }
    final hours = RegExp(r'(\d+(?:\.\d+)?)\s*h').firstMatch(text);
    final minutes = RegExp(r'(\d+)\s*m').firstMatch(text);
    if (hours != null || minutes != null) {
      final hoursValue = double.tryParse(hours?.group(1) ?? '0') ?? 0;
      return (hoursValue * 60).round() +
          (int.tryParse(minutes?.group(1) ?? '0') ?? 0);
    }
    final numericText = text.replaceAll(',', '');
    final numeric = double.tryParse(numericText);
    if (numeric == null || !numeric.isFinite || numeric <= 0) return null;
    if (text.contains('sec') || text.contains('秒')) {
      return (numeric / 60).round();
    }
    return numeric >= 3600 ? (numeric / 60).round() : numeric.round();
  }

  double? _number(Object? value) {
    if (value is num && value.isFinite) return value.toDouble();
    if (value is! String) return null;
    final normalized = value.trim().replaceAll(',', '');
    final match = RegExp(r'-?\d+(?:\.\d+)?').firstMatch(normalized);
    final number = match == null ? null : double.tryParse(match.group(0)!);
    return number?.isFinite == true ? number : null;
  }

  bool _isTimeOnly(Object? value) {
    if (value is String) {
      return RegExp(r'^\d{1,2}[:：]\d{2}(?::\d{2})?$').hasMatch(value.trim());
    }
    if (value is Map) {
      final map = _asMap(value);
      if (map == null) return false;
      for (final key in const [
        'time',
        'departureTime',
        'departure_time',
        'arrivalTime',
        'arrival_time',
        'value',
      ]) {
        if (_isTimeOnly(map[key])) return true;
      }
    }
    if (value is List) {
      return value.any(_isTimeOnly);
    }
    return false;
  }

  DateTime _sameDateWithTime(DateTime date, DateTime time) {
    final dateLocal = date.toLocal();
    final timeLocal = time.toLocal();
    return DateTime(
      dateLocal.year,
      dateLocal.month,
      dateLocal.day,
      timeLocal.hour,
      timeLocal.minute,
      timeLocal.second,
    );
  }

  DateTime? _dateTime(Object? value, {DateTime? fallbackDate}) {
    if (value is DateTime) return value;
    if (value is num && value.isFinite) {
      final numeric = value.toDouble();
      if (numeric <= 0) return null;
      final milliseconds = numeric >= 100000000000
          ? numeric.round()
          : (numeric * 1000).round();
      if (milliseconds > 8640000000000000) return null;
      return DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
    }
    if (value is Map) {
      final nested = _findValueByKey(value, const [
        'timestamp',
        'datetime',
        'dateTime',
        'time',
        'value',
      ]);
      return nested == null
          ? null
          : _dateTime(nested, fallbackDate: fallbackDate);
    }
    if (value is String) {
      final text = value.trim();
      final numeric = double.tryParse(text);
      if (numeric != null) return _dateTime(numeric);
      final time = RegExp(r'^(\d{1,2})[:：](\d{2})(?::(\d{2}))?$')
          .firstMatch(text);
      if (time != null && fallbackDate != null) {
        final hour = int.tryParse(time.group(1)!) ?? -1;
        final minute = int.tryParse(time.group(2)!) ?? -1;
        final second = int.tryParse(time.group(3) ?? '0') ?? -1;
        if (hour >= 0 &&
            hour <= 23 &&
            minute >= 0 &&
            minute <= 59 &&
            second >= 0 &&
            second <= 59) {
          final local = fallbackDate.toLocal();
          return DateTime(
            local.year,
            local.month,
            local.day,
            hour,
            minute,
            second,
          );
        }
      }
      return DateTime.tryParse(text);
    }
    return null;
  }

  String _clean(String value) =>
      value.trim().toUpperCase().replaceAll(RegExp(r'[\s-]+'), '');

  Map<String, dynamic>? _asMap(Object? value) {
    if (value is! Map) return null;
    return <String, dynamic>{
      for (final entry in value.entries) entry.key.toString(): entry.value,
    };
  }
}

class _ObservedAircraft {
  const _ObservedAircraft({
    required this.type,
    required this.registration,
    required this.hex,
    required this.observedAt,
    required this.source,
  });

  final String? type;
  final String? registration;
  final String? hex;
  final DateTime observedAt;
  final String source;
}
