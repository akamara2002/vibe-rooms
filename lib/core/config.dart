/// Build-time configuration, supplied with
/// `--dart-define-from-file=env.json`.
class AppConfig {
  const AppConfig({
    this.supabaseUrl = const String.fromEnvironment('SUPABASE_URL'),
    this.supabaseAnonKey = const String.fromEnvironment('SUPABASE_ANON_KEY'),
    this.audiusApiKey = const String.fromEnvironment('AUDIUS_API_KEY'),
  });

  final String supabaseUrl;
  final String supabaseAnonKey;

  /// Optional. The Audius read endpoints work without it; if it is set it is
  /// sent as `api_key`. It is a client-side key (never put an Audius bearer
  /// token here). Keep it in env.json, never in tracked files.
  final String audiusApiKey;

  /// False when either value is empty or still a placeholder.
  bool get isConfigured => _isReal(supabaseUrl) && _isReal(supabaseAnonKey);

  static bool _isReal(String value) {
    final trimmed = value.trim();
    return trimmed.isNotEmpty && !trimmed.startsWith('YOUR_');
  }
}

const config = AppConfig();
