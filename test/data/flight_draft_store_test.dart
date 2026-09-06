import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:flight_footprint/data/flight_draft_store.dart';

void main() {
  test('round trips a draft and tolerates old/malformed metadata', () async {
    final meta = <String, String>{};
    final store = FlightDraftStore(
      getMeta: (key) async => meta[key],
      setMeta: (key, value) async => meta[key] = value,
    );
    final draft = FlightDraft(
      departureIata: 'PEK',
      arrivalIata: 'HND',
      date: DateTime(2026, 9, 6, 8, 30),
      dateTouched: true,
      identity: 'CA 181',
      duration: '210',
    );

    await store.save(draft);
    expect((await store.load())?.arrivalIata, 'HND');
    expect((await store.load())?.date, draft.date);

    meta[FlightDraftStore.key] = '{not-json';
    expect(await store.load(), isNull);
    meta[FlightDraftStore.key] = '{"identity": "CA 181"}';
    expect((await store.load())?.identity, 'CA 181');
    meta[FlightDraftStore.key] = '{"identity": "future", "version": 2}';
    expect(await store.load(), isNull);
  });

  test('does not persist an empty draft', () async {
    final meta = <String, String>{};
    final store = FlightDraftStore(
      getMeta: (key) async => meta[key],
      setMeta: (key, value) async => meta[key] = value,
    );
    await store.save(const FlightDraft());
    expect(meta, isEmpty);
    await store.save(const FlightDraft(identity: 'MU 510'));
    await store.clear();
    expect(await store.load(), isNull);
  });

  test('serializes writes so clear wins over a pending save', () async {
    final meta = <String, String>{};
    final started = Completer<void>();
    final release = Completer<void>();
    var writes = 0;
    final store = FlightDraftStore(
      getMeta: (key) async => meta[key],
      setMeta: (key, value) async {
        if (writes++ == 0) {
          started.complete();
          await release.future;
        }
        meta[key] = value;
      },
    );

    final saving = store.save(const FlightDraft(identity: 'MU 510'));
    await started.future;
    final clearing = store.clear();
    release.complete();
    await Future.wait([saving, clearing]);
    expect(await store.load(), isNull);
  });

  test(
    'recovers the queue after a failed write and returns each error',
    () async {
      final values = <String>[];
      var shouldFail = true;
      final store = FlightDraftStore(
        getMeta: (_) async => values.isEmpty ? null : values.last,
        setMeta: (key, value) async {
          if (shouldFail) {
            shouldFail = false;
            throw StateError('temporary metadata failure');
          }
          values.add(value);
        },
      );

      await expectLater(
        store.save(const FlightDraft(identity: 'MU 510')),
        throwsA(isA<StateError>()),
      );
      await store.save(const FlightDraft(identity: 'MU 511'));
      expect((await store.load())?.identity, 'MU 511');

      shouldFail = true;
      await expectLater(store.clear(), throwsA(isA<StateError>()));
      await store.clear();
      expect(await store.load(), isNull);
    },
  );
}
