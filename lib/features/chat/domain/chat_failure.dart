enum ChatFailureKind {
  tooLong,
  empty,
  rateLimited,
  notAllowed,
  network,
  unknown,
}

class ChatFailure implements Exception {
  const ChatFailure(this.kind);

  final ChatFailureKind kind;

  String get message => switch (kind) {
    ChatFailureKind.tooLong => 'That message is too long.',
    ChatFailureKind.empty => 'Write something first.',
    ChatFailureKind.rateLimited => 'Slow down a little',
    ChatFailureKind.notAllowed => "You can't send messages in this room.",
    ChatFailureKind.network => 'No connection. Try again.',
    ChatFailureKind.unknown => 'Something went wrong. Try again.',
  };

  @override
  String toString() => 'ChatFailure(${kind.name})';
}
