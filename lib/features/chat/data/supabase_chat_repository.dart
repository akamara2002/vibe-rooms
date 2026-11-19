import 'dart:async';
import 'dart:io' show SocketException;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' show ClientException;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/chat_failure.dart';
import '../domain/chat_message.dart';
import '../domain/chat_repository.dart';
import '../domain/message.dart';

/// Chat has its own channel topic (a channel can be subscribed once; presence,
/// members, room state, queue and reactions each have theirs).
String chatTopic(String roomId) => 'chat:$roomId';

const _select = '*, profiles(display_name, avatar_emoji)';

/// A request that hangs must fail, not freeze the chat.
const chatRequestTimeout = Duration(seconds: 10);

ChatFailure mapChatError(Object error) {
  if (error is ChatFailure) return error;
  if (error is SocketException ||
      error is ClientException ||
      error is TimeoutException ||
      error is AuthRetryableFetchException) {
    return const ChatFailure(ChatFailureKind.network);
  }
  if (error is PostgrestException) {
    if (error.code == '42501' || error.code == 'PGRST301') {
      return const ChatFailure(ChatFailureKind.notAllowed);
    }
    // The body check: 1 to 500 characters after trimming.
    if (error.code == '23514') {
      return const ChatFailure(ChatFailureKind.tooLong);
    }
  }
  // Only the type and code: messages can carry message bodies and ids.
  final code = error is PostgrestException ? ' code=${error.code}' : '';
  debugPrint('Unmapped chat error (${error.runtimeType})$code');
  return const ChatFailure(ChatFailureKind.unknown);
}

/// Raw database and Realtime access under [SupabaseChatRepository], so its
/// rules can be tested without a network.
abstract class ChatSource {
  Future<List<Map<String, dynamic>>> fetchRecent(String roomId, int limit);

  Future<Map<String, dynamic>?> insert(Map<String, dynamic> json);

  Future<Map<String, dynamic>?> fetchProfile(String userId);

  /// [onInsert] gets every INSERT; [onStatus] gets true on every (re)join and
  /// false on channel trouble.
  ChatSubscription subscribe(
    String roomId, {
    required void Function(Map<String, dynamic> row) onInsert,
    required void Function(bool joined) onStatus,
  });
}

abstract class ChatSubscription {
  Future<void> close();
}

class SupabaseChatSource implements ChatSource {
  SupabaseChatSource(this._client);

  final SupabaseClient _client;

  @override
  Future<List<Map<String, dynamic>>> fetchRecent(
    String roomId,
    int limit,
  ) async {
    final rows = await _client
        .from('messages')
        .select(_select)
        .eq('room_id', roomId)
        .order('created_at', ascending: false)
        .order('id', ascending: false)
        .limit(limit);
    return List<Map<String, dynamic>>.from(rows);
  }

  @override
  Future<Map<String, dynamic>?> insert(Map<String, dynamic> json) async {
    // `.select()` returns the inserted row (empty if row level security
    // blocked it).
    final rows = await _client.from('messages').insert(json).select(_select);
    return rows.isEmpty ? null : Map<String, dynamic>.from(rows.first);
  }

  @override
  Future<Map<String, dynamic>?> fetchProfile(String userId) => _client
      .from('profiles')
      .select('display_name, avatar_emoji')
      .eq('id', userId)
      .maybeSingle();

  @override
  ChatSubscription subscribe(
    String roomId, {
    required void Function(Map<String, dynamic> row) onInsert,
    required void Function(bool joined) onStatus,
  }) {
    final ch = _client.channel(chatTopic(roomId));
    ch
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'room_id',
            value: roomId,
          ),
          callback: (payload) => onInsert(payload.newRecord),
        )
        .subscribe((status, error) {
          if (status == RealtimeSubscribeStatus.subscribed) {
            onStatus(true);
          } else if (status == RealtimeSubscribeStatus.channelError ||
              status == RealtimeSubscribeStatus.timedOut ||
              status == RealtimeSubscribeStatus.closed) {
            debugPrint('Chat channel ${status.name}');
            onStatus(false);
          }
        });
    return _SupabaseChatSubscription(_client, ch);
  }
}

class _SupabaseChatSubscription implements ChatSubscription {
  _SupabaseChatSubscription(this._client, this._channel);

  final SupabaseClient _client;
  final RealtimeChannel _channel;

  @override
  Future<void> close() async {
    try {
      await _client.removeChannel(_channel);
    } catch (error) {
      debugPrint('Removing chat channel failed (${error.runtimeType})');
    }
  }
}

class SupabaseChatRepository implements ChatRepository {
  SupabaseChatRepository(SupabaseClient client)
    : this.withSource(
        SupabaseChatSource(client),
        userId: () => client.auth.currentUser?.id,
      );

  SupabaseChatRepository.withSource(this._source, {required this.userId});

  final ChatSource _source;

  /// My user id, or null when signed out.
  final String? Function() userId;

  @override
  Future<List<Message>> recent(String roomId, {int limit = 50}) async {
    try {
      final rows = await _source
          .fetchRecent(roomId, limit)
          .timeout(chatRequestTimeout);
      final messages = <Message>[];
      for (final row in rows) {
        try {
          messages.add(Message.fromJson(row));
        } catch (error) {
          // One bad row must not make the whole chat unreadable.
          debugPrint('Skipped an unreadable message (${error.runtimeType})');
        }
      }
      // Newest first from the database, oldest first for the caller.
      return messages.reversed.toList();
    } catch (error) {
      throw mapChatError(error);
    }
  }

  @override
  Stream<Message> watchNew(String roomId, {required void Function() onJoined}) {
    late final StreamController<Message> controller;
    ChatSubscription? subscription;
    var closed = false;

    controller = StreamController<Message>(
      onListen: () {
        try {
          subscription = _source.subscribe(
            roomId,
            onInsert: (row) {
              if (closed) return;
              try {
                controller.add(Message.fromJson(row));
              } catch (_) {
                // A malformed event: the next re-read picks the row up.
              }
            },
            onStatus: (joined) {
              if (closed) return;
              if (joined) {
                onJoined();
              } else {
                controller.addError(const ChatFailure(ChatFailureKind.network));
              }
            },
          );
        } catch (error) {
          controller.addError(mapChatError(error));
        }
      },
      onCancel: () async {
        closed = true;
        final sub = subscription;
        subscription = null;
        await sub?.close();
      },
    );
    return controller.stream;
  }

  @override
  Future<Message> send(String roomId, String body) async {
    final me = userId();
    if (me == null) throw const ChatFailure(ChatFailureKind.notAllowed);
    try {
      final row = await _source
          .insert({'room_id': roomId, 'user_id': me, 'body': body})
          .timeout(chatRequestTimeout);
      if (row == null) throw const ChatFailure(ChatFailureKind.notAllowed);
      return Message.fromJson(row);
    } catch (error) {
      throw mapChatError(error);
    }
  }

  @override
  Future<ChatSender?> sender(String userId) async {
    try {
      final row = await _source
          .fetchProfile(userId)
          .timeout(chatRequestTimeout);
      final name = row?['display_name'];
      if (name is! String) return null;
      final emoji = row?['avatar_emoji'];
      return ChatSender(name: name, emoji: emoji is String ? emoji : '🎧');
    } catch (_) {
      return null; // the caller shows "Someone"
    }
  }
}
