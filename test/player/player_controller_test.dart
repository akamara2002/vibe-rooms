import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart' hide EnginePhase;
import 'package:vibe_rooms/features/player/domain/audio_engine.dart';
import 'package:vibe_rooms/features/player/domain/player_state.dart';
import 'package:vibe_rooms/features/player/presentation/player_controller.dart';
import 'package:vibe_rooms/features/player/presentation/player_providers.dart';

import '../fakes/fakes.dart';

class _Harness {
  _Harness({bool soundGate = false}) {
    container = ProviderContainer(
      overrides: [
        audioEngineFactoryProvider.overrideWithValue(() {
          engines.add(FakeAudioEngine());
          return engines.last;
        }),
        musicCatalogProvider.overrideWithValue(FakeMusicCatalog()),
        soundGateRequiredProvider.overrideWithValue(soundGate),
      ],
    );
    // autoDispose providers need a listener to stay alive.
    subscription = container.listen(playerControllerProvider, (_, _) {});
  }

  late final ProviderContainer container;
  late final ProviderSubscription<PlayerState> subscription;
  final engines = <FakeAudioEngine>[];

  FakeAudioEngine get engine => engines.first;
  PlayerState get state => container.read(playerControllerProvider);
  PlayerController get controller =>
      container.read(playerControllerProvider.notifier);

  Future<void> settle() => Future<void>.delayed(Duration.zero);
  void dispose() => container.dispose();
}

void main() {
  late _Harness h;

  setUp(() => h = _Harness());
  tearDown(() => h.dispose());

  test('starts idle with nothing loaded', () {
    expect(h.state.track, isNull);
    expect(h.state.phase, EnginePhase.idle);
    expect(h.state.errorMessage, isNull);
  });

  test('playTrack loads the stream URL, then plays', () async {
    final track = fakeTrack(id: 'abc', durationMs: 90000);
    final future = h.controller.playTrack(track);
    expect(h.state.track, track);
    expect(h.state.phase, EnginePhase.loading);
    expect(h.state.duration, const Duration(seconds: 90));

    await future;
    await h.settle();
    expect(h.engine.calls, ['load:abc', 'play']);
    expect(
      h.engine.loadedUrl,
      Uri.parse('https://audio.test/v1/tracks/abc/stream'),
    );
    expect(h.state.phase, EnginePhase.playing);
    expect(h.state.errorMessage, isNull);
  });

  test('pause and resume', () async {
    await h.controller.playTrack(fakeTrack());
    await h.settle();
    await h.controller.togglePlay();
    await h.settle();
    expect(h.state.phase, EnginePhase.paused);
    await h.controller.togglePlay();
    await h.settle();
    expect(h.state.phase, EnginePhase.playing);
    expect(h.engine.calls, ['load:t1', 'play', 'pause', 'play']);
  });

  test('toggling a finished track replays it from the start', () async {
    await h.controller.playTrack(fakeTrack());
    h.engine.emitPhase(EnginePhase.completed);
    await h.settle();
    await h.controller.togglePlay();
    expect(h.engine.calls.last, 'playFrom:0');
  });

  test(
    'seek moves the engine and the position, clamped to the duration',
    () async {
      await h.controller.playTrack(fakeTrack(durationMs: 60000));
      await h.settle();

      await h.controller.seek(const Duration(seconds: 30));
      expect(h.engine.calls.last, 'seek:30000');
      expect(h.state.position, const Duration(seconds: 30));

      await h.controller.seek(const Duration(minutes: 10));
      expect(h.engine.calls.last, 'seek:60000');
      expect(h.state.position, const Duration(seconds: 60));

      await h.controller.seek(const Duration(seconds: -5));
      expect(h.engine.calls.last, 'seek:0');
    },
  );

  test(
    'position and duration updates from the engine reach the state',
    () async {
      await h.controller.playTrack(fakeTrack());
      h.engine.emitPosition(const Duration(seconds: 7));
      h.engine.emitDuration(const Duration(seconds: 200));
      await h.settle();
      expect(h.state.position, const Duration(seconds: 7));
      expect(h.state.duration, const Duration(seconds: 200));
    },
  );

  test('a second playTrack cancels the first load', () async {
    h.engine; // created lazily by the first read below
    final gate = Completer<void>();
    h.controller; // build
    h.engine.loadGate = gate;

    final first = h.controller.playTrack(fakeTrack(id: 'one'));
    await h.settle();
    final second = h.controller.playTrack(fakeTrack(id: 'two'));
    await h.settle();

    gate.complete();
    await first;
    await second;
    await h.settle();

    expect(h.state.track!.id, 'two');
    // Only the second load may start playback.
    expect(h.engine.calls.where((c) => c == 'play'), hasLength(1));
    expect(h.engine.calls, ['load:one', 'load:two', 'play']);
  });

  test('an engine error becomes an error message, and Retry reloads', () async {
    h.controller;
    h.engine.failNextLoad = true;
    await h.controller.playTrack(fakeTrack(id: 'bad'));
    await h.settle();
    expect(h.state.phase, EnginePhase.error);
    expect(h.state.errorMessage, playbackErrorMessage);
    expect(h.engine.calls, ['load:bad']); // no play after a failed load

    await h.controller.retry();
    await h.settle();
    expect(h.state.phase, EnginePhase.playing);
    expect(h.state.errorMessage, isNull);
    expect(h.engine.calls, ['load:bad', 'load:bad', 'play']);
  });

  test('toggling while in error retries', () async {
    h.controller;
    h.engine.failNextLoad = true;
    await h.controller.playTrack(fakeTrack());
    await h.settle();
    await h.controller.togglePlay();
    await h.settle();
    expect(h.state.phase, EnginePhase.playing);
  });

  test('an engine that throws never leaks an exception', () async {
    final container = ProviderContainer(
      overrides: [
        audioEngineFactoryProvider.overrideWithValue(_ThrowingEngine.new),
        musicCatalogProvider.overrideWithValue(FakeMusicCatalog()),
        soundGateRequiredProvider.overrideWithValue(false),
      ],
    );
    addTearDown(container.dispose);
    container.listen(playerControllerProvider, (_, _) {});

    await container
        .read(playerControllerProvider.notifier)
        .playTrack(fakeTrack());
    final state = container.read(playerControllerProvider);
    expect(state.phase, EnginePhase.error);
    expect(state.errorMessage, playbackErrorMessage);
  });

  test('stop clears the track and pauses', () async {
    await h.controller.playTrack(fakeTrack());
    await h.controller.stop();
    expect(h.state.track, isNull);
    expect(h.state.phase, EnginePhase.idle);
    expect(h.engine.calls.last, 'pause');
    // Late engine events no longer touch the state.
    h.engine.emitPhase(EnginePhase.playing);
    await h.settle();
    expect(h.state.phase, EnginePhase.idle);
  });

  test('disposing the controller disposes the engine (leaving the room stops audio)', () async {
    await h.controller.playTrack(fakeTrack());
    final engine = h.engine;
    expect(engine.disposed, isFalse);
    h.subscription.close();
    await h.settle();
    h.container.dispose();
    expect(engine.disposed, isTrue);
  });

  test(
    'every visit gets a fresh engine (a disposed one is never reused)',
    () async {
      final engines = <FakeAudioEngine>[];
      final container = ProviderContainer(
        overrides: [
          audioEngineFactoryProvider.overrideWithValue(() {
            engines.add(FakeAudioEngine());
            return engines.last;
          }),
          musicCatalogProvider.overrideWithValue(FakeMusicCatalog()),
          soundGateRequiredProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);

      final first = container.listen(playerControllerProvider, (_, _) {});
      first.close(); // leave the room
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final second = container.listen(playerControllerProvider, (_, _) {});
      addTearDown(second.close);

      expect(engines, hasLength(2));
      expect(engines.first.disposed, isTrue);
      expect(engines.last.disposed, isFalse);
    },
  );

  group('sound gate (web)', () {
    late _Harness web;
    setUp(() => web = _Harness(soundGate: true));
    tearDown(() => web.dispose());

    test('blocks playTrack until sound is turned on', () async {
      expect(web.container.read(soundEnabledProvider), isFalse);
      await web.controller.playTrack(fakeTrack());
      expect(web.state.errorMessage, soundOffMessage);
      expect(web.state.track, isNull);
      expect(web.engine.calls, isEmpty); // nothing loaded, nothing played
    });

    test('works after the gate is tapped', () async {
      web.container.read(soundEnabledProvider.notifier).enable();
      await web.controller.playTrack(fakeTrack());
      await web.settle();
      expect(web.state.phase, EnginePhase.playing);
      expect(web.state.errorMessage, isNull);
    });
  });

  test('sound is on from the start where no gate is needed', () {
    expect(h.container.read(soundEnabledProvider), isTrue);
  });
}

class _ThrowingEngine extends FakeAudioEngine {
  @override
  Future<void> load(Uri url, {Duration? initialPosition}) =>
      throw StateError('boom');
}
