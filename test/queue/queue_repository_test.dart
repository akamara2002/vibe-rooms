import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart' hide EnginePhase;
import 'package:vibe_rooms/features/queue/data/supabase_queue_repository.dart';
import 'package:vibe_rooms/features/queue/domain/queue_failure.dart';
import 'package:vibe_rooms/features/queue/domain/queue_item.dart';

import '../fakes/fakes.dart';

class _Sub implements QueueSubscription {
  _Sub(this.source);
  final _Source source;
  @override
  Future<void> close() async => source.closed++;
}

class _Source implements QueueSource {
  List<Map<String, dynamic>> rows = [];
  Object? fetchError;
  Map<String, dynamic>? inserted;
  Object? insertError;
  List<dynamic> deleteResult = [
    {'id': 'x'},
  ];
  List<dynamic> updateResult = [
    {'id': 'x'},
  ];
  String? lastPlayedAt = 'unset';
  int fetches = 0;
  int closed = 0;
  Completer<void>? fetchGate;
  Object? subscribeError;
  void Function()? onChange;
  void Function(bool)? onStatus;

  @override
  Future<List<Map<String, dynamic>>> fetchUpcoming(String roomId) async {
    fetches++;
    final snapshot = List<Map<String, dynamic>>.of(rows);
    if (fetchGate != null) await fetchGate!.future;
    final error = fetchError;
    if (error != null) throw error;
    return snapshot;
  }

  @override
  Future<Map<String, dynamic>> insert(Map<String, dynamic> json) async {
    inserted = json;
    final error = insertError;
    if (error != null) throw error;
    return {
      ...fakeQueueItem().toJson(),
      ...json,
      'id': 'new1',
      'sort_key': 9,
      'created_at': '2026-11-18T12:00:00+00:00',
      'played_at': null,
      'profiles': {'display_name': 'Me', 'avatar_emoji': '🎧'},
    };
  }

  @override
  Future<List<dynamic>> delete(String itemId) async => deleteResult;

  @override
  Future<List<dynamic>> setPlayedAt(String itemId, String? iso) async {
    lastPlayedAt = iso;
    return updateResult;
  }

  @override
  QueueSubscription subscribe(
    String roomId, {
    required void Function() onChange,
    required void Function(bool joined) onStatus,
  }) {
    final error = subscribeError;
    if (error != null) throw error;
    this.onChange = onChange;
    this.onStatus = onStatus;
    return _Sub(this);
  }
}

Map<String, dynamic> _row(String id, int sortKey, {Object? profiles}) => {
  ...fakeQueueItem(id: id, sortKey: sortKey).toJson(),
  'profiles': profiles ?? {'display_name': 'Bo', 'avatar_emoji': '🎸'},
};

SupabaseQueueRepository _repo(_Source source, {String? me = 'user-1'}) =>
    SupabaseQueueRepository.withSource(source, userId: () => me);

void main() {
  group('add', () {
    test('inserts only the granted columns, as me', () async {
      final source = _Source();
      final item = await _repo(source).add('room-1', fakeTrack(id: 't9'));
      expect(source.inserted!.keys.toSet(), {
        'room_id',
        'added_by',
        'track_id',
        'title',
        'artist',
        'artwork_url',
        'duration_ms',
      });
      expect(source.inserted!['added_by'], 'user-1');
      expect(source.inserted!['room_id'], 'room-1');
      expect(source.inserted!['track_id'], 't9');
      for (final forbidden in ['id', 'sort_key', 'created_at', 'played_at']) {
        expect(source.inserted!.containsKey(forbidden), isFalse);
      }
      expect(item.addedByName, 'Me');
    });

    test('signed out is not allowed and sends nothing', () async {
      final source = _Source();
      await expectLater(
        _repo(source, me: null).add('room-1', fakeTrack()),
        throwsA(
          isA<QueueFailure>().having(
            (f) => f.kind,
            'kind',
            QueueFailureKind.notAllowed,
          ),
        ),
      );
      expect(source.inserted, isNull);
    });

    test('a database error becomes a failure', () async {
      final source = _Source()..insertError = StateError('boom');
      await expectLater(
        _repo(source).add('room-1', fakeTrack()),
        throwsA(isA<QueueFailure>()),
      );
    });
  });

  group('remove and markPlayed', () {
    test('a delete that removed no row is a failure', () async {
      final source = _Source()..deleteResult = [];
      await expectLater(
        _repo(source).remove('q1'),
        throwsA(
          isA<QueueFailure>().having(
            (f) => f.kind,
            'kind',
            QueueFailureKind.notAllowed,
          ),
        ),
      );
    });

    test('a delete that removed no row says the song is gone', () async {
      final source = _Source()..deleteResult = [];
      await expectLater(
        _repo(source).remove('q1'),
        throwsA(
          isA<QueueFailure>().having(
            (f) => f.message,
            'message',
            'That song is no longer in the queue.',
          ),
        ),
      );
    });

    test('a delete that removed a row succeeds', () async {
      await _repo(_Source()).remove('q1');
    });

    test('an update that changed no row is a failure', () async {
      final source = _Source()..updateResult = [];
      await expectLater(
        _repo(source).markPlayed('q1', DateTime.utc(2026)),
        throwsA(
          isA<QueueFailure>().having(
            (f) => f.kind,
            'kind',
            QueueFailureKind.notAllowed,
          ),
        ),
      );
    });

    test('marks with a UTC time, and null un-marks', () async {
      final source = _Source();
      await _repo(source).markPlayed('q1', DateTime.utc(2026, 11, 18, 12));
      expect(source.lastPlayedAt, '2026-11-18T12:00:00.000Z');
      await _repo(source).markPlayed('q1', null);
      expect(source.lastPlayedAt, isNull);
    });
  });

  group('upcoming', () {
    test('keeps the order and parses who added each item', () async {
      final source = _Source()..rows = [_row('a', 1), _row('b', 2)];
      final items = await _repo(source).upcoming('room-1');
      expect(items.map((i) => i.id), ['a', 'b']);
      expect(items.first.addedByName, 'Bo');
      expect(items.first.addedByEmoji, '🎸');
    });

    test('an embedded profile as a list, or missing, never breaks', () async {
      final source = _Source()
        ..rows = [
          _row(
            'a',
            1,
            profiles: [
              {'display_name': 'Cy', 'avatar_emoji': '🔥'},
            ],
          ),
          {...fakeQueueItem(id: 'b', sortKey: 2).toJson()}, // no profile
          _row('c', 3, profiles: 'nonsense'),
        ];
      final items = await _repo(source).upcoming('room-1');
      expect(items[0].addedByName, 'Cy');
      expect(items[1].addedByName, isNull);
      expect(items[2].addedByName, isNull);
    });

    test(
      'one unreadable row is skipped, the rest of the queue still loads',
      () async {
        final source = _Source()
          ..rows = [
            _row('a', 1),
            {'id': 12345, 'nonsense': true},
            _row('b', 2),
          ];
        final items = await _repo(source).upcoming('room-1');
        expect(items.map((i) => i.id), ['a', 'b']);
      },
    );

    test('a fetch error becomes a failure', () async {
      final source = _Source()..fetchError = StateError('offline');
      await expectLater(
        _repo(source).upcoming('room-1'),
        throwsA(isA<QueueFailure>()),
      );
    });

    test('the embedded profile is not part of the insert shape', () {
      final item = QueueItem.fromJson(_row('a', 1));
      expect(item.toInsertJson().containsKey('profiles'), isFalse);
      expect(item.toJson().containsKey('profiles'), isFalse);
    });
  });

  group('watchUpcoming', () {
    test(
      'loads at once, reloads after a change (debounced), once per burst',
      () {
        fakeAsync((async) {
          final source = _Source()..rows = [_row('a', 1)];
          final seen = <List<String>>[];
          final sub = _repo(source)
              .watchUpcoming('room-1')
              .listen((items) => seen.add(items.map((i) => i.id).toList()));
          async.flushMicrotasks();
          expect(seen, [
            ['a'],
          ]);
          expect(source.fetches, 1);

          source.rows = [_row('a', 1), _row('b', 2)];
          for (var i = 0; i < 5; i++) {
            source.onChange!();
            async.elapse(const Duration(milliseconds: 50));
          }
          expect(source.fetches, 1); // still inside the debounce window
          async.elapse(const Duration(milliseconds: 300));
          expect(source.fetches, 2);
          expect(seen.last, ['a', 'b']);
          sub.cancel();
        });
      },
    );

    test('a rejoin reads again, because missed events are not replayed', () {
      fakeAsync((async) {
        final source = _Source()..rows = [_row('a', 1)];
        final seen = <int>[];
        final sub = _repo(source)
            .watchUpcoming('room-1')
            .listen((items) => seen.add(items.length));
        async.flushMicrotasks();
        source.rows = [_row('a', 1), _row('b', 2), _row('c', 3)];
        source.onStatus!(true);
        async.elapse(const Duration(seconds: 1));
        expect(seen, [1, 3]);
        sub.cancel();
      });
    });

    test('an older answer can never overwrite a newer one', () {
      fakeAsync((async) {
        final source = _Source()..rows = [_row('a', 1)];
        source.fetchGate = Completer<void>(); // the first load is slow
        final seen = <int>[];
        final sub = _repo(source)
            .watchUpcoming('room-1')
            .listen((items) => seen.add(items.length));
        async.flushMicrotasks();

        // A change arrives while the first load is still running.
        source.rows = [_row('a', 1), _row('b', 2)];
        source.onChange!();
        async.elapse(const Duration(seconds: 1));
        expect(source.fetches, 1); // not started in parallel

        source.fetchGate!.complete();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 1));
        // Loads ran one after the other: the last answer is the newest.
        expect(seen.last, 2);
        sub.cancel();
      });
    });

    test('a request that hangs fails after the timeout and does not freeze the '
        'stream', () {
      fakeAsync((async) {
        final source = _Source()..rows = [_row('a', 1)];
        source.fetchGate = Completer<void>(); // never completes
        final seen = <int>[];
        final errors = <Object>[];
        final sub = _repo(source)
            .watchUpcoming('room-1')
            .listen((items) => seen.add(items.length), onError: errors.add);
        async.elapse(requestTimeout + const Duration(seconds: 1));
        expect(errors.single, isA<QueueFailure>());
        expect(seen, isEmpty);

        // The network is back: the next change loads normally.
        source.fetchGate = null;
        source.onChange!();
        async.elapse(const Duration(seconds: 1));
        expect(seen, [1]);
        sub.cancel();
      });
    });

    test('a subscribe that throws is reported, not unhandled', () {
      fakeAsync((async) {
        final source = _Source()
          ..rows = [_row('a', 1)]
          ..subscribeError = StateError('socket');
        final errors = <Object>[];
        final seen = <int>[];
        final sub = _repo(source)
            .watchUpcoming('room-1')
            .listen((items) => seen.add(items.length), onError: errors.add);
        async.flushMicrotasks();
        expect(errors.single, isA<QueueFailure>());
        expect(seen, [1]); // the first load still worked
        sub.cancel();
      });
    });

    test('channel trouble is an error and the stream stays open', () {
      fakeAsync((async) {
        final source = _Source()..rows = [_row('a', 1)];
        final errors = <Object>[];
        final seen = <int>[];
        final sub = _repo(source)
            .watchUpcoming('room-1')
            .listen((items) => seen.add(items.length), onError: errors.add);
        async.flushMicrotasks();
        source.onStatus!(false);
        async.flushMicrotasks();
        expect(errors.single, isA<QueueFailure>());
        source.rows = [];
        source.onChange!();
        async.elapse(const Duration(seconds: 1));
        expect(seen.last, 0);
        sub.cancel();
      });
    });

    test('cancelling closes the channel and stops reloading', () {
      fakeAsync((async) {
        final source = _Source()..rows = [_row('a', 1)];
        final sub = _repo(source).watchUpcoming('room-1').listen((_) {});
        async.flushMicrotasks();
        source.onChange!();
        sub.cancel();
        async.elapse(const Duration(seconds: 2));
        expect(source.closed, 1);
        expect(source.fetches, 1); // the pending reload was dropped
        source.onChange!();
        source.onStatus!(true);
        async.elapse(const Duration(seconds: 2));
        expect(source.fetches, 1);
      });
    });
  });
}
