import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/auth_failure.dart';
import '../domain/auth_repository.dart';
import 'auth_error_mapper.dart';

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._auth);

  final GoTrueClient _auth;

  @override
  Stream<bool> get signedInChanges => _auth.onAuthStateChange
      .map((state) => state.session != null)
      // A failed token refresh adds an error to this stream (next to a
      // signed-out event). Swallow it so listeners never see an unhandled
      // async error.
      .handleError((Object error) {
        debugPrint('Auth state stream error: ${error.runtimeType}');
      })
      // Token refreshes and web tab-focus events re-emit "signed in".
      .distinct();

  @override
  bool get isSignedIn => _auth.currentSession != null;

  @override
  bool get isAnonymous => _auth.currentUser?.isAnonymous ?? false;

  @override
  String? get userId => _auth.currentUser?.id;

  @override
  Future<void> signInAsGuest(String displayName) async {
    try {
      await _auth.signInAnonymously(data: {'display_name': displayName.trim()});
    } catch (error) {
      throw mapAuthError(error);
    }
  }

  @override
  Future<void> signUpWithEmail(
    String email,
    String password,
    String displayName,
  ) async {
    final AuthResponse response;
    try {
      response = await _auth.signUp(
        email: email.trim(),
        password: password,
        data: {'display_name': displayName.trim()},
      );
    } catch (error) {
      throw mapAuthError(error);
    }
    if (response.session == null) {
      throw const AuthFailure(AuthFailureKind.emailConfirmationRequired);
    }
  }

  @override
  Future<void> signInWithEmail(String email, String password) async {
    try {
      await _auth.signInWithPassword(email: email.trim(), password: password);
    } catch (error) {
      throw mapAuthError(error);
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } catch (error) {
      throw mapAuthError(error);
    }
  }
}
