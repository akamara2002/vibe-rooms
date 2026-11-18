import '../../player/domain/track.dart';
import '../domain/queue_failure.dart';
import '../domain/queue_item.dart';
import '../domain/queue_repository.dart';

/// Used when Supabase is not configured: an empty queue that cannot change.
class UnconfiguredQueueRepository implements QueueRepository {
  const UnconfiguredQueueRepository();

  static const _failure = QueueFailure(QueueFailureKind.unknown);

  @override
  Future<List<QueueItem>> upcoming(String roomId) async => const [];

  @override
  Stream<List<QueueItem>> watchUpcoming(String roomId) =>
      Stream.value(const <QueueItem>[]);

  @override
  Future<QueueItem> add(String roomId, Track track) => Future.error(_failure);

  @override
  Future<void> remove(String itemId) => Future.error(_failure);

  @override
  Future<void> markPlayed(String itemId, DateTime? at) =>
      Future.error(_failure);
}
