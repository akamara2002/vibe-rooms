import '../../auth/domain/profile.dart';
import '../domain/room.dart';
import '../domain/room_failure.dart';
import '../domain/room_member.dart';
import '../domain/room_presence.dart';
import '../domain/room_repository.dart';
import '../domain/room_summary.dart';

/// Used when Supabase is not configured or failed to initialise.
class UnconfiguredRoomRepository implements RoomRepository {
  const UnconfiguredRoomRepository();

  static const _failure = RoomFailure(RoomFailureKind.unknown);

  @override
  Future<Room> createRoom(String name) => Future.error(_failure);
  @override
  Future<Room> joinRoom(String code) => Future.error(_failure);
  @override
  Future<List<RoomSummary>> myRooms() => Future.error(_failure);
  @override
  Future<Room?> getRoom(String id) => Future.error(_failure);
  @override
  Stream<List<RoomMember>> watchMembers(String roomId) => const Stream.empty();
  @override
  Future<void> leaveRoom(String roomId) => Future.error(_failure);
  @override
  Future<void> closeRoom(String roomId) => Future.error(_failure);
}

class UnconfiguredRoomPresence implements RoomPresence {
  const UnconfiguredRoomPresence();

  @override
  Stream<Set<String>> watchOnlineUserIds(String roomId, Profile me) =>
      const Stream.empty();
}
