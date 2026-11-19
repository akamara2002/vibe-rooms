import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../domain/chat_message.dart';
import '../domain/sanitize_message.dart';
import 'chat_providers.dart';

/// Height of the message list (the page itself scrolls around it).
const chatPanelHeight = 420.0;

/// A body with hundreds of blank-separated lines (a hostile one) would make a
/// bubble many screens tall, so only the first lines are shown.
const maxDisplayLines = 15;

String _displayBody(String body) {
  final lines = body.split('\n');
  if (lines.length <= maxDisplayLines) return body;
  return '${lines.take(maxDisplayLines).join('\n')}\n…';
}

String _hhmm(DateTime time) {
  final local = time.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)}';
}

/// The Chat tab: messages (newest at the bottom), then the input.
class ChatTab extends ConsumerStatefulWidget {
  const ChatTab({super.key, required this.roomId});

  final String roomId;

  @override
  ConsumerState<ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends ConsumerState<ChatTab> {
  final _scroll = ScrollController();
  bool _atBottom = true;
  bool _showPill = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      // The list is reversed: offset 0 is the bottom (the newest message).
      final atBottom = !_scroll.hasClients || _scroll.offset <= 32;
      if (atBottom != _atBottom || (atBottom && _showPill)) {
        setState(() {
          _atBottom = atBottom;
          if (atBottom) _showPill = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _toBottom() {
    if (_scroll.hasClients) {
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(chatControllerProvider(widget.roomId));
    final controller = ref.read(chatControllerProvider(widget.roomId).notifier);
    ref.listen(chatControllerProvider(widget.roomId), (previous, next) {
      // A message arrived while the reader is up in the history: do not move
      // them, offer a way down.
      if (previous != null &&
          next.messages.length > previous.messages.length &&
          !_atBottom) {
        setState(() => _showPill = true);
      }
    });

    final messages = chat.messages;
    final Widget body;
    if (chat.loading && messages.isEmpty) {
      body = const _Skeleton();
    } else if (chat.loadFailure != null && messages.isEmpty) {
      body = _Centered(
        text: chat.loadFailure!.message,
        action: TextButton(
          onPressed: controller.reload,
          child: const Text('Retry'),
        ),
      );
    } else if (messages.isEmpty) {
      body = const _Centered(text: 'Say hi 👋');
    } else {
      body = ListView.builder(
        controller: _scroll,
        reverse: true,
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: messages.length,
        itemBuilder: (context, index) {
          final message = messages[messages.length - 1 - index];
          return _Bubble(
            key: ValueKey(message.id),
            message: message,
            mine: message.userId == controller.myId,
            onRetry: () => controller.retry(message.id),
            onDelete: () => controller.deleteLocal(message.id),
          );
        },
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: chatPanelHeight,
            child: Stack(
              children: [
                Positioned.fill(child: body),
                if (_showPill)
                  Positioned(
                    bottom: 8,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: FilledButton.tonalIcon(
                        onPressed: _toBottom,
                        icon: const Icon(Icons.arrow_downward, size: 18),
                        label: const Text('New messages'),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (chat.notice != null)
            Semantics(
              liveRegion: true,
              child: Padding(
                padding: const EdgeInsets.only(top: 8, left: 8),
                child: Text(
                  chat.notice!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ),
          const SizedBox(height: 8),
          _Input(roomId: widget.roomId),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    super.key,
    required this.message,
    required this.mine,
    required this.onRetry,
    required this.onDelete,
  });

  final ChatMessage message;
  final bool mine;
  final VoidCallback onRetry;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final failed = message.state == ChatSendState.failed;
    final sending = message.state == ChatSendState.sending;
    final background = mine
        ? scheme.primaryContainer
        : scheme.surfaceContainerHigh;
    final foreground = mine ? scheme.onPrimaryContainer : scheme.onSurface;
    final time = _hhmm(message.createdAt);

    final bubble = Container(
      constraints: const BoxConstraints(maxWidth: 520),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(mine ? 16 : 4),
          bottomRight: Radius.circular(mine ? 4 : 16),
        ),
        border: failed ? Border.all(color: scheme.error) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!mine)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                '${message.senderEmoji} ${message.senderName}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          // Plain text only: no links are made clickable.
          SelectableText(
            _displayBody(message.body),
            style: theme.textTheme.bodyMedium?.copyWith(color: foreground),
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                time,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: foreground.withValues(alpha: 0.7),
                ),
              ),
              if (sending) ...[
                const SizedBox(width: 6),
                const SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(strokeWidth: 1.5),
                ),
              ],
              if (failed) ...[
                const SizedBox(width: 6),
                Icon(Icons.error_outline, size: 14, color: scheme.error),
                const SizedBox(width: 4),
                Text(
                  'Not sent',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.error,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );

    final label =
        '${mine ? 'You' : message.senderName}, $time, ${message.body}'
        '${sending ? ', sending' : ''}${failed ? ', not sent' : ''}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: Column(
        crossAxisAlignment: mine
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Semantics(
            container: true,
            label: label,
            child: Opacity(opacity: sending ? 0.7 : 1, child: bubble),
          ),
          if (failed)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Retry'),
                ),
                TextButton.icon(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('Delete'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _Input extends ConsumerStatefulWidget {
  const _Input({required this.roomId});

  final String roomId;

  @override
  ConsumerState<_Input> createState() => _InputState();
}

class _InputState extends ConsumerState<_Input> {
  late final TextEditingController _text;

  @override
  void initState() {
    super.initState();
    // Starts with the unsent text kept by the controller (see ChatController).
    _text = TextEditingController(
      text: ref.read(chatControllerProvider(widget.roomId).notifier).draft,
    );
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  int get _length => messageLength(_text.text);
  bool get _canSend =>
      sanitizeIncoming(_text.text).isNotEmpty && _length <= maxMessageLength;

  bool get _enterSends =>
      kIsWeb ||
      const {
        TargetPlatform.linux,
        TargetPlatform.windows,
        TargetPlatform.macOS,
      }.contains(defaultTargetPlatform);

  void _send() {
    if (!_canSend) return;
    final failure = ref
        .read(chatControllerProvider(widget.roomId).notifier)
        .send(_text.text);
    // Cleared only when the message was accepted: a rate limit keeps the text.
    if (failure == null) {
      _text.clear();
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tooLong = _length > maxMessageLength;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Focus(
                // Enter sends, Shift+Enter is a new line (web and desktop).
                onKeyEvent: (node, event) {
                  if (_enterSends &&
                      event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.enter &&
                      !HardwareKeyboard.instance.isShiftPressed) {
                    _send();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: TextField(
                  controller: _text,
                  minLines: 1,
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (value) {
                    ref
                        .read(chatControllerProvider(widget.roomId).notifier)
                        .setDraft(value);
                    setState(() {});
                  },
                  decoration: const InputDecoration(
                    hintText: 'Message the room',
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              tooltip: 'Send',
              onPressed: _canSend ? _send : null,
              icon: const Icon(Icons.send),
            ),
          ],
        ),
        if (_length >= counterFromLength)
          Padding(
            padding: const EdgeInsets.only(top: 4, right: 56),
            child: Semantics(
              liveRegion: tooLong,
              child: Text(
                '$_length/$maxMessageLength',
                textAlign: TextAlign.end,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: tooLong ? scheme.error : scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered({required this.text, this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    Widget bubble(double width, {required bool right}) => Align(
      alignment: right ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        width: width,
        height: 36,
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
    return Semantics(
      label: 'Loading messages',
      child: ExcludeSemantics(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            bubble(180, right: false),
            bubble(120, right: true),
            bubble(220, right: false),
          ],
        ),
      ),
    );
  }
}
