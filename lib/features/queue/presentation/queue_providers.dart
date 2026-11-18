import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase_client.dart';
import '../../player/presentation/sync_controller.dart';
import '../../player/presentation/sync_providers.dart';
import '../data/supabase_queue_repository.dart';
import '../data/unconfigured_queue_repository.dart';
import '../domain/queue_item.dart';
import '../domain/queue_limits.dart';
import '../domain/queue_repository.dart';
import 'queue_controller.dart';

final queueRepositoryProvider = Provider<QueueRepository>((ref) {
  if (!ref.watch(supabaseReadyProvider)) {
    return const UnconfiguredQueueRepository();
  }
  return SupabaseQueueRepository(Supabase.instance.client);
});

/// The room's upcoming items, live. Dropping the last listener releases the
/// realtime channel.
final upcomingItemsProvider = StreamProvider.autoDispose
    .family<List<QueueItem>, String>(
      (ref, roomId) => ref.watch(queueRepositoryProvider).watchUpcoming(roomId),
      retry: (_, _) => null,
    );

/// The queue as people see it: [upcomingItemsProvider] without the item that
/// is playing right now (see [visibleUpcoming]).
final visibleUpcomingProvider = Provider.autoDispose
    .family<AsyncValue<List<QueueItem>>, SyncArgs>((ref, args) {
      final nowPlaying = ref.watch(
        syncControllerProvider(args).select((s) => s.room?.queueItemId),
      );
      return ref
          .watch(upcomingItemsProvider(args.roomId))
          .whenData((items) => visibleUpcoming(items, nowPlaying));
    });

/// One per room visit: add, remove and (host) advance.
final queueControllerProvider = NotifierProvider.autoDispose
    .family<QueueController, QueueState, SyncArgs>(QueueController.new);
