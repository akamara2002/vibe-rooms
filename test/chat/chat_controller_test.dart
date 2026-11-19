import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart' hide EnginePhase;
import 'package:vibe_rooms/features/auth/presentation/auth_providers.dart';
import 'package:vibe_rooms/features/chat/domain/chat_failure.dart';
import 'package:vibe_rooms/features/chat/domain/chat_message.dart';
import 'package:vibe_rooms/features/chat/domain/message.dart';
import 'package:vibe_rooms/features/chat/presentation/chat_controller.dart';
import 'package:vibe_rooms/features/chat/presentation/chat_providers.dart';
import 'package:vibe_rooms/features/player/presentation/sync_providers.dart';
import 'package:vibe_rooms/features/rooms/presentation/rooms_providers.dart';

import '../fakes/fakes.dart';

final _base = DateTime.utc(2026, 11, 18, 12);

class _Rig {
  _Rig(
    this.async, {
    List<Message>? messages,
    Map<String, ChatSender>? profiles,
  }) {
    chat = FakeChatRepository(
      messages: messages,
      now: trueNow,
      profiles:
          profiles ??
          {
            'user-2': const ChatSender(name: 'Bo', emoji: '🎸'),
            'user-1': const ChatSender(name: 'Me', emoji: '🎧'),
          },
    );
    container = ProviderContainer(
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
        localClockProvider.overrideWithValue(trueNow),
      ],
    );
    sub = container.listen(chatControllerProvider('room-1'), (_, _) {});
    container.listen(roomMembersProvider('room-1'), (_, _) {});
  }

  final FakeAsync async;
  late final FakeChatRepository chat;
  late final ProviderContainer container;
  late final ProviderSubscription<ChatState> sub;

  DateTime trueNow() => _base.add(async.elapsed);
  ChatState get state => sub.read();
  ChatController get controller =>
      container.read(chatControllerProvider('room-1').notifier);

  List<String> get bodies => state.messages.map((m) => m.body).toList();

  void elapse([Duration d = const Duration(milliseconds: 50)]) {
    async.elapse(d);
    async.flushMicrotasks();
  }

  /// Sends and waits long enough for the rate limiter (1 per second).
  ChatFailure? say(String text) {
    final failure = controller.send(text);
    elapse(const Duration(milliseconds: 1100));
    return failure;
  }

  void dispose() => container.dispose();
}

void main() {
  void rigTest(
    String name,
    void Function(_Rig rig) body, {
    List<Message> Function()? messages,
    Map<String, ChatSender>? profiles,
  }) {
    test(name, () {
      fakeAsync((async) {
        final rig = _Rig(async, messages: messages?.call(), profiles: profiles);
        rig.elapse(const Duration(seconds: 1));
        body(rig);
        rig.dispose();
      });
    });
  }

  Message at(String id, String user, String body, int seconds) => fakeMessage(
    id: id,
    userId: user,
    body: body,
    createdAt: _base.add(Duration(seconds: seconds)),
  );

  group('loading', () {
    rigTest(
      'shows the recent messages, oldest first, with who sent them',
      (rig) {
        expect(rig.state.loading, isFalse);
        expect(rig.bodies, ['one', 'two', 'three']);
        expect(rig.state.messages.first.senderName, 'Bo');
        expect(rig.state.messages.first.senderEmoji, '🎸');
        expect(rig.state.unread, 0); // the first load is not "unread"
      },
      messages: () => [
        at('c', 'user-2', 'three', 3),
        at('a', 'user-2', 'one', 1),
        at('b', 'user-2', 'two', 2),
      ],
    );

    test('a failed first load is shown with a way to retry', () {
      fakeAsync((async) {
        final rig = _Rig(async, messages: [fakeMessage()]);
        rig.chat.failRecent = const ChatFailure(ChatFailureKind.network);
        rig.elapse(const Duration(seconds: 1));
        expect(rig.state.loadFailure, isNotNull);
        expect(rig.state.messages, isEmpty);
        rig.chat.failRecent = null;
        rig.controller.reload();
        rig.elapse();
        expect(rig.state.loadFailure, isNull);
        expect(rig.bodies, ['hello']);
        rig.dispose();
      });
    });
  });

  group('sending', () {
    rigTest('shows the message at once as sending, then as the real row', (
      rig,
    ) {
      rig.chat.sendGate = Completer<void>();
      expect(rig.controller.send('hi there'), isNull);
      rig.elapse();
      expect(rig.state.messages, hasLength(1));
      expect(rig.state.messages.single.state, ChatSendState.sending);
      expect(rig.state.messages.single.id, startsWith('tmp-'));

      rig.chat.sendGate!.complete();
      rig.elapse();
      expect(rig.state.messages, hasLength(1));
      expect(rig.state.messages.single.state, ChatSendState.sent);
      expect(rig.state.messages.single.id, startsWith('srv-'));
      expect(rig.chat.sentBodies, ['hi there']);
    });

    rigTest('the realtime echo that comes after is ignored (same id)', (rig) {
      rig.chat.echoMode = EchoMode.afterReturn;
      rig.controller.send('hello world');
      rig.elapse(const Duration(seconds: 1));
      expect(rig.bodies, ['hello world']);
    });

    rigTest('an echo that arrives BEFORE send() returns does not duplicate', (
      rig,
    ) {
      rig.chat.echoMode = EchoMode.beforeReturn;
      rig.controller.send('hello world');
      rig.elapse(const Duration(seconds: 1));
      expect(rig.bodies, ['hello world']);
      expect(rig.state.messages.single.state, ChatSendState.sent);
    });

    rigTest('no echo at all still ends as one sent message', (rig) {
      rig.chat.echoMode = EchoMode.none;
      rig.controller.send('quiet');
      rig.elapse(const Duration(seconds: 1));
      expect(rig.bodies, ['quiet']);
    });

    rigTest('the same text twice: each echo confirms one temp, no duplicates', (
      rig,
    ) {
      rig.chat.echoMode = EchoMode.beforeReturn;
      rig.say('lol');
      rig.say('lol');
      rig.elapse(const Duration(seconds: 1));
      expect(rig.bodies, ['lol', 'lol']);
      expect(rig.state.messages.every((m) => !m.isPending), isTrue);
    });

    rigTest('my own messages show my name from the room members', (rig) {
      rig.say('hi');
      expect(rig.state.messages.single.senderName, 'Me');
    });

    rigTest('whitespace-only and over-long text are refused before anything '
        'is sent', (rig) {
      expect(rig.controller.send('   \n '), isA<ChatFailure>());
      expect(rig.controller.send('a' * 501)!.kind, ChatFailureKind.tooLong);
      expect(rig.controller.send('\u0000')!.kind, ChatFailureKind.empty);
      rig.elapse();
      expect(rig.chat.sentBodies, isEmpty);
      expect(rig.state.messages, isEmpty);
    });

    rigTest('the text is cleaned before it is sent', (rig) {
      rig.say('  hi\u0007 there\n\n\n\nfriend  ');
      expect(rig.chat.sentBodies, ['hi there\n\nfriend']);
    });
  });

  group('a failed send', () {
    rigTest('stays in the list as failed; Retry sends it again', (rig) {
      rig.chat.failNextSend = const ChatFailure(ChatFailureKind.network);
      rig.say('hello');
      expect(rig.state.messages.single.state, ChatSendState.failed);
      expect(rig.state.messages.single.failureMessage, isNotNull);

      rig.controller.retry(rig.state.messages.single.id);
      rig.elapse(const Duration(seconds: 1));
      expect(rig.state.messages, hasLength(1));
      expect(rig.state.messages.single.state, ChatSendState.sent);
      expect(rig.chat.sentBodies, ['hello', 'hello']);
    });

    rigTest('Delete removes it locally and nothing is sent', (rig) {
      rig.chat.failNextSend = const ChatFailure(ChatFailureKind.notAllowed);
      rig.say('hello');
      rig.controller.deleteLocal(rig.state.messages.single.id);
      rig.elapse();
      expect(rig.state.messages, isEmpty);
      expect(rig.chat.sentBodies, ['hello']);
    });

    rigTest('Delete and Retry ignore messages that are not failed', (rig) {
      rig.chat.sendGate = Completer<void>();
      rig.controller.send('slow');
      rig.elapse();
      final id = rig.state.messages.single.id;
      rig.controller.deleteLocal(id);
      rig.controller.retry(id);
      rig.elapse();
      expect(rig.state.messages, hasLength(1));
      expect(rig.chat.sentBodies, ['slow']);
    });

    rigTest('a failed message is pinned at the bottom, in the order sent', (
      rig,
    ) {
      rig.chat.failNextSend = const ChatFailure(ChatFailureKind.network);
      rig.say('first (fails)');
      rig.chat.externalInsert(
        fakeMessage(id: 'x', userId: 'user-2', body: 'from Bo'),
      );
      rig.say('second');
      // Confirmed messages by time, then the failed one pinned at the bottom.
      expect(rig.bodies, ['from Bo', 'second', 'first (fails)']);
      expect(rig.state.messages.last.state, ChatSendState.failed);
    });

    rigTest('an echo confirms a failed message whose answer was lost', (rig) {
      rig.chat.echoMode = EchoMode.none;
      rig.chat.failNextSend = const ChatFailure(ChatFailureKind.network);
      rig.say('did it arrive?');
      expect(rig.state.messages.single.state, ChatSendState.failed);
      // The insert had succeeded after all; Realtime delivers it.
      rig.chat.externalInsert(
        fakeMessage(
          id: 'real',
          userId: 'user-1',
          body: 'did it arrive?',
          createdAt: rig.trueNow(),
        ),
      );
      rig.elapse();
      expect(rig.state.messages, hasLength(1));
      expect(rig.state.messages.single.state, ChatSendState.sent);
    });

    rigTest('a sending message is confirmed before a failed one with the same '
        'text', (rig) {
      rig.chat.failNextSend = const ChatFailure(ChatFailureKind.network);
      rig.say('lol'); // fails
      rig.chat.echoMode = EchoMode.beforeReturn;
      rig.say('lol'); // succeeds
      rig.elapse(const Duration(seconds: 1));
      final states = rig.state.messages.map((m) => m.state).toList();
      expect(states, [ChatSendState.sent, ChatSendState.failed]);
    });
  });

  group('rate limits', () {
    rigTest('one message per second: the second is refused, kept by the '
        'caller, with a hint', (rig) {
      expect(rig.controller.send('one'), isNull);
      final failure = rig.controller.send('two');
      expect(failure!.kind, ChatFailureKind.rateLimited);
      rig.elapse();
      expect(rig.state.notice, 'Slow down a little');
      expect(rig.chat.sentBodies, ['one']);
      expect(rig.state.messages, hasLength(1)); // two was not added
      // The hint goes away by itself.
      rig.elapse(const Duration(seconds: 4));
      expect(rig.state.notice, isNull);
      // And after a second it works.
      expect(rig.controller.send('two'), isNull);
    });

    rigTest('twenty per minute', (rig) {
      for (var i = 0; i < 20; i++) {
        expect(rig.controller.send('m$i'), isNull, reason: 'message $i');
        rig.elapse(const Duration(milliseconds: 1500));
      }
      // 30 s in: still inside the minute.
      expect(
        rig.controller.send('too many')!.kind,
        ChatFailureKind.rateLimited,
      );
      rig.elapse(const Duration(seconds: 31));
      expect(rig.controller.send('later'), isNull);
    });

    rigTest('five rapid sends: one goes, four are refused, nothing crashes', (
      rig,
    ) {
      var refused = 0;
      for (var i = 0; i < 5; i++) {
        if (rig.controller.send('m$i') != null) refused++;
      }
      rig.elapse();
      expect(refused, 4);
      expect(rig.state.notice, 'Slow down a little');
    });

    rigTest('a retry counts against the limit', (rig) {
      rig.chat.failNextSend = const ChatFailure(ChatFailureKind.network);
      rig.controller.send('hello');
      rig.elapse();
      final id = rig.state.messages.single.id;
      rig.controller.retry(id); // within the same second
      rig.elapse();
      expect(rig.state.messages.single.state, ChatSendState.failed);
      expect(rig.state.notice, 'Slow down a little');
      rig.elapse(const Duration(seconds: 2));
      rig.controller.retry(id);
      rig.elapse();
      expect(rig.state.messages.single.state, ChatSendState.sent);
    });
  });

  group('incoming messages', () {
    rigTest('arrive live with the sender resolved from the members', (rig) {
      rig.chat.externalInsert(
        fakeMessage(
          id: 'n1',
          userId: 'user-2',
          body: 'hey',
          createdAt: rig.trueNow(),
        ),
      );
      rig.elapse();
      expect(rig.bodies, ['hey']);
      expect(rig.state.messages.single.senderName, 'Bo');
    });

    rigTest('the same message twice (event plus refetch) appears once', (rig) {
      final message = fakeMessage(id: 'n1', userId: 'user-2', body: 'hey');
      rig.chat.externalInsert(message);
      rig.chat.externalInsert(message);
      rig.chat.rejoin();
      rig.elapse();
      expect(rig.bodies, ['hey']);
    });

    rigTest('are ordered by time, then id, whatever order they arrive in', (
      rig,
    ) {
      rig.chat.externalInsert(at('c', 'user-2', 'third', 3));
      rig.chat.externalInsert(at('a', 'user-2', 'first', 1));
      rig.chat.externalInsert(at('b2', 'user-2', 'second-b', 2));
      rig.chat.externalInsert(at('b1', 'user-2', 'second-a', 2));
      rig.elapse();
      expect(rig.bodies, ['first', 'second-a', 'second-b', 'third']);
    });

    rigTest('hostile bodies are cleaned before they are shown', (rig) {
      rig.chat.externalInsert(
        fakeMessage(
          id: 'h1',
          userId: 'user-2',
          body: 'safe\u202Etext\n\n\n\n\nmore',
        ),
      );
      rig.chat.externalInsert(
        fakeMessage(id: 'h2', userId: 'user-2', body: '\u0000\u202E'),
      );
      rig.elapse();
      expect(rig.bodies, ['safetext\n\nmore']); // the empty one is dropped
    });

    rigTest('unknown senders show "Someone", then the looked-up name, with '
        'one lookup however many messages arrive', (rig) {
      rig.chat.profiles['user-9'] = const ChatSender(
        name: 'Newbie',
        emoji: '🌟',
      );
      for (var i = 0; i < 5; i++) {
        rig.chat.externalInsert(
          fakeMessage(id: 'q$i', userId: 'user-9', body: 'hi $i'),
        );
      }
      rig.elapse();
      expect(rig.chat.lookups, 1);
      expect(rig.state.messages.every((m) => m.senderName == 'Newbie'), isTrue);
    });

    rigTest('a failed lookup stays "Someone" and is not retried in a loop', (
      rig,
    ) {
      for (var i = 0; i < 3; i++) {
        rig.chat.externalInsert(
          fakeMessage(id: 'q$i', userId: 'ghost', body: 'boo $i'),
        );
      }
      rig.elapse();
      expect(
        rig.state.messages.every((m) => m.senderName == unknownSenderName),
        isTrue,
      );
      expect(rig.chat.lookups, 1);
    });

    rigTest('keeps at most $maxMessagesInMemory messages (the oldest go)', (
      rig,
    ) {
      for (var i = 0; i < 250; i++) {
        rig.chat.externalInsert(
          at('m${i.toString().padLeft(3, '0')}', 'user-2', 'msg $i', i),
        );
      }
      rig.elapse();
      expect(rig.state.messages, hasLength(maxMessagesInMemory));
      expect(rig.bodies.first, 'msg 50');
      expect(rig.bodies.last, 'msg 249');
    });

    rigTest('pending messages are never evicted by the cap', (rig) {
      rig.chat.sendGate = Completer<void>();
      rig.controller.send('still sending');
      for (var i = 0; i < 250; i++) {
        rig.chat.externalInsert(
          at('m${i.toString().padLeft(3, '0')}', 'user-2', 'msg $i', i),
        );
      }
      rig.elapse();
      expect(rig.state.messages.last.body, 'still sending');
      expect(rig.state.messages.last.state, ChatSendState.sending);
      expect(rig.state.messages.length, maxMessagesInMemory + 1);
    });
  });

  group('after a reconnect', () {
    rigTest('missed messages are fetched and merged, without duplicates', (
      rig,
    ) {
      rig.chat.externalInsert(at('a', 'user-2', 'before', 1));
      rig.elapse();
      rig.chat.missedInsert(at('b', 'user-2', 'while away', 2));
      rig.chat.missedInsert(at('c', 'user-2', 'also missed', 3));
      rig.chat.rejoin();
      rig.elapse();
      expect(rig.bodies, ['before', 'while away', 'also missed']);
    });

    rigTest('the first join also re-reads (events before the subscribe are '
        'not replayed)', (rig) {
      final before = rig.chat.recentCalls;
      rig.chat.missedInsert(at('a', 'user-2', 'in the gap', 1));
      rig.chat.rejoin(); // the first onJoined
      rig.elapse();
      expect(rig.chat.recentCalls, before + 1);
      expect(rig.bodies, ['in the gap']);
    });

    rigTest('pending and failed messages survive the merge', (rig) {
      rig.chat.failNextSend = const ChatFailure(ChatFailureKind.network);
      rig.say('mine (fails)');
      rig.chat.sendGate = Completer<void>();
      rig.controller.send('mine (sending)');
      rig.chat.missedInsert(at('a', 'user-2', 'theirs', 1));
      rig.chat.rejoin();
      rig.elapse();
      expect(rig.bodies, ['theirs', 'mine (fails)', 'mine (sending)']);
    });

    rigTest('my own message found by the refetch confirms its temp', (rig) {
      rig.chat.echoMode = EchoMode.none;
      rig.chat.sendGate = Completer<void>();
      rig.controller.send('hello');
      rig.chat.missedInsert(
        fakeMessage(
          id: 'srv-x',
          userId: 'user-1',
          body: 'hello',
          createdAt: rig.trueNow(),
        ),
      );
      rig.chat.rejoin();
      rig.elapse();
      expect(rig.bodies, ['hello']);
      expect(rig.state.messages.single.state, ChatSendState.sent);
    });

    rigTest('more new messages than one window leaves no hole in the middle', (
      rig,
    ) {
      rig.chat.externalInsert(at('old', 'user-2', 'old news', 0));
      rig.elapse();
      for (var i = 0; i < 80; i++) {
        rig.chat.missedInsert(
          at('n${i.toString().padLeft(3, '0')}', 'user-2', 'new $i', 100 + i),
        );
      }
      rig.chat.rejoin();
      rig.elapse();
      expect(rig.bodies, isNot(contains('old news')));
      expect(rig.state.messages, hasLength(recentWindow));
      expect(rig.bodies.last, 'new 79');
    });
  });

  group('unread', () {
    rigTest('counts other people\'s messages while the chat is not showing', (
      rig,
    ) {
      rig.chat.externalInsert(at('a', 'user-2', 'one', 1));
      rig.chat.externalInsert(at('b', 'user-2', 'two', 2));
      rig.elapse();
      expect(rig.state.unread, 2);
    });

    rigTest('my own messages are not unread', (rig) {
      rig.chat.echoMode = EchoMode.beforeReturn;
      rig.say('mine');
      expect(rig.state.unread, 0);
    });

    rigTest('opening the chat clears it, and nothing counts while it shows', (
      rig,
    ) {
      rig.chat.externalInsert(at('a', 'user-2', 'one', 1));
      rig.elapse();
      expect(rig.state.unread, 1);
      rig.controller.setChatVisible(true);
      expect(rig.state.unread, 0);
      rig.chat.externalInsert(at('b', 'user-2', 'two', 2));
      rig.elapse();
      expect(rig.state.unread, 0);
      rig.controller.setChatVisible(false);
      rig.chat.externalInsert(at('c', 'user-2', 'three', 3));
      rig.elapse();
      expect(rig.state.unread, 1);
    });

    rigTest('the same message twice counts once', (rig) {
      final message = at('a', 'user-2', 'one', 1);
      rig.chat.externalInsert(message);
      rig.chat.externalInsert(message);
      rig.chat.rejoin();
      rig.elapse();
      expect(rig.state.unread, 1);
    });

    rigTest('messages revealed by a reconnect count too', (rig) {
      rig.chat.missedInsert(at('a', 'user-2', 'missed', 1));
      rig.chat.missedInsert(at('b', 'user-2', 'missed too', 2));
      rig.chat.rejoin();
      rig.elapse();
      expect(rig.state.unread, 2);
    });

    rigTest('a message that is empty after cleaning is not unread', (rig) {
      rig.chat.externalInsert(
        fakeMessage(id: 'e', userId: 'user-2', body: '\u202E\u0000'),
      );
      rig.elapse();
      expect(rig.state.unread, 0);
    });
  });

  group('leaving the room', () {
    test('cancels the subscription and every timer', () {
      fakeAsync((async) {
        final rig = _Rig(async);
        rig.elapse(const Duration(seconds: 1));
        rig.controller.send('one');
        rig.controller.send('two'); // starts the notice timer
        expect(rig.chat.watchCount, 1);
        rig.dispose();
        async.flushMicrotasks();
        expect(rig.chat.cancelCount, 1);
        async.elapse(const Duration(minutes: 1));
        expect(async.nonPeriodicTimerCount, 0);
        expect(async.periodicTimerCount, 0);
      });
    });
  });
}
