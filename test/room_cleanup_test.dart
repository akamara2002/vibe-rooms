import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart' hide EnginePhase;
import 'package:vibe_rooms/features/auth/presentation/auth_providers.dart';
import 'package:vibe_rooms/features/chat/presentation/chat_providers.dart';
import 'package:vibe_rooms/features/player/presentation/player_providers.dart';
import 'package:vibe_rooms/features/player/presentation/sync_providers.dart';
import 'package:vibe_rooms/features/queue/presentation/queue_providers.dart';
import 'package:vibe_rooms/features/reactions/domain/reaction.dart';
import 'package:vibe_rooms/features/reactions/presentation/reaction_controller.dart';
import 'package:vibe_rooms/features/rooms/presentation/host_presence.dart';
import 'package:vibe_rooms/features/rooms/presentation/rooms_providers.dart';

import 'fakes/fakes.dart';

final _base = DateTime.utc(2026, 11, 18, 12);

/// Entering a room starts a lot of machinery: an audio engine, five realtime
/// subscriptions, a clock, three periodic timers and a presence watcher.
/// Leaving must stop ALL of it: a timer or subscription that outlives the room
/// keeps the audio, the battery and the realtime quota busy.
void main() {
  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

  for (final isHost in [true, false]) {
    test('leaving a room as ${isHost ? 'the host' : 'a listener'} leaves no '
        'timers or subscriptions', () {
      fakeAsync((async) {
        DateTime trueNow() => _base.add(async.elapsed);

        final engine = FakeAudioEngine()..clock = trueNow;
        final roomState = FakeRoomStateRepository(
          current: fakeRoomState(
            trackId: 't1',
            title: 'Song',
            artist: 'Artist',
            durationMs: 240000,
            isPlaying: true,
            positionMs: 30000,
          ),
          serverNow: trueNow,
        );
        final queue = FakeQueueRepository();
        final chat = FakeChatRepository(now: trueNow);
        final reactions = FakeReactionService();
        final presence = FakeRoomPresence()
          ..live = StreamController<Set<String>>();
        final rooms = FakeRoomRepository(
          roomsById: {'room-1': fakeRoom()},
          members: {
            'room-1': [fakeMember('user-1', 'Ana', isHost: true)],
          },
        );

        final container = ProviderContainer(
          overrides: [
            authRepositoryProvider.overrideWithValue(
              FakeAuthRepository(
                signedIn: true,
                userId_: isHost ? 'user-1' : 'user-2',
              ),
            ),
            profileRepositoryProvider.overrideWithValue(
              FakeProfileRepository(),
            ),
            roomRepositoryProvider.overrideWithValue(rooms),
            roomPresenceProvider.overrideWithValue(presence),
            audioEngineFactoryProvider.overrideWithValue(() => engine),
            roomStateRepositoryProvider.overrideWithValue(roomState),
            serverTimeSourceProvider.overrideWithValue(
              FakeServerTimeSource(localNow: trueNow, rtt: Duration.zero),
            ),
            localClockProvider.overrideWithValue(trueNow),
            soundGateRequiredProvider.overrideWithValue(false),
            musicCatalogProvider.overrideWithValue(FakeMusicCatalog()),
            queueRepositoryProvider.overrideWithValue(queue),
            chatRepositoryProvider.overrideWithValue(chat),
            reactionServiceProvider.overrideWithValue(reactions),
          ],
        );

        // Everything the room screen keeps alive.
        final args = (roomId: 'room-1', isHost: isHost);
        final subs = <ProviderSubscription<Object?>>[
          container.listen(syncControllerProvider(args), (_, _) {}),
          container.listen(queueControllerProvider(args), (_, _) {}),
          container.listen(upcomingItemsProvider('room-1'), (_, _) {}),
          container.listen(chatControllerProvider('room-1'), (_, _) {}),
          container.listen(reactionControllerProvider('room-1'), (_, _) {}),
          container.listen(roomMembersProvider('room-1'), (_, _) {}),
          container.listen(roomProvider('room-1'), (_, _) {}),
          container.listen(onlineUsersProvider('room-1'), (_, _) {}),
          container.listen(
            hostOfflineProvider((
              roomId: 'room-1',
              hostId: 'user-1',
              isHost: isHost,
            )),
            (_, _) {},
          ),
        ];

        // Be inside the room for a while, with things happening.
        async.elapse(const Duration(seconds: 3));
        presence.live!.add({'user-2'}); // the host is missing: a timer runs
        chat.externalInsert(fakeMessage(id: 'a', userId: 'user-2', body: 'hi'));
        reactions.emit(ReactionType.fire);
        async.elapse(const Duration(seconds: 5));
        expect(
          async.periodicTimerCount + async.nonPeriodicTimerCount,
          greaterThan(0),
          reason: 'the room should be running something before we leave',
        );
        expect(engine.disposed, isFalse);

        // Leave: the room screen goes, and with it every listener.
        for (final sub in subs) {
          sub.close();
        }
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 1));
        container.dispose();
        async.flushMicrotasks();

        expect(engine.disposed, isTrue, reason: 'audio must stop');
        expect(async.periodicTimerCount, 0, reason: 'periodic timers');
        expect(async.nonPeriodicTimerCount, 0, reason: 'one-shot timers');
        expect(roomState.cancelCount, roomState.watchCount);
        expect(queue.cancelCount, queue.watchCount);
        expect(chat.cancelCount, chat.watchCount);
        expect(reactions.cancels, reactions.listens);
        expect(presence.live!.hasListener, isFalse);
        expect(roomState.watchCount, greaterThan(0));
        expect(queue.watchCount, greaterThan(0));
        expect(chat.watchCount, greaterThan(0));
        expect(reactions.listens, greaterThan(0));
      });
    });
  }
}
