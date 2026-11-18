import 'package:flutter_test/flutter_test.dart' hide EnginePhase;
import 'package:vibe_rooms/features/queue/domain/queue_failure.dart';
import 'package:vibe_rooms/features/queue/domain/queue_item.dart';
import 'package:vibe_rooms/features/queue/domain/queue_limits.dart';

import '../fakes/fakes.dart';

void main() {
  final track = fakeTrack(id: 'new-track');

  test('an empty queue accepts a track', () {
    expect(checkCanAdd(upcoming: [], track: track, userId: 'me'), isNull);
  });

  test('a track that is already upcoming is a duplicate', () {
    final failure = checkCanAdd(
      upcoming: [fakeQueueItem(id: 'a', trackId: 'new-track')],
      track: track,
      userId: 'me',
    );
    expect(failure!.kind, QueueFailureKind.duplicate);
    expect(failure.message, 'Already in the queue');
  });

  test('the room holds at most $maxUpcomingPerRoom', () {
    final full = [
      for (var i = 0; i < maxUpcomingPerRoom; i++)
        fakeQueueItem(id: 'q$i', addedBy: 'other$i', sortKey: i),
    ];
    expect(
      checkCanAdd(upcoming: full, track: track, userId: 'me')!.kind,
      QueueFailureKind.full,
    );
    expect(
      checkCanAdd(
        upcoming: full.take(maxUpcomingPerRoom - 1).toList(),
        track: track,
        userId: 'me',
      ),
      isNull,
    );
  });

  test('a person may have at most $maxUpcomingPerUser upcoming', () {
    List<QueueItem> mine(int n) => [
      for (var i = 0; i < n; i++) fakeQueueItem(id: 'm$i', addedBy: 'me'),
    ];
    final ten = mine(maxUpcomingPerUser);
    expect(
      checkCanAdd(upcoming: ten, track: track, userId: 'me')!.message,
      contains('$maxUpcomingPerUser songs queued'),
    );
    // Other people are not affected by my limit.
    expect(
      checkCanAdd(upcoming: ten, track: track, userId: 'someone-else'),
      isNull,
    );
    expect(
      checkCanAdd(
        upcoming: mine(maxUpcomingPerUser - 1),
        track: track,
        userId: 'me',
      ),
      isNull,
    );
  });

  test('the duplicate check wins over the limits', () {
    final full = [
      for (var i = 0; i < maxUpcomingPerRoom; i++)
        fakeQueueItem(id: 'q$i', trackId: i == 0 ? 'new-track' : null),
    ];
    expect(
      checkCanAdd(upcoming: full, track: track, userId: 'me')!.kind,
      QueueFailureKind.duplicate,
    );
  });

  group('visibleUpcoming', () {
    final items = [fakeQueueItem(id: 'a'), fakeQueueItem(id: 'b')];
    test('hides the item that is playing right now', () {
      expect(visibleUpcoming(items, 'a').map((i) => i.id), ['b']);
    });
    test('keeps everything when nothing from the queue is playing', () {
      expect(visibleUpcoming(items, null), items);
    });
    test('an id that is not in the list changes nothing', () {
      expect(visibleUpcoming(items, 'zzz'), items);
    });
  });

  test('a playing-but-unmarked item does not count toward the room limit', () {
    final items = [
      for (var i = 0; i < maxUpcomingPerRoom; i++)
        fakeQueueItem(id: 'i$i', addedBy: 'u$i', sortKey: i),
    ];
    // Fifty rows, one of them playing right now: 49 are upcoming.
    final visible = visibleUpcoming(items, 'i0');
    expect(checkCanAdd(upcoming: items, track: track, userId: 'me'), isNotNull);
    expect(checkCanAdd(upcoming: visible, track: track, userId: 'me'), isNull);
  });

  test('when both limits are hit, the room limit is reported', () {
    final items = [
      for (var i = 0; i < maxUpcomingPerRoom; i++)
        fakeQueueItem(id: 'i$i', addedBy: 'me', sortKey: i),
    ];
    expect(
      checkCanAdd(upcoming: items, track: track, userId: 'me')!.message,
      contains('$maxUpcomingPerRoom songs'),
    );
  });
}
