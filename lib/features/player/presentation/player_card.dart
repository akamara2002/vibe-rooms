import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../queue/presentation/queue_providers.dart';
import '../domain/sync_status.dart';
import 'artwork.dart';
import 'format_duration.dart';
import 'player_providers.dart';
import 'sync_controller.dart';
import 'sync_providers.dart';
import 'track_search_sheet.dart';

/// The room's "Now playing" card. Everyone sees the same track and position
/// (they come from the room's playback row); only the host has transport
/// controls.
class PlayerCard extends ConsumerStatefulWidget {
  const PlayerCard({super.key, required this.args});

  final SyncArgs args;

  @override
  ConsumerState<PlayerCard> createState() => _PlayerCardState();
}

class _PlayerCardState extends ConsumerState<PlayerCard> {
  /// The slider value while the host drags it (milliseconds).
  double? _dragMs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sync = ref.watch(syncControllerProvider(widget.args));
    final controller = ref.read(syncControllerProvider(widget.args).notifier);
    final isHost = widget.args.isHost;
    final room = sync.room;
    final hasTrack = sync.hasTrack;
    // Only the host has Next; the queue state is read only for them.
    final queue = isHost
        ? ref.watch(queueControllerProvider(widget.args))
        : null;
    final hasUpcoming = isHost
        ? (ref.watch(visibleUpcomingProvider(widget.args)).value ?? const [])
              .isNotEmpty
        : false;

    Future<void> playNext() async {
      final messenger = ScaffoldMessenger.of(context);
      final problem = await ref
          .read(queueControllerProvider(widget.args).notifier)
          .playNext();
      if (problem != null) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(problem)));
      }
    }

    void findMusic() {
      // Picking a track is a tap, so it also unlocks sound on the web.
      showTrackSearchSheet(
        context,
        title: 'Pick a song',
        onTrackSelected: controller.hostSetTrack,
      );
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                Text(
                  'Now playing',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                if (hasTrack) _SyncChip(status: sync.status),
              ],
            ),
            const SizedBox(height: 12),
            if (!hasTrack)
              _EmptyPlayer(
                isHost: isHost,
                onFindMusic: findMusic,
                onPlayNext: hasUpcoming && !(queue?.advancing ?? false)
                    ? playNext
                    : null,
              )
            else ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Artwork(url: room!.artworkUrl, size: 88, radius: 18),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          room.title ?? 'Untitled',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          room.artist ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        if (isHost)
                          TextButton(
                            onPressed: findMusic,
                            child: const Text('Change track'),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _Progress(
                positionMs: sync.position.inMilliseconds,
                durationMs: room.durationMs ?? 0,
                dragMs: _dragMs,
                editable: isHost,
                onDrag: (value) => setState(() => _dragMs = value),
                onDragEnd: (value) {
                  setState(() => _dragMs = null);
                  controller.hostSeek(Duration(milliseconds: value.round()));
                },
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isHost)
                    _PlayButton(
                      playing: room.isPlaying,
                      onPressed: controller.hostTogglePlay,
                    ),
                  if (isHost) const SizedBox(width: 8),
                  if (isHost)
                    IconButton.filledTonal(
                      tooltip: 'Next',
                      onPressed: hasUpcoming && !(queue?.advancing ?? false)
                          ? playNext
                          : null,
                      icon: const Icon(Icons.skip_next),
                    ),
                  const SizedBox(width: 8),
                  _MuteButton(
                    muted: sync.muted,
                    onPressed: controller.toggleMute,
                  ),
                ],
              ),
              if (!isHost) ...[
                const SizedBox(height: 8),
                Text(
                  'The host controls playback',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
            if (sync.errorMessage != null) ...[
              const SizedBox(height: 12),
              _ErrorRow(
                message: sync.errorMessage!,
                onDismiss: controller.clearError,
              ),
            ],
            const SizedBox(height: 12),
            Text(
              'Music via Audius',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SyncChip extends ConsumerWidget {
  const _SyncChip({required this.status});

  final SyncStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final (label, icon, color) = switch (status) {
      SyncStatus.inSync => ('In sync', Icons.check_circle, scheme.primary),
      SyncStatus.syncing => ('Syncing...', Icons.sync, scheme.tertiary),
      SyncStatus.reconnecting => (
        'Reconnecting...',
        Icons.wifi_off,
        scheme.error,
      ),
      SyncStatus.waitingForSound => (
        'Tap to turn on sound',
        Icons.volume_up,
        scheme.primary,
      ),
      SyncStatus.ended => ('Ended', Icons.stop_circle_outlined, scheme.outline),
    };
    final chip = Chip(
      avatar: Icon(icon, size: 18, color: color),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
    if (status != SyncStatus.waitingForSound) {
      return Semantics(
        label: label,
        child: ExcludeSemantics(child: chip),
      );
    }
    // The chip doubles as the web sound gate.
    void enable() => ref.read(soundEnabledProvider.notifier).enable();
    return Semantics(
      button: true,
      label: label,
      onTap: enable,
      child: ExcludeSemantics(
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: enable,
          child: chip,
        ),
      ),
    );
  }
}

class _EmptyPlayer extends StatelessWidget {
  const _EmptyPlayer({
    required this.isHost,
    required this.onFindMusic,
    required this.onPlayNext,
  });

  final bool isHost;
  final VoidCallback onFindMusic;

  /// Songs are queued but nothing is playing: start them.
  final VoidCallback? onPlayNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(Icons.music_note, size: 36, color: scheme.primary),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                isHost
                    ? 'Pick a song to start the party'
                    : 'Waiting for the host to pick a song',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        if (isHost) ...[
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onFindMusic,
            icon: const Icon(Icons.search),
            label: const Text('Find music'),
          ),
          if (onPlayNext != null) ...[
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: onPlayNext,
              icon: const Icon(Icons.skip_next),
              label: const Text('Play next'),
            ),
          ],
        ],
      ],
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({
    required this.positionMs,
    required this.durationMs,
    required this.dragMs,
    required this.editable,
    required this.onDrag,
    required this.onDragEnd,
  });

  final int positionMs;
  final int durationMs;
  final double? dragMs;
  final bool editable;
  final ValueChanged<double> onDrag;
  final ValueChanged<double> onDragEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxMs = durationMs > 0 ? durationMs.toDouble() : 1.0;
    final valueMs = (dragMs ?? positionMs.toDouble()).clamp(0.0, maxMs);
    final total = Duration(milliseconds: durationMs);
    final elapsed = Duration(milliseconds: valueMs.round());
    final style = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final label = '${formatDuration(elapsed)} of ${formatDuration(total)}';

    return Column(
      children: [
        if (editable)
          SliderTheme(
            data: SliderTheme.of(context).copyWith(trackHeight: 4),
            child: Slider(
              value: valueMs,
              max: maxMs,
              onChanged: durationMs > 0 ? onDrag : null,
              // Only the end of the drag is written to the room.
              onChangeEnd: durationMs > 0 ? onDragEnd : null,
              semanticFormatterCallback: (_) => label,
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
            child: Semantics(
              label: 'Progress $label',
              child: ExcludeSemantics(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: valueMs / maxMs,
                    minHeight: 4,
                  ),
                ),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(formatDuration(elapsed), style: style),
              Text(formatDuration(total), style: style),
            ],
          ),
        ),
      ],
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.playing, required this.onPressed});

  final bool playing;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.filled(
      tooltip: playing ? 'Pause' : 'Play',
      style: IconButton.styleFrom(minimumSize: const Size(64, 64)),
      iconSize: 32,
      onPressed: onPressed,
      icon: Icon(playing ? Icons.pause : Icons.play_arrow),
    );
  }
}

class _MuteButton extends StatelessWidget {
  const _MuteButton({required this.muted, required this.onPressed});

  final bool muted;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.outlined(
      tooltip: muted ? 'Unmute' : 'Mute',
      onPressed: onPressed,
      icon: Icon(muted ? Icons.volume_off : Icons.volume_up),
    );
  }
}

class _ErrorRow extends StatelessWidget {
  const _ErrorRow({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: scheme.onErrorContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
          IconButton(
            tooltip: 'Dismiss',
            onPressed: onDismiss,
            icon: Icon(Icons.close, color: scheme.onErrorContainer),
          ),
        ],
      ),
    );
  }
}
