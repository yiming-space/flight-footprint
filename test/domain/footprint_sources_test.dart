import 'package:flight_footprint/domain/airport.dart';
import 'package:flight_footprint/domain/flight.dart';
import 'package:flight_footprint/domain/footprint_sources.dart';
import 'package:flight_footprint/domain/transfer_decision.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final airports = {
    'AAA': const Airport(
      iataCode: 'AAA',
      longitude: 1,
      latitude: 1,
      name: 'A',
      city: 'A',
      countryCode: 'US',
    ),
    'BBB': const Airport(
      iataCode: 'BBB',
      longitude: 2,
      latitude: 2,
      name: 'B',
      city: 'B',
      countryCode: 'CA',
    ),
    'CCC': const Airport(
      iataCode: 'CCC',
      longitude: 3,
      latitude: 3,
      name: 'C',
      city: 'C',
      countryCode: 'US',
    ),
  };

  Flight flight(
    String id,
    String from,
    String to,
    DateTime departure, {
    DateTime? arrival,
  }) => Flight(
    id: id,
    departureIata: from,
    arrivalIata: to,
    departedAt: departure,
    arrivedAt: arrival,
    distanceKm: 123.0,
    durationMinutes: 45,
    createdAt: departure,
    updatedAt: departure,
    isTransitArrival: id == 'inbound',
  );

  test(
    'confirmed matching transfer excludes only the two linked endpoints',
    () {
      final inbound = flight(
        'inbound',
        'AAA',
        'BBB',
        DateTime.utc(2025, 1, 1, 8),
        arrival: DateTime.utc(2025, 1, 1, 10),
      );
      final outbound = flight(
        'outbound',
        'BBB',
        'CCC',
        DateTime.utc(2025, 1, 1, 12),
      );
      final decision = TransferDecision.fromFlights(
        inbound: inbound,
        outbound: outbound,
        status: TransferDecisionStatus.confirmed,
        decidedAt: DateTime.utc(2025, 1, 1, 11),
      );

      final included = buildFootprintSources(
        flights: [inbound, outbound],
        visitedPlaces: const [],
        airportFor: (code) => airports[code],
        includeTransitArrivals: true,
        confirmedTransfers: [decision],
      );
      final excluded = buildFootprintSources(
        flights: [inbound, outbound],
        visitedPlaces: const [],
        airportFor: (code) => airports[code],
        includeTransitArrivals: false,
        confirmedTransfers: [decision],
      );

      expect(
        included.map((source) => '${source.flight!.id}:${source.isArrival}'),
        ['inbound:false', 'inbound:true', 'outbound:false', 'outbound:true'],
      );
      expect(
        excluded.map((source) => '${source.flight!.id}:${source.isArrival}'),
        ['inbound:false', 'outbound:true'],
      );
      // Footprint filtering is derived separately; both flight metric records
      // retain their original distance and duration values.
      expect(inbound.distanceKm, 123.0);
      expect(outbound.distanceKm, 123.0);
      expect(inbound.durationMinutes, 45);
      expect(outbound.durationMinutes, 45);
    },
  );

  test('rejected or stale decisions retain the outbound departure', () {
    final inbound = flight(
      'inbound',
      'AAA',
      'BBB',
      DateTime.utc(2025, 1, 1, 8),
      arrival: DateTime.utc(2025, 1, 1, 10),
    );
    final outbound = flight(
      'outbound',
      'BBB',
      'CCC',
      DateTime.utc(2025, 1, 1, 12),
    );
    final rejected = TransferDecision.fromFlights(
      inbound: inbound,
      outbound: outbound,
      status: TransferDecisionStatus.rejected,
      decidedAt: DateTime.utc(2025, 1, 1, 11),
    );
    final stale = TransferDecision.fromFlights(
      inbound: inbound.copyWith(arrivalIata: 'CCC'),
      outbound: outbound,
      status: TransferDecisionStatus.confirmed,
      decidedAt: DateTime.utc(2025, 1, 1, 11),
    );
    final sources = buildFootprintSources(
      flights: [inbound, outbound],
      visitedPlaces: const [],
      airportFor: (code) => airports[code],
      includeTransitArrivals: false,
      confirmedTransfers: [rejected, stale],
    );

    expect(
      sources.any(
        (source) => source.flight?.id == 'outbound' && !source.isArrival,
      ),
      isTrue,
    );
  });

  test('rejecting a pair does not silently clear a manual transit mark', () {
    final inbound = flight(
      'inbound',
      'AAA',
      'BBB',
      DateTime.utc(2025, 1, 1, 8),
      arrival: DateTime.utc(2025, 1, 1, 10),
    );
    final markedInbound = inbound.copyWith(isTransitArrival: true);
    final outbound = flight(
      'outbound',
      'BBB',
      'CCC',
      DateTime.utc(2025, 1, 1, 12),
    );
    final rejected = TransferDecision.fromFlights(
      inbound: markedInbound,
      outbound: outbound,
      status: TransferDecisionStatus.rejected,
      decidedAt: DateTime.utc(2025, 1, 1, 11),
    );

    final sources = buildFootprintSources(
      flights: [markedInbound, outbound],
      visitedPlaces: const [],
      airportFor: (code) => airports[code],
      includeTransitArrivals: false,
      confirmedTransfers: [rejected],
    );

    // Rejecting this connection only changes the pair decision. The separate
    // manual annotation remains intact and the existing preference still
    // controls whether its arrival endpoint counts.
    expect(markedInbound.isTransitArrival, isTrue);
    expect(
      sources.any(
        (source) => source.flight?.id == 'inbound' && source.isArrival,
      ),
      isFalse,
    );
    expect(
      sources.any(
        (source) => source.flight?.id == 'outbound' && !source.isArrival,
      ),
      isTrue,
    );
  });

  test('conflicting confirmed links exclude neither association', () {
    final inbound = flight(
      'inbound',
      'AAA',
      'BBB',
      DateTime.utc(2025, 1, 1, 8),
      arrival: DateTime.utc(2025, 1, 1, 10),
    ).copyWith(isTransitArrival: false);
    final outboundOne = flight(
      'outbound-one',
      'BBB',
      'CCC',
      DateTime.utc(2025, 1, 1, 12),
    );
    final outboundTwo = flight(
      'outbound-two',
      'BBB',
      'AAA',
      DateTime.utc(2025, 1, 1, 13),
    );
    final decisions = [
      TransferDecision.fromFlights(
        inbound: inbound,
        outbound: outboundOne,
        status: TransferDecisionStatus.confirmed,
      ),
      TransferDecision.fromFlights(
        inbound: inbound,
        outbound: outboundTwo,
        status: TransferDecisionStatus.confirmed,
      ),
    ];

    final resolution = resolveConfirmedTransfers([
      inbound,
      outboundOne,
      outboundTwo,
    ], decisions);
    final sources = buildFootprintSources(
      flights: [inbound, outboundOne, outboundTwo],
      visitedPlaces: const [],
      airportFor: (code) => airports[code],
      includeTransitArrivals: false,
      confirmedTransfers: decisions,
    );

    expect(
      resolution.conflictedDecisionIds,
      decisions.map((decision) => decision.id).toSet(),
    );
    expect(resolution.excludedEndpoints, isEmpty);
    expect(sources, hasLength(6));
  });
}
