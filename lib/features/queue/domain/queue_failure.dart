enum QueueFailureKind { full, duplicate, notAllowed, network, unknown }

/// A queue action that did not happen, with a short message for the user.
class QueueFailure implements Exception {
  const QueueFailure(this.kind, [this._message]);

  final QueueFailureKind kind;
  final String? _message;

  String get message =>
      _message ??
      switch (kind) {
        QueueFailureKind.full => 'The queue is full.',
        QueueFailureKind.duplicate => 'Already in the queue',
        QueueFailureKind.notAllowed => "You can't do that in this room.",
        QueueFailureKind.network => 'Connection problem. Try again.',
        QueueFailureKind.unknown => 'Something went wrong. Try again.',
      };

  @override
  String toString() => 'QueueFailure(${kind.name})';
}
