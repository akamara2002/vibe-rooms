import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/audio_engine.dart';
import '../domain/room_state.dart';
import '../domain/room_state_repository.dart';
import '../domain/server_clock.dart';
import '../domain/sync_config.dart';
import '../domain/sync_planner.dart';
import '../domain/sync_status.dart';
import '../domain/track.dart';
import 'player_providers.dart';
import 'sync_providers.dart';

/// Which room, and whether I am its host (the database enforces the host
/// check too; this is for the UI).
typedef SyncArgs = ({String roomId, bool isHost});

class SyncState {
  const SyncState({
    this.room,
    this.status = SyncStatus.syncing,
    this.position = Duration.zero,
    this.muted = false,
    this.errorMessage,
    this.debug = const SyncDebug(),
  });

  /// The room's playback row (what everyone sees), or null before it loads.
  final RoomState? room;
  final SyncStatus status;

  /// Where playback is now, from the server clock (not the engine), so every
  /// device shows the same time.
  final Duration position;
  final bool muted;
  final String? errorMessage;
  final SyncDebug debug;

  bool get hasTrack => room?.trackId != null;
}

const hostOnlyMessage = 'Only the host can control the music.';

/// Drives the engine from the room's playback row.
///
///   room_state row ──► planSync(row, engine, server clock) ──► one action
///        ▲                          ▲                              │
///     Realtime            ServerClock (5 samples,                   ▼
///     + refetch           smallest round trip)               AudioEngine
///
/// Actions never overlap: a request that arrives while one runs sets a flag,
/// and the loop plans again with fresh data when the action finishes.
class SyncController extends Notifier<SyncState> {
  SyncController(this.args);

  final SyncArgs args;

  late AudioEngine _engine;
  late RoomStateRepository _repo;
  late ServerClock _clock;
  late DateTime Function() _localNow;
  late SyncConfig _config;

  final _subscriptions = <StreamSubscription<dynamic>>[];
  final _timers = <Timer>[];
  Timer? _postLoadTimer;
  _ResumeObserver? _observer;

  bool _disposed = false;
  bool _busy = false;
  bool _dirty = false;
  bool _reconnecting = false;
  bool _muted = false;

  RoomState? _room;
  DateTime? _newestServerUpdate;
  String? _loadedTrackId;
  DateTime? _lastSeekAt;
  DateTime? _lastLoadAt;
  int _seekCostMs = 0;
  bool _justLoaded = false;
  DateTime? _endWrittenFor;
  String _lastAction = 'none';
  int? _lastDriftMs;

  /// A notice for the user (a refused or failed host action).
  String? _error;

  /// The engine could not load or play the track.
  String? _engineError;

  @override
  SyncState build() {
    _config = syncConfig;
    _localNow = ref.read(localClockProvider);
    _repo = ref.read(roomStateRepositoryProvider);
    _engine = ref.read(audioEngineFactoryProvider)();
    final time = ref.read(serverTimeSourceProvider);
    _clock = ServerClock(
      fetchServerNow: time.serverNow,
      localNow: _localNow,
      samples: _config.clockSamples,
    );

    ref.onDispose(_dispose);
    ref.listen(soundEnabledProvider, (_, _) => _requestTick());
    // Start after build returns: state cannot be set from inside it.
    scheduleMicrotask(_start);
    return const SyncState();
  }

  // ---------------------------------------------------------------- lifecycle

  void _start() {
    if (_disposed) return;
    _subscriptions
      ..add(_repo.watch(args.roomId).listen(_onRoom, onError: _onRoomError))
      ..add(_engine.phaseStream.listen(_onPhase));
    _timers
      ..add(Timer.periodic(_config.driftCheckInterval, (_) => _onDriftTimer()))
      ..add(Timer.periodic(_config.displayTick, (_) => _publish()))
      ..add(
        Timer.periodic(_config.clockRemeasureInterval, (_) => _remeasure()),
      );
    _observer = _ResumeObserver(_onResume);
    WidgetsBinding.instance.addObserver(_observer!);
    unawaited(_remeasure());
  }

  void _dispose() {
    _disposed = true;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    for (final timer in _timers) {
      timer.cancel();
    }
    _postLoadTimer?.cancel();
    final observer = _observer;
    if (observer != null) WidgetsBinding.instance.removeObserver(observer);
    unawaited(_engine.dispose()); // stops the audio
  }

  Future<void> _remeasure() async {
    try {
      await _clock.measure();
    } catch (_) {
      // measure() never throws; this is only a guard for a timer callback.
    }
    if (_disposed) return;
    _requestTick();
  }

  void _onResume() {
    if (_disposed) return;
    unawaited(_remeasure());
    // Events missed while the app was in the background are not replayed.
    unawaited(_refetch());
  }

  Future<void> _refetch() async {
    try {
      final row = await _repo.get(args.roomId);
      if (row != null && !_disposed) _onRoom(row);
    } catch (_) {
      // The stream reports connection trouble; a failed refetch is retried on
      // the next resume or rejoin.
    }
  }

  // ------------------------------------------------------------------ events

  void _onRoom(RoomState next) {
    if (_disposed) return;
    final newest = _newestServerUpdate;
    // A stale answer (an old refetch overtaken by an event) is ignored.
    if (newest != null && next.updatedAt.isBefore(newest)) return;
    final wasReconnecting = _reconnecting;
    final anchorMoved = newest == null || next.updatedAt != newest;
    _newestServerUpdate = next.updatedAt;
    _room = next;
    _reconnecting = false;
    // A new host action is not thrash: let it be followed at once.
    if (anchorMoved) _lastSeekAt = null;
    if (wasReconnecting) unawaited(_remeasure());
    _requestTick();
    _publish();
  }

  void _onRoomError(Object _) {
    if (_disposed) return;
    _reconnecting = true;
    _publish();
  }

  void _onPhase(EnginePhase phase) {
    if (_disposed) return;
    if (phase == EnginePhase.error) {
      _engineError = "Couldn't play this track. Retrying.";
    } else if (_engineError != null && phase != EnginePhase.loading) {
      _engineError = null;
    }
    if (phase == EnginePhase.completed || phase == EnginePhase.error) {
      _requestTick();
    }
    _publish();
  }

  void _onDriftTimer() {
    if (_disposed) return;
    if (!_clock.isMeasured) unawaited(_remeasure());
    _requestTick();
  }

  // ------------------------------------------------------------------- loop

  void _requestTick() {
    if (_disposed) return;
    if (_busy) {
      _dirty = true;
      return;
    }
    unawaited(_run());
  }

  Future<void> _run() async {
    _busy = true;
    try {
      do {
        _dirty = false;
        await _step();
      } while (_dirty && !_disposed);
    } catch (error) {
      debugPrint('Sync step failed (${error.runtimeType})');
    } finally {
      _busy = false;
      if (!_disposed) _publish();
    }
  }

  SyncInput _input(RoomState room) => SyncInput(
    state: room,
    loadedTrackId: _loadedTrackId,
    phase: _engine.phase,
    enginePosition: _engine.position,
    serverNow: _clock.nowServer(),
    soundEnabled: ref.read(soundEnabledProvider),
    lastSeekAt: _lastSeekAt,
  );

  Future<void> _step() async {
    final room = _room;
    // Until the clock is measured, updated_at cannot be interpreted.
    if (room == null || !_clock.isMeasured) return;
    final input = _input(room);
    final action = planSync(input, config: _config);
    _lastAction = action.toString();
    if (input.phase == EnginePhase.playing && room.isPlaying) {
      _lastDriftMs =
          input.enginePosition.inMilliseconds -
          expectedMs(room, input.serverNow);
    }
    await _execute(action, room, input.serverNow);
  }

  Future<void> _execute(
    SyncAction action,
    RoomState room,
    DateTime serverNow,
  ) async {
    switch (action) {
      case SyncNone() || SyncWaitForSoundGate():
        break;
      case SyncLoadThenPlay(:final trackId):
        await _load(trackId);
      case SyncPlay(:final seekToMs):
        await _play(seekToMs, room);
      case SyncPause(:final seekToMs):
        await _engine.pause();
        final drift = (_engine.position.inMilliseconds - seekToMs).abs();
        if (drift > _config.driftThresholdMs) {
          await _engine.seek(Duration(milliseconds: seekToMs));
        }
      case SyncSeek(:final toMs):
        await _seek(toMs, room);
      case SyncEnded():
        if (_engine.phase == EnginePhase.playing) await _engine.pause();
        await _maybeWriteEnd(room);
    }
  }

  Future<void> _load(String trackId) async {
    final failed = _engine.phase == EnginePhase.error;
    final last = _lastLoadAt;
    if (failed &&
        last != null &&
        _localNow().difference(last) < _config.reloadGap) {
      return; // try again on a later tick
    }
    _lastLoadAt = _localNow();
    _loadedTrackId = null;
    await _engine.load(ref.read(musicCatalogProvider).streamUri(trackId));
    if (_disposed) return;
    _loadedTrackId = trackId;
    _lastSeekAt = null;
    if (_engine.phase != EnginePhase.error) {
      _justLoaded = true;
      await _engine.setVolume(_muted ? 0 : 1);
      // Plan again with fresh server time: the load may have taken seconds.
      _dirty = true;
    }
  }

  int _clampMs(int ms, RoomState room) {
    final max = room.durationMs;
    var out = ms < 0 ? 0 : ms;
    if (max != null && out > max) out = max;
    return out;
  }

  void _noteSeekCost(int ms) {
    final clamped = ms < 0 ? 0 : (ms > 1500 ? 1500 : ms);
    _seekCostMs = _seekCostMs == 0 ? clamped : ((_seekCostMs + clamped) ~/ 2);
  }

  Future<void> _play(int seekToMs, RoomState room) async {
    // The seek itself takes time; start that far ahead to land on the spot.
    final target = _clampMs(seekToMs + _seekCostMs, room);
    final started = _localNow();
    await _engine.playFrom(Duration(milliseconds: target));
    if (_disposed) return;
    _noteSeekCost(_localNow().difference(started).inMilliseconds);
    _lastSeekAt = _clock.nowServer();
    if (_justLoaded) {
      _justLoaded = false;
      // Seeks on streamed MP3s can land imprecisely: look once more soon, and
      // let that check correct even though a seek just happened.
      _postLoadTimer?.cancel();
      _postLoadTimer = Timer(_config.postLoadDriftCheck, () {
        _lastSeekAt = null;
        _requestTick();
      });
    }
  }

  Future<void> _seek(int toMs, RoomState room) async {
    final lead = room.isPlaying ? _seekCostMs : 0;
    final started = _localNow();
    await _engine.seek(Duration(milliseconds: _clampMs(toMs + lead, room)));
    if (_disposed) return;
    if (room.isPlaying) {
      _noteSeekCost(_localNow().difference(started).inMilliseconds);
    }
    _lastSeekAt = _clock.nowServer();
  }

  // ------------------------------------------------------------- host: write

  /// The host writes the track end exactly once per anchor.
  Future<void> _maybeWriteEnd(RoomState room) async {
    if (!args.isHost || !room.isPlaying) return;
    final duration = room.durationMs;
    if (duration == null || _endWrittenFor == room.updatedAt) return;
    _endWrittenFor = room.updatedAt;
    try {
      await _repo.hostUpdate(
        args.roomId,
        RoomStateUpdate.playback(isPlaying: false, positionMs: duration),
      );
    } catch (_) {
      _endWrittenFor = null; // allow one more try on a later tick
    }
  }

  void _enableSound() => ref.read(soundEnabledProvider.notifier).enable();

  /// Where the host actually is right now.
  int _currentPositionMs(RoomState room) {
    final fromEngine =
        _engine.phase == EnginePhase.playing ||
            _engine.phase == EnginePhase.paused
        ? _engine.position.inMilliseconds
        : null;
    return _clampMs(
      fromEngine ?? room.expectedPositionMs(_clock.nowServer()),
      room,
    );
  }

  /// Half the round trip, because the server stamps `updated_at` when the
  /// write ARRIVES. Without it listeners would run that much behind the host.
  int _compensationMs() {
    final rtt = _clock.lastRttMs ?? 0;
    final half = rtt ~/ 2;
    return half > _config.maxLatencyCompensationMs
        ? _config.maxLatencyCompensationMs
        : half;
  }

  Future<void> _hostWrite({
    required RoomState optimistic,
    required RoomStateUpdate update,
    bool resetSeekGuard = false,
  }) async {
    final previous = _room;
    // Optimistic: my own engine follows at once; the echo then finds no drift.
    _room = optimistic;
    _error = null;
    if (resetSeekGuard) _lastSeekAt = null;
    _requestTick();
    _publish();
    try {
      await _repo.hostUpdate(args.roomId, update);
    } catch (error) {
      if (_disposed) return;
      // Undo only if nothing newer arrived meanwhile: a fresher row from the
      // server must not be overwritten with the stale pre-write one.
      if (identical(_room, optimistic)) _room = previous;
      _error = error is RoomStateFailure
          ? error.message
          : const RoomStateFailure(RoomStateFailureKind.unknown).message;
      _requestTick();
      _publish();
    }
  }

  /// Host: play [track] from the start.
  Future<void> hostSetTrack(Track track) async {
    if (!args.isHost) return _refuse();
    final room = _room;
    if (room == null) return;
    _enableSound();
    final update = RoomStateUpdate.track(track);
    _endWrittenFor = null;
    await _hostWrite(
      optimistic: RoomState(
        roomId: room.roomId,
        trackId: track.id,
        title: track.title,
        artist: track.artist,
        artworkUrl: track.artworkUrl,
        durationMs: track.durationMs,
        isPlaying: true,
        positionMs: 0,
        updatedAt: _clock.nowServer(),
        updatedBy: room.updatedBy,
      ),
      update: update,
      resetSeekGuard: true,
    );
  }

  Future<void> hostTogglePlay() async {
    if (!args.isHost) return _refuse();
    final room = _room;
    if (room == null || room.trackId == null) return;
    _enableSound();
    final now = _clock.nowServer();
    if (room.isPlaying) {
      final position = _currentPositionMs(room);
      await _hostWrite(
        optimistic: room.copyWith(
          isPlaying: false,
          positionMs: position,
          updatedAt: now,
        ),
        update: RoomStateUpdate.playback(
          isPlaying: false,
          positionMs: position,
        ),
      );
      return;
    }
    final duration = room.durationMs;
    final atEnd = duration != null && room.positionMs >= duration;
    final position = atEnd ? 0 : _currentPositionMs(room);
    _endWrittenFor = null;
    await _hostWrite(
      optimistic: room.copyWith(
        isPlaying: true,
        positionMs: position,
        updatedAt: now,
      ),
      update: RoomStateUpdate.playback(
        isPlaying: true,
        positionMs: _clampMs(position + _compensationMs(), room),
      ),
      resetSeekGuard: true,
    );
  }

  /// Host: jump to [target] (called when the slider is released).
  Future<void> hostSeek(Duration target) async {
    if (!args.isHost) return _refuse();
    final room = _room;
    if (room == null || room.trackId == null) return;
    final position = _clampMs(target.inMilliseconds, room);
    final compensation = room.isPlaying ? _compensationMs() : 0;
    _endWrittenFor = null;
    await _hostWrite(
      optimistic: room.copyWith(
        positionMs: position,
        updatedAt: _clock.nowServer(),
      ),
      update: RoomStateUpdate.playback(
        isPlaying: room.isPlaying,
        positionMs: _clampMs(position + compensation, room),
      ),
      resetSeekGuard: true,
    );
  }

  void _refuse() {
    _error = hostOnlyMessage;
    _publish();
  }

  // ---------------------------------------------------------------- listener

  Future<void> toggleMute() async {
    _muted = !_muted;
    await _engine.setVolume(_muted ? 0 : 1);
    _publish();
  }

  void clearError() {
    _error = null;
    _engineError = null;
    _publish();
  }

  // ----------------------------------------------------------------- publish

  SyncStatus _status(RoomState? room, DateTime now) {
    if (_reconnecting) return SyncStatus.reconnecting;
    if (room == null || room.trackId == null) return SyncStatus.syncing;
    final duration = room.durationMs;
    final over =
        duration != null &&
        (room.isPlaying
            ? room.expectedPositionMs(now) >= duration
            : room.positionMs >= duration);
    if (over) return SyncStatus.ended;
    if (room.isPlaying && !ref.read(soundEnabledProvider)) {
      return SyncStatus.waitingForSound;
    }
    final phase = _engine.phase;
    if (!_clock.isMeasured || _busy) return SyncStatus.syncing;
    if (room.isPlaying &&
        (phase == EnginePhase.loading ||
            phase == EnginePhase.buffering ||
            phase == EnginePhase.idle ||
            _loadedTrackId != room.trackId)) {
      return SyncStatus.syncing;
    }
    return SyncStatus.inSync;
  }

  void _publish() {
    if (_disposed) return;
    final room = _room;
    final now = _clock.nowServer();
    final position = room == null
        ? Duration.zero
        : Duration(milliseconds: room.expectedPositionMs(now));
    final next = SyncState(
      room: room,
      status: _status(room, now),
      position: position,
      muted: _muted,
      errorMessage: _error ?? _engineError,
      debug: SyncDebug(
        offsetMs: _clock.isMeasured ? _clock.offsetMs : null,
        rttMs: _clock.lastRttMs,
        driftMs: _lastDriftMs,
        lastAction: _lastAction,
        loadedTrack: _loadedTrackId != null,
      ),
    );
    final old = state;
    if (old.room == next.room &&
        old.status == next.status &&
        old.position == next.position &&
        old.muted == next.muted &&
        old.errorMessage == next.errorMessage &&
        old.debug.lastAction == next.debug.lastAction &&
        old.debug.driftMs == next.debug.driftMs &&
        old.debug.rttMs == next.debug.rttMs &&
        old.debug.offsetMs == next.debug.offsetMs) {
      return;
    }
    state = next;
  }
}

class _ResumeObserver with WidgetsBindingObserver {
  _ResumeObserver(this._onResume);

  final VoidCallback _onResume;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _onResume();
  }
}
