import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibe_rooms/core/router.dart';

import '../fakes/fakes.dart';

void main() {
  group('authRedirect', () {
    test('signed out: everything goes to /login, /login stays', () {
      expect(authRedirect(signedIn: false, location: '/home'), '/login');
      expect(authRedirect(signedIn: false, location: '/room/demo'), '/login');
      expect(authRedirect(signedIn: false, location: '/nowhere'), '/login');
      expect(authRedirect(signedIn: false, location: '/login'), isNull);
    });

    test('signed in: /login goes to /home, the rest stays', () {
      expect(authRedirect(signedIn: true, location: '/login'), '/home');
      expect(authRedirect(signedIn: true, location: '/home'), isNull);
      expect(authRedirect(signedIn: true, location: '/room/demo'), isNull);
    });

    test('a redirect target never redirects again (no loops)', () {
      for (final signedIn in [true, false]) {
        for (final start in ['/login', '/home', '/room/x', '/nowhere']) {
          final next = authRedirect(signedIn: signedIn, location: start);
          if (next != null) {
            expect(authRedirect(signedIn: signedIn, location: next), isNull);
          }
        }
      }
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

  testWidgets('the home screen has disabled placeholders and a profile chip', (
    tester,
  ) async {
    await pumpApp(tester, auth: FakeAuthRepository(signedIn: true));

    expect(find.text('Join with a code'), findsOneWidget);
    expect(find.text('Coming in the next step'), findsNWidgets(2));
    expect(find.widgetWithText(ActionChip, 'Ana'), findsOneWidget);
  });
}
