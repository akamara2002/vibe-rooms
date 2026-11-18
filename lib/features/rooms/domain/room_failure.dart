enum RoomFailureKind {
  roomNotFound,
  invalidName,
  notAuthenticated,
  closed,
  network,
  unknown,
}

/// A failed room operation with a short, human-readable [message].
class RoomFailure implements Exception {
  const RoomFailure(this.kind);

  final RoomFailureKind kind;

  String get message => switch (kind) {
    RoomFailureKind.roomNotFound => 'No room with that code.',
    RoomFailureKind.invalidName => 'Room names must be 1 to 40 characters.',
    RoomFailureKind.notAuthenticated => 'Please sign in again.',
    RoomFailureKind.closed => 'This room has been closed.',
    RoomFailureKind.network =>
      'Could not reach the server. Check your connection and try again.',
    RoomFailureKind.unknown => 'Something went wrong. Please try again.',
  };

  @override
  String toString() => 'RoomFailure($kind)';
}
