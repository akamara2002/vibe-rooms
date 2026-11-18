enum EnginePhase {
  idle,
  loading,
  buffering,
  ready,
  playing,
  paused,
  completed,
  error,
}

/// The seam between the app and an audio library.
///
/// Built for synced playback: a room can say "the track is at 83.2 s and
/// playing" and every device calls [playFrom] with its own estimate.
///
/// Rules every implementation must follow:
///  * [load] never throws: a failure moves [phaseStream] to
///    [EnginePhase.error]. A [load] that is superseded by a newer [load]
///    completes silently and must not touch the phase of the newer one.
///  * [play] and [playFrom] return as soon as the command is issued. They do
///    NOT wait for the track to finish (just_audio's own `play()` does).
///  * [position] is the best current estimate (it advances between stream
///    events while playing), so it is safe to sample at any moment.
///  * After [dispose], the engine is unusable and audio has stopped.
abstract class AudioEngine {
  Future<void> load(Uri url, {Duration? initialPosition});

  Future<void> play();

  /// Seeks to [position], then starts playing. The fast path for joining a
  /// track that is already in progress.
  Future<void> playFrom(Duration position);

  Future<void> pause();

  Future<void> seek(Duration position);

  /// Playback rate (1.0 is normal). A rate slightly off 1.0 corrects drift
  /// without an audible seek.
  Future<void> setSpeed(double speed);

  Duration get position;

  Stream<Duration> get positionStream;

  EnginePhase get phase;

  Stream<EnginePhase> get phaseStream;

  /// Null until known.
  Duration? get duration;

  Stream<Duration?> get durationStream;

  Future<void> dispose();
}
