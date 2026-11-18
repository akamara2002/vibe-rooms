import 'dart:async';
import 'dart:io' show SocketException;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' show ClientException;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../player/domain/track.dart';
import '../domain/queue_failure.dart';
import '../domain/queue_item.dart';
import '../domain/queue_repository.dart';

/// The queue has its own channel topic (a channel can be subscribed once, and
/// presence, members and room state each have theirs).
String queueTopic(String roomId) => 'queue:$roomId';

/// Upper bound of one reload (the room limit is 50; the rest is headroom).
const maxFetchedItems = 200;

/// A request that hangs (a half-open mobile socket) must fail, not freeze the
/// queue: the reload loop and the advance both wait on these calls.
const requestTimeout = Duration(seconds: 10);

const _select = '*, profiles(display_name, avatar_emoji)';

QueueFailure mapQueueError(Object error) {
  if (error is QueueFailure) return error;
  if (error is SocketException ||
      error is ClientException ||
      error is TimeoutException ||
      error is AuthRetryableFetchException) {
    return const QueueFailure(QueueFailureKind.network);
  }
  if (error is PostgrestException &&
      (error.code == '42501' || error.code == 'PGRST301')) {
    return const QueueFailure(QueueFailureKind.notAllowed);
  }
  // Only the type and code: messages can carry ids and request data.
  final code = error is PostgrestException ? ' code=${error.code}' : '';
  debugPrint('Unmapped queue error (${error.runtimeType})$code');
  return const QueueFailure(QueueFailureKind.unknown);
}

/// Raw database and Realtime access under [SupabaseQueueRepository], so its
/// rules can be tested without a network.
abstract class QueueSource {
  Future<List<Map<String, dynamic>>> fetchUpcoming(String roomId);

  Future<Map<String, dynamic>> insert(Map<String, dynamic> json);

  /// The rows that were deleted (empty when row level security blocked it).
  Future<List<dynamic>> delete(String itemId);

  /// The rows that were changed (empty when row level security blocked it).
  Future<List<dynamic>> setPlayedAt(String itemId, String? iso);

  /// [onChange] fires for every change in the room's queue; [onStatus] gets
  /// true on every (re)join and false on channel trouble.
  QueueSubscription subscribe(
    String roomId, {
    required void Function() onChange,
    required void Function(bool joined) onStatus,
  });
}

abstract class QueueSubscription {
  Future<void> close();
}

class SupabaseQueueSource implements QueueSource {
  SupabaseQueueSource(this._client);

  final SupabaseClient _client;

  @override
  Future<List<Map<String, dynamic>>> fetchUpcoming(String roomId) async {
    final rows = await _client
        .from('queue_items')
        .select(_select)
        .eq('room_id', roomId)
        .isFilter('played_at', null)
        .order('sort_key', ascending: true)
        // The room limit is client-side, so a modified client could exceed it:
        // never fetch an unbounded list.
        .limit(maxFetchedItems);
    return List<Map<String, dynamic>>.from(rows);
  }

  @override
  Future<Map<String, dynamic>> insert(Map<String, dynamic> json) =>
      _client.from('queue_items').insert(json).select(_select).single();

  @override
  Future<List<dynamic>> delete(String itemId) =>
      _client.from('queue_items').delete().eq('id', itemId).select('id');

  @override
  Future<List<dynamic>> setPlayedAt(String itemId, String? iso) => _client
      .from('queue_items')
      .update({'played_at': iso})
      .eq('id', itemId)
      .select('id');

  @override
  QueueSubscription subscribe(
    String roomId, {
    required void Function() onChange,
    required void Function(bool joined) onStatus,
  }) {
    final ch = _client.channel(queueTopic(roomId));
    ch
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'queue_items',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'room_id',
            value: roomId,
          ),
          callback: (_) => onChange(),
        )
        .subscribe((status, error) {
          if (status == RealtimeSubscribeStatus.subscribed) {
            onStatus(true);
          } else if (status == RealtimeSubscribeStatus.channelError ||
              status == RealtimeSubscribeStatus.timedOut ||
              status == RealtimeSubscribeStatus.closed) {
            debugPrint('Queue channel ${status.name}');
            onStatus(false);
          }
        });
    return _SupabaseQueueSubscription(_client, ch);
  }
}

class _SupabaseQueueSubscription implements QueueSubscription {
  _SupabaseQueueSubscription(this._client, this._channel);

  final SupabaseClient _client;
  final RealtimeChannel _channel;

  @override
  Future<void> close() async {
    try {
      await _client.removeChannel(_channel);
    } catch (error) {
      debugPrint('Removing queue channel failed (${error.runtimeType})');
    }
  }
}

class SupabaseQueueRepository implements QueueRepository {
  SupabaseQueueRepository(SupabaseClient client)
    : this.withSource(
        SupabaseQueueSource(client),
        userId: () => client.auth.currentUser?.id,
      );

  SupabaseQueueRepository.withSource(
    this._source, {
    required this.userId,
    this.debounce = const Duration(milliseconds: 250),
  });

  final QueueSource _source;

  /// My user id, or null when signed out.
  final String? Function() userId;

  /// Bursts of changes (an add plus a mark) collapse into one reload.
  final Duration debounce;

  @override
  Future<List<QueueItem>> upcoming(String roomId) async {
    try {
      final rows = await _source.fetchUpcoming(roomId).timeout(requestTimeout);
      final items = <QueueItem>[];
      for (final row in rows) {
        try {
          items.add(QueueItem.fromJson(row));
        } catch (error) {
          // One bad row must not make the whole queue unreadable.
          debugPrint('Skipped an unreadable queue row (${error.runtimeType})');
        }
      }
      return items;
    } catch (error) {
      throw mapQueueError(error);
    }
  }

  @override
  Stream<List<QueueItem>> watchUpcoming(String roomId) {
    late final StreamController<List<QueueItem>> controller;
    QueueSubscription? subscription;
    Timer? timer;
    var closed = false;
    var loading = false;
    var loadAgain = false;

    // Reloading the whole (small) list on any event keeps the order right and
    // needs no merging of inserts, updates and id-only deletes. Only one load
    // runs at a time, so an older answer can never overwrite a newer one.
    Future<void> load() async {
      if (closed) return;
      if (loading) {
        loadAgain = true;
        return;
      }
      loading = true;
      try {
        final items = await upcoming(roomId);
        if (!closed) controller.add(items);
      } catch (error) {
        if (!closed) controller.addError(error);
      } finally {
        loading = false;
      }
      if (loadAgain && !closed) {
        loadAgain = false;
        unawaited(load());
      }
    }

    void scheduleLoad() {
      timer?.cancel();
      timer = Timer(debounce, load);
    }

    controller = StreamController<List<QueueItem>>(
      onListen: () {
        unawaited(load()); // do not wait for the socket
        try {
          subscription = _source.subscribe(
            roomId,
            onChange: () {
              if (!closed) scheduleLoad();
            },
            onStatus: (joined) {
              if (closed) return;
              if (joined) {
                // Runs on every (re)join: missed events are not replayed.
                scheduleLoad();
              } else {
                controller.addError(
                  const QueueFailure(QueueFailureKind.network),
                );
              }
            },
          );
        } catch (error) {
          controller.addError(mapQueueError(error));
        }
      },
      onCancel: () async {
        closed = true;
        timer?.cancel();
        final sub = subscription;
        subscription = null;
        await sub?.close();
      },
    );
    return controller.stream;
  }

  @override
  Future<QueueItem> add(String roomId, Track track) async {
    final me = userId();
    if (me == null) throw const QueueFailure(QueueFailureKind.notAllowed);
    try {
      final row = await _source
          .insert(track.toQueueInsertJson(roomId, me))
          .timeout(requestTimeout);
      return QueueItem.fromJson(row);
    } catch (error) {
      throw mapQueueError(error);
    }
  }

  @override
  Future<void> remove(String itemId) async {
    try {
      final rows = await _source.delete(itemId).timeout(requestTimeout);
      if (rows.isEmpty) {
        // Row level security and "already gone" (the host and the adder both
        // removed it) look the same here: say the neutral thing.
        throw const QueueFailure(
          QueueFailureKind.notAllowed,
          'That song is no longer in the queue.',
        );
      }
    } catch (error) {
      throw mapQueueError(error);
    }
  }

  @override
  Future<void> markPlayed(String itemId, DateTime? at) async {
    try {
      final rows = await _source
          .setPlayedAt(itemId, at?.toUtc().toIso8601String())
          .timeout(requestTimeout);
      if (rows.isEmpty) {
        throw const QueueFailure(QueueFailureKind.notAllowed);
      }
    } catch (error) {
      throw mapQueueError(error);
    }
  }
}
