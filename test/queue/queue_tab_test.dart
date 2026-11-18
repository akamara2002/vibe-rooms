import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart' hide EnginePhase;
import 'package:material_ui/material_ui.dart';
import 'package:vibe_rooms/features/auth/presentation/auth_providers.dart';
import 'package:vibe_rooms/features/player/domain/room_state.dart';
import 'package:vibe_rooms/features/player/presentation/player_card.dart';
import 'package:vibe_rooms/features/player/presentation/player_providers.dart';
import 'package:vibe_rooms/features/player/presentation/sync_controller.dart';
import 'package:vibe_rooms/features/player/presentation/sync_providers.dart';
import 'package:vibe_rooms/features/queue/domain/queue_failure.dart';
import 'package:vibe_rooms/features/queue/domain/queue_item.dart';
import 'package:vibe_rooms/features/queue/presentation/queue_providers.dart';
import 'package:vibe_rooms/features/queue/presentation/queue_tab.dart';

import '../fakes/fakes.dart';

/// user-1 is me. 'a' and 'c' were added by me, 'b' by Bo.
List<QueueItem> _items() => [
  fakeQueueItem(
    id: 'b',
    sortKey: 20,
    addedBy: 'user-2',
    addedByName: 'Bo',
    addedByEmoji: '🎸',
  ),
  fakeQueueItem(
    id: 'a',
    sortKey: 10,
    addedBy: 'user-1',
    addedByName: 'Me',
    addedByEmoji: '🎧',
  ),
  fakeQueueItem(
    id: 'c',
    sortKey: 30,
    addedBy: 'user-1',
    addedByName: 'Me',
    addedByEmoji: '🎧',
  ),
];

class _Setup {
  _Setup({List<QueueItem>? items, RoomState? row, this.isHost = false})
    : queue = FakeQueueRepository(items: items ?? _items()),
      state = FakeRoomStateRepository(current: row ?? fakeRoomState()),
      engine = FakeAudioEngine();

  final FakeQueueRepository queue;
  final FakeRoomStateRepository state;
  final FakeAudioEngine engine;
  final bool isHost;

  SyncArgs get args => (roomId: 'room-1', isHost: isHost);
}

Future<void> _pump(WidgetTester tester, _Setup setup, {Widget? child}) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        audioEngineFactoryProvider.overrideWithValue(() => setup.engine),
        roomStateRepositoryProvider.overrideWithValue(setup.state),
        serverTimeSourceProvider.overrideWithValue(
          FakeServerTimeSource(localNow: DateTime.now, rtt: Duration.zero),
        ),
        soundGateRequiredProvider.overrideWithValue(false),
        musicCatalogProvider.overrideWithValue(
          FakeMusicCatalog(
            trendingTracks: [fakeTrack(id: 'tr1', title: 'Trending One')],
          ),
        ),
        queueRepositoryProvider.overrideWithValue(setup.queue),
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(signedIn: true),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: child ?? QueueTab(args: setup.args),
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

RoomState _nowPlaying() => fakeRoomState(
  trackId: 'now',
  title: 'Midnight Drive',
  artist: 'The Lanes',
  durationMs: 200000,
  isPlaying: true,
  positionMs: 1000,
  updatedAt: DateTime.now().toUtc(),
);

void main() {
  group('the list', () {
    testWidgets('shows the count, the rows in sort order and who added them', (
      tester,
    ) async {
      await _pump(tester, _Setup());
      expect(find.text('Up next (3)'), findsOneWidget);
      final a = tester.getTopLeft(find.text('Song a')).dy;
      final b = tester.getTopLeft(find.text('Song b')).dy;
      final c = tester.getTopLeft(find.text('Song c')).dy;
      expect(a < b && b < c, isTrue);
      expect(find.text('Added by 🎸 Bo'), findsOneWidget);
      expect(find.text('Added by 🎧 Me'), findsNWidgets(2));
      expect(find.text('Artist a'), findsOneWidget);
      expect(find.text('3:20'), findsNWidgets(3));
      expect(find.text('Add songs'), findsOneWidget);
      await _leave(tester);
    });

    testWidgets('an empty queue says so and offers Add songs', (tester) async {
      await _pump(tester, _Setup(items: []));
      expect(find.text('Up next (0)'), findsOneWidget);
      expect(
        find.text('Nothing queued. Add songs with Find music.'),
        findsOneWidget,
      );
      expect(find.text('Add songs'), findsOneWidget);
      await _leave(tester);
    });

    testWidgets('the playing song is a pinned row from the room state', (
      tester,
    ) async {
      await _pump(tester, _Setup(row: _nowPlaying()));
      expect(find.text('Now playing'), findsOneWidget);
      expect(find.text('Midnight Drive'), findsOneWidget);
      // It sits above the upcoming rows.
      expect(
        tester.getTopLeft(find.text('Midnight Drive')).dy <
            tester.getTopLeft(find.text('Song a')).dy,
        isTrue,
      );
      await _leave(tester);
    });

    testWidgets('nothing playing means no pinned row', (tester) async {
      await _pump(tester, _Setup());
      expect(find.text('Now playing'), findsNothing);
      await _leave(tester);
    });

    testWidgets('the item that is playing is not listed as upcoming', (
      tester,
    ) async {
      // Pretend 'a' is the playing item (marked late).
      final setup = _Setup(
        row: RoomState(
          roomId: 'room-1',
          queueItemId: 'a',
          trackId: 'track-a',
          title: 'Song a',
          artist: 'Artist a',
          durationMs: 200000,
          isPlaying: true,
          positionMs: 0,
          updatedAt: DateTime.now().toUtc(),
        ),
      );
      await _pump(tester, setup);
      expect(find.text('Up next (2)'), findsOneWidget);
      // 'Song a' appears once: as the pinned row only.
      expect(find.text('Song a'), findsOneWidget);
      await _leave(tester);
    });

    testWidgets('changes made by others show up live', (tester) async {
      final setup = _Setup(items: []);
      await _pump(tester, setup);
      setup.queue.externalAdd(
        fakeQueueItem(id: 'n', addedByName: 'Cy', addedByEmoji: '🔥'),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Up next (1)'), findsOneWidget);
      expect(find.text('Added by 🔥 Cy'), findsOneWidget);
      await _leave(tester);
    });
  });

  group('actions', () {
    testWidgets('the host can play any item now and remove any item', (
      tester,
    ) async {
      await _pump(tester, _Setup(isHost: true));
      expect(find.byTooltip('Play now'), findsNWidgets(3));
      expect(find.byTooltip('Remove from queue'), findsNWidgets(3));
      await _leave(tester);
    });

    testWidgets('a member has no Play now, and can remove only their own', (
      tester,
    ) async {
      await _pump(tester, _Setup());
      expect(find.byTooltip('Play now'), findsNothing);
      // a and c are mine, b is Bo's.
      expect(find.byTooltip('Remove from queue'), findsNWidgets(2));
      await _leave(tester);
    });

    testWidgets('removing an item removes the row', (tester) async {
      final setup = _Setup(isHost: true);
      await _pump(tester, setup);
      await tester.tap(find.byTooltip('Remove from queue').at(1)); // song b
      await tester.pump(const Duration(milliseconds: 100));
      expect(setup.queue.byId('b'), isNull);
      expect(find.text('Up next (2)'), findsOneWidget);
      expect(find.text('Song b'), findsNothing);
      await _leave(tester);
    });

    testWidgets('a refused remove says why', (tester) async {
      final setup = _Setup();
      setup.queue.failNextRemove = const QueueFailure(
        QueueFailureKind.notAllowed,
      );
      await _pump(tester, setup);
      await tester.tap(find.byTooltip('Remove from queue').first);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text("You can't do that in this room."), findsOneWidget);
      await _leave(tester);
    });

    testWidgets('Play now starts that item: the room follows, the item leaves '
        'the queue', (tester) async {
      final setup = _Setup(isHost: true);
      await _pump(tester, setup);
      await tester.tap(find.byTooltip('Play now').at(1)); // song b
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 600));
      expect(setup.state.writes.single['queue_item_id'], 'b');
      expect(setup.queue.byId('b')!.playedAt, isNotNull);
      expect(find.text('Up next (2)'), findsOneWidget);
      // b is now the pinned row, once.
      expect(find.text('Now playing'), findsOneWidget);
      expect(find.text('Song b'), findsOneWidget);
      await _leave(tester);
    });

    testWidgets('Add songs opens the sheet in add mode', (tester) async {
      final setup = _Setup(isHost: true);
      await _pump(tester, setup);
      await tester.tap(find.text('Add songs'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Add to queue'), findsOneWidget);
      expect(find.text('Play now'), findsWidgets); // the host's extra action
      await tester.tap(find.byTooltip('Add to queue'));
      await tester.pumpAndSettle();
      expect(find.text('Added'), findsOneWidget);
      expect(setup.queue.calls, contains('add:tr1'));
      await _leave(tester);
    });

    testWidgets('a duplicate in the sheet shows "Already in the queue"', (
      tester,
    ) async {
      final setup = _Setup(
        items: [fakeQueueItem(id: 't', trackId: 'tr1', title: 'Trending One')],
      );
      await _pump(tester, setup);
      await tester.tap(find.text('Add songs'));
      await tester.pumpAndSettle();
      // Already queued: shown as Added, and cannot be added again.
      expect(find.text('Added'), findsOneWidget);
      expect(setup.queue.calls.where((c) => c.startsWith('add:')), isEmpty);
      await _leave(tester);
    });
  });

  group('the player card', () {
    Future<void> pumpCard(WidgetTester tester, _Setup setup) =>
        _pump(tester, setup, child: PlayerCard(args: setup.args));

    testWidgets('the host has Next, enabled when songs are queued', (
      tester,
    ) async {
      await pumpCard(tester, _Setup(isHost: true, row: _nowPlaying()));
      final next = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.skip_next),
      );
      expect(next.onPressed, isNotNull);
      await _leave(tester);
    });

    testWidgets('Next is disabled when nothing is queued', (tester) async {
      await pumpCard(
        tester,
        _Setup(isHost: true, row: _nowPlaying(), items: []),
      );
      final next = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.skip_next),
      );
      expect(next.onPressed, isNull);
      await _leave(tester);
    });

    testWidgets('Next starts the first queued song', (tester) async {
      final setup = _Setup(isHost: true, row: _nowPlaying());
      await pumpCard(tester, setup);
      await tester.tap(find.byTooltip('Next'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 600));
      expect(setup.state.writes.single['queue_item_id'], 'a');
      expect(find.text('Song a'), findsOneWidget);
      await _leave(tester);
    });

    testWidgets('Next is disabled while an advance is in flight', (
      tester,
    ) async {
      final setup = _Setup(isHost: true, row: _nowPlaying());
      await pumpCard(tester, setup);
      setup.queue.markGate = Completer<void>();
      await tester.tap(find.byTooltip('Next'));
      await tester.pump(const Duration(milliseconds: 100));
      final next = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.skip_next),
      );
      expect(next.onPressed, isNull);
      setup.queue.markGate!.complete();
      await tester.pump(const Duration(milliseconds: 600));
      await _leave(tester);
    });

    testWidgets('a listener has no Next', (tester) async {
      await pumpCard(tester, _Setup(row: _nowPlaying()));
      expect(find.byTooltip('Next'), findsNothing);
      await _leave(tester);
    });

    testWidgets('an idle room with songs queued offers the host Play next', (
      tester,
    ) async {
      final setup = _Setup(isHost: true);
      await pumpCard(tester, setup);
      expect(find.text('Play next'), findsOneWidget);
      await tester.tap(find.text('Play next'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 600));
      expect(setup.state.writes.single['queue_item_id'], 'a');
      await _leave(tester);
    });

    testWidgets('a listener of an idle room just waits', (tester) async {
      await pumpCard(tester, _Setup());
      expect(find.text('Play next'), findsNothing);
      expect(find.text('Waiting for the host to pick a song'), findsOneWidget);
      await _leave(tester);
    });
  });
}
