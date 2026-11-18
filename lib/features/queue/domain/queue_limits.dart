import '../../player/domain/track.dart';
import 'queue_failure.dart';
import 'queue_item.dart';

/// Client-side only: the database does not enforce these, so a modified client
/// can bypass them.
const maxUpcomingPerRoom = 50;
const maxUpcomingPerUser = 10;

/// Why [track] may not be added by [userId] to [upcoming] (the queue as
/// everyone sees it), or null if it may.
QueueFailure? checkCanAdd({
  required List<QueueItem> upcoming,
  required Track track,
  required String userId,
}) {
  if (upcoming.any((item) => item.trackId == track.id)) {
    return const QueueFailure(QueueFailureKind.duplicate);
  }
  if (upcoming.length >= maxUpcomingPerRoom) {
    return const QueueFailure(
      QueueFailureKind.full,
      'The queue is full ($maxUpcomingPerRoom songs).',
    );
  }
  if (upcoming.where((item) => item.addedBy == userId).length >=
      maxUpcomingPerUser) {
    return const QueueFailure(
      QueueFailureKind.full,
      'You already have $maxUpcomingPerUser songs queued. '
      'Wait for one to play.',
    );
  }
  return null;
}

/// The queue as people see it: the item that is playing right now may still
/// be unmarked for a moment, and must not count as upcoming. Every reader
/// (list, limits, duplicates, Next) goes through this one function.
List<QueueItem> visibleUpcoming(
  List<QueueItem> items,
  String? nowPlayingItemId,
) => nowPlayingItemId == null
    ? items
    : items.where((item) => item.id != nowPlayingItemId).toList();

/// A queue item's length is written by the member who added it, and the host
/// uses it to decide when a song has ended. A row with `duration_ms` = 1 would
/// make the host skip it at once (and, in a batch, the whole queue); a huge
/// value would stall the room. The host skips items outside these bounds.
const minPlayableDurationMs = 5000;
const maxPlayableDurationMs = 6 * 60 * 60 * 1000;

bool isPlayableLength(QueueItem item) =>
    item.durationMs >= minPlayableDurationMs &&
    item.durationMs <= maxPlayableDurationMs;
