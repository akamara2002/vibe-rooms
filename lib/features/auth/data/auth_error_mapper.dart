import 'dart:io' show SocketException;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' show ClientException;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/auth_failure.dart';

/// Translates a backend error into an [AuthFailure].
///
/// Anything unrecognised becomes a generic failure; only its type and codes are
/// logged with [debugPrint], never the message, request data or URLs.
AuthFailure mapAuthError(Object error) {
  if (error is AuthFailure) return error;

  if (error is AuthException) {
    final code = error.code;
    final message = error.message.toLowerCase();

    if (error is AuthWeakPasswordException || code == 'weak_password') {
      return const AuthFailure(AuthFailureKind.weakPassword);
    }
    if (code == 'user_already_exists' ||
        code == 'email_exists' ||
        message.contains('already registered')) {
      return const AuthFailure(AuthFailureKind.userAlreadyExists);
    }
    if (code == 'invalid_credentials' ||
        message.contains('invalid login credentials')) {
      return const AuthFailure(AuthFailureKind.invalidCredentials);
    }
    if (code == 'over_request_rate_limit' ||
        code == 'over_email_send_rate_limit' ||
        code == 'over_sms_send_rate_limit' ||
        error.statusCode == '429') {
      return const AuthFailure(AuthFailureKind.rateLimit);
    }
    if (error is AuthRetryableFetchException) {
      return const AuthFailure(AuthFailureKind.network);
    }
  }

  if (error is SocketException || error is ClientException) {
    return const AuthFailure(AuthFailureKind.network);
  }

  // Log only the type and codes. The message can contain the user's email
  // address and HTTP client errors contain the request URL (the project URL).
  final details = error is AuthException
      ? ' status=${error.statusCode} code=${error.code}'
      : '';
  debugPrint('Unmapped auth error (${error.runtimeType})$details');
  return const AuthFailure(AuthFailureKind.unknown);
}
