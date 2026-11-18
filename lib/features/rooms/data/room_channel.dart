import 'package:supabase_flutter/supabase_flutter.dart';

/// Naming and configuration for the Realtime channels of a room.
///
/// Conventions (read before adding a feature that uses Realtime):
///  * `room:<roomId>` is the room's presence/broadcast channel. Presence uses
///    the user id as its key. Later features (playback sync, reactions) add
///    their listeners to the channel built here, BEFORE it is subscribed.
///  * A channel instance can be subscribed only once, and `channel()` does not
///    de-duplicate by topic, so never create two channels for one topic.
///  * Postgres Changes use their own topic (see [membersTopic], and
///    `room_state:<roomId>` for the playback row) so they never collide with
///    the presence channel.
///  * The channel is public (no RLS on Realtime messages), so it must carry
///    nothing private. Release it with `removeChannel` when done.
class RoomChannel {
  const RoomChannel._();

  static String topic(String roomId) => 'room:$roomId';

  static String membersTopic(String roomId) => 'room-members:$roomId';

  /// The presence channel for [roomId], keyed by [userId]. Not yet subscribed.
  static RealtimeChannel presence(
    SupabaseClient client,
    String roomId,
    String userId,
  ) {
    return client.channel(
      topic(roomId),
      opts: RealtimeChannelConfig(key: userId),
    );
  }
}
