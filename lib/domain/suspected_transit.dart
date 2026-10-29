import 'flight.dart';

/// A conservative, read-only suggestion that consecutive records may form
/// one itinerary. It never edits or groups the source [Flight] records.
class SuspectedTransitCandidate {
  const SuspectedTransitCandidate({
    required this.flightIds,
    required this.connectionGaps,
    required this.hasConflicts,
  });

  /// Ordered source record IDs. A candidate always contains at least 2 IDs.
  final List<String> flightIds;

  /// Absolute elapsed times between each arrival and next departure.
  final List<Duration> connectionGaps;

  /// True when any record in this path has more than one plausible neighbor.
  final bool hasConflicts;
}

class SuspectedTransitDetection {
  const SuspectedTransitDetection({
    required this.candidates,
    required this.unresolvedFlightIds,
    required this.conflictingFlightIds,
    required this.candidatesTruncated,
  });

  final List<SuspectedTransitCandidate> candidates;

  /// Records lacking an arrival instant or with invalid time ordering.
  final List<String> unresolvedFlightIds;

  /// Records with multiple plausible predecessor/successor links.
  final List<String> conflictingFlightIds;

  /// True when an unusually ambiguous graph exceeded the enumeration limit.
  final bool candidatesTruncated;
}

/// Finds possible connections using only recorded absolute instants and exact
/// airport codes. Results are suggestions; callers must never mutate records
/// automatically based on them.
///
/// A valid connection is 45 minutes through 24 hours inclusive. Missing
/// arrivals, duplicate IDs, and invalid flight time ranges are handled
/// conservatively: affected links are omitted and source records are retained.
SuspectedTransitDetection detectSuspectedTransits(
  Iterable<Flight> source, {
  Duration minimumConnection = const Duration(minutes: 45),
  Duration maximumConnection = const Duration(hours: 24),
  int maximumCandidates = 256,
}) {
  if (minimumConnection.isNegative ||
      maximumConnection < minimumConnection ||
      maximumCandidates < 1) {
    throw ArgumentError('Invalid connection interval');
  }

  final flights = List<Flight>.unmodifiable(source);
  final unresolved = <String>{};
  final counts = <String, int>{};
  for (final flight in flights) {
    counts.update(flight.id, (count) => count + 1, ifAbsent: () => 1);
    final arrival = flight.arrivedAt;
    if (arrival == null || !arrival.isAfter(flight.departedAt)) {
      unresolved.add(flight.id);
    }
  }
  final duplicatedIds = counts.entries
      .where((entry) => entry.value > 1)
      .map((entry) => entry.key)
      .toSet();

  final next = <int, List<_Link>>{};
  final incoming = <int, int>{};
  final outgoing = <int, int>{};
  for (var i = 0; i < flights.length; i++) {
    final first = flights[i];
    final arrival = first.arrivedAt;
    if (arrival == null ||
        !arrival.isAfter(first.departedAt) ||
        duplicatedIds.contains(first.id)) {
      continue;
    }
    for (var j = 0; j < flights.length; j++) {
      if (i == j) continue;
      final second = flights[j];
      final connectionAirport = first.arrivalIata.trim();
      if (duplicatedIds.contains(second.id) ||
          connectionAirport.isEmpty ||
          second.departureIata.trim().isEmpty ||
          connectionAirport.toUpperCase() !=
              second.departureIata.trim().toUpperCase()) {
        continue;
      }
      final gap = second.departedAt.difference(arrival);
      if (gap < minimumConnection || gap > maximumConnection) continue;
      (next[i] ??= <_Link>[]).add(_Link(j, gap));
      outgoing.update(i, (value) => value + 1, ifAbsent: () => 1);
      incoming.update(j, (value) => value + 1, ifAbsent: () => 1);
    }
  }

  final conflictIndices = <int>{
    ...outgoing.entries.where((e) => e.value > 1).map((e) => e.key),
    ...incoming.entries.where((e) => e.value > 1).map((e) => e.key),
  };
  final conflictIds = <String>{
    for (final index in conflictIndices) flights[index].id,
    ...duplicatedIds,
  };

  final candidates = <SuspectedTransitCandidate>[];
  var candidatesTruncated = false;
  void addCandidate(List<int> path, List<Duration> gaps) {
    if (candidates.length >= maximumCandidates) {
      candidatesTruncated = true;
      return;
    }
    candidates.add(
      SuspectedTransitCandidate(
        flightIds: List.unmodifiable(path.map((i) => flights[i].id)),
        connectionGaps: List.unmodifiable(gaps),
        hasConflicts: path.any(conflictIndices.contains),
      ),
    );
  }

  void walk(int index, List<int> path, List<Duration> gaps) {
    if (candidatesTruncated) return;
    final links = next[index] ?? const <_Link>[];
    if (links.isEmpty) {
      if (path.length >= 2) addCandidate(path, gaps);
      return;
    }
    for (final link in links) {
      if (candidatesTruncated) return;
      // Prevent cycles from malformed/out-of-order records.
      if (path.contains(link.to)) continue;
      walk(link.to, [...path, link.to], [...gaps, link.gap]);
    }
    if (path.length >= 2) addCandidate(path, gaps);
  }

  for (var i = 0; i < flights.length; i++) {
    if ((incoming[i] ?? 0) == 0 && (next[i]?.isNotEmpty ?? false)) {
      walk(i, [i], const []);
    }
  }
  candidates.sort((a, b) {
    final length = b.flightIds.length.compareTo(a.flightIds.length);
    return length != 0
        ? length
        : a.flightIds.join('|').compareTo(b.flightIds.join('|'));
  });
  return SuspectedTransitDetection(
    candidates: List.unmodifiable(candidates),
    unresolvedFlightIds: List.unmodifiable(unresolved),
    conflictingFlightIds: List.unmodifiable(conflictIds),
    candidatesTruncated: candidatesTruncated,
  );
}

class _Link {
  const _Link(this.to, this.gap);
  final int to;
  final Duration gap;
}
