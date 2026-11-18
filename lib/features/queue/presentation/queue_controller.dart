import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../../player/domain/room_state.dart';
import '../../player/domain/track.dart';
import '../../player/presentation/sync_controller.dart';
import '../../player/presentation/sync_providers.dart';
import '../domain/queue_failure.dart';
import '../domain/queue_item.dart';
import '../domain/queue_limits.dart';
import '../domain/queue_repository.dart';
import 'queue_providers.dart';

class QueueState {
  const QueueState({this.advancing = false, this.busyIds = const {}});

  /// A Next, Play now or automatic advance is running.
  final bool advancing;

  /// Items with a remove in flight.
  final Set<String> busyIds;

  QueueState copyWith({bool? advancing, Set<String>? busyIds}) => QueueState(
    advancing: advancing ?? this.advancing,
    busyIds: busyIds ?? this.busyIds,
  );
}

const notInQueueMessage = 'That song is no longer in the queue.';

/// Add, remove and advance, for one room.
///
/// Advance (the host's client only):
///
///   pick target ──► write room_state (starts the song; the COMMIT point)
///                        │ fails: nothing changed, nothing to undo
///                        ▼
///                   mark target played, and the item that just finished
///                   (best effort; a failure is healed by [_reconcile])
///
/// Writing the room first means a crash or a lost connection can leave an
/// item that is playing but not marked yet, never one that is marked but was
/// never played. Everyone hides the item `room_state.queue_item_id` points to,
/// so the gap is invisible, and the host marks it on the next change.
class QueueController extends Notifier<QueueState> {
  QueueController(this.args);

  final SyncArgs args;

  late QueueRepository _repo;
  late String? _myId;
  bool _disposed = false;

  /// Items this host started. They are never offered again by this client,
  /// even if marking them played keeps failing.
  final _started = <String>{};

  /// Items already marked played, or being marked right now. A failed mark
  /// is removed again so a later change retries it.
  final _reconciled = <String>{};

  SyncController get _sync => ref.read(syncControllerProvider(args).notifier);

  @override
  QueueState build() {
    _repo = ref.read(queueRepositoryProvider);
    _myId = ref.read(authRepositoryProvider).userId;
    if (args.isHost) {
      // Captured now: `ref` cannot be used inside onDispose.
      final sync = _sync;
      sync.onTrackEnded = _onTrackEnded;
      ref.onDispose(() {
        if (sync.onTrackEnded == _onTrackEnded) sync.onTrackEnded = null;
      });
      ref.listen(upcomingItemsProvider(args.roomId), (_, _) => _reconcile());
      ref.listen(
        syncControllerProvider(args).select((s) => s.room?.queueItemId),
        (_, _) => _reconcile(),
      );
    }
    ref.onDispose(() => _disposed = true);
    return const QueueState();
  }

  void _set(QueueState next) {
    if (!_disposed) state = next;
  }

  RoomState? get _room => ref.read(syncControllerProvider(args)).room;

  /// The queue as everyone sees it, read fresh (not from a stale stream value).
  Future<List<QueueItem>> _freshUpcoming() async => visibleUpcoming(
    await _repo.upcoming(args.roomId),
    _room?.queueItemId,
  ).where((item) => !_started.contains(item.id)).toList();

  /// The first item the host can play. Items with an implausible length are
  /// consumed (skipped) on the way, see [isPlayableLength].
  Future<QueueItem?> _firstPlayable(List<QueueItem> upcoming) async {
    for (final item in upcoming) {
      if (isPlayableLength(item)) return item;
      _started.add(item.id);
      await _mark(item.id);
    }
    return null;
  }

  // --------------------------------------------------------------- members

  /// Adds [track]. Returns why it did not happen, or null on success. The
  /// limits are checked against a fresh read, not the list on screen, so a
  /// song someone added a moment ago still counts.
  Future<QueueFailure?> add(Track track) async {
    final me = _myId;
    if (me == null) return const QueueFailure(QueueFailureKind.notAllowed);
    try {
      final failure = checkCanAdd(
        upcoming: await _freshUpcoming(),
        track: track,
        userId: me,
      );
      if (failure != null) return failure;
      await _repo.add(args.roomId, track);
      return null;
    } on QueueFailure catch (failure) {
      return failure;
    } catch (_) {
      return const QueueFailure(QueueFailureKind.unknown);
    }
  }

  /// The host and the adder may remove an item (the database says the same).
  bool canRemove(QueueItem item) => args.isHost || item.addedBy == _myId;

  Future<QueueFailure?> remove(QueueItem item) async {
    if (!canRemove(item)) {
      return const QueueFailure(QueueFailureKind.notAllowed);
    }
    if (state.busyIds.contains(item.id)) return null;
    _set(state.copyWith(busyIds: {...state.busyIds, item.id}));
    try {
      await _repo.remove(item.id);
      return null;
    } on QueueFailure catch (failure) {
      return failure;
    } catch (_) {
      return const QueueFailure(QueueFailureKind.unknown);
    } finally {
      _set(state.copyWith(busyIds: {...state.busyIds}..remove(item.id)));
    }
  }

  // ------------------------------------------------------------------ host

  /// Host: start the first upcoming song, or write the ended state if the
  /// queue is empty. Returns a message if it did not work.
  Future<String?> playNext() => _guardedMessage(() async {
    final next = await _firstPlayable(await _freshUpcoming());
    if (next == null) {
      return await _sync.hostEnd() ? null : _syncError();
    }
    return _advance(next);
  });

  /// Host: jump to [item] now.
  Future<String?> playItem(QueueItem item) => _guardedMessage(() async {
    final upcoming = await _freshUpcoming();
    final current = upcoming.where((i) => i.id == item.id).firstOrNull;
    // It may have been played or removed since the list was drawn.
    if (current == null) return notInQueueMessage;
    if (!isPlayableLength(current)) return "That song can't be played.";
    return _advance(current);
  });

  /// The host's song ended: start the next one, but only if the room still
  /// shows that same ended song (a skip tap or another tab may have moved on).
  Future<TrackEndResult> _onTrackEnded(RoomState ended) async {
    if (_disposed) return TrackEndResult.ignored;
    // A skip is running: try again later (if it fails the song is still over).
    if (state.advancing) return TrackEndResult.failed;
    return _guarded<TrackEndResult>(
      () async {
        final now = _room;
        if (now == null ||
            now.trackId != ended.trackId ||
            now.updatedAt != ended.updatedAt) {
          return TrackEndResult.ignored;
        }
        final next = await _firstPlayable(await _freshUpcoming());
        if (next == null) {
          return await _sync.hostEnd()
              ? TrackEndResult.advanced
              : TrackEndResult.failed;
        }
        return await _advance(next) == null
            ? TrackEndResult.advanced
            : TrackEndResult.failed;
      },
      whenRefused: TrackEndResult.ignored,
      whenBusy: TrackEndResult.failed,
      whenFailed: (_) => TrackEndResult.failed,
    );
  }

  String? _syncError() =>
      ref.read(syncControllerProvider(args)).errorMessage ??
      const QueueFailure(QueueFailureKind.unknown).message;

  /// One advance at a time, and only for the host. [whenRefused] is the answer
  /// for a non-host, [whenBusy] for a call while another advance runs,
  /// [whenFailed] for an error.
  Future<T> _guarded<T>(
    Future<T> Function() body, {
    required T whenRefused,
    required T whenBusy,
    required T Function(Object error) whenFailed,
  }) async {
    if (!args.isHost) return whenRefused;
    if (state.advancing) return whenBusy;
    _set(state.copyWith(advancing: true));
    try {
      return await body();
    } catch (error) {
      if (error is! QueueFailure) {
        debugPrint('Advance failed (${error.runtimeType})');
      }
      return whenFailed(error);
    } finally {
      _set(state.copyWith(advancing: false));
    }
  }

  /// [_guarded] for the buttons: the answer is a message, or null on success.
  Future<String?> _guardedMessage(Future<String?> Function() body) =>
      _guarded<String?>(
        body,
        whenRefused: hostOnlyMessage,
        whenBusy: null,
        whenFailed: (error) => error is QueueFailure
            ? error.message
            : const QueueFailure(QueueFailureKind.unknown).message,
      );

  Future<String?> _advance(QueueItem target) async {
    final before = _room?.queueItemId;
    if (!await _sync.hostAdvanceTo(target)) return _syncError();
    _started.add(target.id);
    // The song is playing now. Marking is best effort: if it fails the item
    // is hidden anyway, and [_reconcile] and the next advance mark it.
    await _mark(target.id);
    if (before != null && before != target.id) await _mark(before);
    return null;
  }

  Future<void> _mark(String itemId) async {
    if (!_reconciled.add(itemId)) return; // done or already in flight
    try {
      await _repo.markPlayed(itemId, DateTime.now().toUtc());
    } catch (error) {
      // Healed later; nothing the user can do. Forgotten, so it is retried.
      debugPrint('Marking an item played failed (${error.runtimeType})');
      _reconciled.remove(itemId);
    }
  }

  /// Heals an item that is playing but was never marked played (the host's
  /// connection dropped between the two writes). It acts once per item and
  /// not during an advance, so it cannot loop with the events it causes.
  void _reconcile() {
    if (_disposed || state.advancing) return;
    final playing = _room?.queueItemId;
    if (playing == null || _reconciled.contains(playing)) return;
    final items = ref.read(upcomingItemsProvider(args.roomId)).value;
    if (items == null || !items.any((i) => i.id == playing)) return;
    unawaited(_mark(playing));
  }
}
