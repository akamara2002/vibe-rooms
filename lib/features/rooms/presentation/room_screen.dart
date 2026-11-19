import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/gradient_background.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../player/presentation/player_card.dart';
import '../../chat/presentation/chat_providers.dart';
import '../../chat/presentation/chat_tab.dart';
import '../../queue/presentation/queue_providers.dart';
import '../../reactions/presentation/reaction_bar.dart';
import '../../reactions/presentation/reaction_controller.dart';
import '../../reactions/presentation/reaction_overlay.dart';
import '../../queue/presentation/queue_tab.dart';
import '../../player/presentation/sync_controller.dart';
import '../../player/presentation/sync_providers.dart';
import '../../player/presentation/sound_gate.dart';
import '../domain/room.dart';
import '../domain/room_code.dart';
import '../domain/room_failure.dart';
import '../domain/room_member.dart';
import '../domain/room_name.dart';
import 'host_presence.dart';
import 'leave_dialog.dart';
import 'room_not_available.dart';
import 'rooms_providers.dart';

class RoomScreen extends ConsumerStatefulWidget {
  const RoomScreen({super.key, required this.id});

  final String id;

  @override
  ConsumerState<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends ConsumerState<RoomScreen> {
  /// True while leaving or closing: the room disappears for me the moment my
  /// membership row is gone, and that must not flash as "not found".
  bool _leaving = false;

  Future<void> _confirmLeave(Room room, {required bool isHost}) async {
    final confirmed = await confirmLeaveOrClose(context, isHost: isHost);
    if (!confirmed || !mounted) return;

    final container = ProviderScope.containerOf(context, listen: false);
    final repo = container.read(roomRepositoryProvider);
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _leaving = true);
    try {
      if (isHost) {
        await repo.closeRoom(room.id);
      } else {
        await repo.leaveRoom(room.id);
      }
      container.invalidate(myRoomsProvider);
      router.go('/home');
    } on RoomFailure catch (failure) {
      if (mounted) setState(() => _leaving = false);
      messenger.showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_leaving) {
      return const GradientBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    // The id comes from the URL: never let a malformed one reach a query or a
    // realtime filter.
    if (!isPlausibleRoomId(widget.id)) {
      return const RoomNotAvailable(
        title: 'Room not found',
        message: "This room doesn't exist, or you're not in it.",
      );
    }

    final room = ref.watch(roomProvider(widget.id));
    return room.when(
      skipLoadingOnRefresh: true,
      loading: () => const GradientBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (error, _) => RoomNotAvailable(
        title: "Can't open this room",
        message: error is RoomFailure
            ? error.message
            : const RoomFailure(RoomFailureKind.unknown).message,
        // Retrying only helps for a temporary failure.
        onRetry:
            error is! RoomFailure ||
                error.kind == RoomFailureKind.network ||
                error.kind == RoomFailureKind.unknown
            ? () => ref.invalidate(roomProvider(widget.id))
            : null,
      ),
      data: (value) {
        if (value == null) {
          return const RoomNotAvailable(
            title: 'Room not found',
            message: "This room doesn't exist, or you're not in it.",
          );
        }
        if (value.closedAt != null) {
          return RoomNotAvailable(
            title: 'Room closed',
            message: const RoomFailure(RoomFailureKind.closed).message,
          );
        }
        return _RoomView(room: value, onLeave: _confirmLeave);
      },
    );
  }
}

class _RoomView extends ConsumerStatefulWidget {
  const _RoomView({required this.room, required this.onLeave});

  final Room room;
  final Future<void> Function(Room room, {required bool isHost}) onLeave;

  @override
  ConsumerState<_RoomView> createState() => _RoomViewState();
}

class _RoomViewState extends ConsumerState<_RoomView> {
  /// Five taps on the room name show the sync debug panel (it is always shown
  /// in debug builds).
  int _titleTaps = 0;

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    final onLeave = widget.onLeave;
    final myId = ref.read(authRepositoryProvider).userId;
    final isHost = room.hostId == myId;
    final args = (roomId: room.id, isHost: isHost);
    final membersAsync = ref.watch(roomMembersProvider(room.id));
    final members = membersAsync.value ?? const <RoomMember>[];
    final online =
        ref.watch(onlineUsersProvider(room.id)).value ?? const <String>{};
    // Watching a slice keeps the sync controller (and its engine) alive for the
    // whole visit without rebuilding the screen on every tick.
    final playing = ref.watch(
      syncControllerProvider(args).select((s) => s.room?.isPlaying ?? false),
    );
    // Keeps the queue controller (and its end-of-song hook) alive for the
    // whole visit without rebuilding the screen.
    ref.watch(queueControllerProvider(args).select((_) => true));
    // And the queue's realtime channel, so switching tabs does not drop and
    // rejoin it.
    ref.watch(upcomingItemsProvider(room.id).select((_) => true));
    // Chat messages, the unread count and reactions keep arriving while
    // another tab is open.
    ref.watch(chatControllerProvider(room.id).select((_) => true));
    ref.watch(reactionControllerProvider(room.id).select((_) => true));
    final hostOffline = ref.watch(
      hostOfflineProvider((
        roomId: room.id,
        hostId: room.hostId,
        isHost: isHost,
      )),
    );
    final showDebug = ref.watch(debugPanelDefaultProvider) || _titleTaps >= 5;

    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          leading: IconButton(
            tooltip: 'Back to home',
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go('/home'),
          ),
          title: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // A hidden developer trigger, not a button: screen readers should
            // not announce it as one.
            excludeFromSemantics: true,
            onTap: () => setState(() => _titleTaps++),
            child: Text(
              room.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          actions: [
            PopupMenuButton<String>(
              tooltip: 'Room menu',
              onSelected: (_) => onLeave(room, isHost: isHost),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'leave',
                  child: Text(isHost ? 'Close room' : 'Leave room'),
                ),
              ],
            ),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 960),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _CodeHeader(room: room),
                    const SizedBox(height: 16),
                    if (hostOffline) const _HostOfflineBanner(),
                    SoundGate(
                      message: playing
                          ? 'Music is playing. Tap to join in'
                          : 'Tap to turn on sound',
                    ),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final nowPlaying = _PlayerArea(args: args);
                        final listeners = _Listeners(
                          state: membersAsync,
                          onRetry: () =>
                              ref.invalidate(roomMembersProvider(room.id)),
                          members: members,
                          online: online,
                          myId: myId,
                        );
                        if (constraints.maxWidth >= 840) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(flex: 3, child: nowPlaying),
                              const SizedBox(width: 16),
                              Expanded(flex: 2, child: listeners),
                            ],
                          );
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            nowPlaying,
                            const SizedBox(height: 16),
                            listeners,
                          ],
                        );
                      },
                    ),
                    if (showDebug) ...[
                      const SizedBox(height: 16),
                      _SyncDebugPanel(args: args),
                    ],
                    const SizedBox(height: 24),
                    _Tabs(args: args, roomId: room.id),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown to listeners while the host is away. Playback is not touched: the
/// last state keeps playing out, only the host can change it.
class _HostOfflineBanner extends StatelessWidget {
  const _HostOfflineBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Semantics(
        liveRegion: true,
        container: true,
        child: Material(
          color: scheme.secondaryContainer,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                ExcludeSemantics(
                  child: Icon(
                    Icons.info_outline,
                    color: scheme.onSecondaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'The host is offline. Only the host can change the music.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSecondaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CodeHeader extends StatelessWidget {
  const _CodeHeader({required this.room});

  final Room room;

  Future<void> _copy(
    BuildContext context,
    String text,
    String confirmation,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: text));
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(confirmation)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final invite = buildInviteText(
      roomName: room.name,
      code: room.code,
      webOrigin: kIsWeb ? Uri.base.origin : null,
    );

    return Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.only(left: 16),
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Semantics(
                  label: 'Room code ${room.code.split('').join(' ')}',
                  child: ExcludeSemantics(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        room.code,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w700,
                          letterSpacing: 4,
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Copy code',
                color: scheme.onPrimaryContainer,
                icon: const Icon(Icons.copy),
                onPressed: () => _copy(context, room.code, 'Code copied'),
              ),
            ],
          ),
        ),
        TextButton.icon(
          onPressed: () => _copy(context, invite, 'Invite copied'),
          icon: const Icon(Icons.ios_share),
          label: const Text('Copy invite'),
        ),
      ],
    );
  }
}

class _Listeners extends StatelessWidget {
  const _Listeners({
    required this.state,
    required this.onRetry,
    required this.members,
    required this.online,
    required this.myId,
  });

  final AsyncValue<List<RoomMember>> state;
  final VoidCallback onRetry;
  final List<RoomMember> members;
  final Set<String> online;
  final String? myId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Host first, then me, then by join time.
    final sorted = [...members]
      ..sort((a, b) {
        int rank(RoomMember m) => m.isHost ? 0 : (m.userId == myId ? 1 : 2);
        final byRank = rank(a).compareTo(rank(b));
        return byRank != 0 ? byRank : a.joinedAt.compareTo(b.joinedAt);
      });

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              members.isEmpty && (state.isLoading || state.hasError)
                  ? 'Listeners'
                  : 'Listeners (${members.length})',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            if (state.isLoading && members.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: LinearProgressIndicator(
                  semanticsLabel: 'Loading listeners',
                ),
              )
            else if (state.hasError && members.isEmpty)
              Row(
                children: [
                  const Expanded(child: Text('Could not load the listeners.')),
                  TextButton(
                    onPressed: onRetry,
                    child: const Text('Try again'),
                  ),
                ],
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final member in sorted)
                    _ListenerChip(
                      member: member,
                      isMe: member.userId == myId,
                      isOnline: online.contains(member.userId),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _ListenerChip extends StatelessWidget {
  const _ListenerChip({
    required this.member,
    required this.isMe,
    required this.isOnline,
  });

  final RoomMember member;
  final bool isMe;
  final bool isOnline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final label =
        '${member.displayName}${isMe ? ', you' : ''}${member.isHost ? ', host' : ''}, ${isOnline ? 'online' : 'offline'}';

    return Semantics(
      label: label,
      child: ExcludeSemantics(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 220),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Text(
                    member.avatarEmoji,
                    style: const TextStyle(fontSize: 22),
                  ),
                  Positioned(
                    right: -4,
                    bottom: -2,
                    child: Container(
                      key: ValueKey('online-dot-${member.userId}'),
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isOnline
                            ? const Color(0xFF3DDC84)
                            : scheme.outline,
                        border: Border.all(
                          color: scheme.surfaceContainerHighest,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 10),
              if (member.isHost) ...[
                const Text('👑', style: TextStyle(fontSize: 14)),
                const SizedBox(width: 4),
              ],
              Flexible(
                child: Text(
                  member.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (isMe) ...[
                const SizedBox(width: 6),
                Text(
                  'You',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.primary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The player card with reactions floating over it and the reaction bar
/// under it.
class _PlayerArea extends StatelessWidget {
  const _PlayerArea({required this.args});

  final SyncArgs args;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Stack(
          children: [
            PlayerCard(args: args),
            Positioned.fill(child: ReactionOverlay(roomId: args.roomId)),
          ],
        ),
        const SizedBox(height: 12),
        ReactionBar(roomId: args.roomId),
      ],
    );
  }
}

class _Tabs extends ConsumerStatefulWidget {
  const _Tabs({required this.args, required this.roomId});

  final SyncArgs args;
  final String roomId;

  @override
  ConsumerState<_Tabs> createState() => _TabsState();
}

class _TabsState extends ConsumerState<_Tabs>
    with SingleTickerProviderStateMixin {
  late final TabController _controller = TabController(length: 2, vsync: this)
    ..addListener(_onTab);

  void _onTab() {
    // The Chat tab is the visible one once the switch has finished.
    ref
        .read(chatControllerProvider(widget.roomId).notifier)
        .setChatVisible(_controller.index == 1 && !_controller.indexIsChanging);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final unread = ref.watch(
      chatControllerProvider(widget.roomId).select((s) => s.unread),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TabBar(
          controller: _controller,
          dividerColor: Colors.transparent,
          indicatorSize: TabBarIndicatorSize.tab,
          indicator: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          labelColor: scheme.onPrimaryContainer,
          tabs: [
            const Tab(text: 'Queue'),
            Tab(
              child: Badge(
                // Outside the label, so it does not cover the last letter.
                alignment: AlignmentDirectional.topEnd,
                offset: const Offset(14, -6),
                label: Text(unread > 9 ? '9+' : '$unread'),
                isLabelVisible: unread > 0,
                child: const Text('Chat'),
              ),
            ),
          ],
        ),
        // Sized by its content (the queue can be 50 rows long), not fixed.
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => _controller.index == 0
              ? QueueTab(args: widget.args)
              : ChatTab(roomId: widget.roomId),
        ),
      ],
    );
  }
}

/// Collapsible sync internals: for debugging only.
class _SyncDebugPanel extends ConsumerWidget {
  const _SyncDebugPanel({required this.args});

  final SyncArgs args;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(syncControllerProvider(args));
    final d = sync.debug;
    String ms(int? value) => value == null ? 'n/a' : '$value ms';
    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        title: const Text('Sync debug'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedAlignment: Alignment.centerLeft,
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Status: ${sync.status.name}'),
          Text('Server offset: ${ms(d.offsetMs)}'),
          Text('Round trip: ${ms(d.rttMs)}'),
          Text('Last drift: ${ms(d.driftMs)}'),
          Text('Last action: ${d.lastAction}'),
          Text('Track loaded: ${d.loadedTrack}'),
          Text('Host: ${args.isHost}'),
        ],
      ),
    );
  }
}
