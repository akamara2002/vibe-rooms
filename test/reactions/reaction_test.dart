import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart' hide EnginePhase;
import 'package:vibe_rooms/features/player/presentation/sync_providers.dart';
import 'package:vibe_rooms/features/reactions/data/supabase_reaction_service.dart';
import 'package:vibe_rooms/features/reactions/domain/reaction.dart';
import 'package:vibe_rooms/features/reactions/presentation/reaction_controller.dart';

import '../fakes/fakes.dart';

class _Channel implements ReactionChannel {
  _Channel(this.transport);
  final _Transport transport;
  @override
  Future<void> send(Map<String, dynamic> payload) async =>
      transport.sent.add(payload);
  @override
  Future<void> close() async => transport.closed++;
}

class _Transport implements ReactionTransport {
  final sent = <Map<String, dynamic>>[];
  int connects = 0;
  int closed = 0;
  void Function(Object? payload)? onPayload;

  @override
  ReactionChannel connect(
    String roomId, {
    required void Function(Object? payload) onPayload,
  }) {
    connects++;
    this.onPayload = onPayload;
    return _Channel(this);
  }
}

void main() {
  group('the fixed set', () {
    test('six reactions, defined once, each with a key and an emoji', () {
      expect(ReactionType.values, hasLength(6));
      expect(ReactionType.values.map((t) => t.emoji), [
        '🔥',
        '❤️',
        '🙌',
        '😂',
        '🎶',
        '👏',
      ]);
      expect(ReactionType.values.map((t) => t.key).toSet(), hasLength(6));
    });
  });

  group('parseReactionPayload (strict)', () {
    test('accepts the payload as the real client delivers it (flat, with its '
        'own event and type keys)', () {
      expect(
        parseReactionPayload({
          'emoji': 'fire',
          'event': 'reaction',
          'type': 'broadcast',
        })!.type,
        ReactionType.fire,
      );
    });

    test('accepts {emoji: <key>}, bare or nested in the realtime envelope', () {
      expect(parseReactionPayload({'emoji': 'fire'})!.type, ReactionType.fire);
      expect(
        parseReactionPayload({
          'event': 'reaction',
          'type': 'broadcast',
          'payload': {'emoji': 'clap'},
        })!.type,
        ReactionType.clap,
      );
    });

    test('every known key is accepted', () {
      for (final type in ReactionType.values) {
        expect(parseReactionPayload({'emoji': type.key})!.type, type);
      }
    });

    test('any key other than the client\'s event and type is dropped', () {
      expect(
        parseReactionPayload({
          'emoji': 'fire',
          'event': 'reaction',
          'type': 'broadcast',
          'user': 'x',
        }),
        isNull,
      );
      expect(
        parseReactionPayload({'event': 'reaction', 'type': 'broadcast'}),
        isNull,
      );
    });

    test('unknown keys are dropped', () {
      expect(parseReactionPayload({'emoji': 'fire', 'extra': 1}), isNull);
      expect(parseReactionPayload({'emoji': 'fire', 'user': 'x'}), isNull);
      expect(parseReactionPayload({'other': 'fire'}), isNull);
      expect(parseReactionPayload({}), isNull);
    });

    test('wrong types are dropped', () {
      for (final bad in [
        1,
        true,
        null,
        ['fire'],
        {'fire': 1},
        1.5,
      ]) {
        expect(parseReactionPayload({'emoji': bad}), isNull, reason: '$bad');
      }
    });

    test('an emoji outside the set is dropped (the wire carries keys, not '
        'emoji)', () {
      expect(parseReactionPayload({'emoji': '🔥'}), isNull);
      expect(parseReactionPayload({'emoji': 'skull'}), isNull);
      expect(parseReactionPayload({'emoji': 'FIRE'}), isNull);
      expect(parseReactionPayload({'emoji': ''}), isNull);
      expect(parseReactionPayload({'emoji': 'fire '}), isNull);
    });

    test('an oversized payload is dropped', () {
      expect(parseReactionPayload({'emoji': 'fire' * 100}), isNull);
    });

    test('things that are not a map are dropped', () {
      for (final bad in [
        null,
        'fire',
        42,
        ['emoji', 'fire'],
        true,
      ]) {
        expect(parseReactionPayload(bad), isNull, reason: '$bad');
      }
    });

    test('a nested non-map payload is dropped', () {
      expect(parseReactionPayload({'payload': 'fire'}), isNull);
      expect(
        parseReactionPayload({
          'payload': {'emoji': 'fire', 'x': 1},
        }),
        isNull,
      );
    });
  });

  group('SupabaseReactionService', () {
    test('sends only {emoji: <key>}', () async {
      final transport = _Transport();
      final service = SupabaseReactionService(transport);
      final sub = service.incoming('room-1').listen((_) {});
      await service.send('room-1', ReactionType.heart);
      expect(transport.sent.single, {'emoji': 'heart'});
      await sub.cancel();
    });

    test('a send with no listener opens no channel', () async {
      final transport = _Transport();
      final service = SupabaseReactionService(transport);
      await service.send('room-1', ReactionType.heart);
      expect(transport.sent, isEmpty);
    });

    test('a huge or non-string emoji value is dropped', () {
      expect(parseReactionPayload({'emoji': 'x' * 100000}), isNull);
      expect(
        parseReactionPayload({
          'emoji': ['fire'],
        }),
        isNull,
      );
    });

    test(
      'valid reactions come through, everything else is dropped silently',
      () {
        fakeAsync((async) {
          final transport = _Transport();
          final service = SupabaseReactionService(transport);
          final seen = <ReactionType>[];
          final sub = service
              .incoming('room-1')
              .listen((r) => seen.add(r.type));
          async.flushMicrotasks();

          transport.onPayload!({
            'payload': {'emoji': 'fire'},
          });
          transport.onPayload!({
            'payload': {'emoji': 'bomb'},
          });
          transport.onPayload!({
            'payload': {'emoji': 'notes', 'x': 1},
          });
          transport.onPayload!('garbage');
          transport.onPayload!(null);
          transport.onPayload!({
            'payload': {'emoji': 'laugh'},
          });
          async.flushMicrotasks();

          expect(seen, [ReactionType.fire, ReactionType.laugh]);
          sub.cancel();
        });
      },
    );

    test('one channel serves sending and receiving, and closes when the '
        'listener goes', () {
      fakeAsync((async) {
        final transport = _Transport();
        final service = SupabaseReactionService(transport);
        final sub = service.incoming('room-1').listen((_) {});
        async.flushMicrotasks();
        service.send('room-1', ReactionType.fire);
        service.send('room-1', ReactionType.clap);
        async.flushMicrotasks();
        expect(transport.connects, 1);
        sub.cancel();
        async.flushMicrotasks();
        expect(transport.closed, 1);
      });
    });
  });

  group('ReactionController', () {
    ProviderContainer container(FakeAsync async, FakeReactionService service) {
      final base = DateTime.utc(2026);
      return ProviderContainer(
        overrides: [
          reactionServiceProvider.overrideWithValue(service),
          localClockProvider.overrideWithValue(() => base.add(async.elapsed)),
        ],
      );
    }

    void rigTest(
      String name,
      void Function(
        FakeAsync async,
        FakeReactionService service,
        ProviderContainer c,
        ReactionController controller,
        ReactionState Function() state,
      )
      body,
    ) {
      test(name, () {
        fakeAsync((async) {
          final service = FakeReactionService();
          final c = container(async, service);
          final sub = c.listen(reactionControllerProvider('room-1'), (_, _) {});
          async.flushMicrotasks();
          body(
            async,
            service,
            c,
            c.read(reactionControllerProvider('room-1').notifier),
            sub.read,
          );
          c.dispose();
        });
      });
    }

    rigTest('a tap animates at once and is sent', (
      async,
      service,
      c,
      ctl,
      state,
    ) {
      ctl.tap(ReactionType.fire);
      async.flushMicrotasks();
      expect(state().alive, hasLength(1));
      expect(service.sent, [ReactionType.fire]);
    });

    rigTest('at most $maxSendsPerSecond are sent per second; extra taps still '
        'animate', (async, service, c, ctl, state) {
      for (var i = 0; i < 12; i++) {
        ctl.tap(ReactionType.fire);
      }
      async.flushMicrotasks();
      expect(service.sent, hasLength(maxSendsPerSecond));
      expect(state().alive, hasLength(12));
      // A second later sending resumes.
      async.elapse(const Duration(milliseconds: 1001));
      ctl.tap(ReactionType.heart);
      async.flushMicrotasks();
      expect(service.sent, hasLength(maxSendsPerSecond + 1));
    });

    rigTest('a failing send is swallowed', (async, service, c, ctl, state) {
      service.failSends = true;
      ctl.tap(ReactionType.fire);
      async.flushMicrotasks();
      expect(state().alive, hasLength(1));
    });

    rigTest('incoming reactions float, at most $maxIncomingPerSecond new per '
        'second', (async, service, c, ctl, state) {
      for (var i = 0; i < 25; i++) {
        service.emit(ReactionType.clap);
      }
      async.flushMicrotasks();
      expect(state().alive, hasLength(maxIncomingPerSecond));
      async.elapse(const Duration(milliseconds: 1001));
      for (var i = 0; i < 25; i++) {
        service.emit(ReactionType.clap);
      }
      async.flushMicrotasks();
      expect(state().alive, hasLength(2 * maxIncomingPerSecond));
    });

    rigTest('at most $maxAliveReactions alive at once (extras are dropped)', (
      async,
      service,
      c,
      ctl,
      state,
    ) {
      // 10 per second is the most that is accepted; nothing expires yet
      // (2 s life), so two bursts a second apart are both alive.
      for (var i = 0; i < 10; i++) {
        service.emit(ReactionType.fire);
      }
      async.elapse(const Duration(milliseconds: 1001));
      for (var i = 0; i < 10; i++) {
        service.emit(ReactionType.fire);
      }
      async.flushMicrotasks();
      expect(state().alive.length, 20);
      for (var i = 0; i < 10; i++) {
        ctl.tap(ReactionType.fire); // local taps share the cap
      }
      async.flushMicrotasks();
      expect(state().alive.length, maxAliveReactions);
      for (var i = 0; i < 10; i++) {
        ctl.tap(ReactionType.fire);
      }
      expect(state().alive.length, maxAliveReactions);
    });

    rigTest('emojis disappear after their life, and the timer stops', (
      async,
      service,
      c,
      ctl,
      state,
    ) {
      ctl.tap(ReactionType.notes);
      expect(state().alive, hasLength(1));
      expect(async.periodicTimerCount, greaterThan(0));
      async.elapse(reactionLifetime + const Duration(milliseconds: 600));
      expect(state().alive, isEmpty);
      expect(async.periodicTimerCount, 0);
    });

    rigTest('every reaction pulses (for reduced motion)', (
      async,
      service,
      c,
      ctl,
      state,
    ) {
      service.emit(ReactionType.heart);
      async.flushMicrotasks();
      expect(state().pulseCount, 1);
      expect(state().pulseType, ReactionType.heart);
    });

    test('leaving the room cancels the listener and the timer', () {
      fakeAsync((async) {
        final service = FakeReactionService();
        final c = container(async, service);
        c.listen(reactionControllerProvider('room-1'), (_, _) {});
        async.flushMicrotasks();
        c
            .read(reactionControllerProvider('room-1').notifier)
            .tap(ReactionType.fire);
        expect(service.listens, 1);
        c.dispose();
        async.flushMicrotasks();
        expect(service.cancels, 1);
        expect(async.periodicTimerCount, 0);
      });
    });
  });
}
