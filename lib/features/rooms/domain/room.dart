import '../../../core/utc.dart';

/// A row of `public.rooms`. Clients never insert it (the `create_room` RPC does).
class Room {
  const Room({
    required this.id,
    required this.code,
    required this.name,
    required this.hostId,
    required this.createdAt,
    this.closedAt,
  });

  factory Room.fromJson(Map<String, dynamic> json) => Room(
    id: json['id'] as String,
    code: json['code'] as String,
    name: json['name'] as String,
    hostId: json['host_id'] as String,
    createdAt: parseUtc(json['created_at'] as String),
    closedAt: json['closed_at'] == null
        ? null
        : parseUtc(json['closed_at'] as String),
  );

  final String id;
  final String code;
  final String name;
  final String hostId;
  final DateTime createdAt;
  final DateTime? closedAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'code': code,
    'name': name,
    'host_id': hostId,
    'created_at': createdAt.toUtc().toIso8601String(),
    'closed_at': closedAt?.toUtc().toIso8601String(),
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Room &&
          other.id == id &&
          other.code == code &&
          other.name == name &&
          other.hostId == hostId &&
          other.createdAt == createdAt &&
          other.closedAt == closedAt;

  @override
  int get hashCode => Object.hash(id, code, name, hostId, createdAt, closedAt);

  @override
  String toString() => 'Room($id, $code, $name)';
}
