import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vibe_rooms/features/rooms/data/room_error_mapper.dart';
import 'package:vibe_rooms/features/rooms/domain/room_failure.dart';

void main() {
  RoomFailureKind kindOf(Object e) => mapRoomError(e).kind;

  test('room_not_found by message or by P0002', () {
    expect(
      kindOf(
        const PostgrestException(message: 'room_not_found', code: 'P0002'),
      ),
      RoomFailureKind.roomNotFound,
    );
    expect(
      kindOf(const PostgrestException(message: 'x', code: 'P0002')),
      RoomFailureKind.roomNotFound,
    );
    expect(
      kindOf(const PostgrestException(message: 'room_not_found')),
      RoomFailureKind.roomNotFound,
    );
  });

  test('invalid_name', () {
    expect(
      kindOf(const PostgrestException(message: 'invalid_name', code: 'P0001')),
      RoomFailureKind.invalidName,
    );
  });

  test('not_authenticated by message or by 28000', () {
    expect(
      kindOf(const PostgrestException(message: 'not_authenticated')),
      RoomFailureKind.notAuthenticated,
    );
    expect(
      kindOf(const PostgrestException(message: 'x', code: '28000')),
      RoomFailureKind.notAuthenticated,
    );
  });

  test('network errors', () {
    expect(kindOf(const SocketException('offline')), RoomFailureKind.network);
    expect(kindOf(AuthRetryableFetchException()), RoomFailureKind.network);
  });

  test('anything else is unknown, and a RoomFailure passes through', () {
    expect(kindOf(StateError('boom')), RoomFailureKind.unknown);
    expect(
      kindOf(const PostgrestException(message: 'weird', code: '99999')),
      RoomFailureKind.unknown,
    );
    const failure = RoomFailure(RoomFailureKind.closed);
    expect(identical(mapRoomError(failure), failure), isTrue);
  });

  test('every failure has a short human message', () {
    for (final kind in RoomFailureKind.values) {
      final message = RoomFailure(kind).message;
      expect(message, isNotEmpty);
      expect(message.toLowerCase(), isNot(contains('exception')));
    }
    expect(
      const RoomFailure(RoomFailureKind.roomNotFound).message,
      'No room with that code.',
    );
  });

  test('logs only the type and code: no message, code value or ids', () {
    final logged = <String>[];
    final original = debugPrint;
    debugPrint = (String? m, {int? wrapWidth}) => logged.add(m ?? '');
    addTearDown(() => debugPrint = original);

    mapRoomError(
      const PostgrestException(
        message: 'duplicate key for ABC234 user 1b2c3d4e-0000-0000-0000-000000000000',
        code: '23505',
      ),
    );

    expect(logged, hasLength(1));
    expect(logged.single, contains('23505'));
    expect(logged.single, isNot(contains('ABC234')));
    expect(logged.single, isNot(contains('1b2c3d4e')));
  });
}
