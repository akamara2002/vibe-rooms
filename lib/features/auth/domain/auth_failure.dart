/// Why an auth or profile operation failed, in terms the UI can explain.
enum AuthFailureKind {
  invalidCredentials,
  userAlreadyExists,
  weakPassword,
  network,
  rateLimit,
  emailConfirmationRequired,
  notConfigured,
  notSignedIn,
  unknown,
}

/// A failed auth or profile operation with a short, human-readable [message].
///
/// Repositories translate backend errors into this type, so widgets never
/// see (or log) raw exceptions and never need to import Supabase.
class AuthFailure implements Exception {
  const AuthFailure(this.kind);

  final AuthFailureKind kind;

  String get message => switch (kind) {
    AuthFailureKind.invalidCredentials => 'Wrong email or password.',
    AuthFailureKind.userAlreadyExists =>
      'An account with this email already exists. Try signing in.',
    AuthFailureKind.weakPassword =>
      'That password is too weak. Use at least 6 characters.',
    AuthFailureKind.network =>
      'Could not reach the server. Check your connection and try again.',
    AuthFailureKind.rateLimit =>
      'Too many attempts. Please wait a minute and try again.',
    AuthFailureKind.emailConfirmationRequired =>
      'Check your email to confirm your account, then sign in.',
    AuthFailureKind.notConfigured => 'Supabase is not configured: copy env.example.json to env.json and fill in your keys',
    AuthFailureKind.notSignedIn => 'You are not signed in.',
    AuthFailureKind.unknown => 'Something went wrong. Please try again.',
  };

  @override
  String toString() => 'AuthFailure($kind)';
}
