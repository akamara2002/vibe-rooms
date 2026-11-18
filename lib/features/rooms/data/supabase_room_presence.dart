import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../auth/domain/profile.dart';
import '../domain/room_presence.dart';
import 'room_channel.dart';

class SupabaseRoomPresence implements RoomPresence {
  SupabaseRoomPresence(this._client);

  final SupabaseClient _client;

  @override
  Stream<Set<String>> watchOnlineUserIds(String roomId, Profile me) {
    late final StreamController<Set<String>> controller;
    RealtimeChannel? channel;
    var closed = false;

    controller = StreamController<Set<String>>(
      onListen: () {
        final ch = RoomChannel.presence(_client, roomId, me.id);
        channel = ch;
        ch
            .onPresenceSync((_) {
              if (closed) return;
              controller.add(ch.presenceState().map((s) => s.key).toSet());
            })
            .subscribe((status, error) {
              if (closed) return;
              if (status == RealtimeSubscribeStatus.subscribed) {
                // The status callback runs on every (re)join, so presence is
                // announced again after a reconnect.
                unawaited(
                  ch
                      .track({
                        'user_id': me.id,
                        'display_name': me.displayName,
                        'avatar_emoji': me.avatarEmoji,
                      })
                      .then<void>(
                        (_) {},
                        onError: (Object e) {
                          debugPrint(
                            'Presence track failed (${e.runtimeType})',
                          );
                        },
                      ),
                );
              } else if (status == RealtimeSubscribeStatus.channelError ||
                  status == RealtimeSubscribeStatus.timedOut) {
                debugPrint('Room presence channel ${status.name}');
              }
            });
      },
      onCancel: () async {
        closed = true;
        final ch = channel;
        channel = null;
        if (ch == null) return;
        try {
          await ch.untrack();
        } catch (_) {
          // The channel may already be closed; leaving is what matters.
        }
        try {
          await _client.removeChannel(ch);
        } catch (error) {
          debugPrint('Removing presence channel failed (${error.runtimeType})');
        }
      },
    );
    return controller.stream;
  }
}
