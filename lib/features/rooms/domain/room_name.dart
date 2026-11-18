const roomNameMaxLength = 40;

/// Trimmed, 1 to 40 characters (code points, like the database).
String? validateRoomName(String? value) {
  final length = (value ?? '').trim().runes.length;
  if (length == 0) return 'Enter a room name.';
  if (length > roomNameMaxLength) {
    return 'Use $roomNameMaxLength characters or fewer.';
  }
  return null;
}

/// Pure helper for the "Copy invite" text. [webOrigin] is passed only on web.
String buildInviteText({
  required String roomName,
  required String code,
  String? webOrigin,
}) {
  final text = 'Join my Vibe Room "$roomName" with code $code';
  if (webOrigin == null) return text;
  return '$text\n$webOrigin/#/join/$code';
}
