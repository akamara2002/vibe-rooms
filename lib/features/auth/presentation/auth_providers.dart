import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase_client.dart';
import '../data/supabase_auth_repository.dart';
import '../data/supabase_profile_repository.dart';
import '../data/unconfigured_repositories.dart';
import '../domain/auth_repository.dart';
import '../domain/profile.dart';
import '../domain/profile_repository.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  if (!ref.watch(supabaseReadyProvider)) {
    return const UnconfiguredAuthRepository();
  }
  return SupabaseAuthRepository(Supabase.instance.client.auth);
});

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  if (!ref.watch(supabaseReadyProvider)) {
    return const UnconfiguredProfileRepository();
  }
  return SupabaseProfileRepository(Supabase.instance.client);
});

/// Whether a user is signed in, seeded with the current state.
final signedInProvider = StreamProvider<bool>((ref) async* {
  final auth = ref.watch(authRepositoryProvider);
  yield auth.isSignedIn;
  yield* auth.signedInChanges;
});

/// The signed-in user's profile. Rebuilt on every auth change and dropped when
/// unused, so one user never sees another user's cached profile.
class MyProfile extends AsyncNotifier<Profile> {
  @override
  Future<Profile> build() {
    ref.watch(signedInProvider);
    return ref.watch(profileRepositoryProvider).getMyProfile();
  }

  /// Saves the given fields and publishes the updated profile.
  Future<void> save({String? displayName, String? avatarEmoji}) async {
    final updated = await ref
        .read(profileRepositoryProvider)
        .updateMyProfile(displayName: displayName, avatarEmoji: avatarEmoji);
    state = AsyncData(updated);
  }
}

final myProfileProvider = AsyncNotifierProvider.autoDispose<MyProfile, Profile>(
  MyProfile.new,
  retry: (_, _) => null,
);
