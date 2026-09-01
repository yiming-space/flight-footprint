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

  static const colors = [
    Color(0xFFB9A9F2),
    Color(0xFF9CCFE6),
    Color(0xFFA8D7AF),
    Color(0xFFE2B4D1),
    Color(0xFFE6DD79),
  ];

  @override
  Widget build(BuildContext context) {
    final from = controller.airportFor(flight.departureIata);
    final to = controller.airportFor(flight.arrivalIata);
    final color = colors[index % colors.length];
    final arrivalAt = flight.arrivedAt ?? _estimatedArrival(flight);
    final flightLabel = [flight.airline, flight.flightNumber]
        .whereType<String>()
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .join('  ');
    final aircraft = flight.aircraftType?.trim() ?? '';
    final content = Semantics(
      button: onLongPress != null,
      label: '${flight.departureIata} to ${flight.arrivalIata}',
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Container(
          padding: const EdgeInsets.fromLTRB(22, 19, 22, 18),
          decoration: ShapeDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [color, Color.lerp(color, Colors.white, .06)!],
            ),
            shape: AppShapes.large,
          ),
          child: DefaultTextStyle(
            style: const TextStyle(color: Color(0xFF0B0E12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        flightLabel.isEmpty ? '航班记录' : flightLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: .05,
                        ),
                      ),
                    ),
                    if (aircraft.isNotEmpty) ...[
                      const SizedBox(width: 10),
                      _MetaPill(label: aircraft),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: _Airport(
                        code: flight.departureIata,
                        city: from == null
                            ? '机场'
                            : localizedAirportCardDisplayName(from),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 76,
                      child: _FlightDuration(minutes: flight.durationMinutes),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _Airport(
                        code: flight.arrivalIata,
                        city: to == null
                            ? '机场'
                            : localizedAirportCardDisplayName(to),
                        alignEnd: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _DateTimeStrip(
                  departure: flight.departedAt,
                  arrival: arrivalAt,
                ),
              ],
            ),
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

  static String _formatDuration(int minutes) {
    if (minutes < 60) return '${minutes}m';
    final hours = minutes ~/ 60;
    final remaining = minutes % 60;
    return remaining == 0 ? '${hours}h' : '${hours}h ${remaining}m';
  }
}

class _FlightDuration extends StatelessWidget {
  const _FlightDuration({this.minutes});

  final int? minutes;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 42,
        height: 42,
        decoration: ShapeDecoration(
          color: Colors.black.withValues(alpha: .08),
          shape: AppShapes.small,
        ),
        child: const Icon(
          Icons.flight_takeoff_rounded,
          color: Color(0xFF0B0E12),
          size: 23,
        ),
      ),
      if (minutes != null) ...[
        const SizedBox(height: 5),
        Text(
          FlightCard._formatDuration(minutes!),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 11,
            height: 1,
            fontWeight: FontWeight.w700,
            letterSpacing: -.1,
          ),
        ),
      ],
    ],
  );
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: ShapeDecoration(
      color: Colors.black.withValues(alpha: .08),
      shape: AppShapes.pill,
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 10,
          height: 1,
          fontWeight: FontWeight.w700,
          letterSpacing: .15,
        ),
      ),
    ),
  );
}

class _DateTimeStrip extends StatelessWidget {
  const _DateTimeStrip({required this.departure, required this.arrival});

  final DateTime? departure;
  final DateTime? arrival;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: ShapeDecoration(
      color: Colors.black.withValues(alpha: .075),
      shape: AppShapes.small,
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: _DateTimeInfo(value: departure)),
          Container(
            width: 1,
            height: 31,
            color: Colors.black.withValues(alpha: .12),
          ),
          Expanded(child: _DateTimeInfo(value: arrival, alignEnd: true)),
        ],
      ),
    ),
  );
}

class _SwipeActions extends StatefulWidget {
  const _SwipeActions({required this.child, this.onEdit, this.onDelete});

  final Widget child;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  State<_SwipeActions> createState() => _SwipeActionsState();
}

class _SwipeActionsState extends State<_SwipeActions> {
  static const _actionWidth = 116.0;
  double _offset = 0;

  bool get _hasActions => widget.onEdit != null || widget.onDelete != null;

  void _dragUpdate(DragUpdateDetails details) {
    if (!_hasActions) return;
    setState(() {
      _offset = (_offset - details.delta.dx).clamp(0, _actionWidth).toDouble();
    });
  }

  void _dragEnd(DragEndDetails details) {
    final fastLeft =
        details.primaryVelocity != null && details.primaryVelocity! < -260;
    final open = fastLeft || _offset > _actionWidth * .42;
    setState(() => _offset = open ? _actionWidth : 0);
  }

  void _close() {
    if (_offset == 0) return;
    setState(() => _offset = 0);
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasActions) return widget.child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _offset == 0 ? null : _close,
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
                        color: AppColors.purple,
                        onPressed: () {
                          _close();
                          widget.onEdit?.call();
                        },
                      ),
                    if (widget.onDelete != null)
                      _SwipeActionButton(
                        tooltip: context.strings.t('delete'),
                        icon: Icons.delete_outline_rounded,
                        color: AppColors.danger,
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
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            transform: Matrix4.translationValues(-_offset, 0, 0),
            child: GestureDetector(
              onHorizontalDragUpdate: _dragUpdate,
              onHorizontalDragEnd: _dragEnd,
              child: widget.child,
            ),
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
          foregroundColor: Colors.black,
        ),
      ),
    ),
  );
}

class _Airport extends StatelessWidget {
  const _Airport({
    required this.code,
    required this.city,
    this.alignEnd = false,
  });
  final String code;
  final String city;
  final bool alignEnd;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: alignEnd
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start,
    children: [
      Text(
        code,
        style: const TextStyle(
          fontSize: 37,
          height: 1,
          fontWeight: FontWeight.w600,
          letterSpacing: -1.7,
        ),
      ),
      const SizedBox(height: 5),
      SizedBox(
        width: double.infinity,
        height: 30,
        child: Text(
          city,
          textAlign: alignEnd ? TextAlign.end : TextAlign.start,
          maxLines: 2,
          softWrap: true,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 12,
            height: 1.15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ],
  );
}

class _DateTimeInfo extends StatelessWidget {
  const _DateTimeInfo({required this.value, this.alignEnd = false});

  final DateTime? value;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final date = value == null
        ? '—'
        : DateFormat('yyyy-MM-dd').format(value!.toLocal());
    final time = value == null
        ? '—:—'
        : DateFormat('HH:mm').format(value!.toLocal());
    final alignment = alignEnd ? TextAlign.end : TextAlign.start;
    return Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(
          date,
          textAlign: alignment,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.black.withValues(alpha: .62),
            fontSize: 10.5,
            height: 1,
            fontWeight: FontWeight.w700,
            letterSpacing: .1,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          time,
          textAlign: alignment,
          style: const TextStyle(
            color: Color(0xFF0B0E12),
            fontSize: 19,
            height: 1,
            fontWeight: FontWeight.w700,
            letterSpacing: -.3,
          ),
        ),
      ],
    );
  }
}
