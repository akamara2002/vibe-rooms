import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibe_rooms/features/auth/domain/auth_failure.dart';

import '../fakes/fakes.dart';

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(ActionChip, 'Ana'));
  await tester.pumpAndSettle();
}

Finder _save() => find.widgetWithText(FilledButton, 'Save');

void main() {
  testWidgets('save is disabled until something changes', (tester) async {
    await pumpApp(tester, auth: FakeAuthRepository(signedIn: true));
    await _openSheet(tester);

    expect(find.text('Your profile'), findsOneWidget);
    expect(tester.widget<FilledButton>(_save()).onPressed, isNull);

    await tester.tap(find.text('🎸'));
    await tester.pump();
    expect(tester.widget<FilledButton>(_save()).onPressed, isNotNull);
  });

  testWidgets('editing name and emoji and saving calls the repository', (
    tester,
  ) async {
    final profiles = FakeProfileRepository();
    await pumpApp(
      tester,
      auth: FakeAuthRepository(signedIn: true),
      profiles: profiles,
    );
    await _openSheet(tester);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Display name'),
      '  Ana 2  ',
    );
    await tester.tap(find.text('🚀'));
    await tester.pump();
    await tester.tap(_save());
    await tester.pumpAndSettle();

    expect(profiles.updates, [(displayName: 'Ana 2', avatarEmoji: '🚀')]);
    expect(find.text('Profile saved'), findsOneWidget);
    expect(find.text('Your profile'), findsNothing); // sheet closed
    expect(find.widgetWithText(ActionChip, 'Ana 2'), findsOneWidget);
    expect(find.text('Hey, Ana 2'), findsOneWidget);
  });

  testWidgets('only changed fields are sent', (tester) async {
    final profiles = FakeProfileRepository();
    await pumpApp(
      tester,
      auth: FakeAuthRepository(signedIn: true),
      profiles: profiles,
    );
    await _openSheet(tester);

    await tester.tap(find.text('🔥'));
    await tester.pump();
    await tester.tap(_save());
    await tester.pumpAndSettle();

    expect(profiles.updates, [(displayName: null, avatarEmoji: '🔥')]);
  });

  testWidgets('an invalid name blocks saving', (tester) async {
    await pumpApp(tester, auth: FakeAuthRepository(signedIn: true));
    await _openSheet(tester);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Display name'),
      '   ',
    );
    await tester.pump();
    expect(tester.widget<FilledButton>(_save()).onPressed, isNull);
    expect(find.text('Enter a display name.'), findsOneWidget);
  });

  testWidgets('a failed save shows the error and keeps the sheet open', (
    tester,
  ) async {
    final profiles = FakeProfileRepository()
      ..failUpdate = const AuthFailure(AuthFailureKind.network);
    await pumpApp(
      tester,
      auth: FakeAuthRepository(signedIn: true),
      profiles: profiles,
    );
    await _openSheet(tester);

    await tester.tap(find.text('🎹'));
    await tester.pump();
    await tester.tap(_save());
    await tester.pumpAndSettle();

    expect(
      find.text(const AuthFailure(AuthFailureKind.network).message),
      findsOneWidget,
    );
    expect(find.text('Your profile'), findsOneWidget);
  });

  group('sign out', () {
    testWidgets('asks for confirmation; cancel keeps the user signed in', (
      tester,
    ) async {
      final auth = FakeAuthRepository(signedIn: true);
      await pumpApp(tester, auth: auth);
      await _openSheet(tester);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Sign out'));
      await tester.pumpAndSettle();
      expect(find.text('Sign out?'), findsOneWidget);
      expect(auth.calls, isEmpty);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(auth.calls, isEmpty);
      expect(find.text('Your profile'), findsOneWidget);
    });

    testWidgets('confirming signs out and returns to /login', (tester) async {
      final auth = FakeAuthRepository(signedIn: true);
      await pumpApp(tester, auth: auth);
      await _openSheet(tester);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Sign out'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
      await tester.pumpAndSettle();

      expect(auth.calls, ['signOut']);
      expect(find.text('Continue as guest'), findsOneWidget);
    });

    testWidgets('guests are warned their account is lost', (tester) async {
      final auth = FakeAuthRepository(signedIn: true, anonymous: true);
      await pumpApp(tester, auth: auth);
      await _openSheet(tester);

      expect(find.textContaining('lost when you sign out'), findsOneWidget);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Sign out'));
      await tester.pumpAndSettle();
      expect(find.textContaining('guest account will be lost'), findsOneWidget);
    });

    testWidgets('non-guests see no guest warning', (tester) async {
      await pumpApp(tester, auth: FakeAuthRepository(signedIn: true));
      await _openSheet(tester);
      expect(find.textContaining('lost when you sign out'), findsNothing);
    });
  });
}
