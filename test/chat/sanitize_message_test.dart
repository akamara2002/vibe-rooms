import 'package:flutter_test/flutter_test.dart' hide EnginePhase;
import 'package:vibe_rooms/features/chat/domain/sanitize_message.dart';
import 'package:vibe_rooms/features/chat/domain/send_rate_limiter.dart';

void main() {
  displayTextTests();
  group('sanitizeMessage', () {
    test('trims', () => expect(sanitizeMessage('  hi  '), 'hi'));

    test('empty and whitespace-only are null', () {
      expect(sanitizeMessage(''), isNull);
      expect(sanitizeMessage('   '), isNull);
      expect(sanitizeMessage('\n\n\t '), isNull);
    });

    test('control characters are removed, newlines kept', () {
      expect(sanitizeMessage('a\u0000b\u0007c\u001Bd'), 'abcd');
      expect(sanitizeMessage('a\u007Fb\u0085c'), 'abc');
      expect(sanitizeMessage('line1\nline2'), 'line1\nline2');
    });

    test('tabs become spaces and carriage returns become newlines', () {
      expect(sanitizeMessage('a\tb'), 'a b');
      expect(sanitizeMessage('a\r\nb\rc'), 'a\nb\nc');
    });

    test('bidi overrides and isolates are removed', () {
      expect(sanitizeMessage('a\u202Eb\u202Ac'), 'abc');
      expect(sanitizeMessage('x\u2066y\u2069z'), 'xyz');
      expect(sanitizeMessage('a\u200Eb\u200Fc\u061Cd'), 'abcd');
    });

    test('three or more newlines collapse into two', () {
      expect(sanitizeMessage('a\n\n\n\nb'), 'a\n\nb');
      expect(sanitizeMessage('a\n\nb'), 'a\n\nb');
      expect(sanitizeMessage('a\n\n\n\n\n\n\nb\n\n\nc'), 'a\n\nb\n\nc');
    });

    test('a message made only of control characters is empty', () {
      expect(sanitizeMessage('\u0000\u0001\u202E'), isNull);
    });

    test('lengths 1, 500 and 501', () {
      expect(sanitizeMessage('a'), 'a');
      expect(sanitizeMessage('a' * 500), 'a' * 500);
      expect(sanitizeMessage('a' * 501), isNull);
    });

    test('characters are counted like the database: code points', () {
      // 500 emoji are 1000 UTF-16 units but 500 characters: allowed.
      expect(sanitizeMessage('😀' * 500), '😀' * 500);
      expect(sanitizeMessage('😀' * 501), isNull);
      // Multi-byte text counts per character too.
      expect(sanitizeMessage('é' * 500), 'é' * 500);
      expect(sanitizeMessage('日本' * 250), '日本' * 250);
      expect(sanitizeMessage('日本' * 251), isNull);
    });

    test('the length is measured after trimming', () {
      expect(sanitizeMessage('   ${'a' * 500}   '), 'a' * 500);
    });
  });

  group('messageLength', () {
    test('counts code points', () {
      expect(messageLength('abc'), 3);
      expect('😀'.length, 2);
      expect(messageLength('😀'), 1);
      expect(messageLength('a😀é'), 3);
    });
  });

  group('sanitizeIncoming (what arrives from other people)', () {
    test('cleans the same way but has no length rule', () {
      expect(sanitizeIncoming('hi\u202E there'), 'hi there');
      expect(sanitizeIncoming('a' * 600), 'a' * 600);
      expect(sanitizeIncoming('\u0000\n\n\n'), '');
    });

    test('is idempotent, so a sent body compares equal to its echo', () {
      final sent = sanitizeMessage(' hello\n\n\n\nthere\u0007 ')!;
      expect(sanitizeIncoming(sent), sent);
    });
  });

  group('SendRateLimiter', () {
    test('one per second', () {
      var now = DateTime.utc(2026);
      final limiter = SendRateLimiter(now: () => now);
      expect(limiter.tryAcquire(), isTrue);
      expect(limiter.tryAcquire(), isFalse);
      now = now.add(const Duration(milliseconds: 999));
      expect(limiter.tryAcquire(), isFalse);
      now = now.add(const Duration(milliseconds: 2));
      expect(limiter.tryAcquire(), isTrue);
    });

    test('twenty per minute', () {
      var now = DateTime.utc(2026);
      final limiter = SendRateLimiter(now: () => now);
      for (var i = 0; i < 20; i++) {
        expect(limiter.tryAcquire(), isTrue, reason: 'message $i');
        now = now.add(const Duration(seconds: 2));
      }
      // 40 s have passed; all twenty are still inside the minute.
      expect(limiter.tryAcquire(), isFalse);
      now = now.add(const Duration(seconds: 21));
      expect(limiter.tryAcquire(), isTrue);
    });

    test('a refused attempt does not count, so waiting is enough', () {
      var now = DateTime.utc(2026);
      final limiter = SendRateLimiter(now: () => now);
      expect(limiter.tryAcquire(), isTrue);
      for (var i = 0; i < 50; i++) {
        expect(limiter.tryAcquire(), isFalse);
      }
      now = now.add(const Duration(milliseconds: 1001));
      expect(limiter.tryAcquire(), isTrue);
    });
  });
}

void displayTextTests() {
  group('sanitizeDisplayText', () {
    test('one line, no bidi or invisible characters, capped', () {
      expect(
        sanitizeDisplayText(
          'Bo\n\n\u202Eevil\u200B',
          maxChars: 30,
          fallback: 'Someone',
        ),
        'Bo evil',
      );
      expect(
        sanitizeDisplayText('a' * 50, maxChars: 30, fallback: 'x').length,
        30,
      );
      expect(
        sanitizeDisplayText('\u200B\u200B', maxChars: 30, fallback: 'Someone'),
        'Someone',
      );
    });
  });

  test('invisible-only body is empty', () {
    expect(sanitizeMessage('\u200B\u2060\uFEFF'), isNull);
  });
}
