import 'package:flutter_test/flutter_test.dart';
import 'package:vibe_rooms/features/player/data/audius_parser.dart';

Map<String, dynamic> raw({
  Object? id = 'Ma0blKV',
  Object? title = 'Light the Way',
  Object? duration = 227,
  Object? streamable = true,
  Object? artwork = const {
    '150x150': 'https://cdn.test/150.jpg',
    '480x480': 'https://cdn.test/480.jpg',
    '1000x1000': 'https://cdn.test/1000.jpg',
    'mirrors': ['https://m.test'],
  },
  Object? user = const {'name': 'Stony', 'handle': 'stony100'},
  Object? permalink = '/stony/light-the-way',
}) => {
  'id': id,
  'title': title,
  'duration': duration,
  'is_streamable': streamable,
  'is_delete': false,
  'is_unlisted': false,
  'access': {'stream': true, 'download': true},
  'artwork': artwork,
  'user': user,
  'permalink': permalink,
};

void main() {
  test('a normal track', () {
    final track = parseTrack(raw())!;
    expect(track.id, 'Ma0blKV');
    expect(track.title, 'Light the Way');
    expect(track.artist, 'Stony');
    expect(track.durationMs, 227000);
    expect(track.artworkUrl, 'https://cdn.test/480.jpg');
    expect(track.permalinkUrl, 'https://audius.co/stony/light-the-way');
  });

  test('missing artwork gives null artwork, not an error', () {
    expect(parseTrack(raw(artwork: null))!.artworkUrl, isNull);
    expect(parseTrack(raw(artwork: {'mirrors': []}))!.artworkUrl, isNull);
    expect(parseTrack(raw(artwork: 'oops'))!.artworkUrl, isNull);
  });

  test('falls back to another artwork size', () {
    final track = parseTrack(
      raw(artwork: {'150x150': 'https://cdn.test/s.jpg'}),
    )!;
    expect(track.artworkUrl, 'https://cdn.test/s.jpg');
  });

  test('a non-https artwork is dropped by Track validation', () {
    final track = parseTrack(
      raw(artwork: {'480x480': 'http://cdn.test/a.jpg'}),
    )!;
    expect(track.artworkUrl, isNull);
  });

  test('zero, negative, missing or non-numeric duration is skipped', () {
    expect(parseTrack(raw(duration: 0)), isNull);
    expect(parseTrack(raw(duration: -3)), isNull);
    expect(parseTrack(raw(duration: null)), isNull);
    expect(parseTrack(raw(duration: 'long')), isNull);
    expect(parseTrack(raw(duration: double.nan)), isNull);
  });

  test('fractional seconds are kept as milliseconds', () {
    expect(parseTrack(raw(duration: 12.5))!.durationMs, 12500);
  });

  test('non-streamable tracks are skipped', () {
    expect(parseTrack(raw(streamable: false)), isNull);
    expect(parseTrack(raw(streamable: null)), isNull);
    expect(parseTrack(raw(streamable: 'true')), isNull);
  });

  test('deleted, unlisted and stream-gated tracks are skipped', () {
    expect(parseTrack({...raw(), 'is_delete': true}), isNull);
    expect(parseTrack({...raw(), 'is_unlisted': true}), isNull);
    expect(
      parseTrack({
        ...raw(),
        'access': {'stream': false},
      }),
      isNull,
    );
  });

  test('artist falls back to the handle, then to "Unknown artist"', () {
    expect(parseTrack(raw(user: {'handle': 'h'}))!.artist, 'h');
    expect(parseTrack(raw(user: {'name': '  ', 'handle': 'h'}))!.artist, 'h');
    expect(parseTrack(raw(user: null))!.artist, 'Unknown artist');
    expect(parseTrack(raw(user: 'x'))!.artist, 'Unknown artist');
  });

  test('a missing title becomes "Untitled"', () {
    expect(parseTrack(raw(title: null))!.title, 'Untitled');
    expect(parseTrack(raw(title: '   '))!.title, 'Untitled');
  });

  test('unexpected id types', () {
    expect(parseTrack(raw(id: null)), isNull);
    expect(parseTrack(raw(id: '')), isNull);
    expect(parseTrack(raw(id: <String>[])), isNull);
    expect(parseTrack(raw(id: 42))!.id, '42');
  });

  test('a permalink that is not a path is ignored', () {
    expect(
      parseTrack(raw(permalink: 'https://evil.test/x'))!.permalinkUrl,
      isNull,
    );
    expect(parseTrack(raw(permalink: 5))!.permalinkUrl, isNull);
    expect(parseTrack(raw(permalink: '/a b'))!.permalinkUrl, isNull);
  });

  test('never throws on garbage', () {
    for (final junk in [
      null,
      1,
      'x',
      [],
      <String, Object?>{},
      {'id': {}},
    ]) {
      expect(() => parseTrack(junk), returnsNormally);
      expect(parseTrack(junk), isNull);
    }
  });

  group('parseTrackList', () {
    test('keeps the good tracks and skips the bad ones', () {
      final tracks = parseTrackList({
        'data': [raw(), raw(duration: 0), 'junk', null, raw(id: 'second')],
      });
      expect(tracks.map((t) => t.id), ['Ma0blKV', 'second']);
    });

    test('unexpected bodies give an empty list', () {
      expect(parseTrackList(null), isEmpty);
      expect(parseTrackList('x'), isEmpty);
      expect(parseTrackList({'data': 'nope'}), isEmpty);
      expect(parseTrackList({'other': []}), isEmpty);
      expect(parseTrackList([raw()]), isEmpty);
    });
  });
}
