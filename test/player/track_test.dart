import 'package:flutter_test/flutter_test.dart';
import 'package:vibe_rooms/features/player/domain/track.dart';
import 'package:vibe_rooms/features/queue/domain/queue_item.dart';

void main() {
  Track make({
    String id = 'abc',
    String title = 'Song',
    String artist = 'Artist',
    String? artwork,
    int durationMs = 1000,
    String? permalink,
  }) => Track(
    id: id,
    title: title,
    artist: artist,
    artworkUrl: artwork,
    durationMs: durationMs,
    permalinkUrl: permalink,
  );

  group('validation', () {
    test('a duration of zero or less is rejected', () {
      expect(
        Track.tryCreate(id: 'a', title: 't', artist: 'x', durationMs: 0),
        isNull,
      );
      expect(
        Track.tryCreate(id: 'a', title: 't', artist: 'x', durationMs: -5),
        isNull,
      );
      expect(() => make(durationMs: 0), throwsArgumentError);
    });

    test('an empty id is rejected', () {
      expect(
        Track.tryCreate(id: '  ', title: 't', artist: 'x', durationMs: 1),
        isNull,
      );
    });

    test('title and artist are cut to 300 characters, the id to 100', () {
      final track = make(id: 'i' * 150, title: 't' * 400, artist: 'a' * 301);
      expect(track.id.length, 100);
      expect(track.title.length, 300);
      expect(track.artist.length, 300);
    });

    test('exactly at the limits is kept whole', () {
      final track = make(id: 'i' * 100, title: 't' * 300, artist: 'a' * 300);
      expect(track.id.length, 100);
      expect(track.title.length, 300);
      expect(track.artist.length, 300);
    });

    test(
      'truncation counts code points, not UTF-16 units (no split emoji)',
      () {
        final track = make(title: '🎧' * 400);
        expect(track.title.runes.length, 300);
        expect(track.title.endsWith('🎧'), isTrue);
      },
    );

    test('text is trimmed', () {
      final track = make(title: '  Hello  ', artist: ' Me ');
      expect(track.title, 'Hello');
      expect(track.artist, 'Me');
    });

    test('artwork is kept only when https, whitespace-free and <= 2048', () {
      expect(
        make(artwork: 'https://x.test/a.jpg').artworkUrl,
        'https://x.test/a.jpg',
      );
      expect(make(artwork: 'http://x.test/a.jpg').artworkUrl, isNull);
      expect(make(artwork: 'javascript:alert(1)').artworkUrl, isNull);
      expect(make(artwork: 'https://x.test/a b.jpg').artworkUrl, isNull);
      expect(make(artwork: '//x.test/a.jpg').artworkUrl, isNull);
      expect(make(artwork: 'https://x.test/${'a' * 2048}').artworkUrl, isNull);
      expect(
        make(artwork: 'https://x.test/${'a' * 2000}').artworkUrl,
        isNotNull,
      );
      expect(make().artworkUrl, isNull);
    });

    test('the permalink follows the same https rule', () {
      expect(
        make(permalink: 'https://audius.co/a/b').permalinkUrl,
        'https://audius.co/a/b',
      );
      expect(make(permalink: 'http://audius.co/a/b').permalinkUrl, isNull);
    });
  });

  group('toQueueInsertJson', () {
    test('has exactly the queue_items insert shape', () {
      final track = make(
        id: 'id1',
        title: 'T',
        artist: 'A',
        artwork: 'https://x.test/a.jpg',
        durationMs: 2500,
      );
      final json = track.toQueueInsertJson('room-1', 'user-1');
      expect(json, {
        'room_id': 'room-1',
        'added_by': 'user-1',
        'track_id': 'id1',
        'title': 'T',
        'artist': 'A',
        'artwork_url': 'https://x.test/a.jpg',
        'duration_ms': 2500,
      });
    });

    test('matches the keys QueueItem.toInsertJson writes', () {
      final item = QueueItem(
        id: 'q',
        roomId: 'room-1',
        addedBy: 'user-1',
        trackId: 'id1',
        title: 'T',
        artist: 'A',
        durationMs: 2500,
        sortKey: 1,
        createdAt: DateTime.utc(2026),
      );
      expect(
        make().toQueueInsertJson('room-1', 'user-1').keys.toSet(),
        item.toInsertJson().keys.toSet(),
      );
    });

    test('never contains server-owned columns', () {
      final keys = make().toQueueInsertJson('r', 'u').keys;
      for (final forbidden in ['id', 'sort_key', 'played_at', 'created_at']) {
        expect(keys, isNot(contains(forbidden)));
      }
    });
  });

  test('equality and hashCode', () {
    expect(make(), make());
    expect(make().hashCode, make().hashCode);
    expect(make(), isNot(make(title: 'Other')));
  });
}
