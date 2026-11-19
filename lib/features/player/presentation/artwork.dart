import 'package:cached_network_image/cached_network_image.dart';
import 'package:material_ui/material_ui.dart';

/// The most pixels an artwork is ever decoded at, however large it is shown.
const maxArtworkDecodePx = 1024;

/// Rounded track artwork with a tonal placeholder when there is none (or it
/// fails to load).
class Artwork extends StatelessWidget {
  const Artwork({
    super.key,
    required this.url,
    required this.size,
    this.radius = 14,
  });

  final String? url;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Decode at the size it is shown (in device pixels), not at the full size
    // of the file: Audius artwork can be 1000 px square or more.
    final cacheWidth = (size * MediaQuery.devicePixelRatioOf(context))
        .round()
        .clamp(1, maxArtworkDecodePx);
    final placeholder = Container(
      width: size,
      height: size,
      color: scheme.primary.withValues(alpha: 0.16),
      child: Icon(Icons.music_note, size: size * 0.45, color: scheme.primary),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: url == null
          ? placeholder
          : CachedNetworkImage(
              imageUrl: url!,
              width: size,
              height: size,
              memCacheWidth: cacheWidth,
              fit: BoxFit.cover,
              placeholder: (_, _) => placeholder,
              errorWidget: (_, _, _) => placeholder,
            ),
    );
  }
}
