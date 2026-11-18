import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibe_rooms/features/auth/domain/auth_failure.dart';

import '../fakes/fakes.dart';

Finder _guestButton() => find.widgetWithText(FilledButton, 'Continue as guest');

bool _enabled(WidgetTester tester, Finder button) =>
    tester.widget<FilledButton>(button).onPressed != null;

void main() {
  testWidgets('guest button is disabled for an empty or too-long name', (
    tester,
  ) async {
    await pumpApp(tester, auth: FakeAuthRepository());
    final field = find.byType(TextFormField);

    expect(_enabled(tester, _guestButton()), isFalse); // empty

    await tester.enterText(field, '   ');
    await tester.pump();
    expect(_enabled(tester, _guestButton()), isFalse); // whitespace only

    await tester.enterText(field, 'a' * 31);
    await tester.pump();
    expect(_enabled(tester, _guestButton()), isFalse); // too long
    expect(find.text('Use 30 characters or fewer.'), findsOneWidget);

    await tester.enterText(field, 'a' * 30);
    await tester.pump();
    expect(_enabled(tester, _guestButton()), isTrue);
  });

  testWidgets('continue as guest signs in with the trimmed name and lands on '
      'home', (tester) async {
    final auth = FakeAuthRepository();
    await pumpApp(tester, auth: auth);

    await tester.enterText(find.byType(TextFormField), '  TestGuest  ');
    await tester.pump();
    await tester.tap(_guestButton());
    await tester.pumpAndSettle();

    expect(auth.calls, ['guest:TestGuest']);
    expect(find.text('Hey, Ana'), findsOneWidget); // from the fake profile
    expect(find.text('Create a room'), findsOneWidget);
  });

  testWidgets('shows a loading state and ignores taps while a request runs', (
    tester,
  ) async {
    final auth = FakeAuthRepository()..gate = Completer<void>();
    await pumpApp(tester, auth: auth);

    await tester.enterText(find.byType(TextFormField), 'Ana');
    await tester.pump();
    await tester.tap(_guestButton());
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Continue as guest'), findsNothing);
    final button = tester.widget<FilledButton>(find.byType(FilledButton).first);
    expect(button.onPressed, isNull);
    expect(auth.calls, hasLength(1));

    auth.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('shows an error snackbar and re-enables the button on failure', (
    tester,
  ) async {
    final auth = FakeAuthRepository()
      ..failNext = const AuthFailure(AuthFailureKind.rateLimit);
    await pumpApp(tester, auth: auth);

    await tester.enterText(find.byType(TextFormField), 'Ana');
    await tester.pump();
    await tester.tap(_guestButton());
    await tester.pumpAndSettle();

    expect(
      find.text(const AuthFailure(AuthFailureKind.rateLimit).message),
      findsOneWidget,
    );
    expect(find.text('Continue as guest'), findsOneWidget); // still on login
    expect(_enabled(tester, _guestButton()), isTrue);
  });

  group('email tab', () {
    Future<void> openEmailTab(WidgetTester tester) async {
      await tester.tap(find.text('Email'));
      await tester.pumpAndSettle();
    }

    testWidgets('sign in needs a valid email and password', (tester) async {
      final auth = FakeAuthRepository();
      await pumpApp(tester, auth: auth);
      await openEmailTab(tester);

      final submit = find.widgetWithText(FilledButton, 'Sign in');
      expect(_enabled(tester, submit), isFalse);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'),
        'nope',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        '123456',
      );
      await tester.pump();
      expect(_enabled(tester, submit), isFalse);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'),
        'ana@example.com',
      );
      await tester.pump();
      expect(_enabled(tester, submit), isTrue);

      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(auth.calls, ['signIn:ana@example.com']);
    });

    testWidgets('create account also asks for a display name', (tester) async {
      final auth = FakeAuthRepository();
      await pumpApp(tester, auth: auth);
      await openEmailTab(tester);

      expect(find.widgetWithText(TextFormField, 'Display name'), findsNothing);
      await tester.tap(find.text('Create account'));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(TextFormField, 'Display name'),
        findsOneWidget,
      );

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'),
        'ana@example.com',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'secret12',
      );
      await tester.pump();
      final submit = find.widgetWithText(FilledButton, 'Create account');
      expect(_enabled(tester, submit), isFalse); // name still missing

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Display name'),
        'Ana',
      );
      await tester.pump();
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(auth.calls, ['signUp:ana@example.com:Ana']);
    });

    testWidgets('email confirmation required is explained, not silent', (
      tester,
    ) async {
      final auth = FakeAuthRepository()
        ..failNext = const AuthFailure(
          AuthFailureKind.emailConfirmationRequired,
        );
      await pumpApp(tester, auth: auth);
      await openEmailTab(tester);
      await tester.tap(find.text('Create account'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Display name'),
        'Ana',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'),
        'ana@example.com',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'secret12',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Check your email'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
    });

    testWidgets('the password can be shown and hidden', (tester) async {
      await pumpApp(tester, auth: FakeAuthRepository());
      await openEmailTab(tester);

      EditableText password() => tester.widget<EditableText>(
        find.descendant(
          of: find.widgetWithText(TextFormField, 'Password'),
          matching: find.byType(EditableText),
        ),
      );
      expect(password().obscureText, isTrue);
      await tester.tap(find.byTooltip('Show password'));
      await tester.pump();
      expect(password().obscureText, isFalse);
    });
  });
}
