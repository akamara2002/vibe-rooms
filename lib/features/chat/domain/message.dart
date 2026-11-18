import '../../../core/utc.dart';

/// A row of `public.messages`. Messages cannot be edited or deleted.
class Message {
  const Message({
    required this.id,
    required this.roomId,
    required this.userId,
    required this.body,
    required this.createdAt,
  });

  factory Message.fromJson(Map<String, dynamic> json) => Message(
    id: json['id'] as String,
    roomId: json['room_id'] as String,
    userId: json['user_id'] as String,
    body: json['body'] as String,
    createdAt: parseUtc(json['created_at'] as String),
  );

  final String id;
  final String roomId;
  final String userId;
  final String body;
  final DateTime createdAt;

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
  String toString() => 'Message($id, $body)';
}
