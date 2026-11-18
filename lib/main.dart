import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'app.dart';
import 'core/config.dart';
import 'core/supabase_client.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Skipped (not failed) when keys are missing; the login screen explains it.
  final supabaseReady = await initSupabase(config);
  runApp(
    ProviderScope(
      overrides: [supabaseReadyProvider.overrideWithValue(supabaseReady)],
      child: const VibeRoomsApp(),
    ),
  );
}
