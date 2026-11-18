import 'package:flutter_test/flutter_test.dart' hide EnginePhase;
import 'package:vibe_rooms/features/player/domain/audio_engine.dart';
import 'package:vibe_rooms/features/player/domain/room_state.dart';
import 'package:vibe_rooms/features/player/domain/sync_config.dart';
import 'package:vibe_rooms/features/player/domain/sync_planner.dart';

final _now = DateTime.utc(2026, 11, 18, 12, 0, 30);

/// A row whose anchor was stamped [agoMs] ago.
RoomState _row({
  String? trackId = 't1',
  bool playing = true,
  int positionMs = 10000,
  int agoMs = 0,
  int? durationMs = 200000,
}) => RoomState(
  roomId: 'r',
  trackId: trackId,
  durationMs: durationMs,
  isPlaying: playing,
  positionMs: positionMs,
  updatedAt: _now.subtract(Duration(milliseconds: agoMs)),
);

SyncAction _plan({
  RoomState? state,
  String? loaded = 't1',
  EnginePhase phase = EnginePhase.playing,
  int engineMs = 0,
  bool sound = true,
  int? lastSeekAgoMs,
}) => planSync(
  SyncInput(
    state: state,
    loadedTrackId: loaded,
    phase: phase,
    enginePosition: Duration(milliseconds: engineMs),
    serverNow: _now,
    soundEnabled: sound,
    lastSeekAt: lastSeekAgoMs == null
        ? null
        : _now.subtract(Duration(milliseconds: lastSeekAgoMs)),
  ),
);

void main() {
  group('nothing to do', () {
    test('no row yet', () => expect(_plan(state: null), isA<SyncNone>()));
    test(
      'a row without a track',
      () => expect(_plan(state: _row(trackId: null)), isA<SyncNone>()),
    );
  });

  group('late joiner mid-song', () {
    test('loads the track first (nothing loaded yet)', () {
      final action = _plan(
        state: _row(positionMs: 10000, agoMs: 5000),
        loaded: null,
        phase: EnginePhase.idle,
      );
      expect(action, isA<SyncLoadThenPlay>());
      expect((action as SyncLoadThenPlay).trackId, 't1');
    });

    test('once loaded it plays from the expected position', () {
      final action = _plan(
        state: _row(positionMs: 10000, agoMs: 5000),
        phase: EnginePhase.ready,
      );
      expect(action, isA<SyncPlay>());
      expect((action as SyncPlay).seekToMs, 15000);
    });

    test('a 2 second load is covered: the plan uses the time it is asked', () {
      final state = _row(positionMs: 10000, agoMs: 5000);
      final before = planSync(
        SyncInput(
          state: state,
          loadedTrackId: 't1',
          phase: EnginePhase.ready,
          enginePosition: Duration.zero,
          serverNow: _now,
          soundEnabled: true,
          lastSeekAt: null,
        ),
      );
      final after = planSync(
        SyncInput(
          state: state,
          loadedTrackId: 't1',
          phase: EnginePhase.ready,
          enginePosition: Duration.zero,
          serverNow: _now.add(const Duration(seconds: 2)),
          soundEnabled: true,
          lastSeekAt: null,
        ),
      );
      expect((before as SyncPlay).seekToMs, 15000);
      expect((after as SyncPlay).seekToMs, 17000);
    });
  });

  group('a paused room', () {
    test('an unloaded track is still loaded (paused)', () {
      expect(
        _plan(
          state: _row(playing: false),
          loaded: null,
          phase: EnginePhase.idle,
        ),
        isA<SyncLoadThenPlay>(),
      );
    });

    test('a playing engine is paused at the stored position', () {
      final action = _plan(
        state: _row(playing: false, positionMs: 30000),
        engineMs: 30100,
      );
      expect(action, isA<SyncPause>());
      expect((action as SyncPause).seekToMs, 30000);
    });

    test('a loaded, paused engine far from the position seeks there', () {
      final action = _plan(
        state: _row(playing: false, positionMs: 30000),
        phase: EnginePhase.paused,
        engineMs: 0,
      );
      expect(action, isA<SyncSeek>());
      expect((action as SyncSeek).toMs, 30000);
    });

    test('a paused engine at the position does nothing', () {
      expect(
        _plan(
          state: _row(playing: false, positionMs: 30000),
          phase: EnginePhase.paused,
          engineMs: 30050,
        ),
        isA<SyncNone>(),
      );
    });

    test('it needs no sound to stay paused', () {
      expect(
        _plan(
          state: _row(playing: false, positionMs: 30000),
          phase: EnginePhase.paused,
          engineMs: 30000,
          sound: false,
        ),
        isA<SyncNone>(),
      );
    });
  });

  group('resume', () {
    test('a paused engine in a playing room plays from the expected spot', () {
      final action = _plan(
        state: _row(positionMs: 30000, agoMs: 400),
        phase: EnginePhase.paused,
        engineMs: 30000,
      );
      expect((action as SyncPlay).seekToMs, 30400);
    });

    test('an engine that finished its load (ready) plays', () {
      expect(_plan(state: _row(), phase: EnginePhase.ready), isA<SyncPlay>());
    });
  });

  group('drift', () {
    test('a host seek: far from expected, seek there', () {
      final action = _plan(
        state: _row(positionMs: 60000, agoMs: 100),
        engineMs: 20000,
      );
      expect((action as SyncSeek).toMs, 60100);
    });

    test('under the threshold is ignored (either direction)', () {
      final state = _row(positionMs: 10000, agoMs: 0);
      expect(_plan(state: state, engineMs: 10250), isA<SyncNone>());
      expect(_plan(state: state, engineMs: 9750), isA<SyncNone>());
      expect(_plan(state: state, engineMs: 10300), isA<SyncNone>());
    });

    test('over the threshold is corrected', () {
      final state = _row(positionMs: 10000, agoMs: 0);
      expect(_plan(state: state, engineMs: 10350), isA<SyncSeek>());
      expect(_plan(state: state, engineMs: 9650), isA<SyncSeek>());
    });

    test('thrash guard: a recent seek blocks a small correction', () {
      final state = _row(positionMs: 10000);
      expect(
        _plan(state: state, engineMs: 10500, lastSeekAgoMs: 2000),
        isA<SyncNone>(),
      );
      expect(
        _plan(state: state, engineMs: 10500, lastSeekAgoMs: 5000),
        isA<SyncSeek>(),
      );
      expect(
        _plan(state: state, engineMs: 10500, lastSeekAgoMs: 60000),
        isA<SyncSeek>(),
      );
    });

    test('hard limit: big drift is corrected inside the guard window', () {
      final state = _row(positionMs: 10000);
      expect(
        _plan(state: state, engineMs: 12500, lastSeekAgoMs: 2000),
        isA<SyncSeek>(),
      );
      // ...but not on every tick: a seek in the last second still blocks it.
      expect(
        _plan(state: state, engineMs: 12500, lastSeekAgoMs: 500),
        isA<SyncNone>(),
      );
    });

    test('exactly at the hard limit counts as hard', () {
      expect(
        _plan(
          state: _row(positionMs: 10000),
          engineMs: 12000,
          lastSeekAgoMs: 1500,
        ),
        isA<SyncSeek>(),
      );
    });

    test('while buffering the position means nothing: no seek storm', () {
      expect(
        _plan(
          state: _row(positionMs: 100000),
          phase: EnginePhase.buffering,
          engineMs: 5000,
        ),
        isA<SyncNone>(),
      );
      expect(_plan(state: _row(), phase: EnginePhase.loading), isA<SyncNone>());
    });

    test('a clock that puts updated_at in the future never goes backwards', () {
      final action = _plan(
        state: _row(positionMs: 10000, agoMs: -3000),
        engineMs: 10000,
      );
      expect(action, isA<SyncNone>());
    });
  });

  group('track change', () {
    test('another track than the loaded one loads', () {
      final action = _plan(state: _row(trackId: 't2'));
      expect((action as SyncLoadThenPlay).trackId, 't2');
    });

    test('also while the room is paused', () {
      expect(
        _plan(state: _row(trackId: 't2', playing: false)),
        isA<SyncLoadThenPlay>(),
      );
    });

    test('a load error loads again', () {
      expect(
        _plan(state: _row(), phase: EnginePhase.error),
        isA<SyncLoadThenPlay>(),
      );
    });
  });

  group('track end', () {
    test('expected position at or past the duration', () {
      expect(
        _plan(state: _row(positionMs: 199000, agoMs: 1000)),
        isA<SyncEnded>(),
      );
      expect(
        _plan(state: _row(positionMs: 199000, agoMs: 5000)),
        isA<SyncEnded>(),
      );
    });

    test('nothing is loaded for a track that is already over', () {
      expect(
        _plan(
          state: _row(trackId: 't9', positionMs: 199000, agoMs: 5000),
          loaded: null,
          phase: EnginePhase.idle,
        ),
        isA<SyncEnded>(),
      );
    });

    test(
      'an engine that completed a little early is the end, not a restart',
      () {
        expect(
          _plan(
            state: _row(positionMs: 198000, agoMs: 0),
            phase: EnginePhase.completed,
            engineMs: 197500,
          ),
          isA<SyncEnded>(),
        );
      },
    );

    test('an engine that completed far from the end plays again', () {
      expect(
        _plan(
          state: _row(positionMs: 50000),
          phase: EnginePhase.completed,
          engineMs: 0,
        ),
        isA<SyncPlay>(),
      );
    });

    test('a paused room at the end is just paused', () {
      expect(
        _plan(
          state: _row(playing: false, positionMs: 200000),
          phase: EnginePhase.paused,
          engineMs: 200000,
        ),
        isA<SyncNone>(),
      );
    });
  });

  group('sound gate', () {
    test('a playing room without sound waits', () {
      expect(
        _plan(state: _row(), phase: EnginePhase.ready, sound: false),
        isA<SyncWaitForSoundGate>(),
      );
    });

    test('the track is still loaded before the gate is tapped', () {
      expect(
        _plan(
          state: _row(),
          loaded: null,
          phase: EnginePhase.idle,
          sound: false,
        ),
        isA<SyncLoadThenPlay>(),
      );
    });

    test('the end does not wait for sound', () {
      expect(
        _plan(state: _row(positionMs: 199000, agoMs: 5000), sound: false),
        isA<SyncEnded>(),
      );
    });
  });

  test('the constants are the documented ones', () {
    const c = syncConfig;
    expect(c.driftThresholdMs, 300);
    expect(c.driftHardLimitMs, 2000);
    expect(c.driftCheckInterval, const Duration(seconds: 2));
    expect(c.minSeekGap, const Duration(seconds: 5));
    expect(c.clockRemeasureInterval, const Duration(seconds: 60));
    expect(c.postLoadDriftCheck, const Duration(milliseconds: 1500));
  });
}
