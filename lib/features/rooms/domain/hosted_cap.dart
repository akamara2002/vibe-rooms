import 'room_summary.dart';

/// How many open rooms one user may host. Enforced by the client only (the
/// database has no such rule), so it is a courtesy against accidents, not a
/// defence against a modified client.
const maxHostedRooms = 5;

/// How many of [rooms] (open rooms I belong to) I host.
int hostedRoomCount(List<RoomSummary> rooms, String? myId) =>
    myId == null ? 0 : rooms.where((r) => r.room.hostId == myId).length;
