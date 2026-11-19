import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vibe_rooms/features/auth/presentation/auth_providers.dart';
import 'package:vibe_rooms/features/auth/presentation/profile_sheet.dart';
import 'package:vibe_rooms/features/rooms/presentation/home_screen.dart';

import '../fakes/fakes.dart';

/// The loading, empty and error state of every async surface that has not got
/// its own test file: each failure offers a retry that works.
void main() {
  group('My rooms', () {
    testWidgets('an error offers Try again, which reloads', (tester) async {
      final rooms = FakeRoomRepository()..failMyRooms = 99;
      await pumpApp(
        tester,
        auth: FakeAuthRepository(signedIn: true),
        rooms: rooms,
      );
      expect(find.text('Could not load your rooms.'), findsOneWidget);
      rooms.failMyRooms = 0;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Could not load your rooms.'), findsNothing);
      expect(
        find.text('No rooms yet. Create one or join with a code.'),
        findsOneWidget,
      );
    });
  });

  group('the room', () {
    testWidgets('a load error offers Try again, which opens the room', (
      tester,
    ) async {
      final rooms = FakeRoomRepository(
        roomsById: {'room-1': fakeRoom(name: 'Friday Vibes')},
      )..failGetRoom = 99;
      await pumpApp(
        tester,
        auth: FakeAuthRepository(signedIn: true),
        rooms: rooms,
      );
      GoRouter.of(tester.element(find.byType(HomeScreen))).go('/room/room-1');
      await tester.pumpAndSettle();
      expect(find.text("Can't open this room"), findsOneWidget);
      expect(find.text('Back to home'), findsOneWidget);

      rooms.failGetRoom = 0;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Friday Vibes'), findsOneWidget);
    });

    testWidgets('"not found" has no retry (it would not help)', (tester) async {
      await pumpApp(tester, auth: FakeAuthRepository(signedIn: true));
      GoRouter.of(tester.element(find.byType(HomeScreen))).go('/room/nope');
      await tester.pumpAndSettle();
      expect(find.text('Room not found'), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
    });

    testWidgets('the listeners card shows an error with Try again', (
      tester,
    ) async {
      final rooms = FakeRoomRepository(
        roomsById: {'room-1': fakeRoom()},
        members: {
          'room-1': [fakeMember('user-1', 'Ana', isHost: true)],
        },
      )..failMembers = 99;
      await pumpApp(
        tester,
        auth: FakeAuthRepository(signedIn: true),
        rooms: rooms,
      );
      GoRouter.of(tester.element(find.byType(HomeScreen))).go('/room/room-1');
      await tester.pumpAndSettle();
      expect(find.text('Could not load the listeners.'), findsOneWidget);
      expect(find.text('Listeners (0)'), findsNothing);

      rooms.failMembers = 0;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Could not load the listeners.'), findsNothing);
      expect(find.text('Listeners (1)'), findsOneWidget);
    });
  });

  group('the profile', () {
    testWidgets('the chip offers a retry that loads it', (tester) async {
      final profiles = FakeProfileRepository()..failGet = 99;
      await pumpApp(
        tester,
        auth: FakeAuthRepository(signedIn: true),
        profiles: profiles,
      );
      expect(find.text('Retry profile'), findsOneWidget);
      profiles.failGet = 0;
      await tester.tap(find.text('Retry profile'));
      await tester.pumpAndSettle();
      expect(find.text('Ana'), findsWidgets);
    });

    testWidgets('the sheet shows an error with Try again, not a spinner '
        'forever', (tester) async {
      final profiles = FakeProfileRepository()..failGet = 99;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(
              FakeAuthRepository(signedIn: true),
            ),
            profileRepositoryProvider.overrideWithValue(profiles),
          ],
          child: const MaterialApp(home: Scaffold(body: ProfileSheet())),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Could not load your profile.'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      profiles.failGet = 0;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Could not load your profile.'), findsNothing);
    });
  });
}
