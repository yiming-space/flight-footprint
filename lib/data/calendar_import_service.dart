import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../domain/airport.dart';
import '../domain/flight.dart';
import 'airport_catalog.dart';
import 'airline_catalog.dart';

/// The result of one explicit system-calendar scan.
enum CalendarScanStatus { available, unsupported, permissionDenied, failed }

class CalendarImportResult {
  const CalendarImportResult({
    required this.status,
    required this.eventsRead,
    required this.flights,
    this.errorCode,
  });

  const CalendarImportResult.unsupported()
    : status = CalendarScanStatus.unsupported,
      eventsRead = 0,
      flights = const [],
      errorCode = null;

  final CalendarScanStatus status;
  final int eventsRead;
  final List<CalendarFlightDraft> flights;
  final String? errorCode;

  bool get isAvailable => status == CalendarScanStatus.available;
}

/// A flight candidate parsed from a calendar event, before the user confirms
/// which candidates should be imported.
class CalendarFlightDraft {
  const CalendarFlightDraft({
    required this.eventId,
    required this.title,
    required this.departureText,
    required this.arrivalText,
    required this.departureAirport,
    required this.arrivalAirport,
    required this.airline,
    required this.flightNumber,
    required this.departedAt,
    required this.arrivedAt,
    required this.status,
    required this.distanceKm,
    required this.durationMinutes,
  });

  final String eventId;
  final String title;
  final String departureText;
  final String arrivalText;
  final Airport departureAirport;
  final Airport arrivalAirport;
  final String airline;
  final String flightNumber;
  final DateTime departedAt;
  final DateTime arrivedAt;
  final FlightStatus status;
  final double distanceKm;
  final int durationMinutes;

  String get departureIata => departureAirport.iataCode;
  String get arrivalIata => arrivalAirport.iataCode;

  /// Uses a deterministic id so importing the same calendar event again does
  /// not create another row. Repository identity matching still protects the
  /// import when a provider changes an event id.
  Flight toFlight({DateTime? now}) {
    final timestamp = (now ?? DateTime.now()).toUtc();
    final stableKey = eventId.trim().isEmpty
        ? '${departedAt.toIso8601String()}|$flightNumber|$departureIata|$arrivalIata'
        : eventId.trim();
    return Flight(
      id: const Uuid().v5(Namespace.url.value, 'calendar-v1|$stableKey'),
      departureIata: departureIata,
      arrivalIata: arrivalIata,
      departedAt: departedAt.toUtc(),
      arrivedAt: arrivedAt.toUtc(),
      createdAt: timestamp,
      updatedAt: timestamp,
      status: status,
      airline: airline,
      flightNumber: flightNumber,
      durationMinutes: durationMinutes,
      distanceKm: distanceKm,
    );
  }
}

/// Reads raw calendar events through the tiny Android channel and turns the
/// flight-like ones into local candidates. Parsing is deliberately offline so
/// the calendar contents never leave the device.
class CalendarImportService {
  CalendarImportService({
    required this.airports,
    MethodChannel? channel,
    DateTime Function()? clock,
  }) : _channel = channel ?? _defaultChannel,
       _clock = clock ?? DateTime.now;

  static const channelName = 'flight_footprint/calendar';
  static const _defaultChannel = MethodChannel(channelName);

  static final _flightPattern = RegExp(
    // IATA prefixes are normally two letters, but regional carriers also
    // use letter-number forms such as G5/9H. Keep the three-letter branch so
    // calendars that expose an ICAO callsign (for example SIA328) work too.
    r'(?<![A-Za-z0-9])((?:[A-Za-z]{2,3}|[0-9][A-Za-z]|[A-Za-z][0-9]))\s*[- ]?\s*(\d{1,4}[A-Za-z]?)(?![A-Za-z0-9])',
    caseSensitive: false,
  );
  static final _standaloneFlightNumberPattern = RegExp(
    r'(?<![A-Za-z0-9])(\d{1,4}[A-Za-z]?)(?![A-Za-z0-9])',
  );
  static final _clockPairPattern = RegExp(
    r'(\d{1,2})\s*[:：]\s*(\d{2})\s*(?:-|–|—|－|~|～|至|到)\s*(\d{1,2})\s*[:：]\s*(\d{2})',
  );
  static final _routeSeparatorPattern = RegExp(
    r'\s*(?:->|→|⟶|—|–|－|\-|至|到)\s*',
  );

  final AirportCatalog airports;
  final MethodChannel _channel;
  final DateTime Function() _clock;

  Future<CalendarImportResult> scan({DateTime? start, DateTime? end}) async {
    final now = _clock();
    final from = (start ?? DateTime(now.year - 10, 1, 1)).toUtc();
    final until = (end ?? DateTime(now.year + 3, 12, 31, 23, 59, 59)).toUtc();
    try {
      final response = await _channel.invokeMethod<List<dynamic>>(
        'queryEvents',
        <String, Object>{
          'startMillis': from.millisecondsSinceEpoch,
          'endMillis': until.millisecondsSinceEpoch,
        },
      );
      final rawEvents = response ?? const <dynamic>[];
      final flights = <CalendarFlightDraft>[];
      final seenEventIds = <String>{};
      final seenFlightKeys = <String>{};
      for (final raw in rawEvents) {
        if (raw is! Map) continue;
        final event = <String, dynamic>{
          for (final entry in raw.entries)
            if (entry.key != null) entry.key.toString(): entry.value,
        };
        final draft = parseEvent(event, now: now);
        if (draft == null) continue;
        final eventId = draft.eventId.trim();
        final flightKey = _flightIdentityKey(draft);
        if (eventId.isNotEmpty && !seenEventIds.add(eventId)) continue;
        if (!seenFlightKeys.add(flightKey)) continue;
        flights.add(draft);
      }
      flights.sort(
        (left, right) => left.departedAt.compareTo(right.departedAt),
      );
      return CalendarImportResult(
        status: CalendarScanStatus.available,
        eventsRead: rawEvents.length,
        flights: List.unmodifiable(flights),
      );
    } on PlatformException catch (error) {
      final status = switch (error.code) {
        'calendar_permission_denied' => CalendarScanStatus.permissionDenied,
        'calendar_request_in_progress' => CalendarScanStatus.failed,
        _ => CalendarScanStatus.failed,
      };
      return CalendarImportResult(
        status: status,
        eventsRead: 0,
        flights: const [],
        errorCode: error.code,
      );
    } on MissingPluginException {
      return const CalendarImportResult.unsupported();
    } on Object {
      return const CalendarImportResult(
        status: CalendarScanStatus.failed,
        eventsRead: 0,
        flights: [],
        errorCode: 'calendar_query_failed',
      );
    }
  }

  /// Public for deterministic unit tests and for future provider adapters.
  CalendarFlightDraft? parseEvent(Map<String, dynamic> event, {DateTime? now}) {
    final title = _string(event['title']);
    final description = _string(event['description']);
    final location = _string(event['location']);
    final text = _normalizeText([title, location, description]);
    if (text.isEmpty) return null;

    final flightMatch = _flightPattern.firstMatch(text);
    final namedFlight = flightMatch == null ? _namedFlight(text) : null;
    if (flightMatch == null && namedFlight == null) return null;
    final prefix = flightMatch != null
        ? flightMatch.group(1)!.toUpperCase()
        : namedFlight!.prefix;
    final number = flightMatch != null
        ? flightMatch.group(2)!.toUpperCase()
        : namedFlight!.number;
    final flightNumber = '$prefix$number';
    final flightEnd = flightMatch?.end ?? namedFlight!.end;
    final afterFlight = text.substring(flightEnd).trim();
    final clockPair = _clockPairPattern.firstMatch(afterFlight);
    final timeMarker = RegExp(
      r'当地时间|本地时间|local\s*time|local',
      caseSensitive: false,
    ).firstMatch(afterFlight);
    final routeText = _routeText(
      afterFlight,
      clockPair: clockPair,
      marker: timeMarker,
    );
    final route = _splitRoute(routeText) ?? _splitRoute(location);
    if (route == null) return null;
    final departureAirport = _resolveAirport(route.$1);
    final arrivalAirport = _resolveAirport(route.$2);
    if (departureAirport == null || arrivalAirport == null) return null;

    final eventStart = _dateFromEpoch(event['startMillis']);
    final eventEnd = _dateFromEpoch(event['endMillis']);
    final times = _resolveTimes(
      eventStart: eventStart,
      eventEnd: eventEnd,
      pair: clockPair,
      now: now ?? _clock(),
    );
    if (times == null) return null;
    final duration = times.$2.difference(times.$1).inMinutes;
    if (duration <= 0 || duration > 48 * 60) return null;

    final airportDistance = AirportCatalog.greatCircleDistanceKm(
      departureAirport,
      arrivalAirport,
    );
    return CalendarFlightDraft(
      eventId: _string(event['id']),
      title: title.isEmpty ? text : title,
      departureText: route.$1,
      arrivalText: route.$2,
      departureAirport: departureAirport,
      arrivalAirport: arrivalAirport,
      airline: _airlineName(prefix, text),
      flightNumber: flightNumber,
      departedAt: times.$1,
      arrivedAt: times.$2,
      status: _statusForDate(times.$1, now ?? _clock()),
      distanceKm: airportDistance,
      durationMinutes: duration,
    );
  }

  String _routeText(
    String afterFlight, {
    required RegExpMatch? clockPair,
    required RegExpMatch? marker,
  }) {
    var end = afterFlight.length;
    if (marker != null && marker.start < end) end = marker.start;
    if (clockPair != null && clockPair.start < end) end = clockPair.start;
    var value = afterFlight.substring(0, end).trim();
    value = value
        .replaceAll(RegExp(r'【[^】]*】|\[[^\]]*\]'), '')
        .replaceFirst(RegExp(r'^[：:，,、\s]+'), '')
        .trim();
    return value;
  }

  (String, String)? _splitRoute(String raw) {
    var value = _normalizeText([raw]);
    value = value.replaceAll(RegExp(r'【[^】]*】|\[[^\]]*\]'), '').trim();
    if (value.isEmpty) return null;
    final parts = value.split(_routeSeparatorPattern);
    if (parts.length < 2) return null;
    final departure = parts.first.trim();
    final arrival = parts.sublist(1).join('-').trim();
    if (departure.isEmpty || arrival.isEmpty) return null;
    return (departure, arrival);
  }

  (DateTime, DateTime)? _resolveTimes({
    required DateTime? eventStart,
    required DateTime? eventEnd,
    required RegExpMatch? pair,
    required DateTime now,
  }) {
    if (pair == null) {
      if (eventStart == null ||
          eventEnd == null ||
          !eventEnd.isAfter(eventStart)) {
        return null;
      }
      return (eventStart.toLocal(), eventEnd.toLocal());
    }
    final departureHour = int.tryParse(pair.group(1) ?? '');
    final departureMinute = int.tryParse(pair.group(2) ?? '');
    final arrivalHour = int.tryParse(pair.group(3) ?? '');
    final arrivalMinute = int.tryParse(pair.group(4) ?? '');
    if (departureHour == null ||
        departureMinute == null ||
        arrivalHour == null ||
        arrivalMinute == null ||
        departureHour > 23 ||
        arrivalHour > 23 ||
        departureMinute > 59 ||
        arrivalMinute > 59) {
      return null;
    }
    final base = (eventStart ?? now).toLocal();
    final departed = DateTime(
      base.year,
      base.month,
      base.day,
      departureHour,
      departureMinute,
    );
    var arrived = DateTime(
      base.year,
      base.month,
      base.day,
      arrivalHour,
      arrivalMinute,
    );
    if (!arrived.isAfter(departed)) {
      arrived = arrived.add(const Duration(days: 1));
    }

    // Prefer the provider's date when it agrees with the title's clock pair.
    // This handles a calendar event that already stores the next-day arrival,
    // while still correcting providers that make both ends share one date.
    if (eventEnd != null) {
      final providerEnd = eventEnd.toLocal();
      final candidate = DateTime(
        providerEnd.year,
        providerEnd.month,
        providerEnd.day,
        arrivalHour,
        arrivalMinute,
      );
      final difference = candidate.difference(departed);
      if (difference > Duration.zero && difference <= const Duration(days: 2)) {
        arrived = candidate;
      }
    }
    return (departed, arrived);
  }

  Airport? _resolveAirport(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    final codes = RegExp(r'(?<![A-Za-z])([A-Za-z]{3})(?![A-Za-z])')
        .allMatches(value)
        .map((match) => match.group(1)!.toUpperCase());
    for (final code in codes) {
      final airport = airports.findByIata(code);
      if (airport != null) return airport;
    }

    final compact = value
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll(
          RegExp(r'(?:T|Terminal|航站楼|航站樓)\d{1,2}$', caseSensitive: false),
          '',
        )
        .trim();
    final queries = <String>{
      value,
      compact,
      compact.replaceAll(RegExp(r'国际机场|國際機場|机场|機場'), ''),
      compact.replaceAll(RegExp(r'市$|區$|区$|县$|縣$'), ''),
    }..removeWhere((item) => item.trim().isEmpty);
    final candidates = <Airport>[];
    final seen = <String>{};
    for (final query in queries) {
      for (final airport in airports.search(query, limit: 12)) {
        if (seen.add(airport.iataCode)) candidates.add(airport);
      }
      if (candidates.isNotEmpty) break;
    }
    return candidates.isEmpty ? null : candidates.first;
  }

  static ({String prefix, String number, int end})? _namedFlight(String text) {
    for (final match in _standaloneFlightNumberPattern.allMatches(text)) {
      final prefix = airlineIataFromText(
        text.substring(match.start > 56 ? match.start - 56 : 0, match.start),
      );
      if (prefix == null) continue;
      return (
        prefix: prefix,
        number: match.group(1)!.toUpperCase(),
        end: match.end,
      );
    }
    return null;
  }

  static String _airlineName(String prefix, String text) {
    final explicit = RegExp(
      // Match the English label as a whole word. Without the plural form,
      // `Airlines` would be read as `airline` with a stray `s` as the carrier
      // name and would override the canonical prefix resolution.
      r'(?:航空公司|航司|airlines?|carrier)(?![A-Za-z])\s*[:：]?\s*([\u3400-\u9fffA-Za-z][\u3400-\u9fffA-Za-z ]{1,29})',
      caseSensitive: false,
    ).firstMatch(text)?.group(1)?.trim();
    if (explicit != null && explicit.isNotEmpty) {
      // Calendar providers differ in whether they localize the carrier
      // name. Normalize a recognized English/ICAO value to the same Chinese
      // label used by manual records, but preserve an unknown explicit name.
      final known = resolveAirlineName('', text: explicit);
      if (known.isNotEmpty) return known;
      return explicit;
    }
    return resolveAirlineName(prefix, text: text);
  }

  static DateTime? _dateFromEpoch(Object? value) {
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt()).toLocal();
    }
    if (value is String) {
      final millis = int.tryParse(value);
      if (millis != null) {
        return DateTime.fromMillisecondsSinceEpoch(millis).toLocal();
      }
    }
    return null;
  }

  static FlightStatus _statusForDate(DateTime date, DateTime now) {
    final flightDay = DateTime(date.year, date.month, date.day);
    final today = DateTime(now.year, now.month, now.day);
    return flightDay.isAfter(today)
        ? FlightStatus.upcoming
        : FlightStatus.completed;
  }

  static String _flightIdentityKey(CalendarFlightDraft draft) {
    final date = draft.departedAt.toLocal();
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}|${draft.flightNumber}';
  }

  static String _string(Object? value) => value?.toString().trim() ?? '';

  static String _normalizeText(Iterable<String> values) => values
      .map(
        (value) => value
            .replaceAll('\u00a0', ' ')
            .replaceAll(RegExp(r'[‐‑‒–—―－]'), '-')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim(),
      )
      .where((value) => value.isNotEmpty)
      .join(' ')
      .trim();
}
