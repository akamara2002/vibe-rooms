import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibe_rooms/core/widgets/config_banner.dart';
import 'package:vibe_rooms/core/config.dart';

import 'fakes/fakes.dart';

void main() {
  testWidgets('app starts on the login screen when signed out', (tester) async {
    await pumpApp(tester, auth: FakeAuthRepository());

    expect(find.text('Vibe Rooms'), findsOneWidget);
    expect(find.text('Listen together, anywhere.'), findsOneWidget);
    expect(find.text('Continue as guest'), findsOneWidget);
  });

  testWidgets('login shows a clear message and disables sign-in when '
      'Supabase is not configured', (tester) async {
    await pumpApp(tester, auth: FakeAuthRepository(), ready: false);

    expect(find.text(configBannerMessage), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), 'Ana');
    await tester.pump();
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Continue as guest'),
    );
    expect(button.onPressed, isNull);
  });

  test('isConfigured rejects empty and placeholder values', () {
    expect(
      const AppConfig(supabaseUrl: '', supabaseAnonKey: 'k').isConfigured,
      isFalse,
    );
    expect(
      const AppConfig(
        supabaseUrl: 'YOUR_SUPABASE_URL',
        supabaseAnonKey: 'k',
      ).isConfigured,
      isFalse,
    );
    expect(
      const AppConfig(
        supabaseUrl: 'https://x.supabase.co',
        supabaseAnonKey: 'k',
      ).isConfigured,
      isTrue,
    );
  });
}
