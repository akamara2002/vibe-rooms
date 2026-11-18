/// Sign-in and session state. All methods throw [AuthFailure] on failure.
///
/// The display name is sent as the `display_name` user-metadata key, which
/// the `handle_new_user` database trigger uses for the new profile row.
abstract class AuthRepository {
  /// Emits when the signed-in state changes. Does not emit the initial value
  /// (read [isSignedIn]) and never emits errors.
  Stream<bool> get signedInChanges;

  bool get isSignedIn;
  bool get isAnonymous;
  String? get userId;

  Future<void> signInAsGuest(String displayName);

  /// Throws [AuthFailure] with kind `emailConfirmationRequired` when the
  /// project requires email confirmation (the account exists but there is no
  /// session yet).
  Future<void> signUpWithEmail(
    String email,
    String password,
    String displayName,
  );

  Future<void> signInWithEmail(String email, String password);

  Future<void> signOut();
}
