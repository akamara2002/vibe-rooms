import 'package:flutter_test/flutter_test.dart' hide EnginePhase;
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vibe_rooms/features/chat/domain/chat_message.dart';
import 'package:vibe_rooms/features/rooms/domain/room_summary.dart';
import 'package:vibe_rooms/features/rooms/presentation/home_screen.dart';

import '../fakes/fakes.dart';

/// Every key screen at four widths and three text scales: no overflow, no
/// exception. (Flutter reports a RenderFlex overflow as an exception, which
/// fails the test.) The data is deliberately awkward: long names, long titles,
/// long messages.
const _sizes = <String, Size>{
  '320': Size(320, 640),
  '390': Size(390, 844),
  '768': Size(768, 1024),
  '1400': Size(1400, 900),
};
const _scales = [1.0, 1.3, 2.0];

const _longName = 'A really quite long room name that keeps going and going';
const _longTitle =
    'An extremely long song title that nobody would ever really choose';

FakeRoomRepository roomsForTest({String me = 'user-1'}) => FakeRoomRepository(
  myRoomsList: [
    RoomSummary(
      room: fakeRoom(id: 'room-1', name: _longName, hostId: me),
      memberCount: 12,
    ),
    RoomSummary(
      room: fakeRoom(id: 'r2', name: 'Friends', code: 'BBBBBB', hostId: 'x'),
      memberCount: 1,
    ),
  ],
  roomsById: {'room-1': fakeRoom(id: 'room-1', name: _longName)},
  members: {
    'room-1': [
      fakeMember('user-1', 'Ana the host with a long name', isHost: true),
      fakeMember('user-2', 'Bo', emoji: '🎸'),
      fakeMember(
        'user-3',
        'Someone with an unreasonably long display',
        emoji: '🥁',
      ),
      fakeMember('user-4', 'Dee', emoji: '🎹'),
    ],
  },
);

Future<void> openRoomForTest(
  WidgetTester tester, {
  required Size size,
  required double scale,
  required bool isHost,
  required bool playing,
}) async {
  final me = isHost ? 'user-1' : 'user-2';
  final roomState = FakeRoomStateRepository(
    current: playing
        ? fakeRoomState(
            trackId: 't1',
            title: _longTitle,
            artist: 'An artist with a very long name indeed',
            durationMs: 240000,
            isPlaying: true,
            positionMs: 30000,
          )
        : null,
    serverNow: () => DateTime.now().toUtc(),
  );
  final queue = FakeQueueRepository(
    items: [
      fakeQueueItem(id: 'a', title: _longTitle, sortKey: 1),
      fakeQueueItem(
        id: 'b',
        sortKey: 2,
        addedByName: 'Someone with a long name',
      ),
    ],
  );
  final chat = FakeChatRepository(
    messages: [
      fakeMessage(id: 'm1', userId: 'user-2', body: 'hello ' * 40),
      fakeMessage(id: 'm2', userId: me, body: 'short one'),
      fakeMessage(id: 'm3', userId: 'user-3', body: 'x' * 120),
    ],
    profiles: {
      'user-2': const ChatSender(name: 'Bo', emoji: '🎸'),
      'user-3': const ChatSender(
        name: 'Someone with an unreasonably long display',
        emoji: '🥁',
      ),
      'user-1': const ChatSender(name: 'Ana', emoji: '🎧'),
    },
  );
  await pumpApp(
    tester,
    auth: FakeAuthRepository(signedIn: true, userId_: me),
    rooms: roomsForTest(me: 'user-1'),
    roomState: roomState,
    queue: queue,
    chat: chat,
    logicalSize: size,
    textScale: scale,
  );
  GoRouter.of(tester.element(find.byType(HomeScreen))).go('/room/room-1');
  await tester.pumpAndSettle();
}

void main() {
  for (final entry in _sizes.entries) {
    for (final scale in _scales) {
      final label = '${entry.key}px, text x$scale';
      final size = entry.value;

      group(label, () {
        testWidgets('login', (tester) async {
          await pumpApp(
            tester,
            auth: FakeAuthRepository(),
            logicalSize: size,
            textScale: scale,
          );
          expect(find.text('Continue as guest'), findsOneWidget);
          await tester.tap(find.text('Email'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        });

        testWidgets('home with rooms', (tester) async {
          await pumpApp(
            tester,
            auth: FakeAuthRepository(signedIn: true),
            rooms: roomsForTest(),
            logicalSize: size,
            textScale: scale,
          );
          expect(find.text('My rooms'), findsOneWidget);
        });

        testWidgets('create, join and profile sheets', (tester) async {
          await pumpApp(
            tester,
            auth: FakeAuthRepository(signedIn: true),
            rooms: roomsForTest(),
            logicalSize: size,
            textScale: scale,
          );
          for (final open in ['Create a room', 'Join with a code']) {
            await tester.ensureVisible(find.text(open));
            await tester.tap(find.text(open));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await tester.tapAt(const Offset(2, 2)); // dismiss on the barrier
            await tester.pumpAndSettle();
          }
          await tester.tap(find.byType(ActionChip).first);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        });

        for (final (name, host, playing) in [
          ('empty room (host)', true, false),
          ('empty room (listener)', false, false),
          ('playing room (host)', true, true),
          ('playing room (listener)', false, true),
        ]) {
          testWidgets(name, (tester) async {
            await openRoomForTest(
              tester,
              size: size,
              scale: scale,
              isHost: host,
              playing: playing,
            );
            expect(tester.takeException(), isNull);

            await tester.ensureVisible(find.text('Chat'));
            await tester.tap(find.text('Chat'));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);

            await tester.tap(find.text('Queue'));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          });
        }

        testWidgets('search sheet', (tester) async {
          await openRoomForTest(
            tester,
            size: size,
            scale: scale,
            isHost: true,
            playing: false,
          );
          final find0 = find.text('Find music');
          await tester.ensureVisible(find0.first);
          await tester.tap(find0.first);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        });

        testWidgets('not found and unknown page', (tester) async {
          await pumpApp(
            tester,
            auth: FakeAuthRepository(signedIn: true),
            logicalSize: size,
            textScale: scale,
          );
          final router = GoRouter.of(tester.element(find.byType(HomeScreen)));
          router.go('/room/nope');
          await tester.pumpAndSettle();
          expect(find.text('Room not found'), findsOneWidget);
          expect(tester.takeException(), isNull);
          router.go('/nowhere');
          await tester.pumpAndSettle();
          expect(find.text('We could not find that page'), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      });
    }
  }
}
