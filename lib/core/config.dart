/// Build-time configuration, supplied with
/// `--dart-define-from-file=env.json`.
class AppConfig {
  const AppConfig({
    this.supabaseUrl = const String.fromEnvironment('SUPABASE_URL'),
    this.supabaseAnonKey = const String.fromEnvironment('SUPABASE_ANON_KEY'),
  });

  final String supabaseUrl;
  final String supabaseAnonKey;

  /// False when either value is empty or still a placeholder.
  bool get isConfigured => _isReal(supabaseUrl) && _isReal(supabaseAnonKey);

  static bool _isReal(String value) {
    final trimmed = value.trim();
    return trimmed.isNotEmpty && !trimmed.startsWith('YOUR_');
  }
}

const config = AppConfig();
