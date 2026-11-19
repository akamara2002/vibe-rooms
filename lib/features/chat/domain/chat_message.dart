import 'message.dart';

enum ChatSendState { sent, sending, failed }

/// A message as the chat shows it: the row, who sent it, and (for my own
/// unconfirmed messages) a local state.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.roomId,
    required this.userId,
    required this.body,
    required this.createdAt,
    required this.senderName,
    required this.senderEmoji,
    this.state = ChatSendState.sent,
    this.failureMessage,
  });

  factory ChatMessage.fromMessage(
    Message message, {
    required String senderName,
    required String senderEmoji,
  }) => ChatMessage(
    id: message.id,
    roomId: message.roomId,
    userId: message.userId,
    body: message.body,
    createdAt: message.createdAt,
    senderName: message.senderName ?? senderName,
    senderEmoji: message.senderEmoji ?? senderEmoji,
  );

  /// The real row id, or a local id (`tmp-...`) while it is not confirmed.
  final String id;
  final String roomId;
  final String userId;
  final String body;
  final DateTime createdAt;
  final String senderName;
  final String senderEmoji;
  final ChatSendState state;

  /// Why a failed send failed.
  final String? failureMessage;

  bool get isPending => state != ChatSendState.sent;

  ChatMessage copyWith({
    String? id,
    String? body,
    DateTime? createdAt,
    String? senderName,
    String? senderEmoji,
    ChatSendState? state,
    String? failureMessage,
  }) => ChatMessage(
    id: id ?? this.id,
    roomId: roomId,
    userId: userId,
    body: body ?? this.body,
    createdAt: createdAt ?? this.createdAt,
    senderName: senderName ?? this.senderName,
    senderEmoji: senderEmoji ?? this.senderEmoji,
    state: state ?? this.state,
    failureMessage: failureMessage,
  );
}

/// Someone's name and emoji, from their profile.
class ChatSender {
  const ChatSender({required this.name, required this.emoji});

  final String name;
  final String emoji;
}
