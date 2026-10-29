import 'package:flutter_test/flutter_test.dart';
import 'package:flight_footprint/domain/flight.dart';
import 'package:flight_footprint/domain/suspected_transit.dart';

void main() {
  final base = DateTime.utc(2026, 1, 1, 0);
  Flight flight(
    String id,
    String from,
    String to,
    int departureHour,
    int arrivalHour, {
    int arrivalMinute = 0,
  }) => Flight(
    id: id,
    departureIata: from,
    arrivalIata: to,
    departedAt: base.add(Duration(hours: departureHour)),
    arrivedAt: base.add(Duration(hours: arrivalHour, minutes: arrivalMinute)),
    createdAt: base,
    updatedAt: base,
  );

  test('uses absolute instants and inclusive 45 minute to 24 hour window', () {
    final a = flight('a', 'AAA', 'BBB', 0, 2);
    final b = flight(
      'b',
      'BBB',
      'CCC',
      2,
      4,
    ).copyWith(departedAt: base.add(const Duration(hours: 2, minutes: 45)));
    final result = detectSuspectedTransits([a, b]);
    expect(result.candidates.single.flightIds, ['a', 'b']);
    expect(
      result.candidates.single.connectionGaps.single,
      const Duration(minutes: 45),
    );
    expect(
      detectSuspectedTransits([a, flight('b24', 'BBB', 'CCC', 26, 28)])
          .candidates
          .single
          .flightIds,
      ['a', 'b24'],
    );
  });

  test('returns multi segment candidates without changing source records', () {
    final records = [
      flight('a', 'AAA', 'BBB', 0, 2),
      flight('b', 'BBB', 'CCC', 3, 5),
      flight('c', 'CCC', 'DDD', 6, 8),
    ];
    final result = detectSuspectedTransits(records);
    expect(result.candidates.first.flightIds, ['a', 'b', 'c']);
    expect(records.map((item) => item.id), ['a', 'b', 'c']);
    expect(records.every((item) => !item.isTransitArrival), isTrue);
  });

  test('keeps ambiguous branches visible and marks the conflict', () {
    final result = detectSuspectedTransits([
      flight('a', 'AAA', 'BBB', 0, 2),
      flight('b', 'BBB', 'CCC', 3, 5),
      flight('c', 'BBB', 'DDD', 4, 6),
    ]);
    expect(result.candidates.map((c) => c.flightIds.toString()).toSet(), {
      '[a, b]',
      '[a, c]',
    });
    expect(result.candidates.every((c) => c.hasConflicts), isTrue);
    expect(result.conflictingFlightIds, contains('a'));
  });

  test(
    'missing or invalid arrival blocks connections and reports unresolved',
    () {
      final missing = Flight(
        id: 'missing',
        departureIata: 'AAA',
        arrivalIata: 'BBB',
        departedAt: base,
        arrivedAt: null,
        createdAt: base,
        updatedAt: base,
      );
      final invalid = flight('invalid', 'AAA', 'BBB', 0, 0);
      final next = flight('next', 'BBB', 'CCC', 2, 4);
      final result = detectSuspectedTransits([missing, invalid, next]);
      expect(result.candidates, isEmpty);
      expect(result.unresolvedFlightIds, containsAll(['missing', 'invalid']));
    },
  );

  test('duplicate IDs are excluded as unsafe and reported as conflicts', () {
    final result = detectSuspectedTransits([
      flight('same', 'AAA', 'BBB', 0, 2),
      flight('same', 'BBB', 'CCC', 3, 5),
    ]);
    expect(result.candidates, isEmpty);
    expect(result.conflictingFlightIds, contains('same'));
  });

  test('blank airport codes do not form a connection', () {
    final result = detectSuspectedTransits([
      flight('a', '', '', 0, 2),
      flight('b', '', 'CCC', 3, 5),
    ]);
    expect(result.candidates, isEmpty);
  });

  test('bounds ambiguous path enumeration and reports truncation', () {
    final records = [
      flight('a', 'AAA', 'BBB', 0, 2),
      flight('b1', 'BBB', 'CCC', 3, 5),
      flight('b2', 'BBB', 'DDD', 4, 6),
      flight('b3', 'BBB', 'EEE', 5, 7),
    ];
    final result = detectSuspectedTransits(records, maximumCandidates: 1);
    expect(result.candidates, hasLength(1));
    expect(result.candidatesTruncated, isTrue);
  });
}
