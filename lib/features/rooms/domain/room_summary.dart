import 'room.dart';

/// A room in "My rooms", with how many people are in it.
class RoomSummary {
  const RoomSummary({required this.room, required this.memberCount});

  /// Reads a `rooms` row selected with `room_members(count)`.
  factory RoomSummary.fromJson(Map<String, dynamic> json) {
    final counts = json['room_members'] as List<dynamic>? ?? const [];
    final count = counts.isEmpty
        ? 0
        : ((counts.first as Map<String, dynamic>)['count'] as num).toInt();
    return RoomSummary(room: Room.fromJson(json), memberCount: count);
  }

  final Room room;
  final int memberCount;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RoomSummary &&
          other.room == room &&
          other.memberCount == memberCount;

  @override
  int get hashCode => Object.hash(room, memberCount);

  @override
  String toString() => 'RoomSummary(${room.name}, $memberCount)';
}
