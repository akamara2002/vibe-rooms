import '../../../core/utc.dart';

/// A row of `public.queue_items`.
class QueueItem {
  const QueueItem({
    required this.id,
    required this.roomId,
    required this.addedBy,
    required this.trackId,
    required this.title,
    required this.artist,
    this.artworkUrl,
    required this.durationMs,
    required this.sortKey,
    this.playedAt,
    required this.createdAt,
    this.addedByName,
    this.addedByEmoji,
  });

  factory QueueItem.fromJson(Map<String, dynamic> json) => QueueItem(
    id: json['id'] as String,
    roomId: json['room_id'] as String,
    addedBy: json['added_by'] as String,
    trackId: json['track_id'] as String,
    title: json['title'] as String,
    artist: json['artist'] as String,
    artworkUrl: json['artwork_url'] as String?,
    durationMs: (json['duration_ms'] as num).toInt(),
    sortKey: (json['sort_key'] as num).toInt(),
    playedAt: json['played_at'] == null
        ? null
        : parseUtc(json['played_at'] as String),
    createdAt: parseUtc(json['created_at'] as String),
    // Embedded by `select('*, profiles(display_name, avatar_emoji)')`.
    addedByName: _profile(json)?['display_name'] as String?,
    addedByEmoji: _profile(json)?['avatar_emoji'] as String?,
  );

  static Map<String, dynamic>? _profile(Map<String, dynamic> json) {
    final profile = json['profiles'];
    if (profile is Map<String, dynamic>) return profile;
    if (profile is List && profile.isNotEmpty && profile.first is Map) {
      return Map<String, dynamic>.from(profile.first as Map);
    }
    return null;
  }

  final String id;
  final String roomId;
  final String addedBy;
  final String trackId;
  final String title;
  final String artist;
  final String? artworkUrl;
  final int durationMs;

  /// Server-generated ordering key; clients can never write it.
  final int sortKey;
  final DateTime? playedAt;
  final DateTime createdAt;

  /// Who added it (from the embedded profile); not a column of this table.
  final String? addedByName;
  final String? addedByEmoji;

  /// The full row (for tests and caching).
  Map<String, dynamic> toJson() => {
    'id': id,
    'room_id': roomId,
    'added_by': addedBy,
    'track_id': trackId,
    'title': title,
    'artist': artist,
    'artwork_url': artworkUrl,
    'duration_ms': durationMs,
    'sort_key': sortKey,
    'played_at': playedAt?.toUtc().toIso8601String(),
    'created_at': createdAt.toUtc().toIso8601String(),
  };

  /// The only columns a client may send when adding a track.
  Map<String, dynamic> toInsertJson() => {
    'room_id': roomId,
    'added_by': addedBy,
    'track_id': trackId,
    'title': title,
    'artist': artist,
    'artwork_url': artworkUrl,
    'duration_ms': durationMs,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QueueItem &&
          other.id == id &&
          other.roomId == roomId &&
          other.addedBy == addedBy &&
          other.trackId == trackId &&
          other.title == title &&
          other.artist == artist &&
          other.artworkUrl == artworkUrl &&
          other.durationMs == durationMs &&
          other.sortKey == sortKey &&
          other.playedAt == playedAt &&
          other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(
    id,
    roomId,
    addedBy,
    trackId,
    title,
    artist,
    artworkUrl,
    durationMs,
    sortKey,
    playedAt,
    createdAt,
  );

  @override
  String toString() => 'QueueItem($id, $title)';
}
