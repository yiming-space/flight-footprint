import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/app_controller.dart';
import '../../data/flight_time_resolver.dart';
import '../../domain/flight.dart';
import '../../domain/footprint_sources.dart';
import '../../domain/suspected_transit.dart';
import '../../domain/transfer_decision.dart';
import '../../ui/theme/app_theme.dart';

/// Discoverable review surface for possible flight-to-flight connections.
/// Every connection is decided independently and requires an explicit tap.
class SuspectedTransitPanel extends StatefulWidget {
  const SuspectedTransitPanel({super.key, required this.controller});

  final AppController controller;

  @override
  State<SuspectedTransitPanel> createState() => _SuspectedTransitPanelState();
}

class _SuspectedTransitPanelState extends State<SuspectedTransitPanel> {
  final Set<String> _saving = {};

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final flights = widget.controller.flights;
    final result = detectSuspectedTransits(flights);
    final byId = <String, Flight>{
      for (final flight in flights) flight.id: flight,
    };
    final unresolvedCompleted = result.unresolvedFlightIds
        .where((id) => byId[id]?.isCompleted ?? false)
        .toSet();
    final hasNearbyDifferentAirportPair = _hasNearbyDifferentAirportPair(
      flights,
    );
    final transferResolution = resolveConfirmedTransfers(
      flights,
      widget.controller.transferDecisions,
    );
    final pairs = <String, _TransitPair>{};
    for (final candidate in result.candidates) {
      for (var index = 0; index + 1 < candidate.flightIds.length; index++) {
        final inbound = byId[candidate.flightIds[index]];
        final outbound = byId[candidate.flightIds[index + 1]];
        if (inbound == null || outbound == null) continue;
        final key = '${inbound.id}|${outbound.id}';
        final existing = widget.controller.transferDecisionFor(
          inbound,
          outbound,
        );
        pairs.putIfAbsent(
          key,
          () => _TransitPair(
            inbound: inbound,
            outbound: outbound,
            hasConflict:
                result.conflictingFlightIds.contains(inbound.id) ||
                result.conflictingFlightIds.contains(outbound.id),
            hasUnpairedLegacyMark: existing == null && inbound.isTransitArrival,
            hasSavedDecisionConflict:
                existing != null &&
                transferResolution.conflictedDecisionIds.contains(existing.id),
          ),
        );
      }
    }
    final pendingPairs = <_TransitPair>[];
    final decidedPairs = <_TransitPair>[];
    for (final pair in pairs.values) {
      if (widget.controller.transferDecisionFor(pair.inbound, pair.outbound) ==
          null) {
        pendingPairs.add(pair);
      } else {
        decidedPairs.add(pair);
      }
    }
    // Keep conflicting saved choices available for correction, while a fully
    // resolved set of confirmations no longer occupies the review panel.
    final needsSavedReview = decidedPairs.any(
      (pair) =>
          pair.hasSavedDecisionConflict ||
          widget.controller
                  .transferDecisionFor(pair.inbound, pair.outbound)
                  ?.status ==
              TransferDecisionStatus.rejected,
    );
    final otherDecidedPairs = decidedPairs;
    final confirmedCount = decidedPairs
        .where(
          (pair) =>
              widget.controller
                  .transferDecisionFor(pair.inbound, pair.outbound)
                  ?.status ==
              TransferDecisionStatus.confirmed,
        )
        .length;
    final rejectedCount = decidedPairs.length - confirmedCount;

    if (pendingPairs.isEmpty &&
        !needsSavedReview &&
        unresolvedCompleted.isEmpty &&
        !hasNearbyDifferentAirportPair) {
      return const SizedBox.shrink();
    }
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.md,
        AppSpacing.page,
        0,
      ),
      child: Material(
        color: colors.surface,
        shape: AppShapes.medium,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: pendingPairs.isNotEmpty,
            tilePadding: const EdgeInsets.symmetric(horizontal: 14),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            leading: Icon(Icons.alt_route_rounded, color: colors.lime),
            title: Text(
              pendingPairs.isEmpty && decidedPairs.isNotEmpty
                  ? (zh
                        ? '中转记录 · ${decidedPairs.length} 个已处理'
                        : 'Transfer records · ${decidedPairs.length} reviewed')
                  : pairs.isEmpty && hasNearbyDifferentAirportPair
                  ? (zh ? '中转记录说明' : 'Transfer review note')
                  : zh
                  ? '疑似中转 · ${pendingPairs.length} 个待核对'
                  : 'Possible transfers · ${pendingPairs.length} to review',
              style: TextStyle(
                color: colors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            subtitle: Text(
              pendingPairs.isEmpty && decidedPairs.isNotEmpty
                  ? (zh
                        ? '已确认 $confirmedCount · 已拒绝 $rejectedCount'
                        : '$confirmedCount confirmed · $rejectedCount rejected')
                  : pairs.isEmpty && hasNearbyDifferentAirportPair
                  ? (zh
                        ? '需要时请手动核对不同机场的行程'
                        : 'Review different-airport itineraries manually when needed')
                  : zh
                  ? '仅供核对；每个衔接点可单独确认、拒绝或更改'
                  : 'Suggestions only; confirm, reject, or change each connection separately',
              style: TextStyle(color: colors.textSecondary, fontSize: 12),
            ),
            children: [
              if (pendingPairs.isNotEmpty)
                for (final pair in pendingPairs)
                  _buildPair(context, pair, zh, colors),
              if (otherDecidedPairs.isNotEmpty)
                Theme(
                  data: Theme.of(context)
                      .copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    key: const ValueKey('suspected-transit-reviewed'),
                    tilePadding: const EdgeInsets.symmetric(horizontal: 4),
                    childrenPadding: const EdgeInsets.only(left: 4, right: 4),
                    title: Text(
                      zh
                          ? '已确认 / 已拒绝 · ${otherDecidedPairs.length} 条'
                          : 'Confirmed / rejected · ${otherDecidedPairs.length}',
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    children: [
                      for (final pair in otherDecidedPairs)
                        _buildPair(context, pair, zh, colors),
                    ],
                  ),
                ),
              if (unresolvedCompleted.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                  child: Text(
                    zh ? '部分记录缺少有效抵达时间，暂不生成候选。仅匹配同一机场代码；同城不同机场不会推断为中转。' : 'Some records lack a valid arrival time, so no suggestion is made. Matching requires the same airport code; different airports in one city are not inferred.',
                    style: TextStyle(color: colors.textSecondary, fontSize: 12),
                  ),
                ),
              if (hasNearbyDifferentAirportPair)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                  child: Text(
                    zh ? '有时间接近但机场代码不同的记录。请自行核对行程；应用不会推断同城不同机场属于同一中转。' : 'Some records are close in time but use different airport codes. Review them manually; the app will not infer a transfer between different airports in one city.',
                    style: TextStyle(color: colors.textSecondary, fontSize: 12),
                  ),
                ),
              if (result.candidatesTruncated)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                  child: Text(
                    zh ? '候选数量较多，列表已限制显示；请缩小记录范围后再核对。' : 'There are many candidates, so the list is limited. Narrow the records and review again.',
                    style: TextStyle(color: colors.textSecondary, fontSize: 12),
                  ),
                ),
              if (pairs.isEmpty && unresolvedCompleted.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    zh ? '没有可核对的候选。' : 'There are no candidates to review.',
                    style: TextStyle(color: colors.textSecondary),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  bool _hasNearbyDifferentAirportPair(List<Flight> flights) {
    const minimum = Duration(minutes: 45);
    const maximum = Duration(hours: 24);
    for (final inbound in flights) {
      final arrival = inbound.arrivedAt;
      if (arrival == null || !arrival.isAfter(inbound.departedAt)) continue;
      final inboundAirport = widget.controller.airportFor(inbound.arrivalIata);
      if (inboundAirport == null || inboundAirport.city.trim().isEmpty) {
        continue;
      }
      for (final outbound in flights) {
        if (identical(inbound, outbound) ||
            inbound.arrivalIata.trim().isEmpty ||
            outbound.departureIata.trim().isEmpty ||
            inbound.arrivalIata.trim().toUpperCase() ==
                outbound.departureIata.trim().toUpperCase()) {
          continue;
        }
        final gap = outbound.departedAt.difference(arrival);
        if (gap < minimum || gap > maximum) continue;
        final outboundAirport = widget.controller.airportFor(
          outbound.departureIata,
        );
        if (outboundAirport == null) continue;
        if (inboundAirport.city.trim().toLowerCase() ==
                outboundAirport.city.trim().toLowerCase() &&
            inboundAirport.countryCode.trim().toUpperCase() ==
                outboundAirport.countryCode.trim().toUpperCase()) {
          return true;
        }
      }
    }
    return false;
  }

  Widget _buildPair(
    BuildContext context,
    _TransitPair pair,
    bool zh,
    AppThemeColors colors,
  ) {
    final inbound = pair.inbound;
    final outbound = pair.outbound;
    final decision = widget.controller.transferDecisionFor(inbound, outbound);
    final key = '${inbound.id}|${outbound.id}';
    final busy = _saving.contains(key);
    final arrival = inbound.arrivedAt!;
    final gap = outbound.departedAt.difference(arrival);
    final gapText = gap.inMinutes < 60
        ? '${gap.inMinutes} min'
        : '${gap.inHours} h ${gap.inMinutes.remainder(60)} min';
    final statusText = switch (decision?.status) {
      TransferDecisionStatus.confirmed when pair.hasSavedDecisionConflict =>
        zh ? '确认冲突 · 需重新核对' : 'Conflicting confirmation · review',
      TransferDecisionStatus.confirmed =>
        zh ? '已确认 · 可更改' : 'Confirmed · changeable',
      TransferDecisionStatus.rejected =>
        zh ? '已拒绝 · 可更改' : 'Rejected · changeable',
      null => zh ? '待核对' : 'Needs review',
    };
    return Container(
      key: ValueKey('suspected-transit-${inbound.id}-${outbound.id}'),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        borderRadius: AppRadii.medium,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '${inbound.departureIata} → ${inbound.arrivalIata} → ${outbound.arrivalIata}',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (pair.hasConflict)
                _statusPill(
                  zh ? '存在冲突 · 请手动选择' : 'Ambiguous · choose manually',
                  colors.purple,
                ),
              if (pair.hasUnpairedLegacyMark)
                _statusPill(
                  zh
                      ? '抵达航班有旧手动中转标记'
                      : 'Inbound has a legacy manual transfer mark',
                  colors.purple,
                ),
              if (decision?.status == TransferDecisionStatus.rejected &&
                  inbound.isTransitArrival)
                _statusPill(
                  zh ? '原手动标记仍保留' : 'Manual mark is retained',
                  colors.purple,
                ),
              _statusPill(statusText, colors.textSecondary),
            ],
          ),
          const SizedBox(height: 6),
          if ((inbound.flightNumber?.trim().isNotEmpty ?? false) ||
              (outbound.flightNumber?.trim().isNotEmpty ?? false)) ...[
            Text(
              '${inbound.flightNumber?.trim().isNotEmpty == true ? inbound.flightNumber!.trim() : inbound.departureIata} → ${outbound.flightNumber?.trim().isNotEmpty == true ? outbound.flightNumber!.trim() : outbound.arrivalIata}',
              style: TextStyle(color: colors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 4),
          ],
          Text(
            '${zh ? '抵达' : 'Arrived'} ${inbound.arrivalIata} ${_airportTime(arrival, inbound.arrivalIata, zh)}  ·  ${zh ? '出发' : 'Departs'} ${outbound.departureIata} ${_airportTime(outbound.departedAt, outbound.departureIata, zh)}  ·  $gapText',
            style: TextStyle(color: colors.textSecondary, fontSize: 12),
          ),
          if (decision?.status == TransferDecisionStatus.rejected &&
              inbound.isTransitArrival) ...[
            const SizedBox(height: 8),
            Text(
              _legacyTransitDecisionNote(zh),
              style: TextStyle(color: colors.textSecondary, fontSize: 12),
            ),
          ],
          if (pair.hasSavedDecisionConflict) ...[
            const SizedBox(height: 8),
            Text(
              zh ? '此确认与另一条记录共用同一航班端点。统计暂不排除任一冲突衔接；请拒绝不成立的一条后再确认。' : 'This confirmation shares a flight endpoint with another. Statistics exclude neither conflicting connection. Reject the incorrect one before confirming again.',
              style: TextStyle(color: colors.textSecondary, fontSize: 12),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: busy
                      ? null
                      : () => _decide(pair, TransferDecisionStatus.rejected),
                  icon: const Icon(Icons.close_rounded, size: 18),
                  label: Text(zh ? '不是中转' : 'Not a transfer'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: busy
                      ? null
                      : () => _decide(pair, TransferDecisionStatus.confirmed),
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: Text(zh ? '确认中转' : 'Confirm transfer'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _legacyTransitDecisionNote(bool zh) {
    if (zh) {
      return widget.controller.countTransitArrivals
          ? '“不是中转”只拒绝这组航班衔接，不会清除抵达航班原有的手动标记；当前设置仍会计入该抵达。'
          : '“不是中转”只拒绝这组航班衔接，不会清除抵达航班原有的手动标记；当前设置下该抵达仍不计入足迹。若要改变，请编辑原航班标记或调整统计设置。';
    }
    return widget.controller.countTransitArrivals
        ? '“Not a transfer” rejects this connection only. The inbound flight’s manual mark stays saved, and the current setting still counts this arrival.'
        : '“Not a transfer” rejects this connection only. The inbound flight’s manual mark stays saved, so this arrival remains excluded. Edit the flight mark or change the footprint setting to change that.';
  }

  Widget _statusPill(String text, Color color) => DecoratedBox(
    decoration: BoxDecoration(
      color: color.withValues(alpha: .12),
      borderRadius: AppRadii.pill,
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );

  Future<void> _decide(_TransitPair pair, TransferDecisionStatus status) async {
    if (status == TransferDecisionStatus.confirmed &&
        _hasConfirmedEndpointConflict(pair)) {
      final zh = Localizations.localeOf(context).languageCode == 'zh';
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            zh ? '该航班端点已确认另一衔接，请先将另一条改为“不是中转”。' : 'This flight endpoint is already linked elsewhere. Reject that connection first.',
          ),
        ),
      );
      return;
    }
    final key = '${pair.inbound.id}|${pair.outbound.id}';
    setState(() => _saving.add(key));
    try {
      await widget.controller.decideTransfer(
        pair.inbound,
        pair.outbound,
        status,
      );
      if (mounted) {
        final zh = Localizations.localeOf(context).languageCode == 'zh';
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              zh
                  ? (status == TransferDecisionStatus.confirmed
                        ? '已保存：确认中转'
                        : '已保存：不是中转')
                  : (status == TransferDecisionStatus.confirmed
                        ? 'Saved: confirmed transfer'
                        : 'Saved: not a transfer'),
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_decisionErrorMessage(error))));
      }
    } finally {
      if (mounted) setState(() => _saving.remove(key));
    }
  }

  String _decisionErrorMessage(Object? error) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    if (error is TransferDecisionConflictException) {
      return zh
          ? '该航班端点已确认另一衔接，请先将另一条改为“不是中转”。'
          : 'This flight endpoint is linked elsewhere. Reject that connection first.';
    }
    if (error is StaleTransferDecisionException) {
      return zh
          ? '航班记录已更改，请刷新后重新核对。'
          : 'A flight changed. Refresh the records and review again.';
    }
    return zh ? '保存失败，请重试' : 'Could not save. Please try again.';
  }

  bool _hasConfirmedEndpointConflict(_TransitPair pair) {
    final flights = widget.controller.flights;
    final counts = <String, int>{};
    final byId = <String, Flight>{};
    for (final flight in flights) {
      counts.update(flight.id, (count) => count + 1, ifAbsent: () => 1);
      byId[flight.id] = flight;
    }
    for (final decision in widget.controller.transferDecisions) {
      if (decision.status != TransferDecisionStatus.confirmed) continue;
      final inbound = byId[decision.inboundFlightId];
      final outbound = byId[decision.outboundFlightId];
      if (inbound == null ||
          outbound == null ||
          counts[inbound.id] != 1 ||
          counts[outbound.id] != 1 ||
          !decision.matchesFlights(inbound, outbound)) {
        continue;
      }
      final sameInboundEndpoint =
          decision.inboundFlightId == pair.inbound.id &&
          decision.outboundFlightId != pair.outbound.id;
      final sameOutboundEndpoint =
          decision.outboundFlightId == pair.outbound.id &&
          decision.inboundFlightId != pair.inbound.id;
      if (sameInboundEndpoint || sameOutboundEndpoint) return true;
    }
    return false;
  }

  String _airportTime(DateTime instant, String airportIata, bool zh) {
    final zone = widget.controller.airports.timeZoneIdForIata(airportIata);
    final airportTime = FlightTimeResolver.toWallTime(instant, zone);
    final formatted = DateFormat('yyyy-MM-dd HH:mm')
        .format(airportTime ?? instant.toLocal());
    return airportTime == null
        ? '$formatted (${zh ? '设备时间' : 'device time'})'
        : formatted;
  }
}

class _TransitPair {
  const _TransitPair({
    required this.inbound,
    required this.outbound,
    required this.hasConflict,
    required this.hasUnpairedLegacyMark,
    required this.hasSavedDecisionConflict,
  });
  final Flight inbound;
  final Flight outbound;
  final bool hasConflict;
  final bool hasUnpairedLegacyMark;
  final bool hasSavedDecisionConflict;
}
