import '../domain/chat_failure.dart';
import '../domain/chat_message.dart';
import '../domain/chat_repository.dart';
import '../domain/message.dart';

/// Used when Supabase is not configured: an empty chat that cannot send.
class UnconfiguredChatRepository implements ChatRepository {
  const UnconfiguredChatRepository();

  @override
  Future<List<Message>> recent(String roomId, {int limit = 50}) async =>
      const [];

  @override
  Stream<Message> watchNew(
    String roomId, {
    required void Function() onJoined,
  }) => const Stream.empty();

  @override
  Future<Message> send(String roomId, String body) =>
      Future.error(const ChatFailure(ChatFailureKind.unknown));

  @override
  Future<ChatSender?> sender(String userId) async => null;
}
