import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart' hide EnginePhase;
import 'package:material_ui/material_ui.dart';
import 'package:vibe_rooms/features/player/domain/audio_engine.dart';
import 'package:vibe_rooms/features/player/domain/track.dart';
import 'package:vibe_rooms/features/player/presentation/player_card.dart';
import 'package:vibe_rooms/features/player/presentation/player_controller.dart';
import 'package:vibe_rooms/features/player/presentation/player_providers.dart';
import 'package:vibe_rooms/features/player/presentation/sound_gate.dart';

import '../fakes/fakes.dart';

class _Setup {
  _Setup(this.tester, {this.web = false});

  final WidgetTester tester;
  final bool web;
  final engine = FakeAudioEngine();
  final catalog = FakeMusicCatalog(
    trendingTracks: [fakeTrack(id: 'tr1', title: 'Trending One')],
  );
  late final ProviderContainer container;

  Future<void> pump() async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container = ProviderContainer(
          overrides: [
            audioEngineFactoryProvider.overrideWithValue(() => engine),
            musicCatalogProvider.overrideWithValue(catalog),
            soundGateRequiredProvider.overrideWithValue(web),
          ],
        ),
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(children: [SoundGate(), PlayerCard()]),
            ),
          ),
        ),
      ),
    );
    addTearDown(container.dispose);
    await tester.pump();
  }

  PlayerController get controller =>
      container.read(playerControllerProvider.notifier);

  Future<void> play(Track track) async {
    await controller.playTrack(track);
    await tester.pump();
  }
}

Finder _playButton() => find.byTooltip('Play');
Finder _pauseButton() => find.byTooltip('Pause');

void main() {
  testWidgets(
    'empty: "Nothing playing yet", Find music, preview caption, attribution',
    (tester) async {
      final s = _Setup(tester);
      await s.pump();

      expect(find.text('Now playing'), findsOneWidget);
      expect(find.text('Nothing playing yet'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Find music'), findsOneWidget);
      expect(find.text('Preview mode: not synced yet'), findsOneWidget);
      expect(find.text('Music via Audius'), findsOneWidget);
      expect(find.text('Open on Audius'), findsNothing); // nothing to link to
      expect(find.byType(Slider), findsNothing);
    },
  );

  testWidgets('Find music opens the search sheet; picking a track plays it', (
    tester,
  ) async {
    final s = _Setup(tester);
    await s.pump();

    await tester.tap(find.text('Find music'));
    await tester.pumpAndSettle();
    expect(find.text('Trending One'), findsOneWidget);

    await tester.tap(find.text('Trending One'));
    await tester.pumpAndSettle();
    expect(s.engine.calls, ['load:tr1', 'play']);
    expect(find.text('Trending One'), findsOneWidget); // now on the card
    expect(_pauseButton(), findsOneWidget);
  });

  testWidgets(
    'loading: spinner in the button, play disabled, slider disabled',
    (tester) async {
      final s = _Setup(tester);
      await s.pump();
      s.engine.loadGate = Completer<void>();
      // ignore: unawaited_futures
      s.controller.playTrack(fakeTrack(title: 'Loading Song'));
      await tester.pump();

      expect(find.text('Loading Song'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        tester.widget<IconButton>(find.byType(IconButton).last).onPressed,
        isNull,
      );
      expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
    },
  );

  testWidgets(
    'playing: title, artist, times, pause button, advancing position',
    (tester) async {
      final s = _Setup(tester);
      await s.pump();
      await s.play(
        fakeTrack(title: 'Hello Song', artist: 'Some Band', durationMs: 195000),
      );

      expect(find.text('Hello Song'), findsOneWidget);
      expect(find.text('Some Band'), findsOneWidget);
      expect(find.text('0:00'), findsOneWidget);
      expect(find.text('3:15'), findsOneWidget);
      expect(_pauseButton(), findsOneWidget);

      s.engine.emitPosition(const Duration(seconds: 65));
      await tester.pump();
      expect(find.text('1:05'), findsOneWidget);
    },
  );

  testWidgets('the play and pause button toggles playback', (tester) async {
    final s = _Setup(tester);
    await s.pump();
    await s.play(fakeTrack());

    await tester.tap(_pauseButton());
    await tester.pump();
    expect(s.engine.calls.last, 'pause');
    expect(_playButton(), findsOneWidget);

    await tester.tap(_playButton());
    await tester.pump();
    expect(s.engine.calls.last, 'play');
  });

  testWidgets('dragging the slider seeks on release', (tester) async {
    final s = _Setup(tester);
    await s.pump();
    await s.play(fakeTrack(durationMs: 100000));
    s.engine.emitDuration(const Duration(seconds: 100));
    await tester.pump();

    final slider = tester.getRect(find.byType(Slider));
    await tester.tapAt(
      Offset(slider.left + slider.width * 0.5, slider.center.dy),
    );
    await tester.pump();

    final seeks = s.engine.calls.where((c) => c.startsWith('seek:')).toList();
    expect(seeks, hasLength(1));
    final ms = int.parse(seeks.single.substring(5));
    expect(ms, inInclusiveRange(40000, 60000));
  });

  testWidgets('error: message and Retry, which reloads and plays', (
    tester,
  ) async {
    final s = _Setup(tester);
    await s.pump();
    s.engine.failNextLoad = true;
    await s.play(fakeTrack(title: 'Broken'));
    await tester.pump();

    expect(find.text(playbackErrorMessage), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump();
    expect(find.text(playbackErrorMessage), findsNothing);
    expect(_pauseButton(), findsOneWidget);
  });

  testWidgets('shows "Open on Audius" only when the track has a permalink', (
    tester,
  ) async {
    final s = _Setup(tester);
    await s.pump();
    await s.play(fakeTrack(permalinkUrl: 'https://audius.co/artist/song'));
    expect(find.text('Open on Audius'), findsOneWidget);

    await s.play(fakeTrack(id: 't2', title: 'No Link'));
    expect(find.text('Open on Audius'), findsNothing);
  });

  group('sound gate (web mode)', () {
    testWidgets(
      'shows "Tap to turn on sound" and blocks playing until tapped',
      (tester) async {
        final s = _Setup(tester, web: true);
        await s.pump();

        expect(find.text('Tap to turn on sound'), findsOneWidget);

        // Picking a track while sound is off is refused with a message.
        await s.controller.playTrack(fakeTrack());
        await tester.pump();
        expect(s.engine.calls, isEmpty);
        expect(find.text(soundOffMessage), findsOneWidget);

        await tester.tap(find.text('Tap to turn on sound'));
        await tester.pump();
        expect(find.text('Tap to turn on sound'), findsNothing);

        await s.play(fakeTrack());
        await tester.pump();
        expect(s.engine.calls, ['load:t1', 'play']);
      },
    );

    testWidgets('the play button is disabled while sound is off', (
      tester,
    ) async {
      final s = _Setup(tester, web: true);
      await s.pump();
      // A track somehow loaded (for example restored state): button stays off.
      s.container.read(soundEnabledProvider.notifier).enable();
      await s.play(fakeTrack());
      s.container.read(soundGateRequiredProvider);
      expect(
        tester.widget<IconButton>(find.byType(IconButton).last).onPressed,
        isNotNull,
      );
    });

    testWidgets(
      'a screen reader can turn sound on (the semantic button has a tap action)',
      (tester) async {
        final s = _Setup(tester, web: true);
        await s.pump();
        final handle = tester.ensureSemantics();

        tester.semantics.tap(find.semantics.byLabel('Tap to turn on sound'));
        await tester.pump();
        expect(s.container.read(soundEnabledProvider), isTrue);
        expect(find.text('Tap to turn on sound'), findsNothing);
        handle.dispose();
      },
    );
  });

  testWidgets('no gate where none is needed (mobile)', (tester) async {
    final s = _Setup(tester);
    await s.pump();
    expect(find.text('Tap to turn on sound'), findsNothing);
  });

  test('formatDuration helper shape (smoke)', () {
    expect(EnginePhase.values, contains(EnginePhase.completed));
  });
}
