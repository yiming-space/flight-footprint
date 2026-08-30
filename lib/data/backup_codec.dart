import 'dart:convert';

import '../domain/flight.dart';
import '../domain/visited_place.dart';

class BackupData {
  const BackupData({required this.flights, required this.visitedPlaces});

  final List<Flight> flights;
  final List<VisitedPlace> visitedPlaces;
}

/// The intentionally small, portable backup contract. Date values are UTC ISO-8601.
class BackupCodec {
  static const format = 'flight-footprint-backup';
  static const version = 1;

  static String encode(BackupData data, {DateTime? exportedAt}) =>
      const JsonEncoder.withIndent('  ').convert({
        'format': format,
        'version': version,
        'exportedAt': (exportedAt ?? DateTime.now()).toUtc().toIso8601String(),
        'flights': data.flights.map(_flightToJson).toList(),
        'visitedPlaces': data.visitedPlaces.map(_placeToJson).toList(),
      });

  /// Decodes a snapshot returned by the cloud API.
  ///
  /// The self-hosted Worker stores the portable v1 backup object, while older
  /// Pages/device-sync deployments returned a web-style object with `places`
  /// and sometimes encoded the object as a JSON string. Keep that migration
  /// boundary here so cloud restore can validate everything before replacing
  /// the local database.
  static BackupData decodeCloudSnapshot(Object? source) {
    dynamic value = source;
    for (var depth = 0; depth < 3 && value is String; depth++) {
      final text = value.trim();
      if (text.isEmpty) {
        throw const FormatException('Cloud snapshot is empty.');
      }
      try {
        value = jsonDecode(text);
      } on FormatException catch (error) {
        throw FormatException(
          'Cloud snapshot is not valid JSON: ${error.message}',
        );
      }
    }
    if (value is Map) {
      final map = Map<String, dynamic>.from(value);
      final hasRecords =
          map['flights'] is List ||
          map['visitedPlaces'] is List ||
          map['places'] is List ||
          map['visited_places'] is List;
      // Some gateways wrap the stored JSON one more time as {snapshot: ...}
      // (or {data: ...}). Only unwrap when this object is not itself a
      // records envelope, otherwise the outer metadata would be discarded.
      if (!hasRecords && map['snapshot'] != null) {
        return decodeCloudSnapshot(map['snapshot']);
      }
      if (!hasRecords && map['data'] != null) {
        return decodeCloudSnapshot(map['data']);
      }
      return _deduplicate(decode(jsonEncode(map)));
    }
    if (value is List) {
      return _deduplicate(decode(jsonEncode(value)));
    }
    throw const FormatException('Cloud snapshot must be an object or array.');
  }

  static BackupData decode(String source) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw FormatException('Backup is not valid JSON: ${error.message}');
    }
    try {
      final object = decoded is Map ? Map<String, dynamic>.from(decoded) : null;
      if (object != null && object['format'] == format) {
        if (_integer(object['version']) != version ||
            object['flights'] is! List ||
            object['visitedPlaces'] is! List) {
          throw const FormatException(
            'Unsupported or malformed Flight Footprint backup.',
          );
        }
        return BackupData(
          flights: (object['flights'] as List)
              .map((item) => _flightFromJson(_object(item, 'flight')))
              .toList(growable: false),
          visitedPlaces: (object['visitedPlaces'] as List)
              .map((item) => _placeFromJson(_object(item, 'visited place')))
              .toList(growable: false),
        );
      }

      // The current web app exports a raw Flight[] array. Newer web builds
      // may wrap that array with visitedPlaces; accept both shapes so users
      // can move their records to the local-first Flutter app directly.
      if (decoded is List || object?['flights'] is List) {
        return _decodeWebExport(decoded is List ? decoded : object!);
      }
      throw const FormatException(
        'Unsupported or malformed Flight Footprint backup.',
      );
    } on FormatException {
      rethrow;
    } catch (error) {
      throw FormatException('Malformed backup record: $error');
    }
  }

  static Map<String, dynamic> _object(Object? value, String label) {
    if (value is! Map) throw FormatException('Each $label must be an object.');
    return Map<String, dynamic>.from(value);
  }

  static Map<String, dynamic> _flightToJson(Flight value) => {
    'id': value.id,
    'departureIata': value.departureIata,
    'arrivalIata': value.arrivalIata,
    'departedAt': value.departedAt.toUtc().toIso8601String(),
    'arrivedAt': value.arrivedAt?.toUtc().toIso8601String(),
    'status': flightStatusToStorage(value.status),
    'airline': value.airline,
    'flightNumber': value.flightNumber,
    'cabinClass': value.cabinClass,
    'aircraftType': value.aircraftType,
    'durationMinutes': value.durationMinutes,
    'seat': value.seat,
    'note': value.note,
    'distanceKm': value.distanceKm,
    'createdAt': value.createdAt.toUtc().toIso8601String(),
    'updatedAt': value.updatedAt.toUtc().toIso8601String(),
    'track': _trackToJson(value.track),
  };

  static Flight _flightFromJson(Map<String, dynamic> json) => Flight(
    id: _stringAny(json, const ['id']),
    departureIata: _stringAny(json, const [
      'departureIata',
      'departure_iata',
      'originCode',
      'origin_code',
    ]).toUpperCase(),
    arrivalIata: _stringAny(json, const [
      'arrivalIata',
      'arrival_iata',
      'destinationCode',
      'destination_code',
    ]).toUpperCase(),
    departedAt: _dateAny(json, const [
      'departedAt',
      'departed_at',
      'actualDepartureAt',
      'actual_departure_at',
    ]),
    arrivedAt: _nullableDateAny(json, const [
      'arrivedAt',
      'arrived_at',
      'actualArrivalAt',
      'actual_arrival_at',
    ]),
    status: flightStatusFromStorage(json['status']),
    airline: _nullableStringAny(json, const ['airline']),
    flightNumber: _nullableStringAny(json, const [
      'flightNumber',
      'flight_number',
    ]),
    cabinClass: _nullableStringAny(json, const [
      'cabinClass',
      'cabin_class',
      'cabin',
    ]),
    aircraftType: _nullableStringAny(json, const [
      'aircraftType',
      'aircraft_type',
    ]),
    durationMinutes: _nullableIntAny(json, const [
      'durationMinutes',
      'duration_minutes',
    ]),
    seat: _nullableStringAny(json, const ['seat']),
    note: _nullableStringAny(json, const ['note']),
    distanceKm: _nullableDoubleAny(json, const ['distanceKm', 'distance_km']),
    createdAt: _dateAny(json, const ['createdAt', 'created_at']),
    updatedAt: _dateAny(json, const [
      'updatedAt',
      'updated_at',
      'createdAt',
      'created_at',
    ]),
    track: _trackFromJson(json['track'] ?? json['track_json']),
  );

  static List<Map<String, dynamic>> _trackToJson(
    List<FlightTrackPoint> track,
  ) => [
    for (final point in track)
      {
        'recordedAt': point.recordedAt,
        'latitude': point.latitude,
        'longitude': point.longitude,
        'altitudeFt': point.altitudeFt,
        'groundSpeedKt': point.groundSpeedKt,
        'heading': point.heading,
        'onGround': point.onGround,
        'source': point.source,
      },
  ];

  static List<FlightTrackPoint> _trackFromJson(dynamic value) {
    if (value is String) {
      try {
        value = jsonDecode(value);
      } catch (_) {
        return const [];
      }
    }
    if (value is! List) return const [];
    final points = <FlightTrackPoint>[];
    for (var index = 0; index < value.length; index++) {
      final item = value[index];
      if (item is! Map) continue;
      final latitude = _number(item['latitude']);
      final longitude = _number(item['longitude']);
      if (latitude == null ||
          longitude == null ||
          latitude < -90 ||
          latitude > 90 ||
          longitude < -180 ||
          longitude > 180) {
        continue;
      }
      points.add(
        FlightTrackPoint(
          recordedAt:
              _integer(item['recordedAt'] ?? item['recorded_at']) ?? index,
          latitude: latitude,
          longitude: longitude,
          altitudeFt: _integer(item['altitudeFt'] ?? item['altitude_ft']),
          groundSpeedKt: _integer(
            item['groundSpeedKt'] ?? item['ground_speed_kt'],
          ),
          heading: _integer(item['heading']),
          onGround: item['onGround'] == true || item['on_ground'] == true,
          source: item['source'] is String
              ? item['source'] as String
              : item['source_name'] is String
              ? item['source_name'] as String
              : '',
        ),
      );
    }
    return List.unmodifiable(points);
  }

  static Map<String, dynamic> _placeToJson(VisitedPlace value) => {
    'id': value.id,
    'name': value.name,
    'latitude': value.latitude,
    'longitude': value.longitude,
    'visitedAt': value.visitedAt.toUtc().toIso8601String(),
    'countryCode': value.countryCode,
    'note': value.note,
    'createdAt': value.createdAt.toUtc().toIso8601String(),
    'updatedAt': value.updatedAt.toUtc().toIso8601String(),
  };

  static VisitedPlace _placeFromJson(Map<String, dynamic> json) => VisitedPlace(
    id: _stringAny(json, const ['id']),
    name: _stringAny(json, const ['name', 'cityName', 'city_name']),
    latitude: _doubleAny(json, const ['latitude']),
    longitude: _doubleAny(json, const ['longitude']),
    visitedAt: _dateAny(json, const ['visitedAt', 'visited_at']),
    countryCode: _nullableStringAny(json, const [
      'countryCode',
      'country_code',
    ]),
    note: _nullableStringAny(json, const ['note']),
    createdAt: _dateAny(json, const ['createdAt', 'created_at']),
    updatedAt: _dateAny(json, const [
      'updatedAt',
      'updated_at',
      'createdAt',
      'created_at',
    ]),
  );

  static Object? _first(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      if (json.containsKey(key) && json[key] != null) return json[key];
    }
    return null;
  }

  static String _stringAny(Map<String, dynamic> json, List<String> keys) {
    final value = _first(json, keys);
    if (value is String && value.trim().isNotEmpty) return value.trim();
    if (value is num && value.isFinite) return '$value';
    throw FormatException('Missing or invalid "${keys.first}".');
  }

  static String? _nullableStringAny(
    Map<String, dynamic> json,
    List<String> keys,
  ) {
    final value = _first(json, keys);
    if (value == null) return null;
    if (value is String) return value.trim().isEmpty ? null : value.trim();
    if (value is num && value.isFinite) return '$value';
    throw FormatException('Invalid "${keys.first}".');
  }

  static double _doubleAny(Map<String, dynamic> json, List<String> keys) {
    final value = _number(_first(json, keys));
    if (value != null && value.isFinite) return value;
    throw FormatException('Missing or invalid "${keys.first}".');
  }

  static double? _nullableDoubleAny(
    Map<String, dynamic> json,
    List<String> keys,
  ) {
    final value = _first(json, keys);
    if (value == null) return null;
    final number = _number(value);
    if (number == null || !number.isFinite || number < 0) {
      throw FormatException('Invalid "${keys.first}".');
    }
    return number;
  }

  static int? _nullableIntAny(Map<String, dynamic> json, List<String> keys) {
    final value = _first(json, keys);
    if (value == null) return null;
    final parsed = _integer(value);
    if (parsed == null || parsed < 0) {
      throw FormatException('Invalid "${keys.first}".');
    }
    return parsed;
  }

  static DateTime _dateAny(Map<String, dynamic> json, List<String> keys) {
    final value = _first(json, keys);
    final parsed = _dateValue(value);
    if (parsed == null) {
      throw FormatException('Missing or invalid "${keys.first}".');
    }
    return parsed;
  }

  static DateTime? _nullableDateAny(
    Map<String, dynamic> json,
    List<String> keys,
  ) {
    final value = _first(json, keys);
    if (value == null) return null;
    final parsed = _dateValue(value);
    if (parsed == null) throw FormatException('Invalid "${keys.first}".');
    return parsed;
  }

  static DateTime? _dateValue(Object? value) {
    if (value is String) {
      final parsed = DateTime.tryParse(value.trim());
      return parsed?.toUtc();
    }
    if (value is num && value.isFinite) {
      final raw = value.round();
      final millis = raw.abs() < 100000000000 ? raw * 1000 : raw;
      return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
    }
    return null;
  }

  static BackupData _decodeWebExport(dynamic decoded) {
    final List<dynamic> rawFlights;
    final List<dynamic> rawPlaces;
    if (decoded is List) {
      rawFlights = decoded;
      rawPlaces = const [];
    } else if (decoded is Map<String, dynamic> && decoded['flights'] is List) {
      rawFlights = decoded['flights'] as List<dynamic>;
      final places =
          decoded['visitedPlaces'] ??
          decoded['places'] ??
          decoded['visited_places'];
      rawPlaces = places is List ? places : const [];
    } else {
      throw const FormatException('Web export must contain a flights array.');
    }
    return BackupData(
      flights: [
        for (final item in rawFlights)
          _webFlightFromJson(_object(item, 'web flight')),
      ],
      visitedPlaces: [
        for (final item in rawPlaces)
          _webPlaceFromJson(_object(item, 'web visited place')),
      ],
    );
  }

  static Flight _webFlightFromJson(Map<String, dynamic> json) {
    final departureIata = _webRequiredText(json, [
      'originCode',
      'departureIata',
      'origin_code',
      'departure_iata',
    ]);
    final arrivalIata = _webRequiredText(json, [
      'destinationCode',
      'arrivalIata',
      'destination_code',
      'arrival_iata',
    ]);
    final flightDate = _webText(json, ['flightDate', 'flight_date']);
    final flightNumber = _webText(json, ['flightNumber', 'flight_number']);
    final airline = _webNullableText(json, ['airline']);
    final departedAt = _webDepartureDate(json);
    final durationMinutes = _webNullableInt(json, [
      'durationMinutes',
      'duration_minutes',
    ]);
    final arrivedAt = _webArrivalDate(json, departedAt, durationMinutes);
    final createdAt =
        _webDateFromKeys(json, [
          'createdAt',
          'created_at',
          'actualDepartureAt',
          'actual_departure_at',
        ]) ??
        departedAt;
    final updatedAt =
        _webDateFromKeys(json, [
          'updatedAt',
          'updated_at',
          'actualArrivalAt',
          'actual_arrival_at',
          'createdAt',
          'created_at',
        ]) ??
        createdAt;
    final rawId = json['id'];
    final id = rawId is num
        ? 'web-flight-${rawId.round()}'
        : _stableId(
            'web-flight',
            '$flightDate|$flightNumber|$departureIata|$arrivalIata',
          );
    return Flight(
      id: id,
      departureIata: departureIata.toUpperCase(),
      arrivalIata: arrivalIata.toUpperCase(),
      departedAt: departedAt,
      arrivedAt: arrivedAt,
      createdAt: createdAt,
      updatedAt: updatedAt,
      status: flightStatusFromStorage(json['status']),
      airline: airline,
      flightNumber: flightNumber,
      cabinClass: _webNullableText(json, [
        'cabin',
        'cabinClass',
        'cabin_class',
      ]),
      aircraftType: _webNullableText(json, ['aircraftType', 'aircraft_type']),
      durationMinutes: durationMinutes,
      seat: _webNullableText(json, ['seat']),
      note: _webNullableText(json, ['note']),
      distanceKm: _webNullableDouble(json, [
        'distanceKm',
        'distance_km',
        'actualDistanceKm',
        'actual_distance_km',
      ]),
      track: _trackFromJson(json['track'] ?? json['track_json']),
    );
  }

  static VisitedPlace _webPlaceFromJson(Map<String, dynamic> json) {
    // The web API returns camelCase fields, while the legacy device-sync
    // endpoint serializes its D1 row names (for example `city_name`). Keep
    // both shapes readable so a snapshot created by the web app can be
    // imported into the local-first Flutter app without manual cleanup.
    final name = _webRequiredText(json, ['cityName', 'city_name', 'name']);
    final latitude = _webNumber(json, ['latitude']);
    final longitude = _webNumber(json, ['longitude']);
    final countryCode = _webNullableText(json, ['countryCode', 'country_code']);
    final visitedAt =
        _webDateFromKeys(json, [
          'visitedAt',
          'visited_at',
          'createdAt',
          'created_at',
        ]) ??
        DateTime.utc(1970, 1, 1);
    final createdAt =
        _webDateFromKeys(json, ['createdAt', 'created_at']) ?? visitedAt;
    final rawId = json['id'];
    final id = rawId is num
        ? 'web-place-${rawId.round()}'
        : _stableId('web-place', '${countryCode ?? ''}|$name');
    return VisitedPlace(
      id: id,
      name: name,
      latitude: latitude,
      longitude: longitude,
      visitedAt: visitedAt,
      createdAt: createdAt,
      updatedAt: createdAt,
      countryCode: countryCode,
      note: _webNullableText(json, ['note']),
    );
  }

  static DateTime _webDepartureDate(Map<String, dynamic> json) {
    final direct = _webDateFromKeys(json, [
      'actualDepartureAt',
      'actual_departure_at',
      'departedAt',
      'departed_at',
    ]);
    if (direct != null) return direct;
    final date = _webText(json, ['flightDate', 'flight_date']);
    final rawTime = _webText(json, ['departureTime', 'departure_time']);
    final match = RegExp(r'^(\d{1,2}:\d{2}(?::\d{2})?)').firstMatch(rawTime);
    final time = match?.group(1) ?? '00:00';
    // Web flightDate/departureTime are displayed wall-clock values without a
    // timezone. Treat them as UTC in the portable file so importing on a
    // device in another timezone does not silently move the recorded day.
    return DateTime.tryParse('${date}T${time}Z')?.toUtc() ??
        DateTime.utc(1970, 1, 1);
  }

  static DateTime? _webArrivalDate(
    Map<String, dynamic> json,
    DateTime departedAt,
    int? durationMinutes,
  ) {
    final direct = _webDateFromKeys(json, [
      'actualArrivalAt',
      'actual_arrival_at',
      'arrivedAt',
      'arrived_at',
      'arrivalAt',
      'arrival_at',
    ]);
    if (direct != null) return direct;

    final date = _webText(json, ['flightDate', 'flight_date']);
    final rawTime = _webText(json, ['arrivalTime', 'arrival_time']);
    final match = RegExp(r'^(\d{1,2}):(\d{2})(?::(\d{2}))?(?:\+(\d+))?')
        .firstMatch(rawTime);
    if (match != null && date.isNotEmpty) {
      final hour = int.tryParse(match.group(1)!) ?? 0;
      final minute = int.tryParse(match.group(2)!) ?? 0;
      final second = int.tryParse(match.group(3) ?? '0') ?? 0;
      final dayOffset = int.tryParse(match.group(4) ?? '0') ?? 0;
      final parsedDate = DateTime.tryParse('${date}T00:00:00Z');
      if (parsedDate != null) {
        return DateTime.utc(
          parsedDate.year,
          parsedDate.month,
          parsedDate.day + dayOffset,
          hour,
          minute,
          second,
        );
      }
    }
    if (durationMinutes != null && durationMinutes > 0) {
      return departedAt.add(Duration(minutes: durationMinutes));
    }
    return null;
  }

  static DateTime? _webDateFromKeys(
    Map<String, dynamic> json,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = json[key];
      if (value is String && value.trim().isNotEmpty) {
        final trimmed = value.trim();
        // Web date-only fields are wall-clock calendar dates, not local
        // timestamps. Pin them to UTC midnight so importing on a device in
        // another timezone never moves the visit to the previous day.
        final normalized = RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(trimmed)
            ? '${trimmed}T00:00:00Z'
            : trimmed;
        final parsed = DateTime.tryParse(normalized);
        if (parsed != null) return parsed.toUtc();
      } else if (value is num && value.isFinite) {
        final raw = value.round();
        final millis = raw.abs() < 100000000000 ? raw * 1000 : raw;
        return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
      }
    }
    return null;
  }

  static String _webRequiredText(Map<String, dynamic> json, List<String> keys) {
    final value = _webText(json, keys);
    if (value.isEmpty) {
      throw FormatException('Missing web field "${keys.first}".');
    }
    return value;
  }

  static String _webText(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
      if (value is num) return '$value';
    }
    return '';
  }

  static String? _webNullableText(
    Map<String, dynamic> json,
    List<String> keys,
  ) {
    final value = _webText(json, keys);
    return value.isEmpty ? null : value;
  }

  static int? _webNullableInt(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = _integer(json[key]);
      if (value != null && value >= 0) return value;
    }
    return null;
  }

  static double? _webNullableDouble(
    Map<String, dynamic> json,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = _number(json[key]);
      if (value != null && value >= 0) return value;
    }
    return null;
  }

  static double _webNumber(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = _number(json[key]);
      if (value != null && value.isFinite) return value;
    }
    throw FormatException('Missing web field "${keys.first}".');
  }

  static double? _number(dynamic value) {
    if (value is num && value.isFinite) return value.toDouble();
    if (value is String) return double.tryParse(value.trim());
    return null;
  }

  static int? _integer(dynamic value) {
    if (value is int) return value;
    if (value is num && value.isFinite) return value.round();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  /// Cloud snapshots from the web runtime may contain records from before the
  /// local-first ID migration. Collapse those legacy duplicates before a
  /// destructive restore, choosing the newest version of each record.
  static BackupData _deduplicate(BackupData data) {
    final flights = <String, Flight>{};
    for (final flight in data.flights) {
      final number = flight.flightNumber?.trim().toUpperCase() ?? '';
      final key = number.isEmpty
          ? 'id:${flight.id}'
          : 'flight:${_dayKey(flight.departedAt)}|$number|'
                '${flight.departureIata.trim().toUpperCase()}|'
                '${flight.arrivalIata.trim().toUpperCase()}';
      final current = flights[key];
      if (current == null || _isNewer(flight.updatedAt, current.updatedAt)) {
        flights[key] = flight;
      }
    }

    final places = <String, VisitedPlace>{};
    for (final place in data.visitedPlaces) {
      final name = place.name.trim().toLowerCase();
      final country = place.countryCode?.trim().toUpperCase() ?? '';
      final key = 'place:$country|$name';
      final current = places[key];
      if (current == null || _isNewer(place.updatedAt, current.updatedAt)) {
        places[key] = place;
      }
    }
    return BackupData(
      flights: List.unmodifiable(flights.values),
      visitedPlaces: List.unmodifiable(places.values),
    );
  }

  static bool _isNewer(DateTime candidate, DateTime current) =>
      candidate.isAfter(current) || candidate.isAtSameMomentAs(current);

  static String _dayKey(DateTime value) {
    final utc = value.toUtc();
    return '${utc.year.toString().padLeft(4, '0')}-'
        '${utc.month.toString().padLeft(2, '0')}-'
        '${utc.day.toString().padLeft(2, '0')}';
  }

  static String _stableId(String prefix, String value) {
    var hash = 2166136261;
    for (final unit in value.codeUnits) {
      hash = (hash ^ unit) * 16777619 & 0x7fffffff;
    }
    return '$prefix-${hash.toRadixString(16)}';
  }
}
