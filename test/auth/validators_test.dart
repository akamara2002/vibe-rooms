import 'package:flutter_test/flutter_test.dart';
import 'package:vibe_rooms/features/auth/domain/validators.dart';

void main() {
  group('validateDisplayName', () {
    test('rejects empty and whitespace-only names', () {
      expect(validateDisplayName(null), isNotNull);
      expect(validateDisplayName(''), isNotNull);
      expect(validateDisplayName('   '), isNotNull);
    });

    test('accepts 1 to 30 characters after trimming', () {
      expect(validateDisplayName('A'), isNull);
      expect(validateDisplayName('  Ana  '), isNull);
      expect(validateDisplayName('a' * 30), isNull);
      expect(validateDisplayName('  ${'a' * 30}  '), isNull);
    });

    test('rejects 31 characters', () {
      expect(validateDisplayName('a' * 31), isNotNull);
    });

    test('counts code points like the database, not UTF-16 units', () {
      expect(validateDisplayName('🎧' * 30), isNull);
      expect(validateDisplayName('🎧' * 31), isNotNull);
    });
  });

  group('validateEmail', () {
    test('accepts normal addresses', () {
      for (final email in ['a@b.co', 'vibe.test+1@example.com', ' a@b.io ']) {
        expect(validateEmail(email), isNull, reason: email);
      }
    });

    test('rejects malformed addresses', () {
      for (final email in [
        '',
        '   ',
        'a',
        'a@',
        '@b.com',
        'a@b',
        'a b@c.com',
      ]) {
        expect(validateEmail(email), isNotNull, reason: email);
      }
    });
  });

  group('validatePassword', () {
    test('requires at least 6 characters', () {
      expect(validatePassword(null), isNotNull);
      expect(validatePassword(''), isNotNull);
      expect(validatePassword('12345'), isNotNull);
      expect(validatePassword('123456'), isNull);
      expect(validatePassword('a much longer password'), isNull);
    });
  });

  test('there are 12 distinct avatar emojis', () {
    expect(avatarEmojis, hasLength(12));
    expect(avatarEmojis.toSet(), hasLength(12));
  });
}
