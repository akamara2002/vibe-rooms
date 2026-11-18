import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/room.dart';
import '../domain/room_failure.dart';
import '../domain/room_member.dart';
import '../domain/room_repository.dart';
import '../domain/room_summary.dart';
import 'room_channel.dart';
import 'room_error_mapper.dart';

class SupabaseRoomRepository implements RoomRepository {
  SupabaseRoomRepository(this._client);

  final SupabaseClient _client;

  String get _uid {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw const RoomFailure(RoomFailureKind.notAuthenticated);
    return id;
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is List && value.isNotEmpty) {
      return value.first as Map<String, dynamic>;
    }
    return value as Map<String, dynamic>;
  }

  @override
  Future<Room> createRoom(String name) async {
    try {
      final result = await _client.rpc(
        'create_room',
        params: {'p_name': name.trim()},
      );
      return Room.fromJson(_asMap(result));
    } catch (error) {
      throw mapRoomError(error);
    }
  }

  @override
  Future<Room> joinRoom(String code) async {
    try {
      final result = await _client.rpc('join_room', params: {'p_code': code});
      return Room.fromJson(_asMap(result));
    } catch (error) {
      throw mapRoomError(error);
    }
  }

  @override
  Future<List<RoomSummary>> myRooms() async {
    try {
      // Row level security already limits `rooms` to rooms I belong to.
      final rows = await _client
          .from('rooms')
          .select('*, room_members(count)')
          .isFilter('closed_at', null)
          .order('created_at', ascending: false);
      return rows.map(RoomSummary.fromJson).toList();
    } catch (error) {
      throw mapRoomError(error);
    }
  }

  @override
  Future<Room?> getRoom(String id) async {
    try {
      final row = await _client
          .from('rooms')
          .select()
          .eq('id', id)
          .maybeSingle();
      return row == null ? null : Room.fromJson(row);
    } on PostgrestException catch (error) {
      // 22P02: the id is not a uuid (a mistyped link). That is just "not found".
      if (error.code == '22P02') return null;
      throw mapRoomError(error);
    } catch (error) {
      throw mapRoomError(error);
    }
  }

  Future<List<RoomMember>> _loadMembers(String roomId) async {
    final rows = await _client
        .from('room_members')
        .select(
          'room_id, user_id, joined_at, profiles(display_name, avatar_emoji), rooms(host_id)',
        )
        .eq('room_id', roomId)
        .order('joined_at');
    return rows.map(RoomMember.fromRow).toList();
  }

  @override
  Stream<List<RoomMember>> watchMembers(String roomId) {
    late final StreamController<List<RoomMember>> controller;
    RealtimeChannel? channel;
    Timer? debounce;
    var closed = false;
    var loading = false;
    var loadAgain = false;

    Future<void> load() async {
      if (closed) return;
      if (loading) {
        loadAgain = true;
        return;
      }
      loading = true;
      try {
        final members = await _loadMembers(roomId);
        if (!closed) controller.add(members);
      } catch (error) {
        if (!closed) controller.addError(mapRoomError(error));
      } finally {
        loading = false;
      }
      if (loadAgain && !closed) {
        loadAgain = false;
        unawaited(load());
      }
    }

    // Bursts of changes (a join plus a profile edit) collapse into one reload.
    void scheduleLoad() {
      debounce?.cancel();
      debounce = Timer(const Duration(milliseconds: 250), load);
    }

    controller = StreamController<List<RoomMember>>(
      onListen: () {
        unawaited(load()); // do not wait for the socket to show the list
        final ch = _client.channel(RoomChannel.membersTopic(roomId));
        channel = ch;
        ch
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'room_members',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'room_id',
                value: roomId,
              ),
              callback: (_) => scheduleLoad(),
            )
            .subscribe((status, error) {
              if (closed) return;
              if (status == RealtimeSubscribeStatus.subscribed) {
                // Fires on every (re)join: changes missed while offline are
                // not replayed, so reload.
                scheduleLoad();
              } else if (status == RealtimeSubscribeStatus.channelError ||
                  status == RealtimeSubscribeStatus.timedOut) {
                debugPrint('Room members channel ${status.name}');
              }
            });
      },
      onCancel: () async {
        closed = true;
        debounce?.cancel();
        final ch = channel;
        channel = null;
        if (ch != null) {
          try {
            await _client.removeChannel(ch);
          } catch (error) {
            debugPrint(
              'Removing members channel failed (${error.runtimeType})',
            );
          }
        }
      },
    );
    return controller.stream;
  }

  @override
  Future<void> leaveRoom(String roomId) async {
    final uid = _uid;
    try {
      // Succeeds with zero rows if I was already out of the room.
      await _client
          .from('room_members')
          .delete()
          .eq('room_id', roomId)
          .eq('user_id', uid);
    } catch (error) {
      throw mapRoomError(error);
    }
  }

  @override
  Future<void> closeRoom(String roomId) async {
    try {
      final updated = await _client
          .from('rooms')
          .update({'closed_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', roomId)
          .select('id');
      // Row level security turns "not the host" into zero updated rows, not an error.
      if (updated.isEmpty) throw const RoomFailure(RoomFailureKind.unknown);
    } catch (error) {
      throw mapRoomError(error);
    }
    await leaveRoom(roomId);
  }
}
