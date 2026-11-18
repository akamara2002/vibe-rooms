import '../../../core/utc.dart';

/// The single playback row of a room (`public.room_state`).
///
/// Every client computes its own position from [updatedAt], which the server
/// sets (never the client). See [expectedPositionMs].
class RoomState {
  const RoomState({
    required this.roomId,
    this.queueItemId,
    this.trackId,
    this.title,
    this.artist,
    this.artworkUrl,
    this.durationMs,
    required this.isPlaying,
    required this.positionMs,
    required this.updatedAt,
    this.updatedBy,
  });

  factory RoomState.fromJson(Map<String, dynamic> json) => RoomState(
    roomId: json['room_id'] as String,
    queueItemId: json['queue_item_id'] as String?,
    trackId: json['track_id'] as String?,
    title: json['title'] as String?,
    artist: json['artist'] as String?,
    artworkUrl: json['artwork_url'] as String?,
    durationMs: (json['duration_ms'] as num?)?.toInt(),
    isPlaying: json['is_playing'] as bool,
    positionMs: (json['position_ms'] as num).toInt(),
    updatedAt: parseUtc(json['updated_at'] as String),
    updatedBy: json['updated_by'] as String?,
  );

  final String roomId;
  final String? queueItemId;
  final String? trackId;
  final String? title;
  final String? artist;
  final String? artworkUrl;
  final int? durationMs;
  final bool isPlaying;
  final int positionMs;
  final DateTime updatedAt;
  final String? updatedBy;

  /// Where playback should be at [serverNow] (the client's estimate of server
  /// time, i.e. local clock plus the offset measured with `server_now()`).
  ///
  /// Paused: [positionMs]. Playing: [positionMs] plus the time since
  /// [updatedAt], never below [positionMs] (clock skew) and never above
  /// [durationMs] when known.
  int expectedPositionMs(DateTime serverNow) {
    if (!isPlaying) return positionMs;
    final elapsedMs = serverNow.difference(updatedAt).inMilliseconds;
    final position = positionMs + (elapsedMs < 0 ? 0 : elapsedMs);
    final duration = durationMs;
    if (duration != null && position > duration) return duration;
    return position;
  }

  /// The full row (for tests and caching). Do not send this to the server.
  Map<String, dynamic> toJson() => {
    'room_id': roomId,
    'queue_item_id': queueItemId,
    'track_id': trackId,
    'title': title,
    'artist': artist,
    'artwork_url': artworkUrl,
    'duration_ms': durationMs,
    'is_playing': isPlaying,
    'position_ms': positionMs,
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'updated_by': updatedBy,
  };

  /// What the host may write. `updated_at`, `updated_by` and `room_id` are
  /// excluded on purpose: the server sets them, and a column-level grant makes
  /// it an error to send them.
  Map<String, dynamic> toUpdateJson() => {
    'queue_item_id': queueItemId,
    'track_id': trackId,
    'title': title,
    'artist': artist,
    'artwork_url': artworkUrl,
    'duration_ms': durationMs,
    'is_playing': isPlaying,
    'position_ms': positionMs,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RoomState &&
          other.roomId == roomId &&
          other.queueItemId == queueItemId &&
          other.trackId == trackId &&
          other.title == title &&
          other.artist == artist &&
          other.artworkUrl == artworkUrl &&
          other.durationMs == durationMs &&
          other.isPlaying == isPlaying &&
          other.positionMs == positionMs &&
          other.updatedAt == updatedAt &&
          other.updatedBy == updatedBy;

  @override
  int get hashCode => Object.hash(
    roomId,
    queueItemId,
    trackId,
    title,
    artist,
    artworkUrl,
    durationMs,
    isPlaying,
    positionMs,
    updatedAt,
    updatedBy,
  );

  @override
  String toString() =>
      'RoomState($roomId, playing: $isPlaying, positionMs: $positionMs)';
}
