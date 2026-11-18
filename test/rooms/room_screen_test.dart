import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:vibe_rooms/features/rooms/presentation/home_screen.dart';

import '../fakes/fakes.dart';

/// Opens /room/room-1 from /home with the given data.
Future<FakeRoomRepository> _openRoom(
  WidgetTester tester, {
  String hostId = 'user-1',
  Set<String> online = const {},
  FakeRoomRepository? repo,
}) async {
  final rooms =
      repo ??
      FakeRoomRepository(
        roomsById: {'room-1': fakeRoom(hostId: hostId, name: 'Friday Vibes')},
        members: {
          'room-1': [
            fakeMember('user-1', 'Ana', isHost: hostId == 'user-1', order: 1),
            fakeMember(
              'user-2',
              'Bo',
              isHost: hostId == 'user-2',
              emoji: '🎸',
              order: 2,
            ),
            fakeMember('user-3', 'Cy', emoji: '🔥', order: 3),
          ],
        },
      );
  await pumpApp(
    tester,
    auth: FakeAuthRepository(signedIn: true),
    rooms: rooms,
    presence: FakeRoomPresence(online),
  );
  GoRouter.of(tester.element(find.byType(HomeScreen))).go('/room/room-1');
  await tester.pumpAndSettle();
  return rooms;
}

void main() {
  testWidgets('shows the name, code chip, now playing, listeners and tabs', (
    tester,
  ) async {
    await _openRoom(tester);

    expect(find.text('Friday Vibes'), findsOneWidget);
    expect(find.text('ABC234'), findsOneWidget);
    expect(find.byTooltip('Copy code'), findsOneWidget);
    expect(find.text('Copy invite'), findsOneWidget);
    expect(find.text('Now playing'), findsOneWidget);
    expect(find.text('Nothing playing yet'), findsOneWidget);
    expect(find.text('Listeners (3)'), findsOneWidget);
    expect(find.text('Queue'), findsOneWidget);
    expect(find.text('Chat'), findsOneWidget);
    expect(find.text('Coming soon'), findsOneWidget);
    await tester.tap(find.text('Chat'));
    await tester.pumpAndSettle();
    expect(find.text('Coming soon'), findsOneWidget);
  });

  testWidgets('listeners: online dots, host crown and "You"', (tester) async {
    await _openRoom(tester, online: {'user-1', 'user-3'});

    Color dot(String id) {
      final box = tester.widget<Container>(
        find.byKey(ValueKey('online-dot-$id')),
      );
      return (box.decoration! as BoxDecoration).color!;
    }

    expect(dot('user-1'), const Color(0xFF3DDC84)); // online
    expect(dot('user-3'), const Color(0xFF3DDC84)); // online
    expect(dot('user-2'), isNot(const Color(0xFF3DDC84))); // offline

    expect(find.text('👑'), findsOneWidget); // the host, once
    expect(find.text('You'), findsOneWidget);
    expect(find.text('Ana'), findsOneWidget);
    expect(find.text('Bo'), findsOneWidget);
    expect(find.text('🎸'), findsOneWidget);
  });

  testWidgets('host sees "Close room", and it closes after confirmation', (
    tester,
  ) async {
    final repo = await _openRoom(tester);

    await tester.tap(find.byTooltip('Room menu'));
    await tester.pumpAndSettle();
    expect(find.text('Leave room'), findsNothing);
    await tester.tap(find.text('Close room'));
    await tester.pumpAndSettle();
    expect(find.text('Close room?'), findsOneWidget);
    expect(repo.calls, isEmpty); // nothing until confirmed

    await tester.tap(find.widgetWithText(FilledButton, 'Close room'));
    await tester.pumpAndSettle();
    expect(repo.calls, ['close:room-1']);
    expect(find.text('My rooms'), findsOneWidget); // back on /home
  });

  testWidgets('a member sees "Leave room", and cancel keeps them in', (
    tester,
  ) async {
    final repo = await _openRoom(tester, hostId: 'user-2');

    await tester.tap(find.byTooltip('Room menu'));
    await tester.pumpAndSettle();
    expect(find.text('Close room'), findsNothing);
    await tester.tap(find.text('Leave room'));
    await tester.pumpAndSettle();
    expect(find.text('Leave room?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repo.calls, isEmpty);
    expect(find.text('Nothing playing yet'), findsOneWidget);

    await tester.tap(find.byTooltip('Room menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Leave room'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Leave room'));
    await tester.pumpAndSettle();
    expect(repo.calls, ['leave:room-1']);
    expect(find.text('My rooms'), findsOneWidget);
  });

  testWidgets('a room I am not in (or that does not exist) shows a friendly '
      'message with a way out', (tester) async {
    await _openRoom(tester, repo: FakeRoomRepository()); // no such room

    expect(find.text('Room not found'), findsOneWidget);
    expect(
      find.text("This room doesn't exist, or you're not in it."),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, 'Back to home'), findsOneWidget);
    expect(
      find.widgetWithText(OutlinedButton, 'Join with a code'),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'Join with a code'));
    await tester.pumpAndSettle();
    expect(find.text('Join with a code'), findsWidgets); // the sheet opened
    await tester.tapAt(const Offset(5, 5)); // dismiss the sheet
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Back to home'));
    await tester.pumpAndSettle();
    expect(find.text('My rooms'), findsOneWidget);
  });

  testWidgets('a closed room shows "Room closed"', (tester) async {
    await _openRoom(
      tester,
      repo: FakeRoomRepository(
        roomsById: {
          'room-1': fakeRoom(closedAt: DateTime.utc(2026, 11, 18, 12)),
        },
      ),
    );
    expect(find.text('Room closed'), findsOneWidget);
    expect(find.text('This room has been closed.'), findsOneWidget);
  });

  testWidgets('copy code and copy invite put text on the clipboard', (
    tester,
  ) async {
    String? clipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await _openRoom(tester);

    await tester.tap(find.byTooltip('Copy code'));
    await tester.pump();
    expect(clipboard, 'ABC234');
    expect(find.text('Code copied'), findsOneWidget);

    await tester.tap(find.text('Copy invite'));
    await tester.pump();
    expect(
      clipboard,
      startsWith('Join my Vibe Room "Friday Vibes" with code ABC234'),
    );
    expect(find.text('Invite copied'), findsOneWidget);
  });

  testWidgets('works at a wide browser width', (tester) async {
    await _openRoom(tester);
    tester.view.physicalSize = const Size(2200, 1200);
    await tester.pumpAndSettle();
    expect(find.text('Listeners (3)'), findsOneWidget);
    expect(find.text('Nothing playing yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a malformed room id shows "Room not found" without touching the '
      'repository', (tester) async {
    final repo = FakeRoomRepository();
    await pumpApp(
      tester,
      auth: FakeAuthRepository(signedIn: true),
      rooms: repo,
    );
    GoRouter.of(tester.element(find.byType(HomeScreen))).go('/room/a,b.c');
    await tester.pumpAndSettle();
    expect(find.text('Room not found'), findsOneWidget);
    expect(repo.calls, isEmpty);
  });
}
