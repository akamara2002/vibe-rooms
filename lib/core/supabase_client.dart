import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';

/// Initialises Supabase when [config] is complete.
///
/// Returns true if Supabase is ready to use. Never throws: a missing or bad
/// config must not stop the app from starting.
Future<bool> initSupabase(AppConfig config) async {
  if (!config.isConfigured) return false;
  try {
    await Supabase.initialize(
      url: config.supabaseUrl,
      publishableKey: config.supabaseAnonKey,
    );
    return true;
  } catch (e) {
    // Keys are present but unusable (bad URL, no network): log, don't crash.
    debugPrint('Supabase.initialize failed: $e');
    return false;
  }
}
