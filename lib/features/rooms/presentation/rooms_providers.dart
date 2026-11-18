import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase_client.dart';
import '../../auth/presentation/auth_providers.dart';
import '../data/supabase_room_presence.dart';
import '../data/supabase_room_repository.dart';
import '../data/unconfigured_room_repositories.dart';
import '../domain/room.dart';
import '../domain/room_member.dart';
import '../domain/room_presence.dart';
import '../domain/room_repository.dart';
import '../domain/room_summary.dart';

final roomRepositoryProvider = Provider<RoomRepository>((ref) {
  if (!ref.watch(supabaseReadyProvider)) {
    return const UnconfiguredRoomRepository();
  }
  return SupabaseRoomRepository(Supabase.instance.client);
});

final roomPresenceProvider = Provider<RoomPresence>((ref) {
  if (!ref.watch(supabaseReadyProvider)) {
    return const UnconfiguredRoomPresence();
  }
  return SupabaseRoomPresence(Supabase.instance.client);
});

/// Open rooms I belong to. Invalidate after create, join, leave and close.
final myRoomsProvider = FutureProvider.autoDispose<List<RoomSummary>>((ref) {
  ref.watch(signedInProvider);
  return ref.watch(roomRepositoryProvider).myRooms();
}, retry: (_, _) => null);

/// The members of a room, live. Dropping the last listener releases the
/// realtime channel.
final roomMembersProvider = StreamProvider.autoDispose
    .family<List<RoomMember>, String>(
      (ref, roomId) => ref.watch(roomRepositoryProvider).watchMembers(roomId),
      retry: (_, _) => null,
    );

/// A room, or null if it does not exist or I am not a member. Re-read whenever
/// the member list changes: that is how members notice the host closed it.
final roomProvider = FutureProvider.autoDispose.family<Room?, String>((
  ref,
  roomId,
) {
  ref.watch(roomMembersProvider(roomId));
  return ref.watch(roomRepositoryProvider).getRoom(roomId);
}, retry: (_, _) => null);

/// User ids that are online in the room. The profile is read once, so editing
/// it does not tear down and rejoin the channel.
final onlineUsersProvider = StreamProvider.autoDispose
    .family<Set<String>, String>((ref, roomId) async* {
      final me = await ref.read(myProfileProvider.future);
      yield* ref.watch(roomPresenceProvider).watchOnlineUserIds(roomId, me);
    }, retry: (_, _) => null);
