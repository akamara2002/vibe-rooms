import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart' hide EnginePhase;
import 'package:material_ui/material_ui.dart';
import 'package:vibe_rooms/features/player/domain/room_state.dart';
import 'package:vibe_rooms/features/player/presentation/player_card.dart';
import 'package:vibe_rooms/features/player/presentation/player_providers.dart';
import 'package:vibe_rooms/features/player/presentation/sync_providers.dart';

import '../fakes/fakes.dart';

RoomState _playing({int positionMs = 65000, bool playing = false}) =>
    fakeRoomState(
      trackId: 't1',
      title: 'Midnight Drive',
      artist: 'The Lanes',
      durationMs: 200000,
      isPlaying: playing,
      positionMs: positionMs,
      updatedAt: DateTime.now().toUtc(),
    );

class _Setup {
  _Setup({RoomState? row, this.sound = true})
    : repo = FakeRoomStateRepository(current: row ?? fakeRoomState()),
      engine = FakeAudioEngine();

  final FakeRoomStateRepository repo;
  final FakeAudioEngine engine;
  final bool sound;
}

Future<void> _pump(
  WidgetTester tester,
  _Setup setup, {
  required bool isHost,
}) async {
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        audioEngineFactoryProvider.overrideWithValue(() => setup.engine),
        roomStateRepositoryProvider.overrideWithValue(setup.repo),
        serverTimeSourceProvider.overrideWithValue(
          FakeServerTimeSource(localNow: DateTime.now, rtt: Duration.zero),
        ),
        soundGateRequiredProvider.overrideWithValue(!setup.sound),
        musicCatalogProvider.overrideWithValue(
          FakeMusicCatalog(
            trendingTracks: [fakeTrack(id: 'tr1', title: 'Trending One')],
          ),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PlayerCard(args: (roomId: 'room-1', isHost: isHost)),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 600));
}

Future<void> _leave(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

void main() {
  group('empty room', () {
    testWidgets('the host is invited to pick a song', (tester) async {
      await _pump(tester, _Setup(), isHost: true);
      expect(find.text('Pick a song to start the party'), findsOneWidget);
      expect(find.text('Find music'), findsOneWidget);
      await _leave(tester);
    });

    testWidgets('a listener just waits', (tester) async {
      await _pump(tester, _Setup(), isHost: false);
      expect(find.text('Waiting for the host to pick a song'), findsOneWidget);
      expect(find.text('Find music'), findsNothing);
      await _leave(tester);
    });
  });

  group('with a track', () {
    testWidgets('everyone sees the same track from the room row', (
      tester,
    ) async {
      for (final host in [true, false]) {
        await _pump(tester, _Setup(row: _playing()), isHost: host);
        expect(find.text('Midnight Drive'), findsOneWidget);
        expect(find.text('The Lanes'), findsOneWidget);
        expect(find.text('Music via Audius'), findsOneWidget);
        // Elapsed time comes from the room position (paused at 1:05 of 3:20).
        expect(find.text('1:05'), findsOneWidget);
        expect(find.text('3:20'), findsOneWidget);
        expect(find.textContaining('Preview mode'), findsNothing);
        await _leave(tester);
      }
    });

    testWidgets('the host has play/pause, a seek slider and Change track', (
      tester,
    ) async {
      await _pump(tester, _Setup(row: _playing()), isHost: true);
      expect(find.byTooltip('Play'), findsOneWidget);
      expect(find.byType(Slider), findsOneWidget);
      expect(find.text('Change track'), findsOneWidget);
      expect(find.text('The host controls playback'), findsNothing);
      await _leave(tester);
    });

    testWidgets('a listener has none of that, only a progress bar and Mute', (
      tester,
    ) async {
      await _pump(tester, _Setup(row: _playing()), isHost: false);
      expect(find.byTooltip('Play'), findsNothing);
      expect(find.byTooltip('Pause'), findsNothing);
      expect(find.byType(Slider), findsNothing);
      expect(find.text('Change track'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('The host controls playback'), findsOneWidget);
      expect(find.byTooltip('Mute'), findsOneWidget);
      await _leave(tester);
    });

    testWidgets('Mute toggles for a listener', (tester) async {
      final setup = _Setup(row: _playing());
      await _pump(tester, setup, isHost: false);
      await tester.tap(find.byTooltip('Mute'));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byTooltip('Unmute'), findsOneWidget);
      expect(setup.engine.volume, 0);
      expect(setup.repo.writes, isEmpty);
      await _leave(tester);
    });

    testWidgets('the host pause button writes to the room', (tester) async {
      final setup = _Setup(row: _playing(playing: true));
      await _pump(tester, setup, isHost: true);
      await tester.tap(find.byTooltip('Pause'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(setup.repo.writes.single['is_playing'], false);
      expect(find.byTooltip('Play'), findsOneWidget);
      await _leave(tester);
    });

    testWidgets('dragging the slider writes once, when the drag ends', (
      tester,
    ) async {
      final setup = _Setup(row: _playing());
      await _pump(tester, setup, isHost: true);
      final slider = find.byType(Slider);
      final gesture = await tester.startGesture(tester.getCenter(slider));
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      expect(setup.repo.writes, isEmpty);
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 100));
      expect(setup.repo.writes, hasLength(1));
      expect(setup.repo.writes.single.keys.toSet(), {
        'is_playing',
        'position_ms',
      });
      await _leave(tester);
    });
  });

  group('the sync chip', () {
    testWidgets('says Syncing... while playing without a loaded engine', (
      tester,
    ) async {
      final setup = _Setup(row: _playing(playing: true));
      setup.engine.loadGate = null;
      await _pump(tester, setup, isHost: false);
      expect(
        find.byWidgetPredicate(
          (w) => w is Text && (w.data == 'Syncing...' || w.data == 'In sync'),
        ),
        findsOneWidget,
      );
      await _leave(tester);
    });

    testWidgets('Tap to turn on sound is also the sound gate', (tester) async {
      final setup = _Setup(row: _playing(playing: true), sound: false);
      await _pump(tester, setup, isHost: false);
      expect(find.text('Tap to turn on sound'), findsOneWidget);
      await tester.tap(find.text('Tap to turn on sound'));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Tap to turn on sound'), findsNothing);
      await _leave(tester);
    });

    testWidgets('says Ended at the end of the track', (tester) async {
      await _pump(
        tester,
        _Setup(row: _playing(positionMs: 200000)),
        isHost: false,
      );
      expect(find.text('Ended'), findsOneWidget);
      await _leave(tester);
    });

    testWidgets('says Reconnecting... when the connection drops', (
      tester,
    ) async {
      final setup = _Setup(row: _playing());
      await _pump(tester, setup, isHost: false);
      setup.repo.emitError();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Reconnecting...'), findsOneWidget);
      await _leave(tester);
    });
  });
}
