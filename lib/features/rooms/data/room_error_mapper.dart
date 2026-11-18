import 'dart:io' show SocketException;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' show ClientException;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/room_failure.dart';

/// Translates a backend error into a [RoomFailure].
///
/// Only the error type and code are logged, never the message (it can contain
/// request data) or any room code or user id.
RoomFailure mapRoomError(Object error) {
  if (error is RoomFailure) return error;

  if (error is PostgrestException) {
    final message = error.message.toLowerCase();
    final code = error.code;
    if (message.contains('room_not_found') || code == 'P0002') {
      return const RoomFailure(RoomFailureKind.roomNotFound);
    }
    if (message.contains('invalid_name')) {
      return const RoomFailure(RoomFailureKind.invalidName);
    }
    if (message.contains('not_authenticated') || code == '28000') {
      return const RoomFailure(RoomFailureKind.notAuthenticated);
    }
    if (code == 'PGRST301' || code == 'PGRST303') {
      return const RoomFailure(RoomFailureKind.notAuthenticated);
    }
  }

  if (error is SocketException ||
      error is ClientException ||
      error is AuthRetryableFetchException) {
    return const RoomFailure(RoomFailureKind.network);
  }

  final code = error is PostgrestException ? ' code=${error.code}' : '';
  debugPrint('Unmapped room error (${error.runtimeType})$code');
  return const RoomFailure(RoomFailureKind.unknown);
}
