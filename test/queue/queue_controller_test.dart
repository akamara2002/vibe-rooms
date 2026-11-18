import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart' hide EnginePhase;
import 'package:vibe_rooms/features/auth/presentation/auth_providers.dart';
import 'package:vibe_rooms/features/player/domain/room_state.dart';
import 'package:vibe_rooms/features/player/domain/room_state_repository.dart';
import 'package:vibe_rooms/features/player/presentation/player_providers.dart';
import 'package:vibe_rooms/features/player/presentation/sync_controller.dart';
import 'package:vibe_rooms/features/player/presentation/sync_providers.dart';
import 'package:vibe_rooms/features/queue/domain/queue_failure.dart';
import 'package:vibe_rooms/features/queue/domain/queue_item.dart';
import 'package:vibe_rooms/features/queue/domain/queue_limits.dart';
import 'package:vibe_rooms/features/queue/presentation/queue_controller.dart';
import 'package:vibe_rooms/features/queue/presentation/queue_providers.dart';

import '../fakes/fakes.dart';

final _base = DateTime.utc(2026, 11, 18, 12);

/// A room on a fake clock: queue, room row, engine and server all fake.
class _Rig {
  _Rig(
    this.async, {
    this.isHost = true,
    List<QueueItem>? items,
    RoomState? row,
  }) {
    engine = FakeAudioEngine()..clock = trueNow;
    queue = FakeQueueRepository(items: items);
    state = FakeRoomStateRepository(
      current: row ?? playing(trackId: 'now', positionMs: 0),
      serverNow: trueNow,
    );
    container = ProviderContainer(
      overrides: [
        audioEngineFactoryProvider.overrideWithValue(() => engine),
        roomStateRepositoryProvider.overrideWithValue(state),
        serverTimeSourceProvider.overrideWithValue(
          FakeServerTimeSource(
            localNow: trueNow,
            rtt: const Duration(milliseconds: 40),
          ),
        ),
        localClockProvider.overrideWithValue(trueNow),
        soundGateRequiredProvider.overrideWithValue(false),
        musicCatalogProvider.overrideWithValue(FakeMusicCatalog()),
        queueRepositoryProvider.overrideWithValue(queue),
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(signedIn: true),
        ),
      ],
    );
    syncSub = container.listen(syncControllerProvider(args), (_, _) {});
    queueSub = container.listen(queueControllerProvider(args), (_, _) {});
    // Keep the queue stream alive like the screen does.
    container.listen(upcomingItemsProvider('room-1'), (_, _) {});
  }

  final FakeAsync async;
  final bool isHost;
  late final FakeAudioEngine engine;
  late final FakeQueueRepository queue;
  late final FakeRoomStateRepository state;
  late final ProviderContainer container;
  late final ProviderSubscription<SyncState> syncSub;
  late final ProviderSubscription<QueueState> queueSub;

  SyncArgs get args => (roomId: 'room-1', isHost: isHost);
  DateTime trueNow() => _base.add(async.elapsed);

  QueueController get controller =>
      container.read(queueControllerProvider(args).notifier);
  SyncController get sync =>
      container.read(syncControllerProvider(args).notifier);

  RoomState playing({
    String? trackId = 'now',
    int positionMs = 0,
    int durationMs = 240000,
    String? queueItemId,
    bool isPlaying = true,
    int agoMs = 0,
  }) => RoomState(
    roomId: 'room-1',
    queueItemId: queueItemId,
    trackId: trackId,
    title: 'Playing $trackId',
    artist: 'Someone',
    durationMs: durationMs,
    isPlaying: isPlaying,
    positionMs: positionMs,
    updatedAt: trueNow().subtract(Duration(milliseconds: agoMs)),
  );

  void elapse(Duration d) {
    async.elapse(d);
    async.flushMicrotasks();
  }

  Iterable<String> get playedIds =>
      queue.all.where((i) => i.playedAt != null).map((i) => i.id);
  Iterable<String> get upcomingIds => queue.upcomingNow.map((i) => i.id);

  void dispose() => container.dispose();
}

void main() {
  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

  void rigTest(
    String name,
    void Function(_Rig rig) body, {
    bool isHost = true,
    List<QueueItem> Function()? items,
    RoomState Function(_Rig rig)? row,
  }) {
    test(name, () {
      fakeAsync((async) {
        final rig = _Rig(async, isHost: isHost, items: items?.call());
        if (row != null) rig.state.current = row(rig);
        rig.elapse(const Duration(seconds: 1));
        body(rig);
        rig.dispose();
      });
    });
  }

  List<QueueItem> three() => [
    fakeQueueItem(id: 'c', sortKey: 30, addedBy: 'user-3', addedByName: 'Cy'),
    fakeQueueItem(id: 'a', sortKey: 10),
    fakeQueueItem(id: 'b', sortKey: 20),
  ];

  group('add', () {
    rigTest('adds a track and returns no failure', (rig) {
      QueueFailure? result = const QueueFailure(QueueFailureKind.unknown);
      rig.controller.add(fakeTrack(id: 'new')).then((r) => result = r);
      rig.elapse(const Duration(milliseconds: 10));
      expect(result, isNull);
      expect(rig.queue.calls, contains('add:new'));
      expect(rig.upcomingIds, hasLength(1));
    });

    rigTest('a duplicate is rejected with "Already in the queue"', (rig) {
      QueueFailure? result;
      rig.controller.add(fakeTrack(id: 'track-a')).then((r) => result = r);
      rig.elapse(const Duration(milliseconds: 10));
      expect(result!.kind, QueueFailureKind.duplicate);
      expect(result!.message, 'Already in the queue');
      expect(rig.queue.calls.where((c) => c.startsWith('add:')), isEmpty);
    }, items: () => [fakeQueueItem(id: 'a')]);

    rigTest(
      'a duplicate added a moment ago by someone else still counts (fresh read)',
      (rig) {
        // Added by another member; the stream has not delivered it yet.
        rig.queue.all.add(fakeQueueItem(id: 'z', trackId: 'hot', sortKey: 5));
        QueueFailure? result;
        rig.controller.add(fakeTrack(id: 'hot')).then((r) => result = r);
        rig.elapse(const Duration(milliseconds: 10));
        expect(result!.kind, QueueFailureKind.duplicate);
      },
    );

    rigTest(
      'the per-user limit',
      (rig) {
        QueueFailure? result;
        rig.controller.add(fakeTrack(id: 'extra')).then((r) => result = r);
        rig.elapse(const Duration(milliseconds: 10));
        expect(result!.kind, QueueFailureKind.full);
        expect(result!.message, contains('$maxUpcomingPerUser'));
      },
      items: () => [
        for (var i = 0; i < maxUpcomingPerUser; i++)
          fakeQueueItem(id: 'm$i', addedBy: 'user-1', sortKey: i),
      ],
    );

    rigTest(
      'the per-room limit',
      (rig) {
        QueueFailure? result;
        rig.controller.add(fakeTrack(id: 'extra')).then((r) => result = r);
        rig.elapse(const Duration(milliseconds: 10));
        expect(result!.kind, QueueFailureKind.full);
        expect(result!.message, contains('$maxUpcomingPerRoom'));
      },
      items: () => [
        for (var i = 0; i < maxUpcomingPerRoom; i++)
          fakeQueueItem(id: 'q$i', addedBy: 'other$i', sortKey: i),
      ],
      isHost: false,
    );

    rigTest('a database failure is reported, not thrown', (rig) {
      rig.queue.failNextAdd = const QueueFailure(QueueFailureKind.network);
      QueueFailure? result;
      rig.controller.add(fakeTrack(id: 'x')).then((r) => result = r);
      rig.elapse(const Duration(milliseconds: 10));
      expect(result!.kind, QueueFailureKind.network);
    });
  });

  group('remove permissions', () {
    // user-1 is me. 'a' was added by me, 'b' by user-2.
    List<QueueItem> mixed() => [
      fakeQueueItem(id: 'a', addedBy: 'user-1', sortKey: 1),
      fakeQueueItem(id: 'b', addedBy: 'user-2', sortKey: 2),
    ];

    for (final (name, isHost, id, allowed) in [
      ('the host removes their own', true, 'a', true),
      ('the host removes anyone\'s', true, 'b', true),
      ('a member removes their own', false, 'a', true),
      ('a member cannot remove someone else\'s', false, 'b', false),
    ]) {
      rigTest(
        name,
        (rig) {
          final item = rig.queue.byId(id)!;
          expect(rig.controller.canRemove(item), allowed);
          QueueFailure? result;
          rig.controller.remove(item).then((r) => result = r);
          rig.elapse(const Duration(milliseconds: 10));
          if (allowed) {
            expect(result, isNull);
            expect(rig.queue.byId(id), isNull);
          } else {
            expect(result!.kind, QueueFailureKind.notAllowed);
            // Refused before any request is sent.
            expect(rig.queue.calls, isNot(contains('remove:$id')));
            expect(rig.queue.byId(id), isNotNull);
          }
        },
        isHost: isHost,
        items: mixed,
      );
    }

    rigTest('a database refusal is reported', (rig) {
      rig.queue.failNextRemove = const QueueFailure(
        QueueFailureKind.notAllowed,
      );
      QueueFailure? result;
      rig.controller.remove(rig.queue.byId('a')!).then((r) => result = r);
      rig.elapse(const Duration(milliseconds: 10));
      expect(result!.kind, QueueFailureKind.notAllowed);
    }, items: mixed);
  });

  group('playNext', () {
    rigTest(
      'starts the lowest sort_key, marks it, and writes its data to the room',
      (rig) {
        String? problem = 'pending';
        rig.controller.playNext().then((r) => problem = r);
        rig.elapse(const Duration(milliseconds: 50));
        expect(problem, isNull);

        final write = rig.state.writes.single;
        expect(write['queue_item_id'], 'a');
        expect(write['track_id'], 'track-a');
        expect(write['title'], 'Song a');
        expect(write['artist'], 'Artist a');
        expect(write['duration_ms'], 200000);
        expect(write['position_ms'], 0);
        expect(write['is_playing'], true);
        expect(write.containsKey('updated_at'), isFalse);

        expect(rig.playedIds, ['a']);
        expect(rig.upcomingIds, ['b', 'c']);
        expect(rig.sync.hashCode, isNotNull);
        expect(rig.syncSub.read().room!.queueItemId, 'a');
      },
      items: three,
    );

    rigTest(
      'the room is written before the item is marked (and an item that was '
      'already marked is not marked twice)',
      (rig) {
        rig.controller.playNext();
        rig.elapse(const Duration(milliseconds: 50));
        rig.controller.playNext();
        rig.elapse(const Duration(milliseconds: 50));
        expect(rig.playedIds, unorderedEquals(['a', 'b']));
        expect(rig.queue.calls.where((c) => c.startsWith('mark:')).toList(), [
          'mark:a:now',
          'mark:b:now',
        ]);
        expect(rig.state.writes.map((w) => w['queue_item_id']), ['a', 'b']);
      },
      items: three,
    );

    rigTest('a failed room write changes nothing: no item is consumed', (rig) {
      rig.state.failNext = const RoomStateFailure(RoomStateFailureKind.network);
      String? problem;
      rig.controller.playNext().then((r) => problem = r);
      rig.elapse(const Duration(milliseconds: 50));
      expect(problem, isNotNull);
      expect(rig.queue.calls.where((c) => c.startsWith('mark:')), isEmpty);
      expect(rig.upcomingIds, ['a', 'b', 'c']);
      expect(rig.syncSub.read().room!.queueItemId, isNull);
      // And it can simply be tried again.
      rig.controller.playNext();
      rig.elapse(const Duration(milliseconds: 50));
      expect(rig.playedIds, ['a']);
    }, items: three);

    rigTest(
      'if marking fails, the song still plays, the item stays hidden, and it '
      'is healed later; it never replays',
      (rig) {
        rig.queue.failAllMarks = true;
        rig.controller.playNext();
        rig.elapse(const Duration(milliseconds: 50));
        expect(rig.syncSub.read().room!.queueItemId, 'a');
        expect(rig.playedIds, isEmpty); // the database still says upcoming
        // Everyone hides it anyway.
        expect(
          rig.container
              .read(visibleUpcomingProvider(rig.args))
              .value!
              .map((i) => i.id),
          ['b', 'c'],
        );

        rig.queue.failAllMarks = false; // the connection is back
        rig.queue.externalAdd(fakeQueueItem(id: 'd', sortKey: 40));
        rig.elapse(const Duration(seconds: 1));
        expect(rig.playedIds, ['a']); // healed by the host's reconcile

        // The next advance picks b, not a.
        rig.controller.playNext();
        rig.elapse(const Duration(milliseconds: 50));
        expect(rig.syncSub.read().room!.queueItemId, 'b');
      },
      items: three,
    );

    rigTest('an item that was playing but never marked is marked by the next '
        'advance, so it cannot come back', (rig) {
      rig.queue.failAllMarks = true;
      rig.controller.playNext(); // a plays, unmarked
      rig.elapse(const Duration(milliseconds: 50));
      rig.queue.failAllMarks = false;
      rig.controller.playNext(); // b plays; a must not reappear
      rig.elapse(const Duration(milliseconds: 50));
      expect(rig.playedIds, containsAll(['a', 'b']));
      expect(rig.upcomingIds, ['c']);
    }, items: three);

    rigTest('with an empty queue it writes the ended state', (rig) {
      rig.elapse(const Duration(seconds: 3));
      String? problem = 'pending';
      rig.controller.playNext().then((r) => problem = r);
      rig.elapse(const Duration(milliseconds: 50));
      expect(problem, isNull);
      expect(rig.state.writes.last, {
        'is_playing': false,
        'position_ms': 240000,
      });
    });
  });

  group('items the host cannot trust', () {
    List<QueueItem> mixed() => [
      fakeQueueItem(id: 'tiny', sortKey: 1, durationMs: 1),
      fakeQueueItem(id: 'huge', sortKey: 2, durationMs: 1 << 30),
      fakeQueueItem(id: 'ok', sortKey: 3),
    ];

    rigTest('an item with an implausible length is skipped and consumed', (
      rig,
    ) {
      rig.controller.playNext();
      rig.elapse(const Duration(milliseconds: 100));
      expect(rig.state.writes.single['queue_item_id'], 'ok');
      expect(rig.playedIds, unorderedEquals(['tiny', 'huge', 'ok']));
      expect(rig.upcomingIds, isEmpty);
    }, items: mixed);

    rigTest('Play now refuses such an item', (rig) {
      String? problem;
      rig.controller.playItem(rig.queue.byId('tiny')!).then((r) => problem = r);
      rig.elapse(const Duration(milliseconds: 100));
      expect(problem, "That song can't be played.");
      expect(rig.state.writes, isEmpty);
    }, items: mixed);

    rigTest(
      'a song the host started is never offered again, even if marking it '
      'keeps failing',
      (rig) {
        rig.queue.failAllMarks = true;
        rig.controller.playNext(); // a
        rig.elapse(const Duration(milliseconds: 100));
        rig.controller
            .playNext(); // b (a is now unmarked and no longer playing)
        rig.elapse(const Duration(milliseconds: 100));
        rig.controller.playNext(); // must be c, not a again
        rig.elapse(const Duration(milliseconds: 100));
        expect(rig.state.writes.map((w) => w['queue_item_id']), [
          'a',
          'b',
          'c',
        ]);
      },
      items: three,
    );
  });

  group('double advance', () {
    rigTest('two taps at once consume exactly one item', (rig) {
      rig.controller.playNext();
      rig.controller.playNext(); // the in-flight guard refuses this one
      rig.elapse(const Duration(seconds: 1));
      expect(rig.playedIds, ['a']);
      expect(rig.state.writes, hasLength(1));
    }, items: three);

    rigTest('a skip while the song ends naturally consumes exactly one item', (
      rig,
    ) {
      // The room is 100 ms from the end of the song.
      rig.state.emit(
        rig.playing(positionMs: 239900, agoMs: 0, queueItemId: null),
      );
      rig.elapse(const Duration(milliseconds: 50));
      rig.queue.markGate = Completer<void>(); // hold the skip half way
      rig.controller.playNext(); // the skip tap
      rig.elapse(const Duration(seconds: 5)); // the song ends meanwhile

      rig.queue.markGate!.complete();
      rig.queue.markGate = null;
      rig.elapse(const Duration(seconds: 10));

      expect(rig.playedIds, ['a']);
      expect(rig.upcomingIds, ['b', 'c']);
      expect(rig.syncSub.read().room!.queueItemId, 'a');
    }, items: three);

    rigTest('a stale end-of-song after a skip is ignored', (rig) {
      rig.elapse(const Duration(seconds: 2));
      final endedRow = rig.syncSub.read().room!;
      rig.controller.playNext(); // skip: the room moves on to a
      rig.elapse(const Duration(milliseconds: 100));

      TrackEndResult? result;
      rig.sync.onTrackEnded!(endedRow).then((r) => result = r);
      rig.elapse(const Duration(milliseconds: 100));
      expect(result, TrackEndResult.ignored);
      expect(rig.playedIds, ['a']);
      expect(rig.state.writes, hasLength(1));
    }, items: three);
  });

  group('playItem', () {
    rigTest('jumps to the chosen item and leaves the others', (rig) {
      String? problem = 'pending';
      rig.controller.playItem(rig.queue.byId('b')!).then((r) => problem = r);
      rig.elapse(const Duration(milliseconds: 50));
      expect(problem, isNull);
      expect(rig.state.writes.single['queue_item_id'], 'b');
      expect(rig.playedIds, ['b']);
      expect(rig.upcomingIds, ['a', 'c']);
    }, items: three);

    rigTest('an item that is gone is not played', (rig) {
      final stale = rig.queue.byId('b')!;
      rig.queue.all.removeWhere((i) => i.id == 'b'); // removed meanwhile
      String? problem;
      rig.controller.playItem(stale).then((r) => problem = r);
      rig.elapse(const Duration(milliseconds: 50));
      expect(problem, notInQueueMessage);
      expect(rig.state.writes, isEmpty);
    }, items: three);

    rigTest('an item that was already played is not played again', (rig) {
      final stale = rig.queue.byId('a')!;
      rig.controller.playNext(); // a is consumed by the natural advance
      rig.elapse(const Duration(milliseconds: 50));
      String? problem;
      rig.controller.playItem(stale).then((r) => problem = r);
      rig.elapse(const Duration(milliseconds: 50));
      expect(problem, notInQueueMessage);
      expect(rig.state.writes, hasLength(1));
    }, items: three);
  });

  group('end of the song', () {
    rigTest(
      'starts the next queued song, exactly once',
      (rig) {
        rig.elapse(const Duration(seconds: 40)); // the 20 s song is long over
        expect(rig.state.writes.map((w) => w['queue_item_id']), ['a']);
        expect(rig.playedIds, ['a']);
        expect(rig.upcomingIds, ['b', 'c']);
        expect(rig.engine.calls, contains('load:track-a'));
      },
      items: three,
      row: (rig) => rig.playing(positionMs: 10000, durationMs: 20000),
    );

    rigTest('and with nothing queued writes the ended state exactly once', (
      rig,
    ) {
      rig.state.autoEcho = false; // a lost echo must not cause repeats
      rig.elapse(const Duration(seconds: 60));
      final ends = rig.state.writes
          .where((w) => w['is_playing'] == false)
          .toList();
      expect(ends, hasLength(1));
      expect(ends.single['position_ms'], 20000);
    }, row: (rig) => rig.playing(positionMs: 10000, durationMs: 20000));

    rigTest(
      'plays the whole queue in order as songs end',
      (rig) {
        // Each queued song is 20 s long.
        for (var i = 0; i < 3; i++) {
          final id = ['a', 'b', 'c'][i];
          rig.queue.all[rig.queue.all.indexWhere((x) => x.id == id)] =
              fakeQueueItem(id: id, sortKey: (i + 1) * 10, durationMs: 20000);
        }
        rig.elapse(const Duration(seconds: 120));
        expect(rig.state.writes.map((w) => w['queue_item_id']).toList(), [
          'a',
          'b',
          'c',
          null,
        ]);
        expect(rig.upcomingIds, isEmpty);
        expect(rig.syncSub.read().room!.isPlaying, isFalse);
      },
      items: three,
      row: (rig) => rig.playing(positionMs: 10000, durationMs: 20000),
    );
  });

  group('failures at the end of a song', () {
    rigTest(
      'a failed advance is retried on a later tick, exactly once more',
      (rig) {
        rig.state.failNext = const RoomStateFailure(
          RoomStateFailureKind.network,
        );
        rig.elapse(const Duration(seconds: 40)); // the 20 s song is long over
        // The first write failed (and was not recorded); the retry worked.
        expect(
          rig.state.writes.where((w) => w['queue_item_id'] == 'a'),
          hasLength(1),
        );
        expect(rig.playedIds, ['a']);
        expect(rig.upcomingIds, ['b', 'c']);
      },
      items: three,
      row: (rig) => rig.playing(positionMs: 10000, durationMs: 20000),
    );

    rigTest('the end of a song during a skip answers "try again later"', (rig) {
      rig.elapse(const Duration(seconds: 1));
      final ended = rig.syncSub.read().room!;
      rig.queue.markGate = Completer<void>();
      rig.controller.playNext(); // the skip is held half way
      rig.elapse(const Duration(milliseconds: 100));
      TrackEndResult? result;
      rig.sync.onTrackEnded!(ended).then((r) => result = r);
      rig.elapse(const Duration(milliseconds: 100));
      expect(result, TrackEndResult.failed);
      rig.queue.markGate!.complete();
      rig.queue.markGate = null;
      rig.elapse(const Duration(seconds: 1));
      expect(rig.playedIds, ['a']);
    }, items: three);
  });

  group('the host methods of the sync controller', () {
    rigTest(
      'a member calling hostAdvanceTo or hostEnd writes nothing',
      (rig) {
        bool? advanced = true;
        bool? ended = true;
        rig.sync.hostAdvanceTo(rig.queue.byId('a')!).then((r) => advanced = r);
        rig.sync.hostEnd().then((r) => ended = r);
        rig.elapse(const Duration(seconds: 1));
        expect(advanced, isFalse);
        expect(ended, isFalse);
        expect(rig.state.writes, isEmpty);
        expect(rig.syncSub.read().errorMessage, hostOnlyMessage);
      },
      isHost: false,
      items: three,
    );

    rigTest(
      'hostEnd without a known duration writes nothing',
      (rig) {
        bool? ended = true;
        rig.sync.hostEnd().then((r) => ended = r);
        rig.elapse(const Duration(seconds: 1));
        expect(ended, isFalse);
        expect(rig.state.writes, isEmpty);
      },
      row: (rig) => RoomState(
        roomId: 'room-1',
        trackId: 'now',
        isPlaying: true,
        positionMs: 0,
        updatedAt: rig.trueNow(),
      ),
    );
  });

  group('remove', () {
    rigTest('a double tap sends one delete', (rig) {
      final item = rig.queue.byId('a')!;
      rig.controller.remove(item);
      rig.controller.remove(item);
      rig.elapse(const Duration(milliseconds: 50));
      expect(rig.queue.calls.where((c) => c == 'remove:a'), hasLength(1));
      expect(rig.queue.byId('a'), isNull);
    }, items: three);

    rigTest(
      'removing the song that is playing leaves the pinned row and the list '
      'consistent',
      (rig) {
        rig.controller.playNext(); // a plays
        rig.elapse(const Duration(milliseconds: 100));
        rig.queue.all.removeWhere(
          (i) => i.id == 'a',
        ); // the database deletes it
        rig.queue.externalAdd(fakeQueueItem(id: 'z', sortKey: 99));
        rig.elapse(const Duration(seconds: 1));
        expect(
          rig.container
              .read(visibleUpcomingProvider(rig.args))
              .value!
              .map((i) => i.id),
          ['b', 'c', 'z'],
        );
        // The room still shows the song; the next advance picks b.
        expect(rig.syncSub.read().room!.title, 'Song a');
        rig.controller.playNext();
        rig.elapse(const Duration(milliseconds: 100));
        expect(rig.syncSub.read().room!.queueItemId, 'b');
      },
      items: three,
    );
  });

  group('a listener or member', () {
    rigTest(
      'cannot advance: the host methods write nothing',
      (rig) {
        String? next;
        String? item;
        rig.controller.playNext().then((r) => next = r);
        rig.controller.playItem(rig.queue.byId('a')!).then((r) => item = r);
        rig.elapse(const Duration(seconds: 1));
        expect(next, hostOnlyMessage);
        expect(item, hostOnlyMessage);
        expect(rig.state.writes, isEmpty);
        expect(rig.queue.calls.where((c) => c.startsWith('mark:')), isEmpty);
        expect(rig.playedIds, isEmpty);
      },
      isHost: false,
      items: three,
    );

    rigTest(
      'does not react to the end of a song (only the host advances)',
      (rig) {
        rig.elapse(const Duration(seconds: 60));
        expect(rig.state.writes, isEmpty);
        expect(rig.playedIds, isEmpty);
        expect(rig.sync.onTrackEnded, isNull);
      },
      isHost: false,
      items: three,
      row: (rig) => rig.playing(positionMs: 10000, durationMs: 20000),
    );
  });

  group('leaving the room', () {
    test('releases the queue stream and the end-of-song hook', () {
      fakeAsync((async) {
        final rig = _Rig(async, items: three());
        rig.elapse(const Duration(seconds: 1));
        expect(rig.queue.watchCount, 1);
        expect(rig.sync.onTrackEnded, isNotNull);
        final sync = rig.sync;
        rig.dispose();
        async.flushMicrotasks();
        expect(rig.queue.cancelCount, 1);
        expect(sync.onTrackEnded, isNull);
        expect(async.periodicTimerCount, 0);
      });
    });
  });
}
