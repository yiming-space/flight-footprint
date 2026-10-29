import 'flight.dart';

enum TransferDecisionStatus { confirmed, rejected }

class TransferDecisionConflictException implements Exception {
  const TransferDecisionConflictException();
}

class StaleTransferDecisionException implements Exception {
  const StaleTransferDecisionException();
}

/// A user's explicit decision about two flights forming a transfer.
///
/// The route and time snapshot is stored with the decision so edits to either
/// flight make it stale instead of silently carrying the choice forward.
class TransferDecision {
  const TransferDecision({
    required this.inboundFlightId,
    required this.outboundFlightId,
    required this.airportIata,
    required this.inboundDepartureIata,
    required this.inboundArrivalIata,
    required this.outboundDepartureIata,
    required this.outboundArrivalIata,
    required this.inboundDepartedAt,
    required this.inboundArrivedAt,
    required this.outboundDepartedAt,
    required this.outboundArrivedAt,
    required this.status,
    required this.decidedAt,
  });

  final String inboundFlightId;
  final String outboundFlightId;
  final String airportIata;
  final String inboundDepartureIata;
  final String inboundArrivalIata;
  final String outboundDepartureIata;
  final String outboundArrivalIata;
  final DateTime inboundDepartedAt;
  final DateTime? inboundArrivedAt;
  final DateTime outboundDepartedAt;
  final DateTime? outboundArrivedAt;
  final TransferDecisionStatus status;
  final DateTime decidedAt;

  String get id => '$inboundFlightId|$outboundFlightId|$airportIata';

  bool matchesFlights(Flight inbound, Flight outbound) =>
      inbound.id == inboundFlightId &&
      outbound.id == outboundFlightId &&
      airportIata == inboundArrivalIata &&
      airportIata == outboundDepartureIata &&
      _same(inbound.departureIata, inboundDepartureIata) &&
      _same(inbound.arrivalIata, inboundArrivalIata) &&
      _same(outbound.departureIata, outboundDepartureIata) &&
      _same(outbound.arrivalIata, outboundArrivalIata) &&
      _sameDate(inbound.departedAt, inboundDepartedAt) &&
      _sameNullableDate(inbound.arrivedAt, inboundArrivedAt) &&
      _sameDate(outbound.departedAt, outboundDepartedAt) &&
      _sameNullableDate(outbound.arrivedAt, outboundArrivedAt);

  factory TransferDecision.fromFlights({
    required Flight inbound,
    required Flight outbound,
    required TransferDecisionStatus status,
    DateTime? decidedAt,
  }) => TransferDecision(
    inboundFlightId: inbound.id,
    outboundFlightId: outbound.id,
    airportIata: inbound.arrivalIata.trim().toUpperCase(),
    inboundDepartureIata: inbound.departureIata.trim().toUpperCase(),
    inboundArrivalIata: inbound.arrivalIata.trim().toUpperCase(),
    outboundDepartureIata: outbound.departureIata.trim().toUpperCase(),
    outboundArrivalIata: outbound.arrivalIata.trim().toUpperCase(),
    inboundDepartedAt: inbound.departedAt.toUtc(),
    inboundArrivedAt: inbound.arrivedAt?.toUtc(),
    outboundDepartedAt: outbound.departedAt.toUtc(),
    outboundArrivedAt: outbound.arrivedAt?.toUtc(),
    status: status,
    decidedAt: (decidedAt ?? DateTime.now()).toUtc(),
  );

  Map<String, Object?> toJson() => {
    'inboundFlightId': inboundFlightId,
    'outboundFlightId': outboundFlightId,
    'airportIata': airportIata,
    'inboundDepartureIata': inboundDepartureIata,
    'inboundArrivalIata': inboundArrivalIata,
    'outboundDepartureIata': outboundDepartureIata,
    'outboundArrivalIata': outboundArrivalIata,
    'inboundDepartedAt': inboundDepartedAt.toUtc().toIso8601String(),
    'inboundArrivedAt': inboundArrivedAt?.toUtc().toIso8601String(),
    'outboundDepartedAt': outboundDepartedAt.toUtc().toIso8601String(),
    'outboundArrivedAt': outboundArrivedAt?.toUtc().toIso8601String(),
    'status': status.name,
    'decidedAt': decidedAt.toUtc().toIso8601String(),
  };

  factory TransferDecision.fromJson(Map<String, dynamic> json) {
    String text(String key) {
      final value = json[key];
      if (value is! String || value.trim().isEmpty) {
        throw FormatException('Transfer decision requires $key.');
      }
      return value.trim();
    }

    DateTime date(String key) {
      final value = json[key];
      if (value is! String) {
        throw FormatException('Transfer decision requires $key.');
      }
      final parsed = DateTime.tryParse(value);
      if (parsed == null) {
        throw FormatException('Invalid transfer decision date: $key.');
      }
      return parsed.toUtc();
    }

    final status = json['status'];
    if (status != 'confirmed' && status != 'rejected') {
      throw const FormatException('Invalid transfer decision status.');
    }
    return TransferDecision(
      inboundFlightId: text('inboundFlightId'),
      outboundFlightId: text('outboundFlightId'),
      airportIata: text('airportIata').toUpperCase(),
      inboundDepartureIata: text('inboundDepartureIata').toUpperCase(),
      inboundArrivalIata: text('inboundArrivalIata').toUpperCase(),
      outboundDepartureIata: text('outboundDepartureIata').toUpperCase(),
      outboundArrivalIata: text('outboundArrivalIata').toUpperCase(),
      inboundDepartedAt: date('inboundDepartedAt'),
      inboundArrivedAt: json['inboundArrivedAt'] == null
          ? null
          : date('inboundArrivedAt'),
      outboundDepartedAt: date('outboundDepartedAt'),
      outboundArrivedAt: json['outboundArrivedAt'] == null
          ? null
          : date('outboundArrivedAt'),
      status: TransferDecisionStatus.values.byName(status as String),
      decidedAt: date('decidedAt'),
    );
  }

  static bool _same(String a, String b) =>
      a.trim().toUpperCase() == b.trim().toUpperCase();
  static bool _sameDate(DateTime a, DateTime b) =>
      a.toUtc().isAtSameMomentAs(b.toUtc());
  static bool _sameNullableDate(DateTime? a, DateTime? b) =>
      a == null ? b == null : b != null && _sameDate(a, b);
}
