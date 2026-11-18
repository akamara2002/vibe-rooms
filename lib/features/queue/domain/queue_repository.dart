import '../../player/domain/track.dart';
import 'queue_item.dart';

abstract class QueueRepository {
  /// Items with `played_at` null, in `sort_key` order, with who added them.
  Future<List<QueueItem>> upcoming(String roomId);

  /// [upcoming], then again after every change in the room's queue and after
  /// every channel rejoin (missed events are not replayed). Reports
  /// connection trouble as a stream error and stays open.
  Stream<List<QueueItem>> watchUpcoming(String roomId);

  /// Adds [track] as me. Limits are checked by the caller, not here.
  Future<QueueItem> add(String roomId, Track track);

  /// Throws [QueueFailure] (notAllowed) when no row was deleted: only the
  /// host and the adder may delete.
  Future<void> remove(String itemId);

  /// Host only. [at] null un-marks. Throws [QueueFailure] (notAllowed) when
  /// no row changed.
  Future<void> markPlayed(String itemId, DateTime? at);
}
