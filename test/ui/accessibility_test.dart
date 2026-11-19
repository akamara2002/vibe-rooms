import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart' hide EnginePhase;
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vibe_rooms/features/rooms/domain/room_summary.dart';
import 'package:vibe_rooms/features/rooms/presentation/home_screen.dart';

import '../fakes/fakes.dart';
import 'responsive_test.dart' show openRoomForTest, roomsForTest;

/// Flutter's own accessibility guidelines on the key screens: tap targets of at
/// least 44 px, a label on every tappable thing, and AA text contrast.
void main() {
  for (final scale in [1.0, 2.0]) {
    group('text x$scale', () {
      Future<void> check(WidgetTester tester) async {
        final handle = tester.ensureSemantics();
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      }

      testWidgets('login', (tester) async {
        await pumpApp(
          tester,
          auth: FakeAuthRepository(),
          logicalSize: const Size(390, 844),
          textScale: scale,
        );
        await check(tester);
      });

      testWidgets('home', (tester) async {
        await pumpApp(
          tester,
          auth: FakeAuthRepository(signedIn: true),
          rooms: roomsForTest(),
          logicalSize: const Size(390, 844),
          textScale: scale,
        );
        await check(tester);
      });

      for (final (name, host) in [('host', true), ('listener', false)]) {
        testWidgets('room as $name, Queue tab', (tester) async {
          await openRoomForTest(
            tester,
            size: const Size(390, 844),
            scale: scale,
            isHost: host,
            playing: true,
          );
          await check(tester);
        });

        testWidgets('room as $name, Chat tab', (tester) async {
          await openRoomForTest(
            tester,
            size: const Size(390, 844),
            scale: scale,
            isHost: host,
            playing: true,
          );
          await tester.ensureVisible(find.text('Chat'));
          await tester.tap(find.text('Chat'));
          await tester.pumpAndSettle();
          await check(tester);
        });
      }

      testWidgets('not found page', (tester) async {
        await pumpApp(
          tester,
          auth: FakeAuthRepository(signedIn: true),
          logicalSize: const Size(390, 844),
          textScale: scale,
        );
        GoRouter.of(tester.element(find.byType(HomeScreen))).go('/nope');
        await tester.pumpAndSettle();
        await check(tester);
      });
    });
  }

  group('keyboard', () {
    testWidgets('Escape closes a sheet', (tester) async {
      await pumpApp(tester, auth: FakeAuthRepository(signedIn: true));
      await tester.tap(find.text('Create a room'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('Escape closes the search sheet', (tester) async {
      await openRoomForTest(
        tester,
        size: const Size(900, 1200),
        scale: 1,
        isHost: true,
        playing: false,
      );
      await tester.ensureVisible(find.text('Find music').first);
      await tester.tap(find.text('Find music').first);
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('Tab moves focus through the login screen', (tester) async {
      await pumpApp(tester, auth: FakeAuthRepository());
      // The first Tab lands on something focusable, and each further Tab moves
      // on to a different widget.
      final seen = <FocusNode?>{};
      for (var i = 0; i < 4; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        seen.add(FocusManager.instance.primaryFocus);
      }
      expect(seen.whereType<FocusNode>().length, greaterThan(1));
    });

    testWidgets('a room tile can be reached with Tab and opened with Enter', (
      tester,
    ) async {
      await pumpApp(
        tester,
        auth: FakeAuthRepository(signedIn: true),
        rooms: FakeRoomRepository(
          myRoomsList: [
            RoomSummary(
              room: fakeRoom(id: 'room-1', name: 'Friends', hostId: 'x'),
              memberCount: 1,
            ),
          ],
          roomsById: {'room-1': fakeRoom(id: 'room-1', name: 'Friends')},
        ),
      );
      // Tab until the room tile has focus (bounded, so a broken order fails).
      var opened = false;
      for (var i = 0; i < 12 && !opened; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        final focus = FocusManager.instance.primaryFocus;
        final tile = find
            .ancestor(of: find.text('Friends'), matching: find.byType(InkWell))
            .evaluate()
            .first
            .widget;
        final inTile =
            focus?.context?.findAncestorWidgetOfExactType<InkWell>() == tile;
        if (inTile) {
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          opened = find
              .text('Pick a song to start the party')
              .evaluate()
              .isNotEmpty;
        }
      }
      expect(opened, isTrue);
    });
  });
}
