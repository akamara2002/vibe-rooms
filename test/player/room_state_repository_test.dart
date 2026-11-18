import 'dart:async';

import 'package:flutter_test/flutter_test.dart' hide EnginePhase;
import 'package:vibe_rooms/features/player/data/supabase_room_state_repository.dart';
import 'package:vibe_rooms/features/player/domain/room_state.dart';
import 'package:vibe_rooms/features/player/domain/room_state_repository.dart';

import '../fakes/fakes.dart';

class _Subscription implements RoomStateSubscription {
  _Subscription(this.source);
  final _Source source;
  @override
  Future<void> close() async => source.closed++;
}

class _Source implements RoomStateSource {
  Map<String, dynamic>? row;
  Object? fetchError;
  List<dynamic> updateResult = [
    {'room_id': 'r'},
  ];
  Object? updateError;
  int fetches = 0;
  int closed = 0;
  Map<String, dynamic>? lastUpdate;
  void Function(Map<String, dynamic>)? onRow;
  void Function(bool)? onStatus;

  @override
  Future<Map<String, dynamic>?> fetch(String roomId) async {
    fetches++;
    final error = fetchError;
    if (error != null) throw error;
    return row;
  }

  @override
  Future<List<dynamic>> update(String roomId, Map<String, dynamic> json) async {
    lastUpdate = json;
    final error = updateError;
    if (error != null) throw error;
    return updateResult;
  }

  @override
  RoomStateSubscription subscribe(
    String roomId, {
    required void Function(Map<String, dynamic> row) onRow,
    required void Function(bool joined) onStatus,
  }) {
    this.onRow = onRow;
    this.onStatus = onStatus;
    return _Subscription(this);
  }
}

Map<String, dynamic> _json({
  int positionMs = 0,
  bool playing = false,
  String updatedAt = '2026-11-18T12:00:00+00:00',
  String? trackId = 't1',
}) => fakeRoomState(
  trackId: trackId,
  isPlaying: playing,
  positionMs: positionMs,
  updatedAt: DateTime.parse(updatedAt),
).toJson();

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  group('RoomStateUpdate (what the host writes)', () {
    test('a track write has exactly the granted columns, never updated_at', () {
      final json = RoomStateUpdate.track(fakeTrack()).toJson();
      expect(json.keys.toSet(), fakeRoomState().toUpdateJson().keys.toSet());
      for (final forbidden in ['updated_at', 'updated_by', 'room_id']) {
        expect(json.containsKey(forbidden), isFalse);
      }
      expect(json['position_ms'], 0);
      expect(json['is_playing'], true);
      expect(json['queue_item_id'], isNull);
    });

    test('a playback write has only is_playing and position_ms', () {
      final json = RoomStateUpdate.playback(
        isPlaying: false,
        positionMs: 1234,
      ).toJson();
      expect(json, {'is_playing': false, 'position_ms': 1234});
    });

    test('the JSON cannot be edited after the fact', () {
      final json = RoomStateUpdate.playback(
        isPlaying: true,
        positionMs: 1,
      ).toJson();
      expect(() => json['updated_at'] = 'x', throwsUnsupportedError);
    });
  });

  group('hostUpdate', () {
    test('sends the update', () async {
      final source = _Source();
      await SupabaseRoomStateRepository.withSource(source).hostUpdate(
        'r',
        RoomStateUpdate.playback(isPlaying: true, positionMs: 5),
      );
      expect(source.lastUpdate, {'is_playing': true, 'position_ms': 5});
    });

    test('zero changed rows (row level security) is a failure', () async {
      final source = _Source()..updateResult = [];
      await expectLater(
        SupabaseRoomStateRepository.withSource(source).hostUpdate(
          'r',
          RoomStateUpdate.playback(isPlaying: true, positionMs: 5),
        ),
        throwsA(
          isA<RoomStateFailure>().having(
            (f) => f.kind,
            'kind',
            RoomStateFailureKind.notAllowed,
          ),
        ),
      );
    });

    test('other errors become a failure too', () async {
      final source = _Source()..updateError = StateError('boom');
      await expectLater(
        SupabaseRoomStateRepository.withSource(source).hostUpdate(
          'r',
          RoomStateUpdate.playback(isPlaying: true, positionMs: 5),
        ),
        throwsA(isA<RoomStateFailure>()),
      );
    });
  });

  group('watch', () {
    late _Source source;
    late SupabaseRoomStateRepository repo;
    late List<RoomState> seen;
    late List<Object> errors;
    late StreamSubscription<RoomState> sub;

    setUp(() async {
      source = _Source()..row = _json(positionMs: 1000);
      repo = SupabaseRoomStateRepository.withSource(source);
      seen = [];
      errors = [];
      sub = repo.watch('r').listen(seen.add, onError: errors.add);
      await _settle();
    });

    tearDown(() => sub.cancel());

    test('starts with the current row', () {
      expect(seen.single.positionMs, 1000);
    });

    test('a newer event is emitted', () async {
      source.onRow!(
        _json(positionMs: 2000, updatedAt: '2026-11-18T12:00:05+00:00'),
      );
      await _settle();
      expect(seen.map((s) => s.positionMs), [1000, 2000]);
    });

    test('an older event is ignored (the newest updated_at wins)', () async {
      source.onRow!(
        _json(positionMs: 3000, updatedAt: '2026-11-18T12:00:10+00:00'),
      );
      source.onRow!(
        _json(positionMs: 2000, updatedAt: '2026-11-18T12:00:05+00:00'),
      );
      await _settle();
      expect(seen.map((s) => s.positionMs), [1000, 3000]);
    });

    test(
      'the same updated_at with other content is kept (foreign key update)',
      () async {
        source.onRow!(_json(positionMs: 1000, trackId: 't2'));
        await _settle();
        expect(seen.last.trackId, 't2');
      },
    );

    test('an identical row is not emitted twice', () async {
      source.onRow!(_json(positionMs: 1000));
      await _settle();
      expect(seen, hasLength(1));
    });

    test('rejoining the channel reads the row again', () async {
      expect(source.fetches, 1);
      source.row = _json(
        positionMs: 9000,
        updatedAt: '2026-11-18T12:01:00+00:00',
      );
      source.onStatus!(true);
      await _settle();
      expect(source.fetches, 2);
      expect(seen.last.positionMs, 9000);
    });

    test('a stale re-read cannot overwrite a newer event', () async {
      source.onRow!(
        _json(positionMs: 5000, updatedAt: '2026-11-18T12:00:30+00:00'),
      );
      source.onStatus!(true); // the re-read still returns the older row
      await _settle();
      expect(seen.last.positionMs, 5000);
    });

    test('channel trouble is an error, and the stream stays open', () async {
      source.onStatus!(false);
      await _settle();
      expect(errors.single, isA<RoomStateFailure>());
      source.onRow!(
        _json(positionMs: 4000, updatedAt: '2026-11-18T12:00:20+00:00'),
      );
      await _settle();
      expect(seen.last.positionMs, 4000);
    });

    test('a malformed event triggers a re-read', () async {
      source.onRow!({'nonsense': true});
      await _settle();
      expect(source.fetches, 2);
    });

    test('cancelling closes the channel and ignores late callbacks', () async {
      await sub.cancel();
      expect(source.closed, 1);
      source.onRow!(
        _json(positionMs: 7000, updatedAt: '2026-11-18T12:05:00+00:00'),
      );
      source.onStatus!(true);
      await _settle();
      expect(seen, hasLength(1));
    });
  });

  test('a failed first read is reported as an error', () async {
    final source = _Source()..fetchError = StateError('offline');
    final errors = <Object>[];
    final sub = SupabaseRoomStateRepository.withSource(source)
        .watch('r')
        .listen((_) {}, onError: errors.add);
    await _settle();
    expect(errors.single, isA<RoomStateFailure>());
    await sub.cancel();
  });
}
