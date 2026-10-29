import 'dart:convert';

import '../domain/flight.dart';
import '../domain/transfer_decision.dart';

/// Codec and lookup helpers for user-authored transfer decisions.
/// Missing metadata from older installs is treated as an empty collection.
class TransferDecisionStore {
  const TransferDecisionStore._();

  static List<TransferDecision> decode(String? source) {
    if (source == null || source.trim().isEmpty) return const [];
    final dynamic value;
    try {
      value = jsonDecode(source);
    } on FormatException catch (error) {
      throw FormatException(
        'Transfer decisions are malformed: ${error.message}',
      );
    }
    if (value is! List) {
      throw const FormatException('Transfer decisions must be a list.');
    }
    final decoded = value
        .map((item) {
          if (item is! Map) {
            throw const FormatException(
              'Each transfer decision must be an object.',
            );
          }
          return TransferDecision.fromJson(Map<String, dynamic>.from(item));
        })
        .toList(growable: false);
    final ids = <String>{};
    for (final decision in decoded) {
      if (!ids.add(decision.id)) {
        throw const FormatException('Duplicate transfer decision.');
      }
    }
    return List.unmodifiable(decoded);
  }

  static String encode(Iterable<TransferDecision> decisions) => jsonEncode(
    decisions.map((decision) => decision.toJson()).toList(growable: false),
  );

  static List<TransferDecision> upsert(
    Iterable<TransferDecision> current,
    TransferDecision decision,
  ) {
    final result = <TransferDecision>[
      for (final item in current)
        if (item.id != decision.id) item,
      decision,
    ];
    return List.unmodifiable(result);
  }

  static TransferDecision? findActive(
    Iterable<TransferDecision> decisions,
    Flight inbound,
    Flight outbound,
  ) {
    for (final decision in decisions) {
      if (decision.matchesFlights(inbound, outbound)) return decision;
    }
    return null;
  }
}
