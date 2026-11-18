enum AudiusFailureKind { network, rateLimited, notFound, unknown }

/// A failed Audius request with a short, human-readable [message].
class AudiusFailure implements Exception {
  const AudiusFailure(this.kind);

  final AudiusFailureKind kind;

  String get message => switch (kind) {
    AudiusFailureKind.network =>
      "Couldn't reach Audius. Check your connection and try again.",
    AudiusFailureKind.rateLimited =>
      'Audius is busy right now. Try again in a moment.',
    AudiusFailureKind.notFound => 'That track is not available.',
    AudiusFailureKind.unknown => 'Something went wrong with Audius. Try again.',
  };

  @override
  String toString() => 'AudiusFailure($kind)';
}
