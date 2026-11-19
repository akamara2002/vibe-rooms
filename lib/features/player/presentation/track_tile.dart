import 'package:material_ui/material_ui.dart';

import 'artwork.dart';
import 'format_duration.dart';

/// One track as a row: artwork, title, artist (and who added it), length, and
/// optional trailing [actions]. Shared by the search sheet and the queue so
/// they look the same. Track data is untrusted: it is only ever shown as
/// `Text`.
class TrackTile extends StatelessWidget {
  const TrackTile({
    super.key,
    required this.title,
    required this.artist,
    required this.duration,
    this.artworkUrl,
    this.addedBy,
    this.onTap,
    this.actions = const [],
    this.highlight = false,
  });

  final String title;
  final String artist;
  final Duration duration;
  final String? artworkUrl;

  /// "Bo" or "🎸 Bo": shown under the artist.
  final String? addedBy;

  /// Makes the whole row a button (the actions stay separate buttons).
  final VoidCallback? onTap;
  final List<Widget> actions;

  /// The pinned "now playing" look.
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final length = formatDuration(duration);
    final label = addedBy == null
        ? '$title by $artist, $length'
        : '$title by $artist, $length, added by $addedBy';

    final body = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 72),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            Artwork(url: artworkUrl, size: 56, radius: 10),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  if (addedBy != null)
                    Text(
                      'Added by $addedBy',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
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
    );

    final Widget main = onTap == null
        ? Semantics(
            container: true,
            label: label,
            child: ExcludeSemantics(child: body),
          )
        : Semantics(
            button: true,
            label: label,
            // The InkWell is excluded from semantics, so the tap action must
            // be declared here for screen readers.
            onTap: onTap,
            child: ExcludeSemantics(
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: onTap,
                child: body,
              ),
            ),
          );

    // Actions sit beside the row when there is room, and under it on a narrow
    // phone or with large text (they would squeeze the title to nothing).
    final compact =
        MediaQuery.textScalerOf(context).scale(1) > 1.25 ||
        MediaQuery.sizeOf(context).width < 420;
    final Widget row = actions.isEmpty
        ? main
        : compact
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              main,
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: Wrap(
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: actions,
                ),
              ),
            ],
          )
        : Row(
            children: [
              Expanded(child: main),
              ...actions,
              const SizedBox(width: 4),
            ],
          );
    if (!highlight) return row;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
      ),
      child: row,
    );
  }
}
