final _hasZone = RegExp(r'(Z|[+-]\d{2}(:?\d{2})?)$', caseSensitive: false);

/// Parses a Postgres timestamp as a UTC [DateTime].
///
/// `timestamptz` values arrive with an offset (`+00:00`), which [DateTime.parse]
/// honours. If a value ever arrives without one, [DateTime.parse] would read it
/// as local time and shift it by the device's UTC offset, so it is treated as
/// UTC here instead. A wrong `updated_at` would break playback sync.
DateTime parseUtc(String value) {
  final text = value.trim();
  return DateTime.parse(_hasZone.hasMatch(text) ? text : '${text}Z').toUtc();
}
