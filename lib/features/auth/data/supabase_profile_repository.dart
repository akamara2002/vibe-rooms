import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/auth_failure.dart';
import '../domain/profile.dart';
import '../domain/profile_repository.dart';
import 'auth_error_mapper.dart';

class SupabaseProfileRepository implements ProfileRepository {
  SupabaseProfileRepository(this._client);

  final SupabaseClient _client;

  String get _uid {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw const AuthFailure(AuthFailureKind.notSignedIn);
    return id;
  }

  @override
  Future<Profile> getMyProfile() async {
    final uid = _uid;
    try {
      final row = await _client
          .from('profiles')
          .select()
          .eq('id', uid)
          .maybeSingle();
      if (row != null) return Profile.fromJson(row);

      // The signup trigger normally creates the row. If it is missing (a user
      // created before the schema existed), create it; RLS allows inserting
      // only your own row.
      final created = await _client
          .from('profiles')
          .insert({
            'id': uid,
            'display_name':
                'Guest ${uid.replaceAll('-', '').substring(0, 4).toUpperCase()}',
          })
          .select()
          .single();
      return Profile.fromJson(created);
    } catch (error) {
      throw mapAuthError(error);
    }
  }

  @override
  Future<Profile> updateMyProfile({
    String? displayName,
    String? avatarEmoji,
  }) async {
    final uid = _uid;
    // Only these two columns are writable by clients (column-level grants).
    final changes = <String, dynamic>{
      'display_name': ?displayName?.trim(),
      'avatar_emoji': ?avatarEmoji,
    };
    if (changes.isEmpty) return getMyProfile();
    try {
      final row = await _client
          .from('profiles')
          .update(changes)
          .eq('id', uid)
          .select()
          .single();
      return Profile.fromJson(row);
    } catch (error) {
      throw mapAuthError(error);
    }
  }
}
