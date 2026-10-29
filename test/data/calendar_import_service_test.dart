import 'package:flight_footprint/data/airport_catalog.dart';
import 'package:flight_footprint/data/calendar_import_service.dart';
import 'package:flight_footprint/domain/airport.dart';
import 'package:flight_footprint/domain/flight.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final airports = AirportCatalog.fromJsonString(
    '{"KUL":[101.7093,2.7456,"Kuala Lumpur International Airport",'
    '"Kuala Lumpur","MY","WMKK","large_airport",true,"MY-14",[]],'
    '"SZX":[113.8107,22.6393,"Shenzhen Baoan International Airport",'
    '"Shenzhen","CN","ZGSZ","large_airport",true,"CN-44",[]],'
    '"LHR":[-0.4543,51.47,"Heathrow Airport","London","GB",'
    '"EGLL","large_airport",true,"GB-ENG",[]],'
    '"JFK":[-73.7781,40.6413,"John F. Kennedy International Airport",'
    '"New York","US","KJFK","large_airport",true,"US-NY",[]],'
    '"AKL":[174.785, -37.0082,"Auckland Airport","Auckland","NZ",'
    '"NZAA","large_airport",true,"NZ-AUK",[]]}',
  );

  test('calendar revision changes with schedule but keeps flight identity', () {
    final service = CalendarImportService(airports: airports);
    final start = DateTime.utc(2026, 1, 1, 20);
    final first = service.parseEvent({
      'id': 'event-42',
      'title': 'NZ1 SZX-AKL',
      'startMillis': start.millisecondsSinceEpoch,
      'endMillis': start.add(const Duration(hours: 8)).millisecondsSinceEpoch,
    })!;
    final changed = service.parseEvent({
      'id': 'event-42',
      'title': 'NZ1 SZX-AKL',
      'startMillis': start.add(const Duration(days: 1)).millisecondsSinceEpoch,
      'endMillis': start
          .add(const Duration(days: 1, hours: 8))
          .millisecondsSinceEpoch,
    })!;
    expect(first.autoImportRevisionKey, isNot(changed.autoImportRevisionKey));
    expect(
      first.autoImportRevisionKey.startsWith(changed.autoImportEventPrefix),
      isTrue,
    );
    expect(first.toFlight().id, changed.toFlight().id);
  });

  test('parses a Umetrip calendar title and infers an overnight arrival', () {
    final service = CalendarImportService(
      airports: airports,
      clock: () => DateTime(2026, 7, 4, 23),
    );
    final event = {
      'id': 'calendar-42',
      'title': '乘坐AK128 吉隆坡国际T 2-深圳宝安 当地时间22:05-02:15 【航旅纵横】',
      'startMillis': DateTime(2026, 7, 4, 22, 5).millisecondsSinceEpoch,
      'endMillis': DateTime(2026, 7, 5, 2, 15).millisecondsSinceEpoch,
    };
    final result = service.parseEvent(event);

    expect(result, isNotNull);
    expect(result!.eventId, 'calendar-42');
    expect(result.flightNumber, 'AK128');
    expect(result.airline, '亚洲航空');
    expect(result.departureIata, 'KUL');
    expect(result.arrivalIata, 'SZX');
    expect(result.departedAt, DateTime(2026, 7, 4, 22, 5));
    expect(result.arrivedAt, DateTime(2026, 7, 5, 2, 15));
    expect(result.durationMinutes, 250);
    expect(result.status, FlightStatus.upcoming);
    expect(
      service.parseEvent(event, now: result.arrivedAt)?.status,
      FlightStatus.completed,
    );
  });

  test('keeps absolute calendar instants across zones and the date line', () {
    final service = CalendarImportService(airports: airports);
    final departure = DateTime.utc(2026, 1, 1, 20);
    final arrival = DateTime.utc(2026, 1, 2, 4);
    final result = service.parseEvent({
      'id': 'date-line-flight',
      // Auckland-local arrival time is later on the clock despite the route
      // crossing the date line. Calendar epochs are the reliable instants.
      'title': 'NZ1 SZX-AKL local time 12:00-17:00',
      'startMillis': departure.millisecondsSinceEpoch,
      'endMillis': arrival.millisecondsSinceEpoch,
    });

    expect(result, isNotNull);
    expect(result!.departedAt.toUtc(), departure);
    expect(result.arrivedAt.toUtc(), arrival);
    expect(result.durationMinutes, 480);
  });

  test('keeps elapsed time across a daylight-saving transition', () {
    final service = CalendarImportService(airports: airports);
    // London is still on GMT while New York has just moved to EDT. The local
    // clock difference is two hours; the actual flight duration is six.
    final departure = DateTime.utc(2026, 3, 8, 1, 30);
    final arrival = DateTime.utc(2026, 3, 8, 7, 30);
    final result = service.parseEvent({
      'id': 'dst-flight',
      'title': 'BA1 LHR-JFK local time 01:30-03:30',
      'startMillis': departure.millisecondsSinceEpoch,
      'endMillis': arrival.millisecondsSinceEpoch,
    });

    expect(result, isNotNull);
    expect(result!.departedAt.toUtc(), departure);
    expect(result.arrivedAt.toUtc(), arrival);
    expect(result.durationMinutes, 360);
  });

  test('does not infer an arrival day from an unzoned earlier clock', () {
    final service = CalendarImportService(airports: airports);
    final result = service.parseEvent({
      'title': 'AK128 KUL-SZX local time 22:05-02:15',
      'startMillis': DateTime.utc(2026, 7, 4, 14, 5).millisecondsSinceEpoch,
      // With no provider end, airport zones or explicit arrival date, this
      // clock pair is insufficient to distinguish overnight from date-line
      // and timezone crossings.
    });

    expect(result, isNull);
  });

  test('ignores an event without a route or flight number', () {
    final service = CalendarImportService(airports: airports);
    expect(
      service.parseEvent({
        'title': '酒店入住 深圳',
        'startMillis': DateTime(2026, 7, 4).millisecondsSinceEpoch,
      }),
      isNull,
    );
  });

  test('creates a deterministic flight id for the same calendar event', () {
    final service = CalendarImportService(airports: airports);
    final event = {
      'id': 'calendar-42',
      'title': '乘坐AK128 吉隆坡国际T2-深圳宝安 当地时间22:05-02:15',
      'startMillis': DateTime(2026, 7, 4, 22, 5).millisecondsSinceEpoch,
      'endMillis': DateTime(2026, 7, 5, 2, 15).millisecondsSinceEpoch,
    };
    final first = service
        .parseEvent(event)!
        .toFlight(now: DateTime(2026, 7, 1));
    final second = service
        .parseEvent(event)!
        .toFlight(now: DateTime(2026, 7, 2));
    expect(first.id, second.id);
    expect(first.departedAt, second.departedAt);
  });

  test('recognizes global IATA and ICAO airline prefixes', () {
    final service = CalendarImportService(
      airports: airports,
      clock: () => DateTime(2026, 7, 1, 12),
    );
    final iata = service.parseEvent({
      'title': 'SQ12 KUL-SZX local time 10:00-14:00',
      'startMillis': DateTime(2026, 7, 4, 10).millisecondsSinceEpoch,
      'endMillis': DateTime(2026, 7, 4, 14).millisecondsSinceEpoch,
    });
    final icao = service.parseEvent({
      'title': 'SIA328 KUL-SZX local time 10:00-14:00',
      'startMillis': DateTime(2026, 7, 4, 10).millisecondsSinceEpoch,
      'endMillis': DateTime(2026, 7, 4, 14).millisecondsSinceEpoch,
    });

    expect(iata?.flightNumber, 'SQ12');
    expect(iata?.airline, '新加坡航空');
    expect(icao?.flightNumber, 'SIA328');
    expect(icao?.airline, '新加坡航空');
  });

  test('recovers a missing prefix from an English airline title', () {
    final service = CalendarImportService(
      airports: airports,
      clock: () => DateTime(2026, 7, 1, 12),
    );
    final result = service.parseEvent({
      'title': 'Singapore Airlines 328 KUL-SZX local time 10:00-14:00',
      'startMillis': DateTime(2026, 7, 4, 10).millisecondsSinceEpoch,
      'endMillis': DateTime(2026, 7, 4, 14).millisecondsSinceEpoch,
    });

    expect(result?.flightNumber, 'SQ328');
    expect(result?.airline, '新加坡航空');
    expect(result?.departureIata, 'KUL');
    expect(result?.arrivalIata, 'SZX');
  });

  test('recognizes Hong Kong Express UO calendar flights', () {
    final service = CalendarImportService(
      airports: airports,
      clock: () => DateTime(2026, 7, 1, 12),
    );
    final result = service.parseEvent({
      'title': '乘坐UO628 吉隆坡国际T2-深圳宝安 当地时间10:00-11:10',
      'startMillis': DateTime(2026, 7, 4, 10).millisecondsSinceEpoch,
      'endMillis': DateTime(2026, 7, 4, 11, 10).millisecondsSinceEpoch,
    });

    expect(result, isNotNull);
    expect(result?.flightNumber, 'UO628');
    expect(result?.airline, '香港快运航空');
    expect(result?.departureIata, 'KUL');
    expect(result?.arrivalIata, 'SZX');
  });

  test(
    'marks only explicitly identified timed events safe for auto-import',
    () {
      final service = CalendarImportService(airports: airports);
      final start = DateTime(2026, 7, 4, 10);
      final end = DateTime(2026, 7, 4, 14);
      final explicit = service.parseEvent({
        'id': 'explicit-flight',
        'title': 'SQ12 KUL-SZX local time 10:00-14:00',
        'startMillis': start.millisecondsSinceEpoch,
        'endMillis': end.millisecondsSinceEpoch,
      });
      final missingId = service.parseEvent({
        'title': 'SQ12 KUL-SZX local time 10:00-14:00',
        'startMillis': start.millisecondsSinceEpoch,
        'endMillis': end.millisecondsSinceEpoch,
      });
      final allDay = service.parseEvent({
        'id': 'all-day-flight',
        'title': 'SQ12 KUL-SZX local time 10:00-14:00',
        'startMillis': start.millisecondsSinceEpoch,
        'endMillis': end.millisecondsSinceEpoch,
        'allDay': true,
      });

      expect(explicit?.isAutoImportSafe, isTrue);
      expect(missingId?.isAutoImportSafe, isFalse);
      expect(allDay?.isAutoImportSafe, isFalse);
    },
  );

  test('keeps ambiguous city-to-airport matches out of automatic import', () {
    final ambiguousAirports = AirportCatalog({
      'LHR': const Airport(
        iataCode: 'LHR',
        longitude: -0.4543,
        latitude: 51.47,
        name: 'Heathrow Airport',
        city: 'London',
        countryCode: 'GB',
      ),
      'LGW': const Airport(
        iataCode: 'LGW',
        longitude: -0.1903,
        latitude: 51.1537,
        name: 'Gatwick Airport',
        city: 'London',
        countryCode: 'GB',
      ),
      'JFK': const Airport(
        iataCode: 'JFK',
        longitude: -73.7781,
        latitude: 40.6413,
        name: 'John F Kennedy International Airport',
        city: 'New York',
        countryCode: 'US',
      ),
    });
    final service = CalendarImportService(airports: ambiguousAirports);
    final result = service.parseEvent({
      'id': 'ambiguous-city-flight',
      'title': 'BA123 London-JFK local time 10:00-12:00',
      'startMillis': DateTime.utc(2026, 7, 4, 10).millisecondsSinceEpoch,
      'endMillis': DateTime.utc(2026, 7, 4, 12).millisecondsSinceEpoch,
    });

    expect(result, isNotNull);
    expect(result!.departureIata, isIn(['LHR', 'LGW']));
    expect(result.isAutoImportSafe, isFalse);
  });

  test(
    'permission check never invokes the permission-requesting query',
    () async {
      final calls = <String>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel(CalendarImportService.channelName),
        (call) async {
          calls.add(call.method);
          return false;
        },
      );
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          const MethodChannel(CalendarImportService.channelName),
          null,
        ),
      );

      expect(
        await CalendarImportService(airports: airports).checkReadPermission(),
        CalendarPermissionState.denied,
      );
      expect(calls, ['hasReadPermission']);
    },
  );

  test(
    'permission check distinguishes an unsupported platform channel',
    () async {
      final service = CalendarImportService(
        airports: airports,
        channel: const MethodChannel('flight_footprint/calendar/unavailable'),
      );

      expect(
        await service.checkReadPermission(),
        CalendarPermissionState.unsupported,
      );
    },
  );

  test('scan forwards the no-prompt permission policy to Android', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    Object? receivedArguments;
    messenger.setMockMethodCallHandler(
      const MethodChannel(CalendarImportService.channelName),
      (call) async {
        receivedArguments = call.arguments;
        return <dynamic>[];
      },
    );
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        const MethodChannel(CalendarImportService.channelName),
        null,
      ),
    );

    final result = await CalendarImportService(airports: airports)
        .scan(allowPermissionRequest: false);

    expect(result.status, CalendarScanStatus.available);
    expect(receivedArguments, containsPair('allowPermissionRequest', false));
  });

  test(
    'scan surfaces flight-like events the parser cannot safely resolve',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel(CalendarImportService.channelName),
        (call) async => [
          {
            'id': 'ambiguous-flight',
            'title': 'CA123 航班信息待确认',
            'startMillis': DateTime(2026, 7, 4, 10).millisecondsSinceEpoch,
            'endMillis': DateTime(2026, 7, 4, 12).millisecondsSinceEpoch,
          },
        ],
      );
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          const MethodChannel(CalendarImportService.channelName),
          null,
        ),
      );

      final result = await CalendarImportService(airports: airports).scan();
      expect(result.flights, isEmpty);
      expect(result.reviewCandidates, 1);
      expect(result.reviewKeys.single, contains('ambiguous-flight'));
      expect(result.reviewKeys.single, contains('CA123'));
    },
  );
}
