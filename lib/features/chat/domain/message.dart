import '../../../core/utc.dart';

/// A row of `public.messages`. Messages cannot be edited or deleted.
class Message {
  const Message({
    required this.id,
    required this.roomId,
    required this.userId,
    required this.body,
    required this.createdAt,
    this.senderName,
    this.senderEmoji,
  });

  factory Message.fromJson(Map<String, dynamic> json) => Message(
    id: json['id'] as String,
    roomId: json['room_id'] as String,
    userId: json['user_id'] as String,
    body: json['body'] as String,
    createdAt: parseUtc(json['created_at'] as String),
    // Embedded by `select('*, profiles(display_name, avatar_emoji)')`. A
    // realtime INSERT event has no embed, so these are null there.
    senderName: _str(_profile(json)?['display_name']),
    senderEmoji: _str(_profile(json)?['avatar_emoji']),
  );

  static String? _str(Object? v) => v is String ? v : null;

  static Map<String, dynamic>? _profile(Map<String, dynamic> json) {
    final profile = json['profiles'];
    if (profile is Map<String, dynamic>) return profile;
    return null;
  }

  final String id;
  final String roomId;
  final String userId;
  final String body;
  final DateTime createdAt;

  /// Who sent it (from the embedded profile); not a column of this table.
  final String? senderName;
  final String? senderEmoji;

  Map<String, dynamic> toJson() => {
    'id': id,
    'room_id': roomId,
    'user_id': userId,
    'body': body,
    'created_at': createdAt.toUtc().toIso8601String(),
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Message &&
          other.id == id &&
          other.roomId == roomId &&
          other.userId == userId &&
          other.body == body &&
          other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(id, roomId, userId, body, createdAt);

  @override
  String toString() => 'Message($id)';
}
