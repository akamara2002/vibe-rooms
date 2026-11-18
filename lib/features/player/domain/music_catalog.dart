import 'track.dart';

/// A source of playable tracks. Methods throw `AudiusFailure` (or the
/// failure type of another catalog) on error.
abstract class MusicCatalog {
  Future<List<Track>> search(String query, {int limit = 20});

  Future<List<Track>> trending({int limit = 20});

  /// Where the audio for [trackId] can be streamed from. The URL may redirect
  /// to a content node and supports HTTP range requests (seeking).
  Uri streamUri(String trackId);
}
