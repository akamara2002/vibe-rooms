import 'package:flutter_test/flutter_test.dart';
import 'package:vibe_rooms/features/rooms/domain/room_code.dart';
import 'package:vibe_rooms/features/rooms/domain/room_name.dart';
import 'package:vibe_rooms/features/rooms/presentation/room_sheets.dart';

void main() {
  group('normalizeRoomCode', () {
    test('upper-cases, trims and strips spaces', () {
      expect(normalizeRoomCode('  abc234 '), 'ABC234');
      expect(normalizeRoomCode('abc 234'), 'ABC234');
    });

    test('drops characters outside the alphabet (0, O, 1, I, symbols)', () {
      expect(normalizeRoomCode('A0B1C2'), 'ABC2');
      expect(normalizeRoomCode('OIoi'), '');
      expect(normalizeRoomCode('A-B_C!2'), 'ABC2');
      expect(normalizeRoomCode('ünï😀AB'), 'NAB'); // n is allowed
    });

    test('does not truncate', () {
      expect(normalizeRoomCode('ABCDEFGH'), 'ABCDEFGH');
    });
  });

  group('isValidRoomCode', () {
    test('accepts exactly six alphabet characters', () {
      expect(isValidRoomCode('ABC234'), isTrue);
      expect(isValidRoomCode('ZZZZZZ'), isTrue);
      expect(isValidRoomCode('999999'), isTrue);
    });

    test('rejects short, long, lower-case and forbidden characters', () {
      expect(isValidRoomCode(''), isFalse);
      expect(isValidRoomCode('ABC23'), isFalse);
      expect(isValidRoomCode('ABC2345'), isFalse);
      expect(isValidRoomCode('abc234'), isFalse);
      expect(isValidRoomCode('ABC230'), isFalse); // 0
      expect(isValidRoomCode('ABC23O'), isFalse); // O
      expect(isValidRoomCode('ABC231'), isFalse); // 1
      expect(isValidRoomCode('ABC23I'), isFalse); // I
      expect(isValidRoomCode('ABC 23'), isFalse);
    });

    test('the alphabet has 32 characters and no look-alikes', () {
      expect(roomCodeAlphabet, hasLength(32));
      for (final bad in ['0', 'O', '1', 'I']) {
        expect(roomCodeAlphabet.contains(bad), isFalse);
      }
    });
  });

  group('RoomCodeFormatter', () {
    TextEditingValue format(String text) => RoomCodeFormatter()
        .formatEditUpdate(TextEditingValue.empty, TextEditingValue(text: text));

    test('upper-cases and strips on typing', () {
      expect(format('abc').text, 'ABC');
    });

    test('pasting "abc 234" gives ABC234 with the cursor at the end', () {
      final value = format('abc 234');
      expect(value.text, 'ABC234');
      expect(value.selection.baseOffset, 6);
    });

    test('caps at six characters and removes forbidden ones', () {
      expect(format('ABCDEFGHJK').text, 'ABCDEF');
      expect(format('a0b1c2').text, 'ABC2');
    });
  });

  group('validateRoomName', () {
    test('rejects empty and whitespace-only names', () {
      expect(validateRoomName(null), isNotNull);
      expect(validateRoomName(''), isNotNull);
      expect(validateRoomName('   '), isNotNull);
    });

    test('accepts 1 to 40 characters after trimming, rejects 41', () {
      expect(validateRoomName('a'), isNull);
      expect(validateRoomName('  Friday  '), isNull);
      expect(validateRoomName('a' * 40), isNull);
      expect(validateRoomName('a' * 41), isNotNull);
    });
  });

  group('buildInviteText', () {
    test('mobile: text only', () {
      expect(
        buildInviteText(roomName: 'Friday', code: 'ABC234'),
        'Join my Vibe Room "Friday" with code ABC234',
      );
    });

    test('web: adds the join link', () {
      expect(
        buildInviteText(
          roomName: 'Friday',
          code: 'ABC234',
          webOrigin: 'http://localhost:8080',
        ),
        'Join my Vibe Room "Friday" with code ABC234\nhttp://localhost:8080/#/join/ABC234',
      );
    });
  });

  test('isPlausibleRoomId allows uuids and plain ids only', () {
    expect(isPlausibleRoomId('20cec9bd-53a2-4efe-8f8d-a8580f55a53d'), isTrue);
    expect(isPlausibleRoomId('room_1'), isTrue);
    for (final bad in [
      '',
      'a,b',
      'a.b',
      'a b',
      '../x',
      'a%20b',
      'a/b',
      'a' * 65,
    ]) {
      expect(isPlausibleRoomId(bad), isFalse, reason: bad);
    }
  });
}
