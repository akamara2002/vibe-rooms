import 'room.dart';
import 'room_member.dart';
import 'room_summary.dart';

/// Rooms and their members. Methods throw [RoomFailure] on failure.
abstract class RoomRepository {
  Future<Room> createRoom(String name);

  /// Joins by code (any case, spaces allowed). Throws `roomNotFound` for a
  /// wrong code or a closed room.
  Future<Room> joinRoom(String code);

  /// Open rooms I belong to, newest first.
  Future<List<RoomSummary>> myRooms();

  /// Null when the room does not exist or I am not a member (the database
  /// hides rooms from non-members).
  Future<Room?> getRoom(String id);

  /// Emits the member list now, and again after every change to the room's
  /// members. Cancelling the subscription releases the realtime channel.
  Stream<List<RoomMember>> watchMembers(String roomId);

  /// Deletes my own membership. Succeeds if I was already out.
  Future<void> leaveRoom(String roomId);

  /// Host only: marks the room closed, then leaves it.
  Future<void> closeRoom(String roomId);
}
