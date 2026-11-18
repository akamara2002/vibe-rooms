import 'package:flutter_test/flutter_test.dart';
import 'package:vibe_rooms/core/utc.dart';
import 'package:vibe_rooms/features/auth/domain/profile.dart';
import 'package:vibe_rooms/features/chat/domain/message.dart';
import 'package:vibe_rooms/features/player/domain/room_state.dart';
import 'package:vibe_rooms/features/queue/domain/queue_item.dart';
import 'package:vibe_rooms/features/rooms/domain/room.dart';

void main() {
  // PostgREST returns timestamptz with microseconds and a +00:00 offset.
  const ts = '2026-11-18T10:00:00.123456+00:00';
  final tsUtc = DateTime.utc(2026, 11, 18, 10, 0, 0, 123, 456);

  group('Profile', () {
    final json = {'id': 'u1', 'display_name': 'Ana', 'avatar_emoji': '🎧'};

    test('fromJson / toJson round trip', () {
      final profile = Profile.fromJson(json);
      expect(profile.displayName, 'Ana');
      expect(profile.toJson(), json);
      expect(Profile.fromJson(profile.toJson()), profile);
    });

    test('equality and hashCode', () {
      expect(Profile.fromJson(json), Profile.fromJson(json));
      expect(Profile.fromJson(json).hashCode, Profile.fromJson(json).hashCode);
      expect(
        Profile.fromJson(json),
        isNot(Profile.fromJson({...json, 'display_name': 'Bo'})),
      );
    });
  });

  group('Room', () {
    final json = {
      'id': 'r1',
      'code': 'ABCD23',
      'name': 'Friday',
      'host_id': 'u1',
      'created_at': ts,
      'closed_at': null,
    };

    test('fromJson parses UTC timestamps and null closed_at', () {
      final room = Room.fromJson(json);
      expect(room.createdAt, tsUtc);
      expect(room.createdAt.isUtc, isTrue);
      expect(room.closedAt, isNull);
    });

    test('toJson round trip, including closed_at', () {
      final room = Room.fromJson({...json, 'closed_at': ts});
      expect(room.closedAt, tsUtc);
      expect(Room.fromJson(room.toJson()), room);
      expect(Room.fromJson(json).toJson()['closed_at'], isNull);
    });

    test('converts non-UTC offsets to UTC', () {
      final room = Room.fromJson({
        ...json,
        'created_at': '2026-11-18T12:00:00.123456+02:00',
      });
      expect(room.createdAt, tsUtc);
    });

    test('equality and hashCode', () {
      expect(Room.fromJson(json), Room.fromJson(json));
      expect(Room.fromJson(json).hashCode, Room.fromJson(json).hashCode);
      expect(Room.fromJson(json), isNot(Room.fromJson({...json, 'name': 'x'})));
    });
  });

  group('QueueItem', () {
    final json = {
      'id': 'q1',
      'room_id': 'r1',
      'added_by': 'u1',
      'track_id': 'aud-1',
      'title': 'Song',
      'artist': 'Artist',
      'artwork_url': null,
      'duration_ms': 180000,
      'sort_key': 42,
      'played_at': null,
      'created_at': ts,
    };

    test('fromJson / toJson round trip', () {
      final item = QueueItem.fromJson(json);
      expect(item.sortKey, 42);
      expect(item.playedAt, isNull);
      expect(item.toJson(), {...json, 'created_at': tsUtc.toIso8601String()});
      expect(QueueItem.fromJson(item.toJson()), item);
    });

    test('toInsertJson contains only the client-writable columns', () {
      final item = QueueItem.fromJson({...json, 'artwork_url': 'https://a/b'});
      expect(item.toInsertJson(), {
        'room_id': 'r1',
        'added_by': 'u1',
        'track_id': 'aud-1',
        'title': 'Song',
        'artist': 'Artist',
        'artwork_url': 'https://a/b',
        'duration_ms': 180000,
      });
      expect(item.toInsertJson().containsKey('sort_key'), isFalse);
    });

    test('equality and hashCode', () {
      expect(QueueItem.fromJson(json), QueueItem.fromJson(json));
      expect(
        QueueItem.fromJson(json).hashCode,
        QueueItem.fromJson(json).hashCode,
      );
      expect(
        QueueItem.fromJson(json),
        isNot(QueueItem.fromJson({...json, 'sort_key': 43})),
      );
    });
  });

  group('Message', () {
    final json = {
      'id': 'm1',
      'room_id': 'r1',
      'user_id': 'u1',
      'body': 'hello 🎶',
      'created_at': ts,
    };

    test('fromJson / toJson round trip', () {
      final message = Message.fromJson(json);
      expect(message.createdAt, tsUtc);
      expect(Message.fromJson(message.toJson()), message);
    });

    test('equality and hashCode', () {
      expect(Message.fromJson(json), Message.fromJson(json));
      expect(Message.fromJson(json).hashCode, Message.fromJson(json).hashCode);
      expect(
        Message.fromJson(json),
        isNot(Message.fromJson({...json, 'body': 'bye'})),
      );
    });
  });

  group('RoomState', () {
    final json = {
      'room_id': 'r1',
      'queue_item_id': 'q1',
      'track_id': 'aud-1',
      'title': 'Song',
      'artist': 'Artist',
      'artwork_url': null,
      'duration_ms': 180000,
      'is_playing': true,
      'position_ms': 10000,
      'updated_at': ts,
      'updated_by': 'u1',
    };

    RoomState state({
      required bool playing,
      int positionMs = 10000,
      int? durationMs = 180000,
    }) => RoomState(
      roomId: 'r1',
      durationMs: durationMs,
      isPlaying: playing,
      positionMs: positionMs,
      updatedAt: tsUtc,
    );

    test('fromJson / toJson round trip', () {
      final s = RoomState.fromJson(json);
      expect(s.updatedAt, tsUtc);
      expect(s.queueItemId, 'q1');
      expect(RoomState.fromJson(s.toJson()), s);
    });

    test('fromJson handles an idle room (all nullable fields null)', () {
      final s = RoomState.fromJson({
        'room_id': 'r1',
        'queue_item_id': null,
        'track_id': null,
        'title': null,
        'artist': null,
        'artwork_url': null,
        'duration_ms': null,
        'is_playing': false,
        'position_ms': 0,
        'updated_at': ts,
        'updated_by': null,
      });
      expect(s.trackId, isNull);
      expect(s.durationMs, isNull);
      expect(RoomState.fromJson(s.toJson()), s);
    });

    test('toUpdateJson never contains server-owned columns', () {
      final update = RoomState.fromJson(json).toUpdateJson();
      expect(
        update.keys,
        isNot(
          anyOf(
            contains('updated_at'),
            contains('updated_by'),
            contains('room_id'),
          ),
        ),
      );
      expect(update['position_ms'], 10000);
      expect(update['is_playing'], true);
    });

    test('equality and hashCode', () {
      expect(RoomState.fromJson(json), RoomState.fromJson(json));
      expect(
        RoomState.fromJson(json).hashCode,
        RoomState.fromJson(json).hashCode,
      );
      expect(
        RoomState.fromJson(json),
        isNot(RoomState.fromJson({...json, 'position_ms': 11})),
      );
    });

    group('expectedPositionMs', () {
      test('paused returns positionMs regardless of elapsed time', () {
        final s = state(playing: false);
        expect(
          s.expectedPositionMs(tsUtc.add(const Duration(minutes: 5))),
          10000,
        );
        expect(s.expectedPositionMs(tsUtc), 10000);
      });

      test('playing for 5 seconds adds 5000 ms', () {
        final s = state(playing: true);
        expect(
          s.expectedPositionMs(tsUtc.add(const Duration(seconds: 5))),
          15000,
        );
      });

      test('playing for exactly 0 ms returns positionMs', () {
        expect(state(playing: true).expectedPositionMs(tsUtc), 10000);
      });

      test('is clamped at durationMs when known', () {
        final s = state(playing: true, positionMs: 170000);
        expect(
          s.expectedPositionMs(tsUtc.add(const Duration(minutes: 10))),
          180000,
        );
      });

      test('is not clamped when durationMs is unknown', () {
        final s = state(playing: true, durationMs: null);
        expect(
          s.expectedPositionMs(tsUtc.add(const Duration(hours: 1))),
          10000 + 3600000,
        );
      });

      test(
        'serverNow earlier than updatedAt (clock skew) returns positionMs',
        () {
          final s = state(playing: true);
          expect(
            s.expectedPositionMs(tsUtc.subtract(const Duration(seconds: 3))),
            10000,
          );
        },
      );

      test('works with a local (non-UTC) serverNow', () {
        final s = state(playing: true);
        final local = tsUtc.add(const Duration(seconds: 2)).toLocal();
        expect(s.expectedPositionMs(local), 12000);
      });
    });
  });

  group('parseUtc', () {
    test('honours an explicit offset', () {
      expect(parseUtc('2026-11-18T12:00:00.123456+02:00'), tsUtc);
      expect(parseUtc('2026-11-18T10:00:00.123456Z'), tsUtc);
    });

    test('treats a timestamp without an offset as UTC, not local time', () {
      final parsed = parseUtc('2026-11-18T10:00:00.123456');
      expect(parsed, tsUtc);
      expect(parsed.isUtc, isTrue);
    });
  });
}
