import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibe_rooms/app.dart';
import 'package:vibe_rooms/core/config.dart';
import 'package:vibe_rooms/core/widgets/config_banner.dart';

void main() {
  testWidgets('app starts on the /login placeholder', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: VibeRoomsApp()));
    await tester.pumpAndSettle();

    expect(find.text('/login'), findsOneWidget);
  });

  testWidgets('banner shows when unconfigured and can be dismissed', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: VibeRoomsApp()));
    await tester.pumpAndSettle();
    expect(find.text(configBannerMessage), findsOneWidget);

    await tester.tap(find.text('Dismiss'));
    await tester.pumpAndSettle();
    expect(find.text(configBannerMessage), findsNothing);
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
