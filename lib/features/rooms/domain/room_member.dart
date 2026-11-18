import '../../../core/utc.dart';

/// A member of a room, with the profile fields needed to show them.
class RoomMember {
  const RoomMember({
    required this.roomId,
    required this.userId,
    required this.joinedAt,
    required this.displayName,
    required this.avatarEmoji,
    required this.isHost,
  });

  /// Reads a `room_members` row that embeds `profiles(...)` and `rooms(host_id)`.
  factory RoomMember.fromRow(Map<String, dynamic> row) {
    final profile = (row['profiles'] as Map<String, dynamic>?) ?? const {};
    final room = (row['rooms'] as Map<String, dynamic>?) ?? const {};
    final userId = row['user_id'] as String;
    return RoomMember(
      roomId: row['room_id'] as String,
      userId: userId,
      joinedAt: parseUtc(row['joined_at'] as String),
      displayName: (profile['display_name'] as String?) ?? 'Guest',
      avatarEmoji: (profile['avatar_emoji'] as String?) ?? '🎧',
      isHost: room['host_id'] == userId,
    );
  }

  final String roomId;
  final String userId;
  final DateTime joinedAt;
  final String displayName;
  final String avatarEmoji;
  final bool isHost;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RoomMember &&
          other.roomId == roomId &&
          other.userId == userId &&
          other.joinedAt == joinedAt &&
          other.displayName == displayName &&
          other.avatarEmoji == avatarEmoji &&
          other.isHost == isHost;

  @override
  int get hashCode =>
      Object.hash(roomId, userId, joinedAt, displayName, avatarEmoji, isHost);

  @override
  String toString() => 'RoomMember($displayName)';
}
