import 'audio_engine.dart';
import 'room_state.dart';
import 'sync_config.dart';

/// What the engine must do next to match the room.
sealed class SyncAction {
  const SyncAction();
}

/// Nothing to do.
class SyncNone extends SyncAction {
  const SyncNone();
  @override
  String toString() => 'none';
}

/// The room is playing but sound is off (web needs a tap first).
class SyncWaitForSoundGate extends SyncAction {
  const SyncWaitForSoundGate();
  @override
  String toString() => 'wait-for-sound';
}

/// Load [trackId] (paused). When it is ready the controller plans again with
/// fresh server time, which gives the seek-and-play (or the paused seek) at the
/// right position even if the load took seconds.
class SyncLoadThenPlay extends SyncAction {
  const SyncLoadThenPlay(this.trackId);
  final String trackId;
  @override
  String toString() => 'load';
}

/// Seek to [seekToMs], then play.
class SyncPlay extends SyncAction {
  const SyncPlay(this.seekToMs);
  final int seekToMs;
  @override
  String toString() => 'play@$seekToMs';
}

/// Pause, at [seekToMs].
class SyncPause extends SyncAction {
  const SyncPause(this.seekToMs);
  final int seekToMs;
  @override
  String toString() => 'pause@$seekToMs';
}

/// Correct drift (or follow a host seek) without changing play/pause.
class SyncSeek extends SyncAction {
  const SyncSeek(this.toMs);
  final int toMs;
  @override
  String toString() => 'seek@$toMs';
}

/// The track is over.
class SyncEnded extends SyncAction {
  const SyncEnded();
  @override
  String toString() => 'ended';
}

/// The facts the planner decides on.
class SyncInput {
  const SyncInput({
    required this.state,
    required this.loadedTrackId,
    required this.phase,
    required this.enginePosition,
    required this.serverNow,
    required this.soundEnabled,
    required this.lastSeekAt,
  });

  /// The room's playback row, or null if none has been read yet.
  final RoomState? state;

  /// The track in the engine, or null.
  final String? loadedTrackId;
  final EnginePhase phase;
  final Duration enginePosition;
  final DateTime serverNow;
  final bool soundEnabled;

  /// Server time of the last corrective seek, or null.
  final DateTime? lastSeekAt;
}

/// Where playback should be, from the row and the server clock.
int expectedMs(RoomState state, DateTime serverNow) =>
    state.expectedPositionMs(serverNow);

/// Pure decision function: exactly one [SyncAction].
SyncAction planSync(SyncInput input, {SyncConfig config = syncConfig}) {
  final state = input.state;
  final trackId = state?.trackId;
  if (state == null || trackId == null) return const SyncNone();

  final expected = expectedMs(state, input.serverNow);
  final duration = state.durationMs;
  final atEnd = duration != null && expected >= duration;

  // The end first: nothing needs loading for a track that is already over.
  if (state.isPlaying && atEnd) return const SyncEnded();

  if (trackId != input.loadedTrackId) return SyncLoadThenPlay(trackId);

  final phase = input.phase;
  final positionMs = input.enginePosition.inMilliseconds;
  final sinceSeek = input.lastSeekAt == null
      ? null
      : input.serverNow.difference(input.lastSeekAt!);

  bool seekAllowed(int driftMs) {
    if (sinceSeek == null) return true;
    if (driftMs >= config.driftHardLimitMs) {
      return sinceSeek >= config.hardSeekGap;
    }
    return sinceSeek >= config.minSeekGap;
  }

  // A load error: try again (the controller throttles the retries).
  if (phase == EnginePhase.error) return SyncLoadThenPlay(trackId);
  // Waiting for the engine: its position means nothing yet.
  if (phase == EnginePhase.loading || phase == EnginePhase.buffering) {
    return const SyncNone();
  }

  if (state.isPlaying) {
    if (!input.soundEnabled) return const SyncWaitForSoundGate();
    if (phase == EnginePhase.completed) {
      // The audio ended a little before the stored duration: that is the end,
      // not a reason to restart it.
      if (duration != null && expected >= duration - config.endToleranceMs) {
        return const SyncEnded();
      }
      return SyncPlay(expected);
    }
    if (phase != EnginePhase.playing) return SyncPlay(expected);
    final drift = (positionMs - expected).abs();
    if (drift <= config.driftThresholdMs) return const SyncNone();
    return seekAllowed(drift) ? SyncSeek(expected) : const SyncNone();
  }

  // The room is paused.
  if (phase == EnginePhase.playing) return SyncPause(state.positionMs);
  final drift = (positionMs - state.positionMs).abs();
  if (drift > config.driftThresholdMs && seekAllowed(drift)) {
    return SyncSeek(state.positionMs);
  }
  return const SyncNone();
}
