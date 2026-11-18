import '../domain/auth_failure.dart';
import '../domain/auth_repository.dart';
import '../domain/profile.dart';
import '../domain/profile_repository.dart';

/// Used when Supabase is not configured or failed to initialise. Always
/// signed out; every action fails with a friendly message. This keeps the app
/// from touching `Supabase.instance` (which throws before `initialize`).
class UnconfiguredAuthRepository implements AuthRepository {
  const UnconfiguredAuthRepository();

  static const _failure = AuthFailure(AuthFailureKind.notConfigured);

  @override
  Stream<bool> get signedInChanges => const Stream<bool>.empty();
  @override
  bool get isSignedIn => false;
  @override
  bool get isAnonymous => false;
  @override
  String? get userId => null;

  @override
  Future<void> signInAsGuest(String displayName) => Future.error(_failure);
  @override
  Future<void> signUpWithEmail(
    String email,
    String password,
    String displayName,
  ) => Future.error(_failure);
  @override
  Future<void> signInWithEmail(String email, String password) =>
      Future.error(_failure);
  @override
  Future<void> signOut() => Future.error(_failure);
}

class UnconfiguredProfileRepository implements ProfileRepository {
  const UnconfiguredProfileRepository();

  @override
  Future<Profile> getMyProfile() =>
      Future.error(const AuthFailure(AuthFailureKind.notConfigured));

  @override
  Future<Profile> updateMyProfile({String? displayName, String? avatarEmoji}) =>
      Future.error(const AuthFailure(AuthFailureKind.notConfigured));
}
