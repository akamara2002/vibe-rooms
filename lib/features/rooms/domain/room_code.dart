/// Room codes: 6 characters from an alphabet without 0, O, 1 and I.
const roomCodeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const roomCodeLength = 6;

/// Trims, upper-cases and drops every character outside [roomCodeAlphabet].
/// Does not truncate (see [isValidRoomCode]).
String normalizeRoomCode(String input) {
  final upper = input.trim().toUpperCase();
  final out = StringBuffer();
  for (final char in upper.split('')) {
    if (roomCodeAlphabet.contains(char)) out.write(char);
  }
  return out.toString();
}

/// True for exactly [roomCodeLength] alphabet characters.
bool isValidRoomCode(String code) {
  if (code.length != roomCodeLength) return false;
  return code.split('').every(roomCodeAlphabet.contains);
}

final _plausibleRoomId = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

/// A room id taken from a URL is only used if it has a harmless shape
/// (letters, digits, `-` and `_`). Real ids are uuids; this only keeps odd
/// characters out of queries and Realtime filters.
bool isPlausibleRoomId(String id) => _plausibleRoomId.hasMatch(id);
