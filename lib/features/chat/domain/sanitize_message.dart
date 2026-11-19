/// The database allows 1 to 500 characters (`char_length`, which counts code
/// points) after trimming.
const maxMessageLength = 500;

/// The character counter appears from here.
const counterFromLength = 400;

/// Length as the database counts it: code points, not UTF-16 units (an emoji
/// is 2 units in Dart but 1 character in Postgres).
int messageLength(String text) => text.runes.length;

// Control characters except newline (and tab, which becomes a space), plus the
// Unicode bidirectional controls that can make text read in a misleading order
// (a right-to-left override can disguise what a message says).
final _unsafe = RegExp(
  '[\u0000-\u0008\u000B-\u001F\u007F-\u009F'
  '\u202A-\u202E\u2066-\u2069\u200E\u200F\u061C]',
);
// Invisible characters that make a body or a name look empty or forge another
// one. U+200C/U+200D (joiners) stay: emoji sequences need them.
final _invisible = RegExp('[\u200B\u2060\uFEFF\u00AD\u3164]');
final _manyNewlines = RegExp(r'\n{3,}');

String _clean(String text) {
  final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  return normalized
      .replaceAll('\t', ' ')
      .replaceAll(_unsafe, '')
      .replaceAll(_invisible, '')
      .replaceAll(_manyNewlines, '\n\n')
      .trim();
}

/// What may be sent: trimmed, without control characters, with at most one
/// blank line in a row. Null when nothing is left or it is over 500 characters.
String? sanitizeMessage(String text) {
  final cleaned = _clean(text);
  if (cleaned.isEmpty || messageLength(cleaned) > maxMessageLength) return null;
  return cleaned;
}

/// The same cleaning for a RECEIVED body, without the length rule. A modified
/// client can insert anything the database check allows (control characters,
/// bidi overrides, hundreds of blank lines), so what arrives is cleaned before
/// it is shown, and before it is compared with what I sent.
String sanitizeIncoming(String text) => _clean(text);

/// A display name or avatar emoji written by another user: one line, no
/// control, bidi or invisible characters, at most [maxChars] code points.
/// Falls back to [fallback] when nothing visible is left.
String sanitizeDisplayText(
  String? text, {
  required int maxChars,
  required String fallback,
}) {
  var cleaned = (text ?? '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(_unsafe, '')
      .replaceAll(_invisible, '')
      .trim();
  if (cleaned.runes.length > maxChars) {
    cleaned = String.fromCharCodes(cleaned.runes.take(maxChars)).trim();
  }
  return cleaned.isEmpty ? fallback : cleaned;
}
