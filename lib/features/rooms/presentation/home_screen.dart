import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/gradient_background.dart';
import '../../auth/domain/profile.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../auth/presentation/profile_sheet.dart';
import '../domain/room_summary.dart';
import '../domain/room_failure.dart';
import 'leave_dialog.dart';
import 'room_sheets.dart';
import 'rooms_providers.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final profile = ref.watch(myProfileProvider);
    final name = profile.value?.displayName;

    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: Text(
            'Vibe Rooms',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: _ProfileChip(
                profile: profile,
                onOpen: () => showProfileSheet(context),
                onRetry: () => ref.invalidate(myProfileProvider),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(myRoomsProvider);
              try {
                await ref.read(myRoomsProvider.future);
              } catch (_) {
                // The list shows its own error state.
              }
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(24),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: SizedBox(
                    width: double.infinity,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name == null ? 'Welcome' : 'Hey, $name',
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Start a room or jump into one with friends.',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 24),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final create = _ActionCard(
                              icon: Icons.add_circle_outline,
                              title: 'Create a room',
                              onTap: () => showCreateRoomSheet(context),
                            );
                            final join = _ActionCard(
                              icon: Icons.keyboard_outlined,
                              title: 'Join with a code',
                              onTap: () => showJoinRoomSheet(context),
                            );
                            if (constraints.maxWidth >= 560) {
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: create),
                                  const SizedBox(width: 16),
                                  Expanded(child: join),
                                ],
                              );
                            }
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                create,
                                const SizedBox(height: 16),
                                join,
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 32),
                        const _MyRooms(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileChip extends StatelessWidget {
  const _ProfileChip({
    required this.profile,
    required this.onOpen,
    required this.onRetry,
  });

  final AsyncValue<Profile> profile;
  final VoidCallback onOpen;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final value = profile.value;
    if (value != null) {
      return ActionChip(
        avatar: Text(value.avatarEmoji),
        label: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 140),
          child: Text(value.displayName, overflow: TextOverflow.ellipsis),
        ),
        onPressed: onOpen,
      );
    }
    if (profile.hasError) {
      return ActionChip(
        avatar: const Icon(Icons.refresh, size: 18),
        label: const Text('Retry profile'),
        onPressed: onRetry,
      );
    }
    return const Chip(label: Text('…'));
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 88),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: scheme.primary),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MyRooms extends ConsumerWidget {
  const _MyRooms();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final rooms = ref.watch(myRoomsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'My rooms',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Refresh rooms',
              icon: const Icon(Icons.refresh),
              onPressed: () => ref.invalidate(myRoomsProvider),
            ),
          ],
        ),
        const SizedBox(height: 8),
        rooms.when(
          skipLoadingOnRefresh: true,
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (_, _) => _Message(
            text: 'Could not load your rooms.',
            actionLabel: 'Try again',
            onAction: () => ref.invalidate(myRoomsProvider),
          ),
          data: (list) => list.isEmpty
              ? const _EmptyRooms()
              : Column(
                  children: [
                    for (final summary in list) _RoomTile(summary: summary),
                  ],
                ),
        ),
      ],
    );
  }
}

class _EmptyRooms extends StatelessWidget {
  const _EmptyRooms();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Text('🎧', style: TextStyle(fontSize: 40)),
            const SizedBox(height: 12),
            Text(
              'No rooms yet. Create one or join with a code.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.text,
    required this.actionLabel,
    required this.onAction,
  });

  final String text;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(child: Text(text)),
            TextButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}

class _RoomTile extends ConsumerWidget {
  const _RoomTile({required this.summary});

  final RoomSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final room = summary.room;
    final isHost = room.hostId == ref.read(authRepositoryProvider).userId;
    final count = summary.memberCount;
    final listeners = '$count ${count == 1 ? 'listener' : 'listeners'}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.go('/room/${room.id}'),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 72),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  if (isHost) ...[
                    const Text('👑', style: TextStyle(fontSize: 20)),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          room.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        // A Wrap, so a big text size or a narrow phone puts
                        // the count under the code instead of overflowing.
                        Wrap(
                          spacing: 12,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              room.code,
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontFamily: 'monospace',
                                letterSpacing: 2,
                                color: scheme.primary,
                              ),
                            ),
                            Text(
                              listeners,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
                  if (isHost)
                    IconButton(
                      tooltip: 'Close room ${room.name}',
                      icon: const Icon(Icons.close),
                      onPressed: () => _close(context),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _close(BuildContext context) async {
    final container = ProviderScope.containerOf(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    if (!await confirmLeaveOrClose(context, isHost: true)) return;
    try {
      await container.read(roomRepositoryProvider).closeRoom(summary.room.id);
    } on RoomFailure catch (failure) {
      messenger.showSnackBar(SnackBar(content: Text(failure.message)));
    } finally {
      container.invalidate(myRoomsProvider);
    }
  }
}
