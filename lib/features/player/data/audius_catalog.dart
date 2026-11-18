import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:http/http.dart' as http;

import '../domain/audius_failure.dart';
import '../domain/music_catalog.dart';
import '../domain/track.dart';
import 'audius_parser.dart';

/// The Audius public API (https://api.audius.co/v1).
///
/// Host handling follows the current docs: there is one stable host, so no
/// discovery step is needed. [hosts] is an ordered list anyway, so a mirror can
/// be added in one line and a failing host falls over to the next.
///
/// Requests are plain GETs without custom headers, so browsers never need a
/// CORS preflight. No key is required; an optional [apiKey] is sent as
/// `api_key`. URLs, queries and keys are never logged.
class AudiusCatalog implements MusicCatalog {
  AudiusCatalog({
    http.Client? client,
    List<Uri>? hosts,
    this.apiKey = '',
    this.appName = 'vibe_rooms',
    this.timeout = const Duration(seconds: 8),
    this.retryDelay = const Duration(milliseconds: 400),
    this.trendingTtl = const Duration(minutes: 2),
    DateTime Function()? now,
  }) : _client = client ?? http.Client(),
       hosts = hosts ?? [Uri.parse('https://api.audius.co')],
       _now = now ?? DateTime.now;

  final http.Client _client;
  final List<Uri> hosts;
  final String apiKey;
  final String appName;
  final Duration timeout;
  final Duration retryDelay;
  final Duration trendingTtl;
  final DateTime Function() _now;

  // Trending barely changes; caching it keeps us well under the free plan's
  // 10 requests per second.
  List<Track>? _trending;
  DateTime? _trendingAt;
  int _trendingLimit = 0;

  /// Longest Retry-After we will honour before retrying.
  static const _maxRetryWait = Duration(seconds: 2);

  @override
  Future<List<Track>> search(String query, {int limit = 20}) async {
    final text = query.trim();
    if (text.isEmpty) return const [];
    final body = await _get('/v1/tracks/search', {
      'query': text,
      'limit': '$limit',
    });
    return parseTrackList(body);
  }

  @override
  Future<List<Track>> trending({int limit = 20}) async {
    final cached = _trending;
    final at = _trendingAt;
    if (cached != null &&
        at != null &&
        _trendingLimit >= limit &&
        _now().difference(at) < trendingTtl) {
      return cached.take(limit).toList();
    }
    final body = await _get('/v1/tracks/trending', {
      'limit': '$limit',
      'time': 'week',
    });
    final tracks = parseTrackList(body);
    _trending = tracks;
    _trendingAt = _now();
    _trendingLimit = limit;
    return tracks;
  }

  @override
  Uri streamUri(String trackId) {
    final host = hosts.first;
    return host.replace(
      // pathSegments percent-encodes the id, so an odd id can never change
      // the path.
      pathSegments: ['v1', 'tracks', trackId, 'stream'],
      queryParameters: _baseQuery(const {}),
    );
  }

  Map<String, String> _baseQuery(Map<String, String> query) => {
    ...query,
    'app_name': appName,
    if (apiKey.isNotEmpty) 'api_key': apiKey,
  };

  Future<Object?> _get(String path, Map<String, String> query) async {
    AudiusFailure? last;
    for (final host in hosts) {
      try {
        return await _getWithRetry(
          host.replace(path: path, queryParameters: _baseQuery(query)),
        );
      } on AudiusFailure catch (failure) {
        last = failure;
        if (failure.kind == AudiusFailureKind.notFound) rethrow;
      }
    }
    throw last ?? const AudiusFailure(AudiusFailureKind.unknown);
  }

  /// One request, retried once after a short backoff on 429, 5xx, a timeout or
  /// a network error.
  Future<Object?> _getWithRetry(Uri uri) async {
    for (var attempt = 0; ; attempt++) {
      final canRetry = attempt == 0;
      http.Response response;
      try {
        response = await _client.get(uri).timeout(timeout);
      } on TimeoutException {
        if (canRetry) {
          await Future<void>.delayed(retryDelay);
          continue;
        }
        throw const AudiusFailure(AudiusFailureKind.network);
      } on SocketException {
        if (canRetry) {
          await Future<void>.delayed(retryDelay);
          continue;
        }
        throw const AudiusFailure(AudiusFailureKind.network);
      } on http.ClientException {
        if (canRetry) {
          await Future<void>.delayed(retryDelay);
          continue;
        }
        throw const AudiusFailure(AudiusFailureKind.network);
      }

      final status = response.statusCode;
      if (status == 200) return _decode(response.body);
      if (status == 404) throw const AudiusFailure(AudiusFailureKind.notFound);

      final retryable = status == 429 || status >= 500;
      if (retryable && canRetry) {
        await Future<void>.delayed(_waitFor(response));
        continue;
      }
      throw AudiusFailure(
        status == 429
            ? AudiusFailureKind.rateLimited
            : (status >= 500
                  ? AudiusFailureKind.network
                  : AudiusFailureKind.unknown),
      );
    }
  }

  Duration _waitFor(http.Response response) {
    final seconds = int.tryParse(response.headers['retry-after'] ?? '');
    if (seconds == null || seconds < 0) return retryDelay;
    final wait = Duration(seconds: seconds);
    return wait > _maxRetryWait ? _maxRetryWait : wait;
  }

  Object? _decode(String body) {
    try {
      return jsonDecode(body);
    } on FormatException {
      throw const AudiusFailure(AudiusFailureKind.unknown);
    }
  }
}
