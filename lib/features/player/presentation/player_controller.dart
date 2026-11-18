import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/audio_engine.dart';
import '../domain/player_state.dart';
import '../domain/track.dart';
import 'player_providers.dart';

const soundOffMessage = 'Tap "Turn on sound" first.';
const playbackErrorMessage = "Couldn't play this track. Try again.";

/// Owns one [AudioEngine] and turns its events into [PlayerState].
///
/// Autodisposed: leaving the room disposes the controller, which disposes the
/// engine and so stops the audio.
class PlayerController extends Notifier<PlayerState> {
  late AudioEngine _engine;
  final _subscriptions = <StreamSubscription<dynamic>>[];

  /// Bumped by every [playTrack] and [stop], so a superseded load notices.
  int _generation = 0;

  @override
  PlayerState build() {
    _engine = ref.read(audioEngineFactoryProvider)();
    _subscriptions
      ..add(_engine.phaseStream.listen(_onPhase))
      ..add(_engine.positionStream.listen(_onPosition))
      ..add(_engine.durationStream.listen(_onDuration));
    ref.onDispose(() {
      _generation++;
      for (final subscription in _subscriptions) {
        unawaited(subscription.cancel());
      }
      unawaited(_engine.dispose());
    });
    return const PlayerState();
  }

  void _onPhase(EnginePhase phase) {
    if (state.track == null) return;
    state = state.copyWith(
      phase: phase,
      errorMessage: phase == EnginePhase.error ? playbackErrorMessage : null,
      clearError: phase != EnginePhase.error,
    );
  }

  void _onPosition(Duration position) {
    if (state.track == null) return;
    state = state.copyWith(position: position);
  }

  void _onDuration(Duration? duration) {
    if (duration == null || state.track == null) return;
    state = state.copyWith(duration: duration);
  }

  bool get _soundAllowed => ref.read(soundEnabledProvider);

  /// Loads and plays [track]. A newer call cancels this one.
  Future<void> playTrack(Track track) async {
    if (!_soundAllowed) {
      state = state.copyWith(errorMessage: soundOffMessage);
      return;
    }
    final generation = ++_generation;
    state = PlayerState(
      track: track,
      phase: EnginePhase.loading,
      duration: track.duration,
    );
    try {
      await _engine.load(ref.read(musicCatalogProvider).streamUri(track.id));
      if (generation != _generation) return;
      if (_engine.phase == EnginePhase.error) return; // _onPhase reported it
      await _engine.play();
    } catch (error) {
      if (generation != _generation) return;
      debugPrint('Playback failed (${error.runtimeType})');
      state = state.copyWith(
        phase: EnginePhase.error,
        errorMessage: playbackErrorMessage,
      );
    }
  }

  /// Retries the current track after an error.
  Future<void> retry() async {
    final track = state.track;
    if (track != null) await playTrack(track);
  }

  Future<void> togglePlay() async {
    final track = state.track;
    if (track == null) return;
    if (!_soundAllowed) {
      state = state.copyWith(errorMessage: soundOffMessage);
      return;
    }
    try {
      switch (state.phase) {
        case EnginePhase.playing:
          await _engine.pause();
        case EnginePhase.completed:
          await _engine.playFrom(Duration.zero);
        case EnginePhase.error:
          await retry();
        case EnginePhase.ready || EnginePhase.paused:
          await _engine.play();
        case EnginePhase.idle || EnginePhase.loading || EnginePhase.buffering:
          break; // nothing sensible to do until it is ready
      }
    } catch (error) {
      debugPrint('Toggle failed (${error.runtimeType})');
      state = state.copyWith(
        phase: EnginePhase.error,
        errorMessage: playbackErrorMessage,
      );
    }
  }

  Future<void> seek(Duration position) async {
    if (state.track == null) return;
    final max = state.duration;
    var target = position < Duration.zero ? Duration.zero : position;
    if (max != null && target > max) target = max;
    state = state.copyWith(position: target);
    try {
      await _engine.seek(target);
    } catch (error) {
      debugPrint('Seek failed (${error.runtimeType})');
    }
  }

  /// Stops playback and clears the current track.
  Future<void> stop() async {
    _generation++;
    state = const PlayerState();
    try {
      await _engine.pause();
    } catch (_) {
      // Disposing the engine stops the audio anyway.
    }
  }
}

final playerControllerProvider =
    NotifierProvider.autoDispose<PlayerController, PlayerState>(
      PlayerController.new,
    );
