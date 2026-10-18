import 'package:flight_footprint/data/flight_data_controller.dart';
import 'package:flight_footprint/data/flight_repository.dart';
import 'package:flight_footprint/domain/flight.dart';
import 'package:flight_footprint/domain/visited_place.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('refresh persists overdue upcoming flights as completed', () async {
    final repository = _FakeRepository([
      _flight(
        id: 'overdue',
        status: FlightStatus.upcoming,
        departedAt: DateTime(2026, 9, 12, 8),
        arrivedAt: DateTime(2026, 9, 12, 10),
      ),
      _flight(
        id: 'future',
        status: FlightStatus.upcoming,
        departedAt: DateTime(2026, 9, 14, 8),
        durationMinutes: 120,
      ),
      _flight(
        id: 'completed',
        status: FlightStatus.completed,
        departedAt: DateTime(2026, 9, 10, 8),
      ),
      _flight(
        id: 'in-flight',
        status: FlightStatus.upcoming,
        departedAt: DateTime(2026, 9, 13, 11),
        arrivedAt: DateTime(2026, 9, 13, 13),
      ),
      _flight(
        id: 'unknown-arrival',
        status: FlightStatus.upcoming,
        departedAt: DateTime(2026, 9, 12, 8),
      ),
    ]);
    final controller = FlightDataController(repository);
    addTearDown(controller.dispose);

    await controller.refresh(now: DateTime(2026, 9, 13, 12));

    expect(controller.flights[0].status, FlightStatus.completed);
    expect(controller.flights[1].status, FlightStatus.upcoming);
    expect(controller.flights[2].status, FlightStatus.completed);
    expect(controller.flights[3].status, FlightStatus.upcoming);
    expect(controller.flights[4].status, FlightStatus.upcoming);
    expect(repository.saved.map((flight) => flight.id), ['overdue']);
  });

  test('repeated refresh is idempotent after status migration', () async {
    final repository = _FakeRepository([
      _flight(
        id: 'overdue',
        status: FlightStatus.upcoming,
        departedAt: DateTime(2026, 9, 12, 8),
        durationMinutes: 120,
      ),
    ]);
    final controller = FlightDataController(repository);
    addTearDown(controller.dispose);

    await controller.refresh(now: DateTime(2026, 9, 13, 12));
    await controller.refresh(now: DateTime(2026, 9, 13, 13));

    expect(repository.saved, hasLength(1));
    expect(controller.flights.single.status, FlightStatus.completed);
  });

  test('overnight flight persists completion only at its arrival', () async {
    final departure = DateTime.utc(2026, 9, 13, 23);
    final arrival = DateTime.utc(2026, 9, 14, 2);
    final repository = _FakeRepository([
      _flight(
        id: 'overnight',
        status: FlightStatus.upcoming,
        departedAt: departure,
        arrivedAt: arrival,
      ),
    ]);
    final controller = FlightDataController(repository);
    addTearDown(controller.dispose);

    await controller.refresh(
      now: arrival.subtract(const Duration(milliseconds: 1)).toLocal(),
    );
    expect(controller.flights.single.status, FlightStatus.upcoming);
    expect(repository.saved, isEmpty);

    await controller.refresh(now: arrival.toLocal());
    expect(controller.flights.single.status, FlightStatus.completed);
    expect(repository.saved, hasLength(1));
    expect(repository.saved.single.departedAt, departure);
    expect(repository.saved.single.arrivedAt, arrival);
  });
}

class _FakeRepository extends FlightRepository {
  _FakeRepository(this.stored);

  List<Flight> stored;
  final List<Flight> saved = [];

  @override
  Future<List<Flight>> listFlights() async => List.of(stored);

  @override
  Future<List<VisitedPlace>> listVisitedPlaces() async => const [];

  @override
  Future<void> upsertFlights(Iterable<Flight> flights) async {
    final updates = flights.toList(growable: false);
    saved.addAll(updates);
    final byId = {for (final flight in updates) flight.id: flight};
    stored = [for (final flight in stored) byId[flight.id] ?? flight];
  }
}

Flight _flight({
  required String id,
  required FlightStatus status,
  required DateTime departedAt,
  DateTime? arrivedAt,
  int? durationMinutes,
}) => Flight(
  id: id,
  departureIata: 'SZX',
  arrivalIata: 'PEK',
  departedAt: departedAt,
  arrivedAt: arrivedAt,
  durationMinutes: durationMinutes,
  createdAt: DateTime.utc(2026, 9, 1),
  updatedAt: DateTime.utc(2026, 9, 1),
  status: status,
);
