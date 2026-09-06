import 'dart:convert';

import 'flight_repository.dart';

typedef MetaGetter = Future<String?> Function(String key);
typedef MetaSetter = Future<void> Function(String key, String value);

/// A small versioned wrapper around app_meta so drafts need no schema change.
class FlightDraftStore {
  FlightDraftStore({required this.getMeta, required this.setMeta});

  factory FlightDraftStore.fromRepository(FlightRepository repository) =>
      FlightDraftStore(
        getMeta: repository.getMeta,
        setMeta: repository.setMeta,
      );

  static const key = 'add_flight_draft_v1';

  final MetaGetter getMeta;
  final MetaSetter setMeta;
  Future<void> _writes = Future<void>.value();

  Future<FlightDraft?> load() async {
    final raw = await getMeta(key);
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return FlightDraft.fromJson(Map<String, Object?>.from(decoded));
    } catch (_) {
      // A malformed/legacy value must never prevent the add-flight page from
      // opening. It will be replaced by the next meaningful draft.
      return null;
    }
  }

  Future<void> save(FlightDraft draft) async {
    if (!draft.hasMeaningfulContent) return;
    final value = jsonEncode(draft.toJson());
    _writes = _enqueue(() => setMeta(key, value));
    await _writes;
  }

  Future<void> clear() {
    _writes = _enqueue(() => setMeta(key, ''));
    return _writes;
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    // Recover from the previous operation before starting this one. The
    // current operation's error is intentionally preserved for its caller.
    return _writes.then<void>(
      (_) => operation(),
      onError: (_, _) => operation(),
    );
  }
}

class FlightDraft {
  const FlightDraft({
    this.departureIata,
    this.arrivalIata,
    this.date,
    this.dateTouched = false,
    this.arrivalAt,
    this.arrivalTouched = false,
    this.identity = '',
    this.aircraft = '',
    this.duration = '',
    this.distance = '',
    this.seat = '',
    this.note = '',
    this.cabin,
    this.more = false,
  });

  final String? departureIata;
  final String? arrivalIata;
  final DateTime? date;
  final bool dateTouched;
  final DateTime? arrivalAt;
  final bool arrivalTouched;
  final String identity;
  final String aircraft;
  final String duration;
  final String distance;
  final String seat;
  final String note;
  final String? cabin;
  final bool more;

  bool get hasMeaningfulContent =>
      [
        departureIata,
        arrivalIata,
        identity,
        aircraft,
        duration,
        distance,
        seat,
        note,
        cabin,
      ].any((value) => value?.trim().isNotEmpty ?? false) ||
      dateTouched ||
      arrivalTouched;

  Map<String, Object?> toJson() => {
    'version': 1,
    'departureIata': departureIata,
    'arrivalIata': arrivalIata,
    'date': date?.toIso8601String(),
    'dateTouched': dateTouched,
    'arrivalAt': arrivalAt?.toIso8601String(),
    'arrivalTouched': arrivalTouched,
    'identity': identity,
    'aircraft': aircraft,
    'duration': duration,
    'distance': distance,
    'seat': seat,
    'note': note,
    'cabin': cabin,
    'more': more,
  };

  factory FlightDraft.fromJson(Map<String, Object?> json) {
    final version = json['version'];
    // Missing version is the original unversioned format. Any explicit
    // unknown version must not be interpreted as a partially compatible one.
    if (version != null && version != 1) {
      throw const FormatException('Unsupported flight draft version');
    }
    return FlightDraft(
      departureIata: _string(json['departureIata']),
      arrivalIata: _string(json['arrivalIata']),
      date: _date(json['date']),
      dateTouched: json['dateTouched'] == true,
      arrivalAt: _date(json['arrivalAt']),
      arrivalTouched: json['arrivalTouched'] == true,
      identity: _string(json['identity']) ?? '',
      aircraft: _string(json['aircraft']) ?? '',
      duration: _string(json['duration']) ?? '',
      distance: _string(json['distance']) ?? '',
      seat: _string(json['seat']) ?? '',
      note: _string(json['note']) ?? '',
      cabin: _string(json['cabin']),
      more: json['more'] == true,
    );
  }

  static String? _string(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static DateTime? _date(Object? value) {
    final text = _string(value);
    return text == null ? null : DateTime.tryParse(text);
  }
}
