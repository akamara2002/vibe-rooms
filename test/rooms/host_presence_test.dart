import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart' hide EnginePhase;
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vibe_rooms/features/auth/presentation/auth_providers.dart';
import 'package:vibe_rooms/features/rooms/presentation/home_screen.dart';
import 'package:vibe_rooms/features/rooms/presentation/host_presence.dart';
import 'package:vibe_rooms/features/rooms/presentation/rooms_providers.dart';

import '../fakes/fakes.dart';

const _banner = 'The host is offline. Only the host can change the music.';

class _Rig {
  _Rig({this.isHost = false}) {
    presence = FakeRoomPresence()..live = StreamController<Set<String>>();
    container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(signedIn: true),
        ),
        profileRepositoryProvider.overrideWithValue(FakeProfileRepository()),
        roomPresenceProvider.overrideWithValue(presence),
      ],
    );
    container.listen(
      hostOfflineProvider((roomId: 'room-1', hostId: 'host', isHost: isHost)),
      (_, _) {},
    );
  }

  final bool isHost;
  late final FakeRoomPresence presence;
  late final ProviderContainer container;

  bool get offline => container.read(
    hostOfflineProvider((roomId: 'room-1', hostId: 'host', isHost: isHost)),
  );

  void emit(Set<String> online, FakeAsync async) {
    async.flushMicrotasks(); // the profile is read first, then presence joins
    presence.live!.add(online);
    async.flushMicrotasks();
  }
}

void main() {
  test('the notice appears after 10 seconds without the host, not before', () {
    fakeAsync((async) {
      final rig = _Rig();
      async.flushMicrotasks();
      rig.emit({'me'}, async);
      async.elapse(const Duration(seconds: 9, milliseconds: 900));
      expect(rig.offline, isFalse);
      async.elapse(const Duration(milliseconds: 200));
      expect(rig.offline, isTrue);
      rig.container.dispose();
    });
  });

  test('it disappears when the host returns', () {
    fakeAsync((async) {
      final rig = _Rig();
      async.flushMicrotasks();
      rig.emit({'me'}, async);
      async.elapse(const Duration(seconds: 11));
      expect(rig.offline, isTrue);
      rig.emit({'me', 'host'}, async);
      expect(rig.offline, isFalse);
      rig.container.dispose();
    });
  });

  test('a host who comes back within the grace never triggers it', () {
    fakeAsync((async) {
      final rig = _Rig();
      async.flushMicrotasks();
      rig.emit({'me'}, async);
      async.elapse(const Duration(seconds: 6));
      rig.emit({'me', 'host'}, async); // a reconnect, not an absence
      async.elapse(const Duration(seconds: 30));
      expect(rig.offline, isFalse);
      rig.container.dispose();
    });
  });

  test('more presence events while waiting do not restart the clock', () {
    fakeAsync((async) {
      final rig = _Rig();
      async.flushMicrotasks();
      rig.emit({'me'}, async);
      async.elapse(const Duration(seconds: 6));
      rig.emit({'me', 'other'}, async); // someone else joins: host still gone
      async.elapse(const Duration(seconds: 5));
      expect(rig.offline, isTrue); // 11 s after the FIRST sighting
      rig.container.dispose();
    });
  });

  test('loading or a stream error is not "offline"', () {
    fakeAsync((async) {
      final rig = _Rig();
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 60)); // no presence event yet
      expect(rig.offline, isFalse);
      rig.presence.live!.addError(Exception('channel trouble'));
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 60));
      expect(rig.offline, isFalse);
      rig.container.dispose();
    });
  });

  test('the host never sees it', () {
    fakeAsync((async) {
      final rig = _Rig(isHost: true);
      async.flushMicrotasks();
      rig.emit({'someone'}, async); // even if the host is missing from the set
      async.elapse(const Duration(minutes: 5));
      expect(rig.offline, isFalse);
      rig.container.dispose();
    });
  });

  test('leaving cancels the timer', () {
    fakeAsync((async) {
      final rig = _Rig();
      async.flushMicrotasks();
      rig.emit({'me'}, async);
      expect(async.nonPeriodicTimerCount, greaterThan(0));
      rig.container.dispose();
      async.flushMicrotasks();
      expect(async.nonPeriodicTimerCount, 0);
    });
  });

  group('on the room screen', () {
    Future<StreamController<Set<String>>> openRoom(
      WidgetTester tester, {
      required String me,
    }) async {
      final live = StreamController<Set<String>>();
      addTearDown(live.close);
      final presence = FakeRoomPresence()..live = live;
      final rooms = FakeRoomRepository(
        roomsById: {'room-1': fakeRoom(name: 'Friday Vibes')},
        members: {
          'room-1': [
            fakeMember('user-1', 'Ana', isHost: true),
            fakeMember('user-2', 'Bo', emoji: '🎸'),
          ],
        },
      );
      await pumpApp(
        tester,
        auth: FakeAuthRepository(signedIn: true, userId_: me),
        rooms: rooms,
        presence: presence,
      );
      GoRouter.of(tester.element(find.byType(HomeScreen))).go('/room/room-1');
      await tester.pumpAndSettle();
      return live;
    }

    testWidgets('a listener sees the banner, then it goes away', (
      tester,
    ) async {
      final live = await openRoom(tester, me: 'user-2');
      live.add({'user-2'});
      await tester.pump(const Duration(seconds: 9));
      expect(find.text(_banner), findsNothing);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text(_banner), findsOneWidget);

      live.add({'user-2', 'user-1'});
      await tester.pump();
      await tester.pump();
      expect(find.text(_banner), findsNothing);
    });

    testWidgets('the host never sees the banner', (tester) async {
      final live = await openRoom(tester, me: 'user-1');
      live.add(<String>{});
      await tester.pump(const Duration(seconds: 30));
      expect(find.text(_banner), findsNothing);
      expect(find.byType(Material), findsWidgets);
    });
  });
}
