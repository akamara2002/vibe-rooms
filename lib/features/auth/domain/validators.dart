// Pure form validators. Each returns an error message, or null when valid.

const displayNameMaxLength = 30;
const passwordMinLength = 6;

/// The 12 avatars a user can pick from.
const avatarEmojis = [
  '🎧', '🎵', '🎸', '🎹', '🥁', '🎤', //
  '🎷', '🎺', '🪩', '🔥', '🌈', '🚀',
];

/// Trimmed, 1 to 30 characters. Counts code points like the database does
/// (`char_length`), not UTF-16 units, so emoji names are not rejected early.
String? validateDisplayName(String? value) {
  final length = (value ?? '').trim().runes.length;
  if (length == 0) return 'Enter a display name.';
  if (length > displayNameMaxLength) {
    return 'Use $displayNameMaxLength characters or fewer.';
  }
  return null;
}

final _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

String? validateEmail(String? value) {
  final text = (value ?? '').trim();
  if (text.isEmpty) return 'Enter your email.';
  if (!_emailPattern.hasMatch(text)) return 'Enter a valid email address.';
  return null;
}

String? validatePassword(String? value) {
  final text = value ?? '';
  if (text.isEmpty) return 'Enter a password.';
  if (text.length < passwordMinLength) {
    return 'Use at least $passwordMinLength characters.';
  }
  return null;
}
