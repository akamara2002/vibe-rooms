import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../domain/audius_failure.dart';
import '../domain/track.dart';
import 'artwork.dart';
import 'format_duration.dart';
import 'player_providers.dart';

/// How long typing must pause before a search is sent.
const searchDebounce = Duration(milliseconds: 400);

/// Opens [TrackSearchSheet]. Reusable: it knows nothing about rooms.
Future<void> showTrackSearchSheet(
  BuildContext context, {
  required void Function(Track track) onTrackSelected,
  String title = 'Find music',
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.85,
      child: TrackSearchSheet(onTrackSelected: onTrackSelected, title: title),
    ),
  );
}

/// Search field plus results (trending while the field is empty).
class TrackSearchSheet extends ConsumerStatefulWidget {
  const TrackSearchSheet({
    super.key,
    required this.onTrackSelected,
    this.title = 'Find music',
  });

  final void Function(Track track) onTrackSelected;
  final String title;

  @override
  ConsumerState<TrackSearchSheet> createState() => _TrackSearchSheetState();
}

class _TrackSearchSheetState extends ConsumerState<TrackSearchSheet> {
  final _field = TextEditingController();
  Timer? _debounce;

  /// Identifies the newest query. A response is shown only if it still
  /// matches, so slow, out-of-order answers can never overwrite newer ones.
  int _generation = 0;

  String _query = '';
  List<Track>? _results;
  AudiusFailure? _failure;
  bool _loading = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _field.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    final query = text.trim();
    // Invalidate anything in flight right away, not when the debounce fires.
    final generation = ++_generation;
    if (query.isEmpty) {
      setState(() {
        _query = '';
        _results = null;
        _failure = null;
        _loading = false;
      });
      return;
    }
    setState(() {
      _query = query;
      _failure = null;
      _loading = true;
    });
    _debounce = Timer(searchDebounce, () => _search(query, generation));
  }

  Future<void> _search(String query, int generation) async {
    try {
      final tracks = await ref.read(musicCatalogProvider).search(query);
      if (!mounted || generation != _generation) return;
      setState(() {
        _results = tracks;
        _failure = null;
        _loading = false;
      });
    } on AudiusFailure catch (failure) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _failure = failure;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _failure = const AudiusFailure(AudiusFailureKind.unknown);
        _loading = false;
      });
    }
  }

  void _retry() {
    if (_query.isEmpty) {
      ref.invalidate(trendingProvider);
      return;
    }
    final generation = ++_generation;
    setState(() {
      _failure = null;
      _loading = true;
    });
    _search(_query, generation);
  }

  void _select(Track track) {
    Navigator.of(context).pop();
    widget.onTrackSelected(track);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Watched even while results are shown, so clearing the field brings
    // trending back instantly instead of reloading it.
    final trendingAsync = ref.watch(trendingProvider);

    final Widget body;
    if (_query.isEmpty) {
      body = trendingAsync.when(
        skipLoadingOnRefresh: false,
        loading: () => const _Skeletons(),
        error: (error, _) => _Problem.failure(
          error is AudiusFailure
              ? error
              : const AudiusFailure(AudiusFailureKind.unknown),
          onRetry: _retry,
        ),
        data: (tracks) => tracks.isEmpty
            ? const _Problem(
                icon: Icons.music_off_outlined,
                message: 'Nothing is trending right now.',
              )
            : _TrackList(label: 'Trending', tracks: tracks, onSelect: _select),
      );
    } else if (_loading) {
      body = const _Skeletons();
    } else if (_failure != null) {
      body = _Problem.failure(_failure!, onRetry: _retry);
    } else if ((_results ?? const []).isEmpty) {
      body = const _Problem(
        icon: Icons.search_off,
        message: 'No tracks found',
        hint: 'Try a different search.',
      );
    } else {
      body = _TrackList(
        label: 'Results for "$_query"',
        tracks: _results!,
        onSelect: _select,
      );
    }

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _field,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  onChanged: _onChanged,
                  decoration: InputDecoration(
                    hintText: 'Search Audius',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _field.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear',
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              _field.clear();
                              _onChanged('');
                            },
                          ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: body),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(
              'Music via Audius',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrackList extends StatelessWidget {
  const _TrackList({
    required this.label,
    required this.tracks,
    required this.onSelect,
  });

  final String label;
  final List<Track> tracks;
  final void Function(Track) onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: tracks.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: Text(label, style: theme.textTheme.labelLarge),
          );
        }
        final track = tracks[index - 1];
        return _TrackRow(track: track, onTap: () => onSelect(track));
      },
    );
  }
}

class _TrackRow extends StatelessWidget {
  const _TrackRow({required this.track, required this.onTap});

  final Track track;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final length = formatDuration(track.duration);
    return Semantics(
      button: true,
      label: '${track.title} by ${track.artist}, $length',
      // The tap action must live here: the InkWell below is excluded from
      // semantics, so without it a screen reader could not open the row.
      onTap: onTap,
      child: ExcludeSemantics(
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 72),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  Artwork(url: track.artworkUrl, size: 56, radius: 10),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    length,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Skeletons extends StatelessWidget {
  const _Skeletons();

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
      label: 'Loading tracks',
      child: ExcludeSemantics(
        child: ListView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          children: [
            for (var i = 0; i < 5; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
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

class _Problem extends StatelessWidget {
  const _Problem({
    required this.icon,
    required this.message,
    this.hint,
    this.onRetry,
  });

  factory _Problem.failure(
    AudiusFailure failure, {
    required VoidCallback onRetry,
  }) => _Problem(
    icon: Icons.cloud_off_outlined,
    message: failure.message,
    onRetry: onRetry,
  );

  final IconData icon;
  final String message;
  final String? hint;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: scheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            if (hint != null) ...[
              const SizedBox(height: 4),
              Text(
                hint!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: onRetry,
                child: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
