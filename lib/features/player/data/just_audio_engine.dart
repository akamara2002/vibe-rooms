import 'dart:async';

import 'package:flutter/foundation.dart';
// just_audio has its own PlayerState; ours lives in the domain.
import 'package:just_audio/just_audio.dart' hide PlayerState;

import '../domain/audio_engine.dart';

/// [AudioEngine] over just_audio's [AudioPlayer].
class JustAudioEngine implements AudioEngine {
  JustAudioEngine([AudioPlayer? player]) : _player = player ?? AudioPlayer() {
    _stateSub = _player.playerStateStream.listen(
      (_) => _syncPhase(),
      onError: (Object _) => _fail(),
    );
    // Playback errors (a dead node, a dropped connection) arrive on this
    // stream, not as exceptions from play().
    _eventSub = _player.playbackEventStream.listen(
      (_) {},
      onError: (Object _) => _fail(),
    );
  }

  final AudioPlayer _player;
  late final StreamSubscription<dynamic> _stateSub;
  late final StreamSubscription<dynamic> _eventSub;
  final _phases = StreamController<EnginePhase>.broadcast();

  EnginePhase _phase = EnginePhase.idle;
  int _generation = 0;
  bool _disposed = false;
  bool _failed = false;
  bool _paused = false;

  @override
  EnginePhase get phase => _phase;

  @override
  Stream<EnginePhase> get phaseStream => _phases.stream;

  @override
  Duration get position => _player.position;

  @override
  Stream<Duration> get positionStream => _player.positionStream;

  @override
  Duration? get duration => _player.duration;

  @override
  Stream<Duration?> get durationStream => _player.durationStream;

  void _emit(EnginePhase phase) {
    if (_disposed || phase == _phase) return;
    _phase = phase;
    _phases.add(phase);
  }

  void _fail() {
    if (_disposed) return;
    _failed = true;
    _emit(EnginePhase.error);
  }

  /// Maps just_audio's processing state and playing flag to an [EnginePhase].
  void _syncPhase() {
    if (_disposed || _failed) return;
    final processing = _player.processingState;
    final playing = _player.playing;
    _emit(switch (processing) {
      ProcessingState.idle => EnginePhase.idle,
      ProcessingState.loading => EnginePhase.loading,
      ProcessingState.buffering => EnginePhase.buffering,
      ProcessingState.completed => EnginePhase.completed,
      ProcessingState.ready =>
        playing
            ? EnginePhase.playing
            : (_paused ? EnginePhase.paused : EnginePhase.ready),
    });
  }

  @override
  Future<void> load(Uri url, {Duration? initialPosition}) async {
    if (_disposed) return;
    final generation = ++_generation;
    _failed = false;
    _paused = false;
    _emit(EnginePhase.loading);
    try {
      await _player.setUrl(url.toString(), initialPosition: initialPosition);
      if (generation != _generation || _disposed) return;
      _syncPhase();
    } catch (error) {
      // A newer load interrupts this one; that is not a failure.
      if (generation != _generation || _disposed) return;
      debugPrint('Audio load failed (${error.runtimeType})');
      _fail();
    }
  }

  @override
  Future<void> play() async {
    if (_disposed) return;
    _paused = false;
    // just_audio's play() completes when playback ENDS, so never await it.
    unawaited(
      _player.play().then<void>(
        (_) {},
        onError: (Object error) {
          debugPrint('Audio play failed (${error.runtimeType})');
          _fail();
        },
      ),
    );
    _syncPhase();
  }

  @override
  Future<void> playFrom(Duration position) async {
    if (_disposed) return;
    await _player.seek(position);
    await play();
  }

  @override
  Future<void> pause() async {
    if (_disposed) return;
    _paused = true;
    await _player.pause();
    _syncPhase();
  }

  @override
  Future<void> seek(Duration position) async {
    if (_disposed) return;
    await _player.seek(position);
  }

  @override
  Future<void> setSpeed(double speed) async {
    if (_disposed) return;
    await _player.setSpeed(speed);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    await _stateSub.cancel();
    await _eventSub.cancel();
    await _phases.close();
    await _player.dispose(); // stops the audio
  }
}
