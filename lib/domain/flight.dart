enum FlightStatus { upcoming, completed }

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
