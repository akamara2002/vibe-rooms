import 'reaction.dart';

/// Ephemeral reactions over Realtime Broadcast. Best effort: no history, no
/// persistence, no delivery guarantee.
abstract class ReactionService {
  /// Validated reactions from OTHER people (the sender's own are not echoed).
  Stream<Reaction> incoming(String roomId);

  /// Sends one reaction. Failures are swallowed by the caller: a lost
  /// reaction is fine.
  Future<void> send(String roomId, ReactionType type);
}
