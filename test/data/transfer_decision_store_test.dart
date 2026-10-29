import 'dart:convert';

import 'package:flight_footprint/data/backup_codec.dart';
import 'package:flight_footprint/data/transfer_decision_store.dart';
import 'package:flight_footprint/domain/flight.dart';
import 'package:flight_footprint/domain/transfer_decision.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final inbound = _flight(
    id: 'in',
    departureIata: 'PVG',
    arrivalIata: 'PEK',
    departedAt: DateTime.utc(2026, 10, 1, 2),
    arrivedAt: DateTime.utc(2026, 10, 1, 5),
  );
  final outbound = _flight(
    id: 'out',
    departureIata: 'PEK',
    arrivalIata: 'HND',
    departedAt: DateTime.utc(2026, 10, 1, 8),
    arrivedAt: DateTime.utc(2026, 10, 1, 12),
  );
  final decision = TransferDecision.fromFlights(
    inbound: inbound,
    outbound: outbound,
    status: TransferDecisionStatus.rejected,
    decidedAt: DateTime.utc(2026, 9, 1),
  );

  test('manual decisions persist and match only the unchanged flight pair', () {
    final restored = TransferDecisionStore.decode(
      TransferDecisionStore.encode([decision]),
    );
    expect(
      TransferDecisionStore.findActive(restored, inbound, outbound)?.status,
      TransferDecisionStatus.rejected,
    );
    expect(
      TransferDecisionStore.findActive(
        restored,
        inbound,
        outbound.copyWith(departedAt: DateTime.utc(2026, 10, 1, 9)),
      ),
      isNull,
    );
    expect(
      TransferDecisionStore.findActive(
        restored,
        inbound.copyWith(arrivalIata: 'SHA'),
        outbound,
      ),
      isNull,
    );
  });

  test('missing legacy metadata means no decisions', () {
    expect(TransferDecisionStore.decode(null), isEmpty);
    expect(TransferDecisionStore.decode(''), isEmpty);
  });

  test(
    'backup round trip carries decisions and legacy backup remains absent',
    () {
      final encoded = BackupCodec.encode(
        BackupData(
          flights: [inbound, outbound],
          visitedPlaces: const [],
          transferDecisions: [decision],
          containsTransferDecisions: true,
        ),
      );
      final decoded = BackupCodec.decode(encoded);
      expect(decoded.containsTransferDecisions, isTrue);
      expect(
        decoded.transferDecisions.single.status,
        TransferDecisionStatus.rejected,
      );
      final legacy = BackupCodec.decode(
        jsonEncode({
          'format': BackupCodec.format,
          'version': BackupCodec.version,
          'flights': [],
          'visitedPlaces': [],
        }),
      );
      expect(legacy.containsTransferDecisions, isFalse);
      expect(legacy.transferDecisions, isEmpty);
    },
  );
}

Flight _flight({
  required String id,
  required String departureIata,
  required String arrivalIata,
  required DateTime departedAt,
  DateTime? arrivedAt,
}) => Flight(
  id: id,
  departureIata: departureIata,
  arrivalIata: arrivalIata,
  departedAt: departedAt,
  arrivedAt: arrivedAt,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
);
