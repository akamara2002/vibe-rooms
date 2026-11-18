import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vibe_rooms/features/auth/data/auth_error_mapper.dart';
import 'package:vibe_rooms/features/auth/domain/auth_failure.dart';

void main() {
  AuthFailureKind kindOf(Object error) => mapAuthError(error).kind;

  test('maps the common auth errors to friendly kinds', () {
    expect(
      kindOf(
        const AuthApiException(
          'Invalid login credentials',
          statusCode: '400',
          code: 'invalid_credentials',
        ),
      ),
      AuthFailureKind.invalidCredentials,
    );
    expect(
      kindOf(
        const AuthApiException(
          'User already registered',
          statusCode: '422',
          code: 'user_already_exists',
        ),
      ),
      AuthFailureKind.userAlreadyExists,
    );
    expect(
      kindOf(
        const AuthApiException('User already registered', statusCode: '400'),
      ),
      AuthFailureKind.userAlreadyExists,
    );
    expect(
      kindOf(
        const AuthApiException(
          'Password is too weak',
          statusCode: '422',
          code: 'weak_password',
        ),
      ),
      AuthFailureKind.weakPassword,
    );
    expect(
      kindOf(
        const AuthApiException(
          'rate limit',
          statusCode: '429',
          code: 'over_request_rate_limit',
        ),
      ),
      AuthFailureKind.rateLimit,
    );
    expect(
      kindOf(const AuthApiException('slow down', statusCode: '429')),
      AuthFailureKind.rateLimit,
    );
  });

  test('maps network failures', () {
    expect(kindOf(AuthRetryableFetchException()), AuthFailureKind.network);
    expect(kindOf(const SocketException('offline')), AuthFailureKind.network);
  });

  test('everything else is a generic failure', () {
    expect(kindOf(StateError('boom')), AuthFailureKind.unknown);
    expect(
      kindOf(const AuthApiException('weird', statusCode: '500', code: 'x')),
      AuthFailureKind.unknown,
    );
  });

  test('passes an AuthFailure through unchanged', () {
    const failure = AuthFailure(AuthFailureKind.notSignedIn);
    expect(identical(mapAuthError(failure), failure), isTrue);
  });

  test('every failure has a short message that does not leak details', () {
    for (final kind in AuthFailureKind.values) {
      final message = AuthFailure(kind).message;
      expect(message, isNotEmpty);
      expect(message.toLowerCase(), isNot(contains('exception')));
    }
  });

  test('logs the error type and codes, never the message (email or URL)', () {
    final logged = <String>[];
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) =>
        logged.add(message ?? '');
    addTearDown(() => debugPrint = original);

    mapAuthError(
      const AuthApiException(
        'Email address "ana@example.com" is invalid https://abc.supabase.co/auth',
        statusCode: '400',
        code: 'email_address_invalid',
      ),
    );
    mapAuthError(StateError('https://abc.supabase.co leaked'));

    expect(logged, hasLength(2));
    for (final line in logged) {
      expect(line, isNot(contains('ana@example.com')));
      expect(line, isNot(contains('supabase.co')));
    }
    expect(logged.first, contains('email_address_invalid'));
  });
}
