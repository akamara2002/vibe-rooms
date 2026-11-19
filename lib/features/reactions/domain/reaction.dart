/// The only reactions there are. Defined once; the wire carries the KEY, never
/// the emoji, so a payload can only select one of these.
enum ReactionType {
  fire('fire', '🔥'),
  heart('heart', '❤️'),
  hands('hands', '🙌'),
  laugh('laugh', '😂'),
  notes('notes', '🎶'),
  clap('clap', '👏');

  const ReactionType(this.key, this.emoji);

  final String key;
  final String emoji;

  /// A spoken name for screen readers: "fire", "heart", ...
  String get label => key;

  static ReactionType? fromKey(Object? key) {
    if (key is! String) return null;
    for (final type in values) {
      if (type.key == key) return type;
    }
    return null;
  }
}

/// The broadcast event name.
const reactionEvent = 'reaction';

/// A payload is `{"emoji": "fire"}`: far below this.
const maxReactionPayloadChars = 64;

class Reaction {
  const Reaction(this.type);

  final ReactionType type;
}

/// Reads an incoming broadcast payload. Reactions travel on a public channel,
/// so ANYTHING can arrive: only exactly `{emoji: <a known key>}` is accepted,
/// and everything else is dropped silently (null).
///
/// The realtime client hands over the payload FLAT, with its own bookkeeping
/// keys added (`{emoji: fire, event: reaction, type: broadcast}`, observed
/// against the real service). Those two keys are set by the client, not by the
/// sender, so they are ignored; any OTHER extra key drops the payload. A
/// payload nested under `payload` is read the same way.
Reaction? parseReactionPayload(Object? raw) {
  try {
    Object? source = raw;
    if (raw is Map && raw['payload'] is Map) source = raw['payload'];
    if (source is! Map) return null;
    final inner = {
      for (final entry in source.entries)
        if (entry.key != 'event' && entry.key != 'type') entry.key: entry.value,
    };
    if (inner.length != 1 || !inner.containsKey('emoji')) return null;
    final key = inner['emoji'];
    if (key is! String || key.length > maxReactionPayloadChars) return null;
    final type = ReactionType.fromKey(inner['emoji']);
    return type == null ? null : Reaction(type);
  } catch (_) {
    return null;
  }
}
