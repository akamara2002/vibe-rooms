import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart' hide EnginePhase;
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vibe_rooms/features/auth/presentation/auth_providers.dart';
import 'package:vibe_rooms/features/chat/domain/chat_failure.dart';
import 'package:vibe_rooms/features/chat/domain/chat_message.dart';
import 'package:vibe_rooms/features/chat/domain/sanitize_message.dart';
import 'package:vibe_rooms/features/chat/presentation/chat_providers.dart';
import 'package:vibe_rooms/features/chat/presentation/chat_tab.dart';
import 'package:vibe_rooms/features/rooms/presentation/home_screen.dart';
import 'package:vibe_rooms/features/rooms/presentation/rooms_providers.dart';

import '../fakes/fakes.dart';

Future<void> _pumpTab(WidgetTester tester, FakeChatRepository chat) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        chatRepositoryProvider.overrideWithValue(chat),
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(signedIn: true),
        ),
        roomRepositoryProvider.overrideWithValue(
          FakeRoomRepository(
            roomsById: {'room-1': fakeRoom()},
            members: {
              'room-1': [
                fakeMember('user-1', 'Me', isHost: true, emoji: '🎧'),
                fakeMember('user-2', 'Bo', emoji: '🎸'),
              ],
            },
          ),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Consumer(
              builder: (context, ref, _) {
                // Keep the members (names) alive like the room screen does.
                ref.watch(roomMembersProvider('room-1'));
                return const ChatTab(roomId: 'room-1');
              },
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
}

Finder _body(String text) =>
    find.byWidgetPredicate((w) => w is SelectableText && w.data == text);

Future<void> _leave(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 5));
}

bool _sendEnabled(WidgetTester tester) =>
    tester
        .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.send))
        .onPressed !=
    null;

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump();
}

void main() {
  testWidgets('an empty chat says "Say hi" and offers the input', (
    tester,
  ) async {
    await _pumpTab(tester, FakeChatRepository());
    expect(find.text('Say hi 👋'), findsOneWidget);
    expect(find.text('Message the room'), findsOneWidget);
    await _leave(tester);
  });

  testWidgets('other people\'s messages show their emoji, name and a HH:mm '
      'stamp; mine are right-aligned without a name', (tester) async {
    final chat = FakeChatRepository(
      messages: [
        fakeMessage(id: 'a', userId: 'user-2', body: 'from Bo'),
        fakeMessage(
          id: 'b',
          userId: 'user-1',
          body: 'from me',
          createdAt: DateTime.utc(2026, 11, 18, 12, 1),
        ),
      ],
      profiles: {
        'user-2': const ChatSender(name: 'Bo', emoji: '🎸'),
        'user-1': const ChatSender(name: 'Me', emoji: '🎧'),
      },
    );
    await _pumpTab(tester, chat);
    expect(_body('from Bo'), findsOneWidget);
    expect(find.text('🎸 Bo'), findsOneWidget);
    expect(_body('from me'), findsOneWidget);
    expect(find.text('🎧 Me'), findsNothing); // my own name is not repeated
    expect(find.textContaining(RegExp(r'^\d\d:\d\d$')), findsNWidgets(2));
    expect(
      tester.getCenter(_body('from me')).dx >
          tester.getCenter(_body('from Bo')).dx,
      isTrue,
    );
    await _leave(tester);
  });

  testWidgets('send is disabled for empty and whitespace-only text', (
    tester,
  ) async {
    await _pumpTab(tester, FakeChatRepository());
    expect(_sendEnabled(tester), isFalse);
    await _type(tester, '   \n  ');
    expect(_sendEnabled(tester), isFalse);
    await _type(tester, 'hi');
    expect(_sendEnabled(tester), isTrue);
    await _leave(tester);
  });

  testWidgets('sending shows the message and clears the input', (tester) async {
    final chat = FakeChatRepository();
    await _pumpTab(tester, chat);
    await _type(tester, 'hello room');
    await tester.tap(find.byTooltip('Send'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_body('hello room'), findsOneWidget);
    expect(chat.sentBodies, ['hello room']);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '',
    );
    await _leave(tester);
  });

  testWidgets('the counter appears from 400 characters and 501 is blocked', (
    tester,
  ) async {
    await _pumpTab(tester, FakeChatRepository());
    await _type(tester, 'a' * 399);
    expect(find.textContaining('/$maxMessageLength'), findsNothing);
    await _type(tester, 'a' * 400);
    expect(find.text('400/500'), findsOneWidget);
    expect(_sendEnabled(tester), isTrue);
    await _type(tester, 'a' * 500);
    expect(find.text('500/500'), findsOneWidget);
    expect(_sendEnabled(tester), isTrue);
    await _type(tester, 'a' * 501);
    expect(find.text('501/500'), findsOneWidget);
    expect(_sendEnabled(tester), isFalse);
    await _leave(tester);
  });

  testWidgets('the counter counts characters, not UTF-16 units', (
    tester,
  ) async {
    await _pumpTab(tester, FakeChatRepository());
    await _type(tester, '😀' * 450);
    expect(find.text('450/500'), findsOneWidget);
    expect(_sendEnabled(tester), isTrue);
    await _leave(tester);
  });

  testWidgets('a 500 character message is sent', (tester) async {
    final chat = FakeChatRepository();
    await _pumpTab(tester, chat);
    await _type(tester, 'b' * 500);
    await tester.tap(find.byTooltip('Send'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(chat.sentBodies.single.length, 500);
    await _leave(tester);
  });

  testWidgets('a second message within a second shows "Slow down a little" '
      'and keeps the text', (tester) async {
    final chat = FakeChatRepository();
    await _pumpTab(tester, chat);
    await _type(tester, 'one');
    await tester.tap(find.byTooltip('Send'));
    await tester.pump(const Duration(milliseconds: 50));
    await _type(tester, 'two');
    await tester.tap(find.byTooltip('Send'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Slow down a little'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'two',
    );
    expect(chat.sentBodies, ['one']);
    await _leave(tester);
  });

  testWidgets('a failed message shows Not sent with Retry and Delete', (
    tester,
  ) async {
    final chat = FakeChatRepository()
      ..failNextSend = const ChatFailure(ChatFailureKind.network);
    await _pumpTab(tester, chat);
    await _type(tester, 'oops');
    await tester.tap(find.byTooltip('Send'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Not sent'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pump();
    expect(find.text('Not sent'), findsNothing);
    await _leave(tester);
  });

  testWidgets('a message that arrives while the reader is up in the history '
      'shows a "New messages" pill that scrolls down', (tester) async {
    final chat = FakeChatRepository(
      messages: [
        for (var i = 0; i < 40; i++)
          fakeMessage(
            id: 'm${i.toString().padLeft(2, '0')}',
            userId: 'user-2',
            body: 'message number $i',
            createdAt: DateTime.utc(2026, 11, 18, 12, 0, i),
          ),
      ],
    );
    await _pumpTab(tester, chat);
    expect(find.text('New messages'), findsNothing);

    // Scroll up into the history.
    await tester.drag(find.byType(ListView), const Offset(0, 500));
    await tester.pump();
    chat.externalInsert(
      fakeMessage(
        id: 'zzz',
        userId: 'user-2',
        body: 'a brand new one',
        createdAt: DateTime.utc(2026, 11, 18, 13),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('New messages'), findsOneWidget);

    final list = tester.widget<ListView>(find.byType(ListView)).controller!;
    expect(list.offset, greaterThan(32)); // really up in the history
    await tester.tap(find.text('New messages'));
    await tester.pumpAndSettle(); // the scroll animation needs frames
    expect(list.offset, 0);
    expect(find.text('New messages'), findsNothing);
    expect(_body('a brand new one'), findsOneWidget);
    await _leave(tester);
  });

  testWidgets('a message that arrives while the reader is at the bottom just '
      'shows, with no pill', (tester) async {
    final chat = FakeChatRepository();
    await _pumpTab(tester, chat);
    chat.externalInsert(fakeMessage(id: 'n', userId: 'user-2', body: 'live!'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_body('live!'), findsOneWidget);
    expect(find.text('New messages'), findsNothing);
    await _leave(tester);
  });

  testWidgets('a bubble is as tall as its text, and a hostile body with '
      'hundreds of lines is cut', (tester) async {
    final chat = FakeChatRepository(
      messages: [
        fakeMessage(id: 'a', userId: 'user-2', body: 'one line'),
        fakeMessage(
          id: 'b',
          userId: 'user-2',
          body: List.generate(200, (i) => 'line $i').join('\n\n'),
          createdAt: DateTime.utc(2026, 11, 18, 12, 1),
        ),
      ],
    );
    await _pumpTab(tester, chat);
    expect(tester.getSize(_body('one line')).height, lessThan(40));
    expect(find.textContaining('line 199', findRichText: true), findsNothing);
    await _leave(tester);
  });

  testWidgets('hostile text is shown cleaned, as plain selectable text', (
    tester,
  ) async {
    final chat = FakeChatRepository(
      messages: [
        fakeMessage(
          id: 'a',
          userId: 'user-2',
          body: 'see https://example.com now\u202E',
        ),
      ],
    );
    await _pumpTab(tester, chat);
    expect(_body('see https://example.com now'), findsOneWidget);
    expect(find.byType(SelectableText), findsOneWidget);
    await _leave(tester);
  });

  group('the unread badge on the Chat tab', () {
    Future<FakeChatRepository> openRoom(WidgetTester tester) async {
      final chat = FakeChatRepository();
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
        auth: FakeAuthRepository(signedIn: true),
        rooms: rooms,
        chat: chat,
      );
      GoRouter.of(tester.element(find.byType(HomeScreen))).go('/room/room-1');
      await tester.pumpAndSettle();
      return chat;
    }

    testWidgets('shows a count while another tab is open, and clears when '
        'Chat is opened', (tester) async {
      final chat = await openRoom(tester);
      expect(find.text('1'), findsNothing);
      chat.externalInsert(fakeMessage(id: 'a', userId: 'user-2', body: 'ping'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('1'), findsOneWidget);
      chat.externalInsert(fakeMessage(id: 'b', userId: 'user-2', body: 'pong'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('2'), findsOneWidget);

      await tester.tap(find.text('Chat'));
      await tester.pumpAndSettle();
      expect(find.text('2'), findsNothing);
      expect(_body('ping'), findsOneWidget);
      expect(_body('pong'), findsOneWidget);

      // While Chat shows, new messages do not count.
      chat.externalInsert(fakeMessage(id: 'c', userId: 'user-2', body: 'more'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('1'), findsNothing);
    });

    testWidgets('shows 9+ above nine, and nothing at zero', (tester) async {
      final chat = await openRoom(tester);
      for (var i = 0; i < 12; i++) {
        chat.externalInsert(
          fakeMessage(id: 'm$i', userId: 'user-2', body: 'msg $i'),
        );
      }
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('9+'), findsOneWidget);
      await tester.tap(find.text('Chat'));
      await tester.pumpAndSettle();
      expect(find.text('9+'), findsNothing);
    });
  });
}
