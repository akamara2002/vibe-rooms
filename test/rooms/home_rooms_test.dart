import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vibe_rooms/features/rooms/domain/hosted_cap.dart';
import 'package:vibe_rooms/features/rooms/domain/room_failure.dart';
import 'package:vibe_rooms/features/rooms/presentation/room_creator.dart';
import 'package:vibe_rooms/features/rooms/domain/room_summary.dart';
import 'package:vibe_rooms/features/rooms/presentation/home_screen.dart';

import '../fakes/fakes.dart';

Future<FakeRoomRepository> _home(
  WidgetTester tester, {
  FakeRoomRepository? rooms,
}) async {
  final repo = rooms ?? FakeRoomRepository();
  await pumpApp(tester, auth: FakeAuthRepository(signedIn: true), rooms: repo);
  return repo;
}

String _codeField(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).controller!.text;

Finder _create() => find.widgetWithText(FilledButton, 'Create');
Finder _join() => find.widgetWithText(FilledButton, 'Join');

List<RoomSummary> _hosted(int n, {String host = 'user-1'}) => [
  for (var i = 0; i < n; i++)
    RoomSummary(
      room: fakeRoom(
        id: 'r$i',
        name: 'Room $i',
        code: 'CODE$i'.padRight(6, 'A'),
        hostId: host,
      ),
      memberCount: 1,
    ),
];

void main() {
  group('the hosted-room cap', () {
    test('counts only open rooms I host', () {
      final mixed = [..._hosted(3), ..._hosted(4, host: 'other')];
      expect(hostedRoomCount(mixed, 'user-1'), 3);
      expect(hostedRoomCount(mixed, null), 0);
    });

    test('the sixth room is refused before any create call', () async {
      final repo = FakeRoomRepository(myRoomsList: _hosted(maxHostedRooms));
      final creator = RoomCreator(repo, () => 'user-1');
      await expectLater(
        creator.create('One more'),
        throwsA(
          isA<RoomFailure>().having(
            (f) => f.message,
            'message',
            'You already host 5 rooms. Close one first.',
          ),
        ),
      );
      expect(repo.calls.where((c) => c.startsWith('create')), isEmpty);
    });

    test(
      'the fifth room is allowed, and rooms I only joined do not count',
      () async {
        final repo = FakeRoomRepository(
          myRoomsList: [
            ..._hosted(maxHostedRooms - 1),
            ..._hosted(6, host: 'other'),
          ],
        )..createResult = fakeRoom(id: 'new');
        final room = await RoomCreator(repo, () => 'user-1').create('Fifth');
        expect(room.id, 'new');
      },
    );

    test(
      'it reads a fresh list, so a room closed elsewhere frees a slot',
      () async {
        final repo = FakeRoomRepository(myRoomsList: _hosted(maxHostedRooms))
          ..createResult = fakeRoom(id: 'new');
        final creator = RoomCreator(repo, () => 'user-1');
        await expectLater(creator.create('x'), throwsA(isA<RoomFailure>()));
        repo.mine = _hosted(maxHostedRooms - 1); // closed on another device
        expect((await creator.create('x')).id, 'new');
      },
    );

    testWidgets('the sheet shows the message and stays open', (tester) async {
      final repo = FakeRoomRepository(myRoomsList: _hosted(maxHostedRooms));
      await _home(tester, rooms: repo);
      await tester.tap(find.text('Create a room'));
      await tester.pumpAndSettle();
      await tester.tap(_create());
      await tester.pumpAndSettle();
      expect(
        find.text('You already host 5 rooms. Close one first.'),
        findsOneWidget,
      );
      expect(repo.calls.where((c) => c.startsWith('create')), isEmpty);
    });

    testWidgets('Close room on a hosted row asks first, then closes it', (
      tester,
    ) async {
      final repo = FakeRoomRepository(
        myRoomsList: [
          ..._hosted(1),
          ..._hosted(1, host: 'other').map(
            (s) => RoomSummary(
              room: fakeRoom(id: 'joined', name: 'Joined', hostId: 'other'),
              memberCount: 2,
            ),
          ),
        ],
      );
      await _home(tester, rooms: repo);
      // Only the room I host has the action.
      expect(find.byTooltip('Close room Room 0'), findsOneWidget);
      expect(find.byTooltip('Close room Joined'), findsNothing);

      await tester.tap(find.byTooltip('Close room Room 0'));
      await tester.pumpAndSettle();
      expect(find.text('Close room?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(repo.calls.where((c) => c.startsWith('close')), isEmpty);

      await tester.tap(find.byTooltip('Close room Room 0'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Close room'));
      await tester.pumpAndSettle();
      expect(repo.calls, contains('close:r0'));
      expect(find.text('Room 0'), findsNothing);
      expect(find.text('Joined'), findsOneWidget);
    });
  });

  group('My rooms', () {
    testWidgets('empty state', (tester) async {
      await _home(tester);
      expect(find.text('My rooms'), findsOneWidget);
      expect(
        find.text('No rooms yet. Create one or join with a code.'),
        findsOneWidget,
      );
    });

    testWidgets('lists name, code, listener count and a crown for hosts', (
      tester,
    ) async {
      await _home(
        tester,
        rooms: FakeRoomRepository(
          myRoomsList: [
            RoomSummary(
              room: fakeRoom(id: 'a', name: 'Mine', code: 'AAAAAA'),
              memberCount: 1,
            ),
            RoomSummary(
              room: fakeRoom(
                id: 'b',
                name: 'Friends',
                code: 'BBBBBB',
                hostId: 'other',
              ),
              memberCount: 3,
            ),
          ],
        ),
      );

      expect(find.text('Mine'), findsOneWidget);
      expect(find.text('AAAAAA'), findsOneWidget);
      expect(find.text('1 listener'), findsOneWidget);
      expect(find.text('Friends'), findsOneWidget);
      expect(find.text('3 listeners'), findsOneWidget);
      expect(find.text('👑'), findsOneWidget); // only the room I host
      expect(
        find.text('No rooms yet. Create one or join with a code.'),
        findsNothing,
      );
    });

    testWidgets('tapping a room opens it', (tester) async {
      await _home(
        tester,
        rooms: FakeRoomRepository(
          myRoomsList: [
            RoomSummary(
              room: fakeRoom(id: 'a', name: 'Mine'),
              memberCount: 1,
            ),
          ],
          roomsById: {'a': fakeRoom(id: 'a', name: 'Mine')},
        ),
      );
      await tester.tap(find.text('Mine'));
      await tester.pumpAndSettle();
      expect(find.text('Pick a song to start the party'), findsOneWidget);
    });

    testWidgets('pull to refresh reloads the list', (tester) async {
      final repo = await _home(tester);
      repo.mine = [
        RoomSummary(
          room: fakeRoom(id: 'a', name: 'Fresh'),
          memberCount: 2,
        ),
      ];

      await tester.fling(
        find.byType(SingleChildScrollView).first,
        const Offset(0, 400),
        1000,
      );
      await tester.pumpAndSettle();
      expect(find.text('Fresh'), findsOneWidget);
    });
  });

  group('create sheet', () {
    Future<void> open(WidgetTester tester) async {
      await tester.tap(find.text('Create a room'));
      await tester.pumpAndSettle();
    }

    testWidgets("is filled with \"<my name>'s room\"", (tester) async {
      await _home(tester);
      await open(tester);
      expect(find.widgetWithText(TextFormField, "Ana's room"), findsOneWidget);
      expect(tester.widget<FilledButton>(_create()).onPressed, isNotNull);
    });

    testWidgets('empty and 41-character names block Create', (tester) async {
      await _home(tester);
      await open(tester);
      final field = find.byType(TextFormField);

      await tester.enterText(field, '   ');
      await tester.pump();
      expect(tester.widget<FilledButton>(_create()).onPressed, isNull);
      expect(find.text('Enter a room name.'), findsOneWidget);

      await tester.enterText(field, 'a' * 41);
      await tester.pump();
      expect(tester.widget<FilledButton>(_create()).onPressed, isNull);

      await tester.enterText(field, 'a' * 40);
      await tester.pump();
      expect(tester.widget<FilledButton>(_create()).onPressed, isNotNull);
    });

    testWidgets('creates with the trimmed name and opens the room', (
      tester,
    ) async {
      final repo = FakeRoomRepository(
        roomsById: {'room-9': fakeRoom(id: 'room-9', name: 'Friday')},
      )..createResult = fakeRoom(id: 'room-9', name: 'Friday');
      await _home(tester, rooms: repo);
      await open(tester);

      await tester.enterText(find.byType(TextFormField), '  Friday  ');
      await tester.pump();
      await tester.tap(_create());
      await tester.pumpAndSettle();

      expect(repo.calls, contains('create:Friday'));
      expect(find.text('Pick a song to start the party'), findsOneWidget);
    });

    testWidgets('a failure is shown in the sheet and the sheet stays', (
      tester,
    ) async {
      final repo = FakeRoomRepository()
        ..createFailure = const RoomFailure(RoomFailureKind.network);
      await _home(tester, rooms: repo);
      await open(tester);

      await tester.tap(_create());
      await tester.pumpAndSettle();
      expect(
        find.text(const RoomFailure(RoomFailureKind.network).message),
        findsOneWidget,
      );
      expect(find.text('Create a room'), findsWidgets);
    });
  });

  group('join sheet', () {
    Future<void> open(WidgetTester tester) async {
      await tester.tap(find.text('Join with a code'));
      await tester.pumpAndSettle();
    }

    testWidgets('formats input and enables Join only for a valid code', (
      tester,
    ) async {
      await _home(tester);
      await open(tester);
      final field = find.byType(TextField);

      expect(tester.widget<FilledButton>(_join()).onPressed, isNull);

      await tester.enterText(field, 'abc 23');
      await tester.pump();
      expect(_codeField(tester), 'ABC23');
      expect(tester.widget<FilledButton>(_join()).onPressed, isNull);

      await tester.enterText(field, 'abc 234');
      await tester.pump();
      expect(_codeField(tester), 'ABC234');
      expect(tester.widget<FilledButton>(_join()).onPressed, isNotNull);

      await tester.enterText(field, 'a0b1o2i3');
      await tester.pump();
      expect(_codeField(tester), 'AB23'); // 0, 1, O, I are dropped
      expect(tester.widget<FilledButton>(_join()).onPressed, isNull);
    });

    testWidgets('joins and opens the room', (tester) async {
      final repo = FakeRoomRepository(
        roomsById: {'room-2': fakeRoom(id: 'room-2', code: 'ABC234')},
      )..joinResult = fakeRoom(id: 'room-2', code: 'ABC234');
      await _home(tester, rooms: repo);
      await open(tester);

      await tester.enterText(find.byType(TextField), 'abc 234');
      await tester.pump();
      await tester.tap(_join());
      await tester.pumpAndSettle();

      expect(repo.calls, ['join:ABC234']);
      expect(find.text('Pick a song to start the party'), findsOneWidget);
    });

    testWidgets('a wrong code shows "No room with that code." in the sheet', (
      tester,
    ) async {
      final repo = FakeRoomRepository()
        ..joinFailure = const RoomFailure(RoomFailureKind.roomNotFound);
      await _home(tester, rooms: repo);
      await open(tester);

      await tester.enterText(find.byType(TextField), 'ZZZZZZ');
      await tester.pump();
      await tester.tap(_join());
      await tester.pumpAndSettle();

      expect(find.text('No room with that code.'), findsOneWidget);
      expect(tester.widget<FilledButton>(_join()).onPressed, isNotNull);
    });
  });

  group('/join/:code', () {
    Future<void> goTo(WidgetTester tester, String location) async {
      final context = tester.element(find.byType(HomeScreen));
      GoRouter.of(context).go(location);
      await tester.pump();
    }

    testWidgets('joins and replaces itself with the room', (tester) async {
      final repo = FakeRoomRepository(
        roomsById: {'room-3': fakeRoom(id: 'room-3', code: 'ABC234')},
      )..joinResult = fakeRoom(id: 'room-3', code: 'ABC234');
      await _home(tester, rooms: repo);

      await goTo(tester, '/join/abc234');
      await tester.pumpAndSettle();

      expect(repo.calls, ['join:ABC234']);
      expect(find.text('Pick a song to start the party'), findsOneWidget);
    });

    testWidgets('shows a spinner while joining', (tester) async {
      final repo = FakeRoomRepository()..joinGate = Completer();
      await _home(tester, rooms: repo);

      await goTo(tester, '/join/ABC234');
      await tester.pump();
      await tester.pump();
      expect(find.text('Joining room…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('a wrong code goes home with a snackbar', (tester) async {
      final repo = FakeRoomRepository()
        ..joinFailure = const RoomFailure(RoomFailureKind.roomNotFound);
      await _home(tester, rooms: repo);

      await goTo(tester, '/join/ZZZZZZ');
      await tester.pumpAndSettle();

      expect(find.text('No room with that code.'), findsOneWidget);
      expect(find.text('My rooms'), findsOneWidget); // back on /home
    });

    testWidgets('a malformed code never calls the repository', (tester) async {
      final repo = FakeRoomRepository();
      await _home(tester, rooms: repo);

      await goTo(tester, '/join/abc');
      await tester.pumpAndSettle();

      expect(repo.calls, isEmpty);
      expect(find.text('No room with that code.'), findsOneWidget);
    });
  });

  group('races', () {
    testWidgets('dismissing the create sheet while the request runs does not '
        'crash', (tester) async {
      final repo = FakeRoomRepository()..createGate = Completer();
      await _home(tester, rooms: repo);

      await tester.tap(find.text('Create a room'));
      await tester.pumpAndSettle();
      await tester.tap(_create());
      await tester.pump();

      await tester.tapAt(const Offset(5, 5)); // dismiss the sheet mid-request
      await tester.pumpAndSettle();
      repo.createGate!.complete(fakeRoom(id: 'room-5'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('leaving /join/:code while the request runs does not crash', (
      tester,
    ) async {
      final repo = FakeRoomRepository()..joinGate = Completer();
      await _home(tester, rooms: repo);
      GoRouter.of(tester.element(find.byType(HomeScreen))).go('/join/ABC234');
      await tester.pump();
      await tester.pump();

      GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/home');
      await tester.pumpAndSettle();
      repo.joinGate!.complete(fakeRoom(id: 'room-6'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('My rooms'), findsOneWidget); // still on /home
    });
  });
}
