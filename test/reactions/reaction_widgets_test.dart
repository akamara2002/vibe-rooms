import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart' hide EnginePhase;
import 'package:material_ui/material_ui.dart';
import 'package:vibe_rooms/features/player/presentation/sync_providers.dart';
import 'package:vibe_rooms/features/reactions/domain/reaction.dart';
import 'package:vibe_rooms/features/reactions/presentation/reaction_bar.dart';
import 'package:vibe_rooms/features/reactions/presentation/reaction_controller.dart';
import 'package:vibe_rooms/features/reactions/presentation/reaction_overlay.dart';

import '../fakes/fakes.dart';

Future<void> _pump(
  WidgetTester tester,
  FakeReactionService service, {
  bool reduceMotion = false,
}) async {
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        reactionServiceProvider.overrideWithValue(service),
        // The test binding's clock follows pumped (fake) time.
        localClockProvider.overrideWithValue(() => tester.binding.clock.now()),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(disableAnimations: reduceMotion),
          child: child!,
        ),
        home: Scaffold(
          body: Column(
            children: [
              SizedBox(
                height: 300,
                child: Stack(
                  children: const [
                    Positioned.fill(child: ReactionOverlay(roomId: 'room-1')),
                  ],
                ),
              ),
              const ReactionBar(roomId: 'room-1'),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _leave(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 3));
}

Finder _button(String emoji) =>
    find.descendant(of: find.byType(ReactionBar), matching: find.text(emoji));

int _floating(WidgetTester tester) => find
    .descendant(of: find.byType(ReactionOverlay), matching: find.byType(Text))
    .evaluate()
    .length;

void main() {
  testWidgets(
    'six reaction buttons, each at least 44 px, with a spoken label',
    (tester) async {
      await _pump(tester, FakeReactionService());
      for (final type in ReactionType.values) {
        expect(
          find.bySemanticsLabel('Send ${type.label} reaction'),
          findsOneWidget,
        );
        final size = tester.getSize(
          find.ancestor(
            of: _button(type.emoji),
            matching: find.byType(InkWell),
          ),
        );
        expect(size.width, greaterThanOrEqualTo(44));
        expect(size.height, greaterThanOrEqualTo(44));
      }
      await _leave(tester);
    },
  );

  testWidgets('a tap sends once and floats an emoji', (tester) async {
    final service = FakeReactionService();
    await _pump(tester, service);
    await tester.tap(_button('🔥'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(service.sent, [ReactionType.fire]);
    expect(_floating(tester), 1);
    await _leave(tester);
  });

  testWidgets('spamming a button sends at most 5 in a second, never freezes', (
    tester,
  ) async {
    final service = FakeReactionService();
    await _pump(tester, service);
    for (var i = 0; i < 25; i++) {
      await tester.tap(_button('👏'));
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(service.sent.length, lessThanOrEqualTo(maxSendsPerSecond));
    expect(_floating(tester), 25);
    await tester.pump(const Duration(seconds: 3)); // they all fade away
    expect(_floating(tester), 0);
    await _leave(tester);
  });

  testWidgets('never more than $maxAliveReactions floating at once', (
    tester,
  ) async {
    final service = FakeReactionService();
    await _pump(tester, service);
    for (var i = 0; i < 50; i++) {
      await tester.tap(_button('🎶'));
      await tester.pump(const Duration(milliseconds: 5));
    }
    expect(_floating(tester), maxAliveReactions);
    await _leave(tester);
  });

  testWidgets('incoming reactions float too, and take no taps', (tester) async {
    final service = FakeReactionService();
    await _pump(tester, service);
    service.emit(ReactionType.heart);
    await tester.pump(const Duration(milliseconds: 100));
    expect(_floating(tester), 1);
    expect(
      find.ancestor(
        of: find.descendant(
          of: find.byType(ReactionOverlay),
          matching: find.byType(Text),
        ),
        matching: find.byType(IgnorePointer),
      ),
      findsWidgets,
    );
    await _leave(tester);
  });

  testWidgets('with reduced motion nothing floats; the bar pulses instead', (
    tester,
  ) async {
    final service = FakeReactionService();
    await _pump(tester, service, reduceMotion: true);
    await tester.tap(_button('🔥'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(service.sent, [ReactionType.fire]); // still sent
    expect(_floating(tester), 0);

    final color = tester
        .widget<Material>(
          find
              .ancestor(of: _button('🔥'), matching: find.byType(Material))
              .first,
        )
        .color;
    expect(color, isNot(const Color(0x00000000)));
    service.emit(ReactionType.clap); // someone else's reaction pulses too
    await tester.pump(const Duration(milliseconds: 50));
    expect(_floating(tester), 0);
    await tester.pump(const Duration(milliseconds: 600)); // the pulse ends
    await _leave(tester);
  });
}
