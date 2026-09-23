import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/app_controller.dart';
import '../../core/localization/app_strings.dart';
import '../../data/airport_localization.dart';
import '../../domain/flight.dart';
import '../../ui/theme/app_theme.dart';

class FlightCard extends StatelessWidget {
  const FlightCard({
    super.key,
    required this.flight,
    required this.controller,
    this.index = 0,
    this.onLongPress,
    this.onEdit,
    this.onDelete,
  });

  final Flight flight;
  final AppController controller;
  final int index;
  final VoidCallback? onLongPress;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final from = controller.airportFor(flight.departureIata);
    final to = controller.airportFor(flight.arrivalIata);
    // Keep the card surface quiet; in the dark theme, a slightly brighter
    // edge and semantic route colors make each boarding pass easier to scan.
    final color = colors.surface;
    final departureAccent = isLight
        ? Color.lerp(AppColors.mapBlueDeep, colors.textPrimary, .36)!
        : colors.lime;
    final arrivalAccent = isLight
        ? AppColors.flightArrival
        : AppColors.routePurple;
    final cardTint = isLight ? colors.iceTint : colors.surfaceElevated;
    // Keep an overnight arrival on the following calendar day. Imported
    // records already carry the explicit arrival timestamp; for older/manual
    // records whose arrival clock was stored before departure, prefer the
    // known duration and otherwise roll the display date forward by one day.
    final arrivalAt = _arrivalForDisplay(flight);
    final arrivalDayOffset = _calendarDayOffset(flight.departedAt, arrivalAt);
    final arrivalDayOffsetLabel = arrivalDayOffset > 0
        ? context.strings.isZh
              ? arrivalDayOffset == 1
                    ? '次日'
                    : '+$arrivalDayOffset天'
              : arrivalDayOffset == 1
              ? '+1 day'
              : '+$arrivalDayOffset days'
        : null;
    final airline = flight.airline?.trim() ?? '';
    final flightNumber = flight.flightNumber?.trim() ?? '';
    final aircraft = flight.aircraftType?.trim() ?? '';
    final flightCode = flightNumber.isEmpty ? '航班记录' : flightNumber;
    final topMeta = [
      if (airline.isNotEmpty) airline,
      if (aircraft.isNotEmpty) aircraft,
    ].join(' · ');
    final content = Semantics(
      button: onLongPress != null,
      label: '$flightCode, ${flight.departureIata} to ${flight.arrivalIata}',
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Container(
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 16),
          decoration: ShapeDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              stops: isLight ? const [0, .68, 1] : const [0, .7, 1],
              colors: [
                color,
                Color.lerp(color, cardTint, isLight ? .08 : .16)!,
                Color.lerp(color, cardTint, isLight ? .18 : .3)!,
              ],
            ),
            // A slightly tighter corner keeps the card's generous layout
            // while matching the compact boarding-pass reference.
            shape:
                const RoundedSuperellipseBorder(
                  borderRadius: BorderRadius.all(Radius.circular(32)),
                ).copyWith(
                  side: isLight
                      ? BorderSide(
                          color: colors.iceTint.withValues(alpha: .68),
                          width: .8,
                        )
                      : BorderSide(
                          color: colors.border.withValues(alpha: .42),
                          width: .8,
                        ),
                ),
          ),
          child: Stack(
            children: [
              DefaultTextStyle(
                style: TextStyle(color: colors.cardText),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _FlightCardHeader(
                      flightCode: flightCode,
                      topMeta: topMeta,
                      color: colors.cardText,
                    ),
                    const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: _AirportStop(
                            code: flight.departureIata,
                            city: from == null
                                ? '机场'
                                : localizedAirportCardDisplayName(from),
                            value: flight.departedAt,
                            accentColor: departureAccent,
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: _AirportStop(
                            code: flight.arrivalIata,
                            city: to == null
                                ? '机场'
                                : localizedAirportCardDisplayName(to),
                            value: arrivalAt,
                            alignEnd: true,
                            accentColor: arrivalAccent,
                            dayOffsetLabel: arrivalDayOffsetLabel,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        RotatedBox(
                          quarterTurns: 1,
                          child: Icon(
                            Icons.flight_rounded,
                            size: 26,
                            color: colors.cardText.withValues(alpha: .58),
                          ),
                        ),
                        if (flight.durationMinutes != null &&
                            flight.durationMinutes! > 0) ...[
                          const SizedBox(height: 5),
                          Text(
                            _formatDuration(flight.durationMinutes!),
                            style: TextStyle(
                              color: colors.cardText.withValues(alpha: .62),
                              fontSize: 10,
                              height: 1,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -.1,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (onEdit == null && onDelete == null) return content;
    return _SwipeActions(onEdit: onEdit, onDelete: onDelete, child: content);
  }

  static DateTime? _estimatedArrival(Flight flight) {
    final duration = flight.durationMinutes;
    if (duration == null || duration <= 0) return null;
    return flight.departedAt.add(Duration(minutes: duration));
  }

  static DateTime? _arrivalForDisplay(Flight flight) {
    final arrival = flight.arrivedAt ?? _estimatedArrival(flight);
    if (arrival == null || arrival.isAfter(flight.departedAt)) return arrival;
    final duration = flight.durationMinutes;
    if (duration != null && duration > 0) {
      return flight.departedAt.add(Duration(minutes: duration));
    }
    return arrival.add(const Duration(days: 1));
  }

  static int _calendarDayOffset(DateTime departure, DateTime? arrival) {
    if (arrival == null) return 0;
    final localDeparture = departure.toLocal();
    final localArrival = arrival.toLocal();
    final departureDate = DateTime.utc(
      localDeparture.year,
      localDeparture.month,
      localDeparture.day,
    );
    final arrivalDate = DateTime.utc(
      localArrival.year,
      localArrival.month,
      localArrival.day,
    );
    return arrivalDate.difference(departureDate).inDays;
  }

  static String _formatDuration(int minutes) {
    if (minutes < 60) return '${minutes}m';
    final hours = minutes ~/ 60;
    final remaining = minutes % 60;
    return remaining == 0 ? '${hours}h' : '${hours}h ${remaining}m';
  }
}

class _FlightCardHeader extends StatelessWidget {
  const _FlightCardHeader({
    required this.flightCode,
    required this.topMeta,
    required this.color,
  });

  final String flightCode;
  final String topMeta;
  final Color color;

  static const _codeStyle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w700,
    letterSpacing: .05,
  );

  @override
  Widget build(BuildContext context) {
    final metaStyle = TextStyle(
      color: color,
      fontSize: 12,
      fontWeight: FontWeight.w700,
      letterSpacing: .05,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final direction = Directionality.of(context);
        final codeWidth = _textWidth(
          flightCode,
          _codeStyle.copyWith(color: color),
          direction,
        );
        final metaWidth = topMeta.isEmpty
            ? 0.0
            : _textWidth(topMeta, metaStyle, direction);
        const iconAndGapWidth = 26.0;
        const textGap = 8.0;
        final availableTextWidth = constraints.maxWidth - iconAndGapWidth;
        final fitsOnOneLine =
            topMeta.isEmpty ||
            codeWidth + textGap + metaWidth <= availableTextWidth;

        if (!fitsOnOneLine && topMeta.isNotEmpty) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.flight_takeoff_rounded, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      flightCode,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _codeStyle.copyWith(color: color),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      topMeta,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: metaStyle,
                    ),
                  ],
                ),
              ),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(Icons.flight_takeoff_rounded, size: 18, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                flightCode,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _codeStyle.copyWith(color: color),
              ),
            ),
            if (topMeta.isNotEmpty) ...[
              const SizedBox(width: textGap),
              SizedBox(
                width: metaWidth,
                child: Text(
                  topMeta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: metaStyle,
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  static double _textWidth(
    String value,
    TextStyle style,
    ui.TextDirection direction,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: value, style: style),
      textDirection: direction,
      maxLines: 1,
    )..layout();
    return painter.width;
  }
}

class _SwipeActions extends StatefulWidget {
  const _SwipeActions({required this.child, this.onEdit, this.onDelete});

  final Widget child;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  State<_SwipeActions> createState() => _SwipeActionsState();
}

class _SwipeActionsState extends State<_SwipeActions>
    with SingleTickerProviderStateMixin {
  static const _actionWidth = 116.0;
  late final AnimationController _controller;
  bool _open = false;

  bool get _hasActions => widget.onEdit != null || widget.onDelete != null;
  double get _offset => _controller.value * _actionWidth;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
  }

  @override
  void didUpdateWidget(covariant _SwipeActions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_hasActions) {
      _open = false;
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _dragStart(DragStartDetails details) {
    _controller.stop();
  }

  void _dragUpdate(DragUpdateDetails details) {
    if (!_hasActions) return;
    _controller.value = ((_offset - details.delta.dx) / _actionWidth).clamp(
      0.0,
      1.0,
    );
  }

  void _dragEnd(DragEndDetails details) {
    final fastLeft =
        details.primaryVelocity != null && details.primaryVelocity! < -260;
    final fastRight =
        details.primaryVelocity != null && details.primaryVelocity! > 260;
    final open = fastLeft || (!fastRight && _offset > _actionWidth * .42);
    _snapTo(open ? 1 : 0);
  }

  void _close() {
    if (_controller.value == 0) return;
    _snapTo(0);
  }

  void _snapTo(double target) {
    final open = target > 0;
    if (_open != open) setState(() => _open = open);
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = target;
      return;
    }
    _controller.animateTo(
      target,
      duration: AppMotion.control,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasActions) return widget.child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _open ? _close : null,
      child: Stack(
        children: [
          Positioned.fill(
            child: Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.onEdit != null)
                      _SwipeActionButton(
                        tooltip: context.strings.t('edit'),
                        icon: Icons.edit_rounded,
                        color: context.appColors.purple,
                        onPressed: () {
                          _close();
                          widget.onEdit?.call();
                        },
                      ),
                    if (widget.onDelete != null)
                      _SwipeActionButton(
                        tooltip: context.strings.t('delete'),
                        icon: Icons.delete_outline_rounded,
                        color: context.appColors.danger,
                        onPressed: () {
                          _close();
                          widget.onDelete?.call();
                        },
                      ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedBuilder(
            animation: _controller,
            child: GestureDetector(
              onHorizontalDragStart: _dragStart,
              onHorizontalDragUpdate: _dragUpdate,
              onHorizontalDragEnd: _dragEnd,
              onHorizontalDragCancel: _close,
              child: widget.child,
            ),
            builder: (context, child) =>
                Transform.translate(offset: Offset(-_offset, 0), child: child),
          ),
        ],
      ),
    );
  }
}

class _SwipeActionButton extends StatelessWidget {
  const _SwipeActionButton({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: tooltip,
    child: Padding(
      padding: const EdgeInsets.only(left: 6),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, size: 21),
        style: IconButton.styleFrom(
          fixedSize: const Size(48, 48),
          backgroundColor: color,
          foregroundColor: context.appColors.cardText,
        ),
      ),
    ),
  );
}

class _AirportStop extends StatelessWidget {
  const _AirportStop({
    required this.code,
    required this.city,
    required this.value,
    this.alignEnd = false,
    this.accentColor,
    this.dayOffsetLabel,
  });
  final String code;
  final String city;
  final DateTime? value;
  final bool alignEnd;
  final Color? accentColor;
  final String? dayOffsetLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final time = value == null
        ? '—:—'
        : DateFormat('HH:mm').format(value!.toLocal());
    final date = value == null
        ? '—'
        : DateFormat('yyyy.M.d').format(value!.toLocal());
    final textAlign = alignEnd ? TextAlign.end : TextAlign.start;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
            child: Text(
              code,
              textAlign: textAlign,
              maxLines: 1,
              style: const TextStyle(
                fontSize: 36,
                height: 1,
                fontWeight: FontWeight.w800,
                letterSpacing: -1.5,
              ).copyWith(color: accentColor ?? colors.cardText),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: EdgeInsetsDirectional.only(
            start: alignEnd ? 32 : 0,
            end: alignEnd ? 0 : 32,
          ),
          child: SizedBox(
            width: double.infinity,
            child: Text(
              city,
              textAlign: textAlign,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.cardText.withValues(alpha: isLight ? .72 : .68),
                fontSize: 12,
                height: 1.1,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(height: 13),
        Text(
          time,
          textAlign: textAlign,
          style: TextStyle(
            fontSize: 18,
            height: 1,
            fontWeight: FontWeight.w800,
            letterSpacing: -.25,
            color: accentColor ?? colors.cardText,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: alignEnd
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          children: [
            if (dayOffsetLabel != null) ...[
              DecoratedBox(
                decoration: BoxDecoration(
                  color: (accentColor ?? colors.textSecondary).withValues(
                    alpha: isLight ? .13 : .18,
                  ),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 3,
                  ),
                  child: Text(
                    dayOffsetLabel!,
                    style: TextStyle(
                      color: accentColor ?? colors.textSecondary,
                      fontSize: 9,
                      height: 1,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              date,
              textAlign: textAlign,
              style: TextStyle(
                color: colors.cardText.withValues(alpha: isLight ? .68 : .58),
                fontSize: 11,
                height: 1,
                fontWeight: FontWeight.w600,
                letterSpacing: .05,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
