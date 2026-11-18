import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../domain/audio_engine.dart';
import '../domain/player_state.dart';
import 'artwork.dart';
import 'format_duration.dart';
import 'player_controller.dart';
import 'player_providers.dart';
import 'track_search_sheet.dart';

/// The "Now playing" card: artwork, title, progress, play/pause, errors.
/// Local playback only for now (see the "Preview mode" caption).
class PlayerCard extends ConsumerStatefulWidget {
  const PlayerCard({super.key});

  @override
  ConsumerState<PlayerCard> createState() => _PlayerCardState();
}

class _PlayerCardState extends ConsumerState<PlayerCard> {
  /// The slider value while the thumb is being dragged (milliseconds).
  double? _dragMs;

  Future<void> _openOnAudius(String url) async {
    final uri = Uri.tryParse(url);
    // Only ever open the audius.co page of the track.
    if (uri == null || uri.scheme != 'https' || uri.host != 'audius.co') return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final player = ref.watch(playerControllerProvider);
    final soundOn = ref.watch(soundEnabledProvider);
    final controller = ref.read(playerControllerProvider.notifier);
    final track = player.track;

    void findMusic() =>
        showTrackSearchSheet(context, onTrackSelected: controller.playTrack);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Now playing',
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            if (track == null)
              _EmptyPlayer(onFindMusic: findMusic)
            else ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Artwork(url: track.artworkUrl, size: 88, radius: 18),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
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
                player: player,
                dragMs: _dragMs,
                onDrag: (value) => setState(() => _dragMs = value),
                onDragEnd: (value) {
                  setState(() => _dragMs = null);
                  controller.seek(Duration(milliseconds: value.round()));
                },
              ),
              const SizedBox(height: 4),
              Center(
                child: _PlayButton(
                  player: player,
                  enabled: soundOn,
                  onPressed: controller.togglePlay,
                ),
              ),
            ],
            if (player.errorMessage != null) ...[
              const SizedBox(height: 12),
              _ErrorRow(
                message: player.errorMessage!,
                onRetry: track != null && player.phase == EnginePhase.error
                    ? controller.retry
                    : null,
              ),
            ],
            const SizedBox(height: 12),
            Text(
              'Preview mode: not synced yet',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Music via Audius',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (track?.permalinkUrl != null)
                  TextButton.icon(
                    onPressed: () => _openOnAudius(track!.permalinkUrl!),
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('Open on Audius'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyPlayer extends StatelessWidget {
  const _EmptyPlayer({required this.onFindMusic});

  final VoidCallback onFindMusic;

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
                'Nothing playing yet',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: onFindMusic,
          icon: const Icon(Icons.search),
          label: const Text('Find music'),
        ),
      ],
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({
    required this.player,
    required this.dragMs,
    required this.onDrag,
    required this.onDragEnd,
  });

  final PlayerState player;
  final double? dragMs;
  final ValueChanged<double> onDrag;
  final ValueChanged<double> onDragEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = player.duration ?? player.track?.duration ?? Duration.zero;
    final maxMs = total.inMilliseconds.toDouble();
    final seekable =
        maxMs > 0 &&
        const {
          EnginePhase.ready,
          EnginePhase.playing,
          EnginePhase.paused,
          EnginePhase.buffering,
          EnginePhase.completed,
        }.contains(player.phase);
    final valueMs = (dragMs ?? player.position.inMilliseconds.toDouble()).clamp(
      0.0,
      maxMs <= 0 ? 1.0 : maxMs,
    );
    final elapsed = Duration(milliseconds: valueMs.round());
    final style = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(trackHeight: 4),
          child: Slider(
            value: valueMs,
            max: maxMs <= 0 ? 1.0 : maxMs,
            onChanged: seekable ? onDrag : null,
            onChangeEnd: seekable ? onDragEnd : null,
            semanticFormatterCallback: (v) =>
                '${formatDuration(Duration(milliseconds: v.round()))} of ${formatDuration(total)}',
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
  const _PlayButton({
    required this.player,
    required this.enabled,
    required this.onPressed,
  });

  final PlayerState player;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final busy =
        player.phase == EnginePhase.loading ||
        player.phase == EnginePhase.buffering;
    final playing = player.phase == EnginePhase.playing;
    return IconButton.filled(
      tooltip: playing ? 'Pause' : 'Play',
      style: IconButton.styleFrom(minimumSize: const Size(64, 64)),
      iconSize: 32,
      onPressed: enabled && !busy ? onPressed : null,
      icon: busy
          ? const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 3),
            )
          : Icon(playing ? Icons.pause : Icons.play_arrow),
    );
  }
}

class _ErrorRow extends StatelessWidget {
  const _ErrorRow({required this.message, required this.onRetry});

  final String message;
  final VoidCallback? onRetry;

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
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
