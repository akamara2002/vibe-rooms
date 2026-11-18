import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../player/presentation/sync_controller.dart';
import '../../player/presentation/track_search_sheet.dart';
import '../../player/presentation/track_tile.dart';
import '../domain/queue_failure.dart';
import '../domain/queue_item.dart';
import '../../player/presentation/sync_providers.dart';
import 'queue_providers.dart';

/// The Queue tab: the song playing now (pinned), then "Up next". Everyone sees
/// the same list live; everyone can add; the host and the adder can remove;
/// only the host can play an item now.
class QueueTab extends ConsumerWidget {
  const QueueTab({super.key, required this.args});

  final SyncArgs args;

  void _say(ScaffoldMessengerState messenger, String? message) {
    if (message == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final room = ref.watch(syncControllerProvider(args).select((s) => s.room));
    final items = ref.watch(visibleUpcomingProvider(args));
    final queue = ref.watch(queueControllerProvider(args));
    final controller = ref.read(queueControllerProvider(args).notifier);
    final sync = ref.read(syncControllerProvider(args).notifier);
    final count = items.value?.length;

    void addSongs() {
      showTrackSearchSheet(
        context,
        title: 'Add songs',
        queuedTrackIds: {...?items.value?.map((i) => i.trackId)},
        onAdd: (track) async => (await controller.add(track))?.message,
        // "Play now" from search keeps writing queue_item_id null and does
        // not touch the queue.
        onPlayNow: args.isHost ? sync.hostSetTrack : null,
      );
    }

    final Widget list = items.when(
      skipLoadingOnRefresh: true,
      loading: () => const _QueueSkeleton(),
      error: (error, _) => _Message(
        icon: Icons.cloud_off_outlined,
        text: error is QueueFailure
            ? error.message
            : const QueueFailure(QueueFailureKind.unknown).message,
        action: TextButton(
          onPressed: () => ref.invalidate(upcomingItemsProvider(args.roomId)),
          child: const Text('Retry'),
        ),
      ),
      data: (list) {
        if (list.isEmpty) {
          return const _Message(
            icon: Icons.queue_music,
            text: 'Nothing queued. Add songs with Find music.',
          );
        }
        return Column(
          children: [
            for (final item in list)
              _QueueRow(
                key: ValueKey(item.id),
                item: item,
                isHost: args.isHost,
                canRemove: controller.canRemove(item),
                busy: queue.busyIds.contains(item.id),
                advancing: queue.advancing,
                onRemove: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  _say(messenger, (await controller.remove(item))?.message);
                },
                onPlayNow: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  _say(messenger, await controller.playItem(item));
                },
              ),
          ],
        );
      },
    );

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  header: true,
                  label: count == null ? 'Up next' : 'Up next, $count songs',
                  child: ExcludeSemantics(
                    child: Text(
                      count == null ? 'Up next' : 'Up next ($count)',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: addSongs,
                icon: const Icon(Icons.add),
                label: const Text('Add songs'),
              ),
            ],
          ),
          if (room?.trackId != null) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 4),
              child: Text(
                'Now playing',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            TrackTile(
              highlight: true,
              title: room!.title ?? 'Untitled',
              artist: room.artist ?? '',
              artworkUrl: room.artworkUrl,
              duration: Duration(milliseconds: room.durationMs ?? 0),
            ),
          ],
          const SizedBox(height: 8),
          list,
        ],
      ),
    );
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({
    super.key,
    required this.item,
    required this.isHost,
    required this.canRemove,
    required this.busy,
    required this.advancing,
    required this.onRemove,
    required this.onPlayNow,
  });

  final QueueItem item;
  final bool isHost;
  final bool canRemove;
  final bool busy;
  final bool advancing;
  final VoidCallback onRemove;
  final VoidCallback onPlayNow;

  @override
  Widget build(BuildContext context) {
    final name = item.addedByName;
    final emoji = item.addedByEmoji;
    final addedBy = name == null
        ? null
        : (emoji == null || emoji.isEmpty ? name : '$emoji $name');
    return TrackTile(
      title: item.title,
      artist: item.artist,
      artworkUrl: item.artworkUrl,
      duration: Duration(milliseconds: item.durationMs),
      addedBy: addedBy,
      actions: [
        if (isHost)
          IconButton(
            tooltip: 'Play now',
            onPressed: advancing || busy ? null : onPlayNow,
            icon: const Icon(Icons.play_arrow),
          ),
        if (canRemove)
          busy
              ? const SizedBox(
                  width: 48,
                  height: 48,
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                  ),
                )
              : IconButton(
                  tooltip: 'Remove from queue',
                  onPressed: onRemove,
                  icon: const Icon(Icons.close),
                ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      child: Column(
        children: [
          Icon(icon, size: 36, color: color),
          const SizedBox(height: 8),
          Text(
            text,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(color: color),
          ),
          ?action,
        ],
      ),
    );
  }
}

class _QueueSkeleton extends StatelessWidget {
  const _QueueSkeleton();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    Widget bar(double width) => Container(
      width: width,
      height: 12,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
    );
    return Semantics(
      label: 'Loading the queue',
      child: ExcludeSemantics(
        child: Column(
          children: [
            for (var i = 0; i < 3; i++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [bar(180), const SizedBox(height: 8), bar(110)],
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
