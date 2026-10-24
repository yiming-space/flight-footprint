import 'package:timezone/data/latest_all.dart' as timezone_data;
import 'package:timezone/timezone.dart' as tz;

/// Why an airport-local wall time could not be converted to one UTC instant.
enum AirportWallTimeStatus { resolved, unknownTimeZone, nonexistent, ambiguous }

class AirportWallTimeResolution {
  const AirportWallTimeResolution(this.status, {this.instant});

  final AirportWallTimeStatus status;
  final DateTime? instant;

  bool get isResolved => status == AirportWallTimeStatus.resolved;
}

/// Converts airport-local clock readings to stored absolute instants.
///
/// A [DateTime] passed to [resolveWallTime] is treated as a container for wall
/// clock components; its device-local offset is deliberately ignored. Returned
/// values are UTC. Fall-back overlaps and spring-forward gaps are reported so
/// callers can ask for corrected input instead of silently choosing an offset.
class FlightTimeResolver {
  FlightTimeResolver._();

  static bool _initialized = false;

  static AirportWallTimeResolution resolveWallTime(
    DateTime wallTime,
    String? timeZoneId,
  ) {
    final zoneId = timeZoneId?.trim() ?? '';
    if (zoneId.isEmpty) {
      return const AirportWallTimeResolution(
        AirportWallTimeStatus.unknownTimeZone,
      );
    }
    final location = _location(zoneId);
    if (location == null) {
      return const AirportWallTimeResolution(
        AirportWallTimeStatus.unknownTimeZone,
      );
    }

    final wallUtc = DateTime.utc(
      wallTime.year,
      wallTime.month,
      wallTime.day,
      wallTime.hour,
      wallTime.minute,
      wallTime.second,
      wallTime.millisecond,
      wallTime.microsecond,
    );
    final wallMillis = wallUtc.millisecondsSinceEpoch;
    final offsets = <int>{};
    // Sampling a broad interval finds both offsets in a DST fold and also
    // handles non-hour and date-line shifts without assuming a fixed offset.
    for (var hours = -48; hours <= 48; hours += 3) {
      final sample = DateTime.fromMillisecondsSinceEpoch(
        wallMillis + hours * Duration.millisecondsPerHour,
        isUtc: true,
      );
      offsets.add(
        tz.TZDateTime.from(sample, location).timeZoneOffset.inMilliseconds,
      );
    }

    final matches = <DateTime>{};
    for (final offset in offsets) {
      final candidate = DateTime.fromMicrosecondsSinceEpoch(
        wallUtc.microsecondsSinceEpoch -
            offset * Duration.microsecondsPerMillisecond,
        isUtc: true,
      );
      final projected = tz.TZDateTime.from(candidate, location);
      if (_sameWallComponents(projected, wallUtc)) matches.add(candidate);
    }
    if (matches.length == 1) {
      return AirportWallTimeResolution(
        AirportWallTimeStatus.resolved,
        instant: matches.single,
      );
    }
    return AirportWallTimeResolution(
      matches.isEmpty
          ? AirportWallTimeStatus.nonexistent
          : AirportWallTimeStatus.ambiguous,
    );
  }

  /// Projects an absolute instant to an airport-local wall-clock container.
  /// The returned UTC DateTime preserves the airport's displayed components
  /// without allowing the device timezone to change them.
  static DateTime? toWallTime(DateTime instant, String? timeZoneId) {
    final zoneId = timeZoneId?.trim() ?? '';
    if (zoneId.isEmpty) return null;
    final location = _location(zoneId);
    if (location == null) return null;
    final local = tz.TZDateTime.from(instant.toUtc(), location);
    return DateTime.utc(
      local.year,
      local.month,
      local.day,
      local.hour,
      local.minute,
      local.second,
      local.millisecond,
      local.microsecond,
    );
  }

  /// Returns the airport-local calendar year, using the legacy device-local
  /// year only when no valid airport zone exists.
  static int calendarYearAtAirport(DateTime instant, String? timeZoneId) =>
      toWallTime(instant, timeZoneId)?.year ?? instant.toLocal().year;

  static tz.Location? _location(String zoneId) {
    try {
      if (!_initialized) {
        timezone_data.initializeTimeZones();
        _initialized = true;
      }
      return tz.getLocation(zoneId);
    } on Object {
      return null;
    }
  }

  static bool _sameWallComponents(DateTime left, DateTime right) =>
      left.year == right.year &&
      left.month == right.month &&
      left.day == right.day &&
      left.hour == right.hour &&
      left.minute == right.minute &&
      left.second == right.second &&
      left.millisecond == right.millisecond &&
      left.microsecond == right.microsecond;
}
