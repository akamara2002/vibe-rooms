import 'dart:async';
import 'dart:io' show SocketException;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' show ClientException;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utc.dart';
import '../domain/room_state.dart';
import '../domain/room_state_repository.dart';

/// Topic of the playback row's own channel. It is separate from the presence
/// (`room:<id>`) and members (`room-members:<id>`) channels because a channel
/// can be subscribed only once.
String roomStateTopic(String roomId) => 'room_state:$roomId';

RoomStateFailure mapRoomStateError(Object error) {
  if (error is RoomStateFailure) return error;
  if (error is SocketException ||
      error is ClientException ||
      error is TimeoutException ||
      error is AuthRetryableFetchException) {
    return const RoomStateFailure(RoomStateFailureKind.network);
  }
  if (error is PostgrestException &&
      (error.code == '42501' || error.code == 'PGRST301')) {
    return const RoomStateFailure(RoomStateFailureKind.notAllowed);
  }
  // Only the type and code, never the message or any id.
  final code = error is PostgrestException ? ' code=${error.code}' : '';
  debugPrint('Unmapped room state error (${error.runtimeType})$code');
  return const RoomStateFailure(RoomStateFailureKind.unknown);
}

/// The raw database and Realtime access under [SupabaseRoomStateRepository].
/// It exists so the repository's rules (stale events, rejoin, zero-row
/// updates) can be tested without a network.
abstract class RoomStateSource {
  Future<Map<String, dynamic>?> fetch(String roomId);

  /// The rows the update changed (empty when row level security blocked it).
  Future<List<dynamic>> update(String roomId, Map<String, dynamic> json);

  /// [onRow] gets every UPDATE; [onStatus] gets true on every (re)join and
  /// false when the channel has trouble.
  RoomStateSubscription subscribe(
    String roomId, {
    required void Function(Map<String, dynamic> row) onRow,
    required void Function(bool joined) onStatus,
  });
}

abstract class RoomStateSubscription {
  Future<void> close();
}

class SupabaseRoomStateSource implements RoomStateSource {
  SupabaseRoomStateSource(this._client);

  final SupabaseClient _client;

  @override
  Future<Map<String, dynamic>?> fetch(String roomId) =>
      _client.from('room_state').select().eq('room_id', roomId).maybeSingle();

  @override
  Future<List<dynamic>> update(String roomId, Map<String, dynamic> json) =>
      // `.select()` returns the changed rows: row level security turns a
      // non-host write into zero rows, not an error.
      _client
          .from('room_state')
          .update(json)
          .eq('room_id', roomId)
          .select('room_id');

  @override
  RoomStateSubscription subscribe(
    String roomId, {
    required void Function(Map<String, dynamic> row) onRow,
    required void Function(bool joined) onStatus,
  }) {
    final ch = _client.channel(roomStateTopic(roomId));
    ch
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'room_state',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'room_id',
            value: roomId,
          ),
          callback: (payload) => onRow(payload.newRecord),
        )
        .subscribe((status, error) {
          if (status == RealtimeSubscribeStatus.subscribed) {
            onStatus(true);
          } else if (status == RealtimeSubscribeStatus.channelError ||
              status == RealtimeSubscribeStatus.timedOut ||
              status == RealtimeSubscribeStatus.closed) {
            debugPrint('Room state channel ${status.name}');
            onStatus(false);
          }
        });
    return _SupabaseSubscription(_client, ch);
  }
}

class _SupabaseSubscription implements RoomStateSubscription {
  _SupabaseSubscription(this._client, this._channel);

  final SupabaseClient _client;
  final RealtimeChannel _channel;

  @override
  Future<void> close() async {
    try {
      await _client.removeChannel(_channel);
    } catch (error) {
      debugPrint('Removing room state channel failed (${error.runtimeType})');
    }
  }
}

class SupabaseRoomStateRepository implements RoomStateRepository {
  SupabaseRoomStateRepository(SupabaseClient client)
    : this.withSource(SupabaseRoomStateSource(client));

  SupabaseRoomStateRepository.withSource(this._source);

  final RoomStateSource _source;

  @override
  Future<RoomState?> get(String roomId) async {
    try {
      final row = await _source.fetch(roomId);
      return row == null ? null : RoomState.fromJson(row);
    } catch (error) {
      throw mapRoomStateError(error);
    }
  }

  @override
  Stream<RoomState> watch(String roomId) {
    late final StreamController<RoomState> controller;
    RoomStateSubscription? subscription;
    RoomState? last;
    var closed = false;
    var loading = false;
    var loadAgain = false;

    // Stale-event rule: an event older than the newest `updated_at` seen is
    // dropped. Equal is accepted (a foreign-key update changes the row without
    // moving `updated_at`), but an identical row is not emitted twice.
    void offer(RoomState next) {
      if (closed) return;
      final newest = last;
      if (newest != null) {
        if (next.updatedAt.isBefore(newest.updatedAt)) return;
        if (next == newest) return;
      }
      last = next;
      controller.add(next);
    }

    Future<void> load() async {
      if (closed) return;
      if (loading) {
        loadAgain = true;
        return;
      }
      loading = true;
      try {
        final row = await get(roomId);
        if (row != null) offer(row);
      } catch (error) {
        if (!closed) controller.addError(mapRoomStateError(error));
      } finally {
        loading = false;
      }
      if (loadAgain && !closed) {
        loadAgain = false;
        unawaited(load());
      }
    }

    controller = StreamController<RoomState>(
      onListen: () {
        unawaited(load()); // do not wait for the socket
        subscription = _source.subscribe(
          roomId,
          onRow: (row) {
            try {
              offer(RoomState.fromJson(row));
            } catch (_) {
              // A malformed event: read the row again instead.
              unawaited(load());
            }
          },
          onStatus: (joined) {
            if (closed) return;
            if (joined) {
              // Runs on every (re)join. Events missed while offline are not
              // replayed, so read the row again.
              unawaited(load());
            } else {
              controller.addError(
                const RoomStateFailure(RoomStateFailureKind.network),
              );
            }
          },
        );
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
  Future<void> hostUpdate(String roomId, RoomStateUpdate update) async {
    try {
      final rows = await _source.update(roomId, update.toJson());
      if (rows.isEmpty) {
        throw const RoomStateFailure(RoomStateFailureKind.notAllowed);
      }
    } catch (error) {
      throw mapRoomStateError(error);
    }
  }
}

class SupabaseServerTimeSource implements ServerTimeSource {
  SupabaseServerTimeSource(this._client);

  final SupabaseClient _client;

  @override
  Future<DateTime> serverNow() async {
    final value = await _client.rpc('server_now');
    return parseUtc(value as String);
  }
}
