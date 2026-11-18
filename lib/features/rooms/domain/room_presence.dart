import '../../auth/domain/profile.dart';

/// Who is online in a room right now (Realtime presence).
abstract class RoomPresence {
  /// Emits the set of online user ids on every presence sync. Cancelling the
  /// subscription leaves the channel.
  Stream<Set<String>> watchOnlineUserIds(String roomId, Profile me);
}
