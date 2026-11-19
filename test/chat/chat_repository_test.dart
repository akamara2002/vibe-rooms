import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart' hide EnginePhase;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vibe_rooms/features/chat/data/supabase_chat_repository.dart';
import 'package:vibe_rooms/features/chat/domain/chat_failure.dart';

class _Sub implements ChatSubscription {
  _Sub(this.source);
  final _Source source;
  @override
  Future<void> close() async => source.closed++;
}

class _Source implements ChatSource {
  List<Map<String, dynamic>> rows = [];
  Map<String, dynamic>? insertResult;
  Object? insertError;
  Map<String, dynamic>? inserted;
  Map<String, dynamic>? profile;
  Object? profileError;
  Completer<void>? fetchGate;
  Object? subscribeError;
  int closed = 0;
  void Function(Map<String, dynamic>)? onInsert;
  void Function(bool)? onStatus;

  @override
  Future<List<Map<String, dynamic>>> fetchRecent(
    String roomId,
    int limit,
  ) async {
    if (fetchGate != null) await fetchGate!.future;
    return rows;
  }

  @override
  Future<Map<String, dynamic>?> insert(Map<String, dynamic> json) async {
    inserted = json;
    final error = insertError;
    if (error != null) throw error;
    return insertResult;
  }

  @override
  Future<Map<String, dynamic>?> fetchProfile(String userId) async {
    final error = profileError;
    if (error != null) throw error;
    return profile;
  }

  @override
  ChatSubscription subscribe(
    String roomId, {
    required void Function(Map<String, dynamic> row) onInsert,
    required void Function(bool joined) onStatus,
  }) {
    final error = subscribeError;
    if (error != null) throw error;
    this.onInsert = onInsert;
    this.onStatus = onStatus;
    return _Sub(this);
  }
}

Map<String, dynamic> _row(
  String id,
  String body, {
  String at = '2026-11-18T12:00:00+00:00',
  Object? profiles,
}) => {
  'id': id,
  'room_id': 'room-1',
  'user_id': 'user-2',
  'body': body,
  'created_at': at,
  'profiles': ?profiles,
};

SupabaseChatRepository _repo(_Source source, {String? me = 'user-1'}) =>
    SupabaseChatRepository.withSource(source, userId: () => me);

void main() {
  group('recent', () {
    test(
      'returns the newest first rows oldest first, with who sent them',
      () async {
        final source = _Source()
          ..rows = [
            _row(
              'b',
              'second',
              profiles: {'display_name': 'Bo', 'avatar_emoji': '🎸'},
            ),
            _row('a', 'first'),
          ];
        final messages = await _repo(source).recent('room-1');
        expect(messages.map((m) => m.id), ['a', 'b']);
        expect(messages.last.senderName, 'Bo');
        expect(messages.last.senderEmoji, '🎸');
        expect(messages.first.senderName, isNull); // no embed: realtime-like
      },
    );

    test('one unreadable row is skipped', () async {
      final source = _Source()
        ..rows = [
          _row('a', 'ok'),
          {'id': 5, 'oops': true},
        ];
      expect((await _repo(source).recent('room-1')).map((m) => m.id), ['a']);
    });

    test('a request that hangs fails after the timeout', () {
      fakeAsync((async) {
        final source = _Source()..fetchGate = Completer<void>();
        Object? error;
        _repo(source)
            .recent('room-1')
            .then(
              (_) {},
              onError: (Object e) {
                error = e;
              },
            );
        async.elapse(chatRequestTimeout + const Duration(seconds: 1));
        expect(error, isA<ChatFailure>());
        expect((error! as ChatFailure).kind, ChatFailureKind.network);
      });
    });
  });

  group('send', () {
    test(
      'inserts only the granted columns, as me, and returns the row',
      () async {
        final source = _Source()..insertResult = _row('new', 'hi there');
        final message = await _repo(source).send('room-1', 'hi there');
        expect(source.inserted, {
          'room_id': 'room-1',
          'user_id': 'user-1',
          'body': 'hi there',
        });
        for (final forbidden in ['id', 'created_at']) {
          expect(source.inserted!.containsKey(forbidden), isFalse);
        }
        expect(message.id, 'new');
      },
    );

    test('a blocked insert (no row came back) is a failure', () async {
      final source = _Source()..insertResult = null;
      await expectLater(
        _repo(source).send('room-1', 'hi'),
        throwsA(
          isA<ChatFailure>().having(
            (f) => f.kind,
            'kind',
            ChatFailureKind.notAllowed,
          ),
        ),
      );
    });

    test('signed out sends nothing', () async {
      final source = _Source();
      await expectLater(
        _repo(source, me: null).send('room-1', 'hi'),
        throwsA(isA<ChatFailure>()),
      );
      expect(source.inserted, isNull);
    });

    test('row level security and the body check are mapped', () async {
      for (final (code, kind) in [
        ('42501', ChatFailureKind.notAllowed),
        ('23514', ChatFailureKind.tooLong),
      ]) {
        final source = _Source()
          ..insertError = PostgrestException(message: 'x', code: code);
        await expectLater(
          _repo(source).send('room-1', 'hi'),
          throwsA(isA<ChatFailure>().having((f) => f.kind, 'kind', kind)),
        );
      }
    });

    test('other errors become a failure', () async {
      final source = _Source()..insertError = StateError('boom');
      await expectLater(
        _repo(source).send('room-1', 'hi'),
        throwsA(isA<ChatFailure>()),
      );
    });
  });

  group('sender', () {
    test('reads name and emoji', () async {
      final source = _Source()
        ..profile = {'display_name': 'Cy', 'avatar_emoji': '🔥'};
      final sender = await _repo(source).sender('user-3');
      expect(sender!.name, 'Cy');
      expect(sender.emoji, '🔥');
    });

    test('a missing profile or an error is null', () async {
      expect(await _repo(_Source()).sender('x'), isNull);
      final broken = _Source()..profileError = StateError('x');
      expect(await _repo(broken).sender('x'), isNull);
    });
  });

  group('watchNew', () {
    test('delivers inserts and calls onJoined on EVERY (re)join', () {
      fakeAsync((async) {
        final source = _Source();
        var joins = 0;
        final seen = <String>[];
        final sub = _repo(source)
            .watchNew('room-1', onJoined: () => joins++)
            .listen((m) => seen.add(m.id), onError: (Object _) {});
        async.flushMicrotasks();

        source.onStatus!(true);
        source.onInsert!(_row('a', 'one'));
        source.onStatus!(false);
        source.onStatus!(true); // a rejoin
        source.onInsert!(_row('b', 'two'));
        async.flushMicrotasks();

        expect(joins, 2);
        expect(seen, ['a', 'b']);
        sub.cancel();
      });
    });

    test('a malformed event is ignored, channel trouble is an error, and '
        'the stream stays open', () {
      fakeAsync((async) {
        final source = _Source();
        final seen = <String>[];
        final errors = <Object>[];
        final sub = _repo(source)
            .watchNew('room-1', onJoined: () {})
            .listen((m) => seen.add(m.id), onError: errors.add);
        async.flushMicrotasks();

        source.onInsert!({'nonsense': true});
        source.onStatus!(false);
        source.onInsert!(_row('a', 'still works'));
        async.flushMicrotasks();

        expect(errors.single, isA<ChatFailure>());
        expect(seen, ['a']);
        sub.cancel();
      });
    });

    test('a subscribe that throws is an error, not unhandled', () {
      fakeAsync((async) {
        final source = _Source()..subscribeError = StateError('socket');
        final errors = <Object>[];
        final sub = _repo(source)
            .watchNew('room-1', onJoined: () {})
            .listen((_) {}, onError: errors.add);
        async.flushMicrotasks();
        expect(errors.single, isA<ChatFailure>());
        sub.cancel();
      });
    });

    test('cancelling closes the channel and ignores late callbacks', () {
      fakeAsync((async) {
        final source = _Source();
        var joins = 0;
        final seen = <String>[];
        final sub = _repo(source)
            .watchNew('room-1', onJoined: () => joins++)
            .listen((m) => seen.add(m.id));
        async.flushMicrotasks();
        sub.cancel();
        async.flushMicrotasks();
        source.onInsert!(_row('late', 'x'));
        source.onStatus!(true);
        async.flushMicrotasks();
        expect(source.closed, 1);
        expect(seen, isEmpty);
        expect(joins, 0);
      });
    });
  });
}
