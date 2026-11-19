import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../../player/presentation/sync_providers.dart';
import '../../rooms/presentation/rooms_providers.dart';
import '../domain/chat_failure.dart';
import '../domain/chat_message.dart';
import '../domain/chat_repository.dart';
import '../domain/message.dart';
import '../domain/sanitize_message.dart';
import '../domain/send_rate_limiter.dart';
import 'chat_providers.dart';

/// Messages kept in memory (the oldest confirmed ones are dropped).
const maxMessagesInMemory = 200;

/// How many recent messages are read at once.
const recentWindow = 50;

const unknownSenderName = 'Someone';
const unknownSenderEmoji = '🎧';

class ChatState {
  const ChatState({
    this.messages = const [],
    this.unread = 0,
    this.loading = true,
    this.loadFailure,
    this.notice,
  });

  /// Oldest first; my own unconfirmed (sending or failed) messages come last,
  /// in the order I sent them.
  final List<ChatMessage> messages;

  /// Other people's messages that arrived while the Chat tab was not showing.
  final int unread;
  final bool loading;
  final ChatFailure? loadFailure;

  /// A short hint, like "Slow down a little".
  final String? notice;
}

/// Loads, merges and sends the room's chat messages.
///
///   send("hi") ──► temp "sending" ──► insert ──► row ──┐
///                       ▲                              ├─► confirmed (by id)
///   realtime INSERT ────┴─ echo of MY message confirms ─┘
///                          the oldest matching temp
///
/// The echo can arrive BEFORE `send` returns, so both paths confirm the same
/// temp and everything is de-duplicated by the real id, in either order.
class ChatController extends Notifier<ChatState> {
  ChatController(this.roomId);

  final String roomId;

  late ChatRepository _repo;
  late String? _me;
  late SendRateLimiter _limiter;

  final _confirmed = <String, ChatMessage>{};
  final _pending = <ChatMessage>[];
  final _profiles = <String, ChatSender>{};
  final _lookups = <String>{};

  StreamSubscription<Message>? _subscription;
  Timer? _noticeTimer;
  bool _disposed = false;
  bool _initialLoaded = false;
  bool _visible = false;
  int _unread = 0;
  int _tmp = 0;
  bool _loading = true;
  ChatFailure? _loadFailure;
  String? _notice;

  String? get myId => _me;

  @override
  ChatState build() {
    _repo = ref.read(chatRepositoryProvider);
    _me = ref.read(authRepositoryProvider).userId;
    _limiter = SendRateLimiter(now: ref.read(localClockProvider));
    ref.onDispose(() {
      _disposed = true;
      _noticeTimer?.cancel();
      _retryTimer?.cancel();
      unawaited(_subscription?.cancel());
    });
    scheduleMicrotask(_start);
    return const ChatState();
  }

  void _start() {
    if (_disposed) return;
    _subscription = _repo
        .watchNew(roomId, onJoined: _onJoined)
        .listen(_onInsert, onError: (Object _) {});
    unawaited(_refetch());
  }

  // ------------------------------------------------------------------ loading

  /// Runs on EVERY join of the channel, the first included.
  void _onJoined() {
    if (!_disposed) unawaited(_refetch());
  }

  Future<void> reload() => _refetch();

  Timer? _retryTimer;

  /// A catch-up read that failed (network still flapping) is tried once more
  /// shortly, so messages missed while offline are not lost until the next
  /// rejoin.
  void _retryLater() {
    if (!_initialLoaded || _retryTimer?.isActive == true) return;
    _retryTimer = Timer(const Duration(seconds: 5), () {
      if (!_disposed) unawaited(_refetch());
    });
  }

  Future<void> _refetch() async {
    try {
      final fetched = await _repo.recent(roomId, limit: recentWindow);
      if (_disposed) return;
      _merge(fetched);
      _loadFailure = null;
    } on ChatFailure catch (failure) {
      if (_disposed) return;
      if (!_initialLoaded) _loadFailure = failure;
      _retryLater();
    } catch (_) {
      if (_disposed) return;
      if (!_initialLoaded) {
        _loadFailure = const ChatFailure(ChatFailureKind.unknown);
      }
      _retryLater();
    }
    _loading = false;
    _publish();
  }

  void _merge(List<Message> fetched) {
    final initial = !_initialLoaded;
    // If everything I know is OLDER than the whole window that came back, the
    // room had more than a window of new messages while I was away: keep the
    // window, not a history with a hole in the middle.
    if (!initial && fetched.length >= recentWindow && _confirmed.isNotEmpty) {
      final newestKnown = _confirmed.values
          .map((m) => m.createdAt)
          .reduce((a, b) => a.isAfter(b) ? a : b);
      if (fetched.first.createdAt.isAfter(newestKnown)) _confirmed.clear();
    }
    for (final message in fetched) {
      _addConfirmed(message, countUnread: !initial);
    }
    _initialLoaded = true;
  }

  // ----------------------------------------------------------------- incoming

  void _onInsert(Message message) {
    if (_disposed) return;
    _addConfirmed(message, countUnread: true);
    _publish();
  }

  /// Adds a confirmed message once (by id). Returns true if it was new.
  bool _addConfirmed(Message message, {required bool countUnread}) {
    if (_confirmed.containsKey(message.id)) return false;
    final body = sanitizeIncoming(message.body);
    if (body.isEmpty) return false; // nothing to show after cleaning
    final mine = message.userId == _me;
    if (mine) _consumePendingFor(body);
    final sender = _senderFor(message);
    _confirmed[message.id] = ChatMessage(
      id: message.id,
      roomId: message.roomId,
      userId: message.userId,
      body: body,
      createdAt: message.createdAt,
      senderName: sender.name,
      senderEmoji: sender.emoji,
    );
    if (!mine && countUnread && !_visible) _unread++;
    _evictOld();
    return true;
  }

  /// The echo of my own message (or the row a refetch returned) confirms the
  /// oldest unconfirmed message with the same text: still sending first, and a
  /// failed one only if nothing else matches (its insert may have succeeded
  /// with the answer lost).
  void _consumePendingFor(String body) {
    var index = _pending.indexWhere(
      (p) =>
          p.state == ChatSendState.sending && sanitizeIncoming(p.body) == body,
    );
    if (index < 0) {
      index = _pending.indexWhere(
        (p) =>
            p.state == ChatSendState.failed && sanitizeIncoming(p.body) == body,
      );
    }
    if (index >= 0) _pending.removeAt(index);
  }

  void _evictOld() {
    if (_confirmed.length <= maxMessagesInMemory) return;
    final sorted = _sortedConfirmed();
    final extra = _confirmed.length - maxMessagesInMemory;
    for (final message in sorted.take(extra)) {
      _confirmed.remove(message.id);
    }
  }

  // ------------------------------------------------------------------- names

  ChatSender _senderFor(Message message) =>
      _cleanSender(_rawSenderFor(message));

  /// Names and emoji are written by other users: clean them before display.
  ChatSender _cleanSender(ChatSender s) => ChatSender(
    name: sanitizeDisplayText(
      s.name,
      maxChars: 30,
      fallback: unknownSenderName,
    ),
    emoji: sanitizeDisplayText(
      s.emoji,
      maxChars: 16,
      fallback: unknownSenderEmoji,
    ),
  );

  ChatSender _rawSenderFor(Message message) {
    final embedded = message.senderName;
    if (embedded != null) {
      return ChatSender(
        name: embedded,
        emoji: message.senderEmoji ?? unknownSenderEmoji,
      );
    }
    final known = _knownSender(message.userId);
    if (known != null) return known;
    _lookup(message.userId);
    return const ChatSender(name: unknownSenderName, emoji: unknownSenderEmoji);
  }

  /// The room members first, then profiles looked up before.
  ChatSender? _knownSender(String userId) {
    final members = ref.read(roomMembersProvider(roomId)).value;
    if (members != null) {
      for (final member in members) {
        if (member.userId == userId) {
          return ChatSender(
            name: member.displayName,
            emoji: member.avatarEmoji,
          );
        }
      }
    }
    return _profiles[userId];
  }

  /// One lookup per unknown user, however many messages arrive meanwhile.
  void _lookup(String userId) {
    if (!_lookups.add(userId)) return;
    unawaited(() async {
      final sender = await _repo.sender(userId);
      if (_disposed) return;
      if (sender == null) return; // stays "Someone", not retried in a loop
      _profiles[userId] = _cleanSender(sender);
      for (final entry in _confirmed.entries.toList()) {
        if (entry.value.userId == userId) {
          _confirmed[entry.key] = entry.value.copyWith(
            senderName: _profiles[userId]!.name,
            senderEmoji: _profiles[userId]!.emoji,
          );
        }
      }
      _publish();
    }());
  }

  // ------------------------------------------------------------------ sending

  /// Sends [text]. Returns why it was not accepted, or null if it is now in
  /// the list (sending). The caller clears its input only on null, so nothing
  /// the user typed is lost to a rate limit.
  ChatFailure? send(String text) {
    final body = sanitizeMessage(text);
    if (body == null) {
      return ChatFailure(
        sanitizeIncoming(text).isEmpty
            ? ChatFailureKind.empty
            : ChatFailureKind.tooLong,
      );
    }
    if (!_limiter.tryAcquire()) {
      const failure = ChatFailure(ChatFailureKind.rateLimited);
      _showNotice(failure.message);
      return failure;
    }
    final me = _me;
    if (me == null) return const ChatFailure(ChatFailureKind.notAllowed);
    final mine = _senderFor(
      Message(
        id: '',
        roomId: roomId,
        userId: me,
        body: body,
        createdAt: DateTime.now().toUtc(),
      ),
    );
    final temp = ChatMessage(
      id: 'tmp-${_tmp++}',
      roomId: roomId,
      userId: me,
      body: body,
      createdAt: ref.read(localClockProvider)().toUtc(),
      senderName: mine.name,
      senderEmoji: mine.emoji,
      state: ChatSendState.sending,
    );
    _pending.add(temp);
    _publish();
    unawaited(_deliver(temp));
    return null;
  }

  Future<void> _deliver(ChatMessage temp) async {
    try {
      final row = await _repo.send(roomId, temp.body);
      if (_disposed) return;
      // The echo may have confirmed it already; the id decides.
      final index = _pending.indexWhere((p) => p.id == temp.id);
      if (index >= 0) _pending.removeAt(index);
      if (!_confirmed.containsKey(row.id)) {
        final body = sanitizeIncoming(row.body);
        final sender = _senderFor(row);
        _confirmed[row.id] = ChatMessage(
          id: row.id,
          roomId: row.roomId,
          userId: row.userId,
          body: body.isEmpty ? temp.body : body,
          createdAt: row.createdAt,
          senderName: sender.name,
          senderEmoji: sender.emoji,
        );
        _evictOld();
      }
    } catch (error) {
      if (_disposed) return;
      final failure = error is ChatFailure
          ? error
          : const ChatFailure(ChatFailureKind.unknown);
      final index = _pending.indexWhere((p) => p.id == temp.id);
      if (index >= 0) {
        _pending[index] = _pending[index].copyWith(
          state: ChatSendState.failed,
          failureMessage: failure.message,
        );
      }
    }
    _publish();
  }

  /// Tries a failed message again. A retry counts against the rate limit.
  void retry(String tempId) {
    final index = _pending.indexWhere(
      (p) => p.id == tempId && p.state == ChatSendState.failed,
    );
    if (index < 0) return;
    if (!_limiter.tryAcquire()) {
      _showNotice(const ChatFailure(ChatFailureKind.rateLimited).message);
      return;
    }
    _pending[index] = _pending[index].copyWith(state: ChatSendState.sending);
    _publish();
    unawaited(_deliver(_pending[index]));
  }

  /// Removes a failed message from the list (it was never sent).
  void deleteLocal(String tempId) {
    _pending.removeWhere(
      (p) => p.id == tempId && p.state == ChatSendState.failed,
    );
    _publish();
  }

  // -------------------------------------------------------------------- state

  /// Called by the tabs: the Chat tab is (or is not) the visible one.
  void setChatVisible(bool visible) {
    if (_visible == visible) return;
    _visible = visible;
    if (visible) _unread = 0;
    _publish();
  }

  void _showNotice(String text) {
    _notice = text;
    _noticeTimer?.cancel();
    _noticeTimer = Timer(const Duration(seconds: 3), () {
      if (_disposed) return;
      _notice = null;
      _publish();
    });
    _publish();
  }

  List<ChatMessage> _sortedConfirmed() {
    final list = _confirmed.values.toList()
      ..sort((a, b) {
        final byTime = a.createdAt.compareTo(b.createdAt);
        return byTime != 0 ? byTime : a.id.compareTo(b.id);
      });
    return list;
  }

  void _publish() {
    if (_disposed) return;
    state = ChatState(
      messages: [..._sortedConfirmed(), ..._pending],
      unread: _unread,
      loading: _loading,
      loadFailure: _loadFailure,
      notice: _notice,
    );
  }
}
