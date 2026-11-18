import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vibe_rooms/core/redirect.dart';
import 'package:vibe_rooms/features/rooms/presentation/home_screen.dart';

import '../fakes/fakes.dart';

void main() {
  group('authRedirect', () {
    String? redirect(
      String location, {
      bool signedIn = false,
      bool was = false,
    }) => authRedirect(
      signedIn: signedIn,
      uri: Uri.parse(location),
      wasSignedIn: was,
    );

    test('signed out: protected paths go to /login, /login stays', () {
      expect(redirect('/home'), '/login');
      expect(redirect('/nowhere'), '/login');
      expect(redirect('/login'), isNull);
      expect(redirect('/login?from=%2Froom%2Fabc'), isNull);
    });

    test('signed out: a safe deep link is kept as ?from=', () {
      expect(redirect('/room/abc'), '/login?from=%2Froom%2Fabc');
      expect(redirect('/join/ABC234'), '/login?from=%2Fjoin%2FABC234');
    });

    test('signed out after an explicit sign-out: from is not kept', () {
      expect(redirect('/room/abc', was: true), '/login');
      expect(redirect('/join/ABC234', was: true), '/login');
    });

    test('signed in: /login goes to /home, the rest stays', () {
      expect(redirect('/login', signedIn: true), '/home');
      expect(redirect('/home', signedIn: true), isNull);
      expect(redirect('/room/abc', signedIn: true), isNull);
    });

    test('signed in: /login?from=<safe path> returns there', () {
      expect(
        redirect('/login?from=%2Froom%2Fabc', signedIn: true),
        '/room/abc',
      );
      expect(
        redirect('/login?from=%2Fjoin%2FABC234', signedIn: true),
        '/join/ABC234',
      );
      expect(redirect('/login?from=%2Fhome', signedIn: true), '/home');
    });

    test('signed in: external or malformed from values are ignored', () {
      for (final from in [
        '//evil.com',
        'https://evil.com',
        'http://evil.com/room/abc',
        '/\\evil.com',
        '\\evil.com',
        'javascript:alert(1)',
        '/room/abc/../../evil',
        '/room/abc?next=https://evil.com',
        '/room/abc#x',
        '/login',
        '/login?from=/home',
        '/room/%2e%2e',
        '/room/a b',
        '/room/',
        '/join/',
        '',
        'room/abc',
        '/nowhere',
        '/room/${'a' * 65}',
      ]) {
        expect(
          redirect(
            '/login?from=${Uri.encodeQueryComponent(from)}',
            signedIn: true,
          ),
          '/home',
          reason: 'from=$from',
        );
      }
    });

    test('a redirect target never redirects again (no loops)', () {
      for (final signedIn in [true, false]) {
        for (final was in [true, false]) {
          for (final start in [
            '/login',
            '/home',
            '/room/x',
            '/join/ABC234',
            '/nowhere',
            '/login?from=%2F%2Fevil.com',
            '/login?from=%2Froom%2Fx',
          ]) {
            final next = redirect(start, signedIn: signedIn, was: was);
            if (next != null) {
              expect(
                redirect(next, signedIn: signedIn, was: was),
                isNull,
                reason: 'signedIn=$signedIn was=$was $start -> $next',
              );
            }
          }
        }
      }
    });

    test('safeRedirectTarget accepts only the allowlisted shapes', () {
      expect(safeRedirectTarget('/home'), '/home');
      expect(safeRedirectTarget('/room/abc-DEF_1'), '/room/abc-DEF_1');
      expect(safeRedirectTarget('/join/ABC234'), '/join/ABC234');
      expect(safeRedirectTarget(null), isNull);
      expect(safeRedirectTarget('https://evil.com'), isNull);
    });
  });

  testWidgets('signed out, the app shows /login', (tester) async {
    await pumpApp(tester, auth: FakeAuthRepository());
    expect(find.text('Continue as guest'), findsOneWidget);
    expect(find.text('Create a room'), findsNothing);
  });

  testWidgets('signed in, the app skips /login and shows /home', (
    tester,
  ) async {
    await pumpApp(tester, auth: FakeAuthRepository(signedIn: true));
    expect(find.text('Create a room'), findsOneWidget);
    expect(find.text('Continue as guest'), findsNothing);
  });

  testWidgets('signing in on /login moves to /home, signing out returns', (
    tester,
  ) async {
    final auth = FakeAuthRepository();
    await pumpApp(tester, auth: auth);

    auth.setSignedIn(true);
    await tester.pumpAndSettle();
    expect(find.text('Create a room'), findsOneWidget);

    auth.setSignedIn(false);
    await tester.pumpAndSettle();
    expect(find.text('Continue as guest'), findsOneWidget);
  });

  group('deep links through login', () {
    Future<void> goTo(WidgetTester tester, String location) async {
      GoRouter.of(tester.element(find.byType(Scaffold).first)).go(location);
      await tester.pumpAndSettle();
    }

    testWidgets('a room link opened signed out returns to the room after '
        'sign-in', (tester) async {
      final auth = FakeAuthRepository();
      final rooms = FakeRoomRepository(
        roomsById: {'abc': fakeRoom(id: 'abc', name: 'Deep Room')},
      );
      await pumpApp(tester, auth: auth, rooms: rooms);

      await goTo(tester, '/room/abc');
      expect(find.text('Continue as guest'), findsOneWidget); // sent to /login

      auth.setSignedIn(true);
      await tester.pumpAndSettle();
      expect(find.text('Deep Room'), findsOneWidget); // back in the room
      expect(find.text('Nothing playing yet'), findsOneWidget);
    });

    testWidgets('a join link signed out joins after sign-in', (tester) async {
      final auth = FakeAuthRepository();
      final rooms = FakeRoomRepository(
        roomsById: {'room-7': fakeRoom(id: 'room-7', name: 'Linked')},
      )..joinResult = fakeRoom(id: 'room-7', code: 'ABC234', name: 'Linked');
      await pumpApp(tester, auth: auth, rooms: rooms);

      await goTo(tester, '/join/ABC234');
      expect(rooms.calls, isEmpty); // not joined while signed out
      auth.setSignedIn(true);
      await tester.pumpAndSettle();

      expect(rooms.calls, ['join:ABC234']);
      expect(find.text('Linked'), findsOneWidget);
    });

    for (final evil in ['//evil.com', 'https://evil.com']) {
      testWidgets('from=$evil is ignored after sign-in', (tester) async {
        final auth = FakeAuthRepository();
        await pumpApp(tester, auth: auth);

        await goTo(tester, '/login?from=${Uri.encodeQueryComponent(evil)}');
        auth.setSignedIn(true);
        await tester.pumpAndSettle();

        expect(find.text('My rooms'), findsOneWidget); // /home
        expect(find.byType(HomeScreen), findsOneWidget);
      });
    }

    testWidgets('after an explicit sign-out, from is not kept', (tester) async {
      final auth = FakeAuthRepository(signedIn: true);
      await pumpApp(tester, auth: auth);

      await goTo(tester, '/room/abc');
      auth.setSignedIn(false);
      await tester.pumpAndSettle();
      expect(find.text('Continue as guest'), findsOneWidget);

      auth.setSignedIn(true);
      await tester.pumpAndSettle();
      expect(find.text('My rooms'), findsOneWidget); // /home, not /room/abc
    });
  });

  testWidgets('the home screen has two enabled cards and a profile chip', (
    tester,
  ) async {
    await pumpApp(tester, auth: FakeAuthRepository(signedIn: true));

    expect(find.text('Create a room'), findsOneWidget);
    expect(find.text('Join with a code'), findsOneWidget);
    expect(find.text('Coming in the next step'), findsNothing);
    expect(find.widgetWithText(ActionChip, 'Ana'), findsOneWidget);
  });
}
