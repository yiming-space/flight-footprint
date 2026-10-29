enum FlightStatus { upcoming, completed }

/// Automatically completes a flight only once its reliable arrival is due.
/// DateTime comparisons use absolute instants, including UTC/local mixtures
/// and overnight flights. Without an end time, the flight stays upcoming.
FlightStatus flightStatusForDeparture(
  DateTime departedAt,
  DateTime now, {
  DateTime? arrivedAt,
  int? durationMinutes,
}) {
  final transition = flightStatusTransitionAt(
    departedAt,
    arrivedAt: arrivedAt,
    durationMinutes: durationMinutes,
  );
  return transition != null && !now.isBefore(transition)
      ? FlightStatus.completed
      : FlightStatus.upcoming;
}

/// Prefer the recorded arrival. A missing arrival can use a positive duration
/// within the same 48-hour range accepted by itinerary imports.
DateTime? flightStatusTransitionAt(
  DateTime departedAt, {
  DateTime? arrivedAt,
  int? durationMinutes,
}) {
  if (arrivedAt != null) {
    return arrivedAt.isAfter(departedAt) ? arrivedAt : null;
  }
  if (durationMinutes == null ||
      durationMinutes <= 0 ||
      durationMinutes > 48 * 60) {
    return null;
  }
  return departedAt.add(Duration(minutes: durationMinutes));
}

FlightStatus flightStatusFromStorage(Object? value) =>
    value?.toString().toLowerCase() == 'upcoming'
    ? FlightStatus.upcoming
    : FlightStatus.completed;

String flightStatusToStorage(FlightStatus value) => value.name;

class Flight {
  const Flight({
    required this.id,
    required this.departureIata,
    required this.arrivalIata,
    required this.departedAt,
    this.arrivedAt,
    required this.createdAt,
    required this.updatedAt,
    this.status = FlightStatus.completed,
    this.airline,
    this.flightNumber,
    this.cabinClass,
    this.aircraftType,
    this.durationMinutes,
    this.seat,
    this.note,
    this.distanceKm,
    this.track = const [],
    this.isTransitArrival = false,
    this.hasTransitArrivalAnnotation = true,
  });

  final String id;
  final String departureIata;
  final String arrivalIata;
  final DateTime departedAt;
  final DateTime? arrivedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final FlightStatus status;
  final String? airline;
  final String? flightNumber;
  final String? cabinClass;
  final String? aircraftType;
  final int? durationMinutes;
  final String? seat;
  final String? note;
  final double? distanceKm;
  final List<FlightTrackPoint> track;

  /// Explicit user annotation; never inferred from route/time patterns.
  final bool isTransitArrival;

  /// False only when a legacy interchange format omitted the field entirely.
  final bool hasTransitArrivalAnnotation;

  Flight copyWith({
    String? departureIata,
    String? arrivalIata,
    DateTime? departedAt,
    DateTime? arrivedAt,
    String? airline,
    String? flightNumber,
    String? cabinClass,
    String? aircraftType,
    int? durationMinutes,
    String? seat,
    String? note,
    double? distanceKm,
    List<FlightTrackPoint>? track,
    DateTime? updatedAt,
    FlightStatus? status,
    bool? isTransitArrival,
    bool? hasTransitArrivalAnnotation,
  }) => Flight(
    id: id,
    departureIata: departureIata ?? this.departureIata,
    arrivalIata: arrivalIata ?? this.arrivalIata,
    departedAt: departedAt ?? this.departedAt,
    arrivedAt: arrivedAt ?? this.arrivedAt,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    status: status ?? this.status,
    airline: airline ?? this.airline,
    flightNumber: flightNumber ?? this.flightNumber,
    cabinClass: cabinClass ?? this.cabinClass,
    aircraftType: aircraftType ?? this.aircraftType,
    durationMinutes: durationMinutes ?? this.durationMinutes,
    seat: seat ?? this.seat,
    note: note ?? this.note,
    distanceKm: distanceKm ?? this.distanceKm,
    track: track ?? this.track,
    isTransitArrival: isTransitArrival ?? this.isTransitArrival,
    hasTransitArrivalAnnotation:
        hasTransitArrivalAnnotation ?? this.hasTransitArrivalAnnotation,
  );

  /// Merge an imported annotation without treating a missing legacy field as
  /// an instruction to clear the locally confirmed value.
  Flight withImportedTransitAnnotation({bool? existingValue}) => copyWith(
    isTransitArrival: hasTransitArrivalAnnotation
        ? isTransitArrival
        : existingValue ?? isTransitArrival,
  );

  /// Completed records stay completed; upcoming records automatically mature
  /// at their recorded or duration-derived arrival.
  FlightStatus effectiveStatusAt(DateTime now) =>
      status == FlightStatus.completed
      ? FlightStatus.completed
      : flightStatusForDeparture(
          departedAt,
          now,
          arrivedAt: arrivedAt,
          durationMinutes: durationMinutes,
        );

  bool get isUpcoming => status == FlightStatus.upcoming;
  bool get isCompleted => status == FlightStatus.completed;
}

/// A sampled aircraft position from the web app's live-flight recorder.
/// Coordinates are kept as numbers so the portable backup stays lossless and
/// can be rendered offline without a network map SDK.
class FlightTrackPoint {
  const FlightTrackPoint({
    required this.recordedAt,
    required this.latitude,
    required this.longitude,
    this.altitudeFt,
    this.groundSpeedKt,
    this.heading,
    this.onGround = false,
    this.source = '',
  });

  final int recordedAt;
  final double latitude;
  final double longitude;
  final int? altitudeFt;
  final int? groundSpeedKt;
  final int? heading;
  final bool onGround;
  final String source;
}
