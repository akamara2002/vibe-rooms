import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'app.dart';
import 'core/config.dart';
import 'core/supabase_client.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Skipped (not failed) when keys are missing; screens show a banner.
  await initSupabase(config);
  runApp(const ProviderScope(child: VibeRoomsApp()));
}
