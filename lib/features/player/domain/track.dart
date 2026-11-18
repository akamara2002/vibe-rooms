/// A playable track, always safe to store in the database later.
///
/// The constructor enforces the limits of the `queue_items` table, so a
/// [Track] can never hold a value the database would reject:
///  * `durationMs > 0` (otherwise [ArgumentError]; use [tryCreate] to get null),
///  * `id` at most 100 characters, `title` and `artist` at most 300 characters
///    (counted in code points, like Postgres `char_length`),
///  * `artworkUrl` only when it is `https` with no whitespace and at most 2048
///    characters, otherwise null.
class Track {
  factory Track({
    required String id,
    required String title,
    required String artist,
    String? artworkUrl,
    required int durationMs,
    String? permalinkUrl,
  }) {
    final track = tryCreate(
      id: id,
      title: title,
      artist: artist,
      artworkUrl: artworkUrl,
      durationMs: durationMs,
      permalinkUrl: permalinkUrl,
    );
    if (track == null) {
      throw ArgumentError('A track needs a non-empty id and durationMs > 0');
    }
    return track;
  }

  const Track._({
    required this.id,
    required this.title,
    required this.artist,
    required this.artworkUrl,
    required this.durationMs,
    required this.permalinkUrl,
  });

  /// Like the constructor, but returns null for an unusable track.
  static Track? tryCreate({
    required String id,
    required String title,
    required String artist,
    String? artworkUrl,
    required int durationMs,
    String? permalinkUrl,
  }) {
    final cleanId = _clip(id.trim(), maxIdLength);
    if (cleanId.isEmpty || durationMs <= 0) return null;
    return Track._(
      id: cleanId,
      title: _clip(title.trim(), maxTextLength),
      artist: _clip(artist.trim(), maxTextLength),
      artworkUrl: _safeHttpsUrl(artworkUrl),
      durationMs: durationMs,
      permalinkUrl: _safeHttpsUrl(permalinkUrl),
    );
  }

  static const maxIdLength = 100;
  static const maxTextLength = 300;
  static const maxUrlLength = 2048;

  final String id;
  final String title;
  final String artist;
  final String? artworkUrl;
  final int durationMs;
  final String? permalinkUrl;

  Duration get duration => Duration(milliseconds: durationMs);

  /// The row to insert into `queue_items` (same shape as
  /// `QueueItem.toInsertJson`).
  Map<String, dynamic> toQueueInsertJson(String roomId, String addedBy) => {
    'room_id': roomId,
    'added_by': addedBy,
    'track_id': id,
    'title': title,
    'artist': artist,
    'artwork_url': artworkUrl,
    'duration_ms': durationMs,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Track &&
          other.id == id &&
          other.title == title &&
          other.artist == artist &&
          other.artworkUrl == artworkUrl &&
          other.durationMs == durationMs &&
          other.permalinkUrl == permalinkUrl;

  @override
  int get hashCode =>
      Object.hash(id, title, artist, artworkUrl, durationMs, permalinkUrl);

  @override
  String toString() => 'Track($id, $title)';
}

/// Cuts to [max] code points without splitting a surrogate pair.
String _clip(String value, int max) {
  final runes = value.runes;
  if (runes.length <= max) return value;
  return String.fromCharCodes(runes.take(max));
}

final _httpsUrl = RegExp(r'^https://\S+$');

String? _safeHttpsUrl(String? value) {
  if (value == null) return null;
  if (value.length > Track.maxUrlLength) return null;
  return _httpsUrl.hasMatch(value) ? value : null;
}
