import 'chat_message.dart';
import 'message.dart';

abstract class ChatRepository {
  /// The newest [limit] messages, oldest first, with who sent them.
  Future<List<Message>> recent(String roomId, {int limit = 50});

  /// Every message inserted in the room from now on (Postgres Changes). A
  /// realtime event carries no profile, so [Message.senderName] is null.
  /// [onJoined] runs on EVERY (re)join of the channel, the first one included:
  /// events missed while offline (or before the first join) are not replayed,
  /// so the caller reads the recent messages again and merges them.
  Stream<Message> watchNew(String roomId, {required void Function() onJoined});

  /// Inserts only room_id, user_id and body, and returns the inserted row.
  /// Throws `ChatFailure`.
  Future<Message> send(String roomId, String body);

  /// One profile lookup, or null if it cannot be read.
  Future<ChatSender?> sender(String userId);
}
