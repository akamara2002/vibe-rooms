import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart' hide EnginePhase;
import 'package:vibe_rooms/features/player/domain/audio_engine.dart';
import 'package:vibe_rooms/features/player/domain/room_state.dart';
import 'package:vibe_rooms/features/player/domain/room_state_repository.dart';
import 'package:vibe_rooms/features/player/domain/sync_status.dart';
import 'package:vibe_rooms/features/player/presentation/player_providers.dart';
import 'package:vibe_rooms/features/player/presentation/sync_controller.dart';
import 'package:vibe_rooms/features/player/presentation/sync_providers.dart';

import '../fakes/fakes.dart';

final _base = DateTime.utc(2026, 11, 18, 12);

/// Everything a SyncController needs, on a fake clock.
class _Rig {
  _Rig(
    this.async, {
    this.isHost = false,
    bool sound = true,
    this.deviceSkew = Duration.zero,
    Duration rtt = const Duration(milliseconds: 40),
    Duration loadDelay = Duration.zero,
    Duration seekDelay = Duration.zero,
    RoomState? row,
  }) {
    engine = FakeAudioEngine()
      ..clock = trueNow
      ..loadDelay = loadDelay
      ..seekDelay = seekDelay;
    repo = FakeRoomStateRepository(current: row ?? _row(), serverNow: trueNow);
    time = FakeServerTimeSource(localNow: trueNow, rtt: rtt);
    container = ProviderContainer(
      overrides: [
        audioEngineFactoryProvider.overrideWithValue(() => engine),
        roomStateRepositoryProvider.overrideWithValue(repo),
        serverTimeSourceProvider.overrideWithValue(time),
        localClockProvider.overrideWithValue(deviceNow),
        soundGateRequiredProvider.overrideWithValue(!sound),
        musicCatalogProvider.overrideWithValue(FakeMusicCatalog()),
      ],
    );
    subscription = container.listen(syncControllerProvider(args), (_, _) {});
  }

  final FakeAsync async;
  final bool isHost;
  final Duration deviceSkew;
  late final FakeAudioEngine engine;
  late final FakeRoomStateRepository repo;
  late final FakeServerTimeSource time;
  late final ProviderContainer container;
  late final ProviderSubscription<SyncState> subscription;

  SyncArgs get args => (roomId: 'room-1', isHost: isHost);

  DateTime trueNow() => _base.add(async.elapsed);
  DateTime deviceNow() => trueNow().add(deviceSkew);

  SyncState get state => subscription.read();
  SyncController get controller =>
      container.read(syncControllerProvider(args).notifier);

  /// A row anchored [agoMs] ago at the TRUE server time.
  RoomState _row({
    String? trackId = 't1',
    bool playing = true,
    int positionMs = 30000,
    int agoMs = 0,
    int? durationMs = 240000,
  }) => fakeRoomState(
    trackId: trackId,
    title: 'Song $trackId',
    artist: 'Artist',
    durationMs: durationMs,
    isPlaying: playing,
    positionMs: positionMs,
    updatedAt: trueNow().subtract(Duration(milliseconds: agoMs)),
  );

  RoomState row({
    String? trackId = 't1',
    bool playing = true,
    int positionMs = 30000,
    int agoMs = 0,
    int? durationMs = 240000,
  }) => _row(
    trackId: trackId,
    playing: playing,
    positionMs: positionMs,
    agoMs: agoMs,
    durationMs: durationMs,
  );

  void elapse(Duration d) {
    async.elapse(d);
    async.flushMicrotasks();
  }

  /// The position the room says playback is at, right now, in true time.
  int expectedNow() => repo.current!.expectedPositionMs(trueNow());

  void dispose() => container.dispose();
}

void main() {
  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

  void rigTest(
    String name,
    void Function(_Rig rig) body, {
    bool isHost = false,
    bool sound = true,
    Duration deviceSkew = Duration.zero,
    Duration rtt = const Duration(milliseconds: 40),
    Duration loadDelay = Duration.zero,
    Duration seekDelay = Duration.zero,
    RoomState Function(_Rig rig)? row,
  }) {
    test(name, () {
      fakeAsync((async) {
        late final _Rig rig;
        rig = _Rig(
          async,
          isHost: isHost,
          sound: sound,
          deviceSkew: deviceSkew,
          rtt: rtt,
          loadDelay: loadDelay,
          seekDelay: seekDelay,
        );
        if (row != null) rig.repo.current = row(rig);
        rig.elapse(const Duration(milliseconds: 1));
        body(rig);
        rig.dispose();
      });
    });
  }

  group('a late joiner', () {
    rigTest(
      'rejoins at the room position, with a 2 second load',
      (rig) {
        rig.elapse(const Duration(seconds: 5));
        final plays = rig.engine.calls.where((c) => c.startsWith('playFrom:'));
        expect(rig.engine.calls, contains('load:t1'));
        expect(plays, isNotEmpty);
        final target = int.parse(plays.last.split(':').last);
        // The row said 30s, anchored 10s before the joiner arrived; the load
        // took 2s. The engine started where the room is NOW, not where it was
        // when the load began.
        expect(rig.engine.phase, EnginePhase.playing);
        expect(
          (rig.engine.position.inMilliseconds - rig.expectedNow()).abs(),
          lessThan(300),
        );
        expect(target, greaterThan(40000 + 1900));
        expect(rig.state.status, SyncStatus.inSync);
      },
      loadDelay: const Duration(seconds: 2),
      row: (rig) => rig.row(positionMs: 30000, agoMs: 10000),
    );

    rigTest(
      'a phone with a clock 5 minutes fast still lands on the right spot',
      (rig) {
        rig.elapse(const Duration(seconds: 3));
        expect(rig.engine.phase, EnginePhase.playing);
        expect(
          (rig.engine.position.inMilliseconds - rig.expectedNow()).abs(),
          lessThan(300),
        );
      },
      deviceSkew: const Duration(minutes: 5),
    );

    rigTest(
      'without sound it loads, then waits for the tap and starts in place',
      (rig) {
        rig.elapse(const Duration(seconds: 3));
        expect(rig.engine.calls, contains('load:t1'));
        expect(
          rig.engine.calls.where((c) => c.startsWith('playFrom')),
          isEmpty,
        );
        expect(rig.state.status, SyncStatus.waitingForSound);

        rig.container.read(soundEnabledProvider.notifier).enable();
        rig.elapse(const Duration(milliseconds: 50));
        expect(rig.engine.phase, EnginePhase.playing);
        expect(
          (rig.engine.position.inMilliseconds - rig.expectedNow()).abs(),
          lessThan(300),
        );
        expect(rig.state.status, SyncStatus.inSync);
      },
      sound: false,
    );
  });

  group('following the host', () {
    rigTest('pause and resume reach a listener', (rig) {
      rig.elapse(const Duration(seconds: 3));
      expect(rig.engine.phase, EnginePhase.playing);

      final pausedAt = rig.engine.position.inMilliseconds;
      rig.repo.emit(rig.row(playing: false, positionMs: pausedAt, agoMs: 0));
      rig.elapse(const Duration(milliseconds: 100));
      expect(rig.engine.phase, EnginePhase.paused);
      expect(rig.state.room!.isPlaying, isFalse);

      // The room stays paused for a while, then resumes.
      rig.elapse(const Duration(seconds: 4));
      rig.repo.emit(rig.row(playing: true, positionMs: pausedAt, agoMs: 0));
      rig.elapse(const Duration(milliseconds: 100));
      expect(rig.engine.phase, EnginePhase.playing);
      expect(
        (rig.engine.position.inMilliseconds - rig.expectedNow()).abs(),
        lessThan(300),
      );
    });

    rigTest('a host seek moves the listener', (rig) {
      rig.elapse(const Duration(seconds: 3));
      rig.repo.emit(rig.row(positionMs: 120000));
      rig.elapse(const Duration(milliseconds: 100));
      expect(
        (rig.engine.position.inMilliseconds - rig.expectedNow()).abs(),
        lessThan(300),
      );
      expect(rig.engine.position.inMilliseconds, greaterThan(119000));
    });

    rigTest('a track change reloads and starts at the right position', (rig) {
      rig.elapse(const Duration(seconds: 3));
      rig.repo.emit(rig.row(trackId: 't2', positionMs: 0));
      rig.elapse(const Duration(seconds: 1));
      expect(rig.engine.calls.where((c) => c.startsWith('load:')), [
        'load:t1',
        'load:t2',
      ]);
      expect(rig.engine.phase, EnginePhase.playing);
      expect(rig.state.room!.trackId, 't2');
      expect(
        (rig.engine.position.inMilliseconds - rig.expectedNow()).abs(),
        lessThan(300),
      );
    });

    rigTest(
      'a row that carries a new queue_item_id makes the listener play that song',
      (rig) {
        rig.elapse(const Duration(seconds: 3));
        expect(rig.engine.calls, contains('load:t1'));

        // The host's queue advanced: a new track, linked to a queue item.
        rig.repo.emit(
          RoomState(
            roomId: 'room-1',
            queueItemId: 'item-7',
            trackId: 'queued-track',
            title: 'From the queue',
            artist: 'Someone',
            durationMs: 200000,
            isPlaying: true,
            positionMs: 0,
            updatedAt: rig.trueNow(),
          ),
        );
        rig.elapse(const Duration(seconds: 1));

        expect(rig.state.room!.queueItemId, 'item-7');
        expect(rig.state.room!.title, 'From the queue');
        expect(rig.engine.calls, contains('load:queued-track'));
        expect(rig.engine.phase, EnginePhase.playing);
        expect(
          (rig.engine.position.inMilliseconds - rig.expectedNow()).abs(),
          lessThan(300),
        );
        // The listener never wrote anything.
        expect(rig.repo.writes, isEmpty);
      },
    );

    rigTest('an event older than the newest is ignored', (rig) {
      rig.elapse(const Duration(seconds: 3));
      final newer = rig.row(positionMs: 100000);
      rig.repo.emit(newer);
      rig.elapse(const Duration(milliseconds: 100));
      rig.repo.emit(rig.row(positionMs: 5000, agoMs: 8000)); // older anchor
      rig.elapse(const Duration(milliseconds: 100));
      expect(rig.state.room!.positionMs, 100000);
    });

    rigTest('small drift is left alone, large drift is corrected', (rig) {
      rig.elapse(const Duration(seconds: 3));
      final seeksBefore = rig.engine.calls
          .where((c) => c.startsWith('seek'))
          .length;

      // 200 ms off: below the threshold.
      rig.engine.emitPosition(
        rig.engine.position + const Duration(milliseconds: 200),
      );
      rig.elapse(const Duration(seconds: 6));
      expect(
        rig.engine.calls.where((c) => c.startsWith('seek')).length,
        seeksBefore,
      );

      // 1.5 s off: seek back.
      rig.engine.emitPosition(
        rig.engine.position + const Duration(milliseconds: 1500),
      );
      rig.elapse(const Duration(seconds: 6));
      expect(
        rig.engine.calls.where((c) => c.startsWith('seek')).length,
        seeksBefore + 1,
      );
      expect(
        (rig.engine.position.inMilliseconds - rig.expectedNow()).abs(),
        lessThan(400),
      );
    });

    rigTest('drift is not corrected while the engine is buffering', (rig) {
      rig.elapse(const Duration(seconds: 3));
      rig.engine.emitPhase(EnginePhase.buffering);
      rig.engine.emitPosition(const Duration(seconds: 1));
      final before = rig.engine.calls.length;
      rig.elapse(const Duration(seconds: 10));
      expect(rig.engine.calls.length, before);
    });

    rigTest('a load error is retried, but not in a tight loop', (rig) {
      rig.engine.failNextLoad = true;
      rig.repo.emit(rig.row(trackId: 't2'));
      rig.elapse(const Duration(seconds: 2));
      expect(rig.state.errorMessage, isNotNull);
      int loads() =>
          rig.engine.calls.where((c) => c.startsWith('load:t2')).length;
      expect(loads(), 1);
      rig.elapse(const Duration(seconds: 12));
      expect(loads(), inInclusiveRange(2, 4));
      expect(rig.engine.phase, EnginePhase.playing);
      expect(rig.state.errorMessage, isNull);
    });
  });

  group('serialised actions', () {
    rigTest(
      'two actions never overlap, however fast rows arrive',
      (rig) {
        rig.elapse(const Duration(milliseconds: 100));
        for (var i = 0; i < 6; i++) {
          rig.repo.emit(
            rig.row(trackId: 't${i % 2 + 1}', positionMs: i * 20000),
          );
          rig.elapse(const Duration(milliseconds: 150));
        }
        rig.elapse(const Duration(seconds: 10));
        expect(rig.engine.maxInFlight, 1);
        expect(rig.engine.phase, EnginePhase.playing);
        expect(rig.state.room!.positionMs, 100000);
      },
      loadDelay: const Duration(milliseconds: 600),
      seekDelay: const Duration(milliseconds: 300),
    );
  });

  group('clock', () {
    rigTest('is measured on entry, every 60 seconds and on resume', (rig) {
      rig.elapse(const Duration(seconds: 1));
      expect(rig.time.calls, 5);
      rig.elapse(const Duration(seconds: 60));
      expect(rig.time.calls, 10);
      rig.elapse(const Duration(seconds: 60));
      expect(rig.time.calls, 15);

      WidgetsBinding.instance
        ..handleAppLifecycleStateChanged(AppLifecycleState.paused)
        ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      rig.elapse(const Duration(seconds: 1));
      expect(rig.time.calls, 20);
    });

    rigTest('is measured again after a reconnect', (rig) {
      rig.elapse(const Duration(seconds: 3));
      final before = rig.time.calls;
      rig.repo.emitError();
      rig.elapse(const Duration(milliseconds: 10));
      expect(rig.state.status, SyncStatus.reconnecting);
      expect(rig.time.calls, before);

      rig.repo.emit(rig.row(positionMs: 50000));
      rig.elapse(const Duration(seconds: 1));
      expect(rig.state.status, isNot(SyncStatus.reconnecting));
      expect(rig.time.calls, before + 5);
    });

    rigTest('a resume reads the row again', (rig) {
      rig.elapse(const Duration(seconds: 3));
      // The host changed the song while the app was away: no event arrived.
      rig.repo.current = rig.row(trackId: 't3', positionMs: 0);
      WidgetsBinding.instance
        ..handleAppLifecycleStateChanged(AppLifecycleState.paused)
        ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      rig.elapse(const Duration(seconds: 2));
      expect(rig.state.room!.trackId, 't3');
      expect(rig.engine.calls, contains('load:t3'));
    });

    rigTest('nothing plays until the clock is measured', (rig) {
      rig.time.failing = true;
      rig.elapse(const Duration(seconds: 10));
      expect(rig.engine.calls, isEmpty);
      expect(rig.state.status, SyncStatus.syncing);

      rig.time.failing = false; // the next tick measures again
      rig.elapse(const Duration(seconds: 4));
      expect(rig.engine.calls, contains('load:t1'));
      expect(rig.engine.phase, EnginePhase.playing);
    });
  });

  group('the host', () {
    rigTest(
      'pause writes the engine position, and resume adds half the round trip',
      (rig) {
        rig.elapse(const Duration(seconds: 3));
        final enginePos = rig.engine.position.inMilliseconds;

        rig.controller.hostTogglePlay(); // pause
        rig.elapse(const Duration(milliseconds: 10));
        expect(rig.repo.writes.last, {
          'is_playing': false,
          'position_ms': enginePos,
        });
        expect(rig.engine.phase, EnginePhase.paused);

        rig.elapse(const Duration(seconds: 2));
        rig.controller.hostTogglePlay(); // resume
        rig.elapse(const Duration(milliseconds: 10));
        final write = rig.repo.writes.last;
        expect(write['is_playing'], true);
        // 40 ms round trip: half of it is 20 ms.
        expect(write['position_ms'], enginePos + 20);
        expect(rig.engine.phase, EnginePhase.playing);
      },
      isHost: true,
    );

    rigTest(
      'latency compensation is capped at 1.5 seconds',
      (rig) {
        rig.elapse(const Duration(seconds: 30));
        expect(rig.time.calls, greaterThanOrEqualTo(5));
        rig.controller.hostTogglePlay(); // pause
        rig.elapse(const Duration(milliseconds: 10));
        final pausedAt = rig.repo.writes.last['position_ms'] as int;
        rig.controller.hostTogglePlay(); // resume
        rig.elapse(const Duration(milliseconds: 10));
        expect(rig.repo.writes.last['position_ms'], pausedAt + 1500);
      },
      isHost: true,
      rtt: const Duration(seconds: 4),
    );

    rigTest('a seek while playing is compensated, while paused it is not', (
      rig,
    ) {
      rig.elapse(const Duration(seconds: 3));
      rig.controller.hostSeek(const Duration(seconds: 60));
      rig.elapse(const Duration(milliseconds: 10));
      expect(rig.repo.writes.last, {'is_playing': true, 'position_ms': 60020});

      rig.controller.hostTogglePlay(); // pause
      rig.elapse(const Duration(milliseconds: 10));
      rig.controller.hostSeek(const Duration(seconds: 90));
      rig.elapse(const Duration(milliseconds: 10));
      expect(rig.repo.writes.last, {'is_playing': false, 'position_ms': 90000});
    }, isHost: true);

    rigTest(
      'the echo of my own write finds no drift, so nothing is corrected',
      (rig) {
        rig.elapse(const Duration(seconds: 3));
        rig.controller.hostTogglePlay(); // pause
        rig.elapse(const Duration(seconds: 1));
        rig.controller.hostTogglePlay(); // resume
        rig.elapse(const Duration(seconds: 1));
        final before = List.of(rig.engine.calls);
        rig.elapse(const Duration(seconds: 10));
        expect(rig.engine.calls, before);
        expect(rig.engine.phase, EnginePhase.playing);
        expect(rig.state.status, SyncStatus.inSync);
      },
      isHost: true,
    );

    rigTest(
      'setTrack writes the whole track, starts at 0 and unlocks sound',
      (rig) {
        rig.controller.hostSetTrack(fakeTrack(id: 'new', title: 'New song'));
        rig.elapse(const Duration(seconds: 1));
        final write = rig.repo.writes.single;
        expect(write['track_id'], 'new');
        expect(write['title'], 'New song');
        expect(write['position_ms'], 0);
        expect(write['is_playing'], true);
        expect(write['queue_item_id'], isNull);
        expect(write.containsKey('updated_at'), isFalse);
        expect(rig.container.read(soundEnabledProvider), isTrue);
        expect(rig.engine.calls, contains('load:new'));
        expect(rig.engine.phase, EnginePhase.playing);
        expect(rig.state.room!.title, 'New song');
      },
      isHost: true,
      sound: false,
      row: (rig) => rig.row(trackId: null, playing: false, positionMs: 0),
    );

    rigTest('a failed write is undone and explained', (rig) {
      rig.elapse(const Duration(seconds: 3));
      rig.repo.failNext = const RoomStateFailure(
        RoomStateFailureKind.notAllowed,
      );
      rig.controller.hostTogglePlay();
      rig.elapse(const Duration(seconds: 1));
      expect(rig.state.errorMessage, hostOnlyMessageForTest);
      expect(rig.state.room!.isPlaying, isTrue);
      expect(rig.engine.phase, EnginePhase.playing);
    }, isHost: true);

    rigTest(
      'the end of the track is written exactly once',
      (rig) {
        rig.repo.autoEcho = false; // a lost echo must not cause repeats
        rig.elapse(const Duration(seconds: 3));
        rig.elapse(const Duration(seconds: 40));
        final ends = rig.repo.writes
            .where((w) => w['is_playing'] == false && w['position_ms'] == 20000)
            .toList();
        expect(ends, hasLength(1));
        expect(rig.engine.phase, isNot(EnginePhase.playing));
      },
      isHost: true,
      row: (rig) => rig.row(positionMs: 10000, durationMs: 20000),
    );

    rigTest(
      'a restart after the end begins at 0',
      (rig) {
        rig.elapse(const Duration(seconds: 2));
        rig.controller.hostTogglePlay();
        rig.elapse(const Duration(milliseconds: 100));
        expect(rig.repo.writes.last['is_playing'], true);
        expect(rig.repo.writes.last['position_ms'], 20);
      },
      isHost: true,
      row: (rig) =>
          rig.row(playing: false, positionMs: 20000, durationMs: 20000),
    );
  });

  group('a failed host write', () {
    rigTest('does not overwrite a newer row that arrived meanwhile', (rig) {
      rig.elapse(const Duration(seconds: 3));
      rig.repo.failNext = const RoomStateFailure(RoomStateFailureKind.network);
      // The write fails, but before that a fresher row from the server
      // (another action of mine, or a late event) is applied.
      rig.controller.hostSeek(const Duration(seconds: 100));
      rig.repo.emit(rig.row(positionMs: 150000));
      rig.elapse(const Duration(seconds: 1));
      expect(rig.state.room!.positionMs, 150000);
    }, isHost: true);
  });

  group('a listener', () {
    rigTest('cannot control playback: nothing is written', (rig) {
      rig.elapse(const Duration(seconds: 3));
      rig.controller.hostTogglePlay();
      rig.controller.hostSeek(const Duration(seconds: 10));
      rig.controller.hostSetTrack(fakeTrack());
      rig.elapse(const Duration(seconds: 1));
      expect(rig.repo.writes, isEmpty);
      expect(rig.state.errorMessage, hostOnlyMessageForTest);
    });

    rigTest('can mute locally, which does not touch the room', (rig) {
      rig.elapse(const Duration(seconds: 3));
      rig.controller.toggleMute();
      rig.elapse(const Duration(milliseconds: 10));
      expect(rig.engine.volume, 0);
      expect(rig.state.muted, isTrue);
      expect(rig.engine.phase, EnginePhase.playing);
      rig.controller.toggleMute();
      rig.elapse(const Duration(milliseconds: 10));
      expect(rig.engine.volume, 1);
      expect(rig.repo.writes, isEmpty);
    });

    rigTest('an ended room shows Ended and stops the engine', (rig) {
      rig.elapse(const Duration(seconds: 3));
      rig.repo.emit(
        rig.row(playing: false, positionMs: 240000, durationMs: 240000),
      );
      rig.elapse(const Duration(seconds: 1));
      expect(rig.state.status, SyncStatus.ended);
      expect(rig.engine.phase, isNot(EnginePhase.playing));
    });
  });

  group('leaving the room', () {
    test('disposes the engine, the subscription and every timer', () {
      fakeAsync((async) {
        final rig = _Rig(async);
        rig.elapse(const Duration(seconds: 5));
        expect(rig.repo.watchCount, 1);
        expect(async.periodicTimerCount, greaterThan(0));
        final calls = rig.time.calls;

        rig.dispose();
        async.flushMicrotasks();

        expect(rig.engine.disposed, isTrue);
        expect(rig.repo.cancelCount, 1);
        expect(async.periodicTimerCount, 0);
        // And nothing runs afterwards.
        async.elapse(const Duration(minutes: 5));
        expect(rig.time.calls, calls);
        expect(async.nonPeriodicTimerCount, 0);
      });
    });
  });
}

const hostOnlyMessageForTest = 'Only the host can control the music.';
