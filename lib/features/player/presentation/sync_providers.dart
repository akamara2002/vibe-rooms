import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase_client.dart';
import '../data/supabase_room_state_repository.dart';
import '../data/unconfigured_room_state.dart';
import '../domain/room_state_repository.dart';
import 'sync_controller.dart';

final roomStateRepositoryProvider = Provider<RoomStateRepository>((ref) {
  if (!ref.watch(supabaseReadyProvider)) {
    return const UnconfiguredRoomStateRepository();
  }
  return SupabaseRoomStateRepository(Supabase.instance.client);
});

final serverTimeSourceProvider = Provider<ServerTimeSource>((ref) {
  if (!ref.watch(supabaseReadyProvider)) {
    return const UnconfiguredServerTimeSource();
  }
  return SupabaseServerTimeSource(Supabase.instance.client);
});

/// The device clock. Overridden in tests.
final localClockProvider = Provider<DateTime Function()>((_) => DateTime.now);

/// One per room visit: it owns the engine, the clock and the subscription, and
/// disposing it (leaving the room) stops all of them.
final syncControllerProvider = NotifierProvider.autoDispose
    .family<SyncController, SyncState, SyncArgs>(SyncController.new);

/// Whether the sync debug panel is shown without the five-tap unlock.
/// Overridable in tests.
final debugPanelDefaultProvider = Provider<bool>((_) => kDebugMode);
