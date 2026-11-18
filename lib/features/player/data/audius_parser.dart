import '../domain/track.dart';

/// Turns Audius JSON into [Track]s. Never throws: anything unexpected is
/// skipped, so one odd track cannot break a whole result list.
const _audiusWeb = 'https://audius.co';

List<Track> parseTrackList(Object? body) {
  if (body is! Map) return const [];
  final data = body['data'];
  if (data is! List) return const [];
  final tracks = <Track>[];
  for (final item in data) {
    final track = parseTrack(item);
    if (track != null) tracks.add(track);
  }
  return tracks;
}

/// Null for tracks that cannot be played or stored: deleted, unlisted, not
/// streamable (or stream-gated), without a usable id, or without a duration.
Track? parseTrack(Object? json) {
  try {
    if (json is! Map) return null;

    if (json['is_delete'] == true || json['is_unlisted'] == true) return null;
    if (json['is_streamable'] != true) return null;
    final access = json['access'];
    if (access is Map && access['stream'] == false) return null;

    final id = _string(json['id']) ?? _string(json['track_id']);
    if (id == null || id.trim().isEmpty) return null;

    final seconds = json['duration'];
    if (seconds is! num || !seconds.isFinite || seconds <= 0) return null;
    final durationMs = (seconds * 1000).round();

    final title = _string(json['title'])?.trim();
    final user = json['user'];
    final artist = user is Map
        ? (_nonEmpty(_string(user['name'])) ??
              _nonEmpty(_string(user['handle'])))
        : null;

    final permalink = _string(json['permalink']);

    return Track.tryCreate(
      id: id,
      title: _nonEmpty(title) ?? 'Untitled',
      artist: artist ?? 'Unknown artist',
      artworkUrl: _artwork(json['artwork']),
      durationMs: durationMs,
      permalinkUrl: permalink != null && permalink.startsWith('/')
          ? '$_audiusWeb$permalink'
          : null,
    );
  } catch (_) {
    return null;
  }
}

String? _artwork(Object? artwork) {
  if (artwork is! Map) return null;
  for (final size in const ['480x480', '150x150', '1000x1000']) {
    final url = _string(artwork[size]);
    if (url != null && url.isNotEmpty) return url;
  }
  return null;
}

String? _string(Object? value) {
  if (value is String) return value;
  if (value is int) return value.toString();
  return null;
}

String? _nonEmpty(String? value) =>
    value == null || value.trim().isEmpty ? null : value.trim();
