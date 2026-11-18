import 'audio_engine.dart';
import 'track.dart';

/// What the player UI shows. Immutable.
class PlayerState {
  const PlayerState({
    this.track,
    this.phase = EnginePhase.idle,
    this.position = Duration.zero,
    this.duration,
    this.errorMessage,
  });

  final Track? track;
  final EnginePhase phase;
  final Duration position;
  final Duration? duration;
  final String? errorMessage;

  bool get isPlaying => phase == EnginePhase.playing;
  bool get hasError => errorMessage != null;

  PlayerState copyWith({
    Track? track,
    bool clearTrack = false,
    EnginePhase? phase,
    Duration? position,
    Duration? duration,
    String? errorMessage,
    bool clearError = false,
  }) {
    return PlayerState(
      track: clearTrack ? null : (track ?? this.track),
      phase: phase ?? this.phase,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlayerState &&
          other.track == track &&
          other.phase == phase &&
          other.position == position &&
          other.duration == duration &&
          other.errorMessage == errorMessage;

  @override
  int get hashCode =>
      Object.hash(track, phase, position, duration, errorMessage);

  @override
  String toString() => 'PlayerState($phase, $position, ${track?.title})';
}
