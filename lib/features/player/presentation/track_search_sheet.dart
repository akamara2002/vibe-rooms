import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../domain/audius_failure.dart';
import '../domain/track.dart';
import 'player_providers.dart';
import 'track_tile.dart';

/// How long typing must pause before a search is sent.
const searchDebounce = Duration(milliseconds: 400);

/// Opens [TrackSearchSheet]. Reusable: it knows nothing about rooms.
///
/// Two modes, both through callbacks (the sheet knows nothing about rooms or
/// the database):
///  * pick mode ([onTrackSelected]): a tap picks a track and closes the sheet;
///  * add mode ([onAdd]): each result has a "+" that adds it and shows
///    "Added", and the sheet stays open. [onAdd] returns why it failed (shown
///    in a snackbar) or null. [onPlayNow], if given, adds a "Play now" action
///    (host only). [queuedTrackIds] are shown as already added.
Future<void> showTrackSearchSheet(
  BuildContext context, {
  void Function(Track track)? onTrackSelected,
  Future<String?> Function(Track track)? onAdd,
  void Function(Track track)? onPlayNow,
  Set<String> queuedTrackIds = const {},
  String title = 'Find music',
}) {
  assert(onTrackSelected != null || onAdd != null);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.85,
      child: TrackSearchSheet(
        onTrackSelected: onTrackSelected,
        onAdd: onAdd,
        onPlayNow: onPlayNow,
        queuedTrackIds: queuedTrackIds,
        title: title,
      ),
    ),
  );
}

/// Search field plus results (trending while the field is empty).
class TrackSearchSheet extends ConsumerStatefulWidget {
  const TrackSearchSheet({
    super.key,
    this.onTrackSelected,
    this.onAdd,
    this.onPlayNow,
    this.queuedTrackIds = const {},
    this.title = 'Find music',
  });

  final void Function(Track track)? onTrackSelected;
  final Future<String?> Function(Track track)? onAdd;
  final void Function(Track track)? onPlayNow;
  final Set<String> queuedTrackIds;
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

  /// Add mode: tracks being added or added (by track id).
  final _adding = <String>{};
  late final Set<String> _added = {...widget.queuedTrackIds};

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
    widget.onTrackSelected?.call(track);
  }

  Future<void> _addTrack(Track track) async {
    final onAdd = widget.onAdd;
    if (onAdd == null ||
        _adding.contains(track.id) ||
        _added.contains(track.id)) {
      return;
    }
    // Captured before the await: the sheet may be closed meanwhile.
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _adding.add(track.id));
    final problem = await onAdd(track);
    if (!mounted) return;
    setState(() {
      _adding.remove(track.id);
      if (problem == null) _added.add(track.id);
    });
    if (problem != null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(problem)));
    }
  }

  void _playNow(Track track) {
    Navigator.of(context).pop();
    widget.onPlayNow?.call(track);
  }

  Widget _tile(Track track) {
    final adding = widget.onAdd != null;
    return TrackTile(
      title: track.title,
      artist: track.artist,
      duration: track.duration,
      artworkUrl: track.artworkUrl,
      onTap: adding ? () => _addTrack(track) : () => _select(track),
      actions: [
        if (adding && widget.onPlayNow != null)
          TextButton(
            onPressed: () => _playNow(track),
            child: const Text('Play now'),
          ),
        if (adding)
          _AddButton(
            added: _added.contains(track.id),
            adding: _adding.contains(track.id),
            onPressed: () => _addTrack(track),
          ),
      ],
    );
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
            : _TrackList(label: 'Trending', tracks: tracks, tile: _tile),
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
        tile: _tile,
      );
    }

    // Escape closes the sheet (the Scaffold below would otherwise keep the
    // default dismiss from reaching the sheet's route), also from the field.
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
      },
      // Its own Scaffold, so a snackbar shows above the sheet instead of behind.
      child: Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: false,
        body: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
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
        ),
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({
    required this.added,
    required this.adding,
    required this.onPressed,
  });

  final bool added;
  final bool adding;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (added) {
      return Semantics(
        label: 'Added',
        child: ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check, size: 20, color: scheme.primary),
                const SizedBox(width: 4),
                Text('Added', style: TextStyle(color: scheme.primary)),
              ],
            ),
          ),
        ),
      );
    }
    if (adding) {
      return const SizedBox(
        width: 48,
        height: 48,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      );
    }
    return IconButton(
      tooltip: 'Add to queue',
      onPressed: onPressed,
      icon: const Icon(Icons.add),
    );
  }
}

class _TrackList extends StatelessWidget {
  const _TrackList({
    required this.label,
    required this.tracks,
    required this.tile,
  });

  final String label;
  final List<Track> tracks;
  final Widget Function(Track) tile;

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
        return tile(track);
      },
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
      child: SingleChildScrollView(
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
