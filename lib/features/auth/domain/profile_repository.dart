import 'profile.dart';

/// The signed-in user's `profiles` row. Writes touch only `display_name` and
/// `avatar_emoji`. Methods throw [AuthFailure] on failure.
abstract class ProfileRepository {
  Future<Profile> getMyProfile();

  Future<Profile> updateMyProfile({String? displayName, String? avatarEmoji});
}
