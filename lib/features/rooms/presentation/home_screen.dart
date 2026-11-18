import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/gradient_background.dart';
import '../../auth/domain/profile.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../auth/presentation/profile_sheet.dart';

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
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
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
                          const create = _ComingSoonCard(
                            icon: Icons.add_circle_outline,
                            title: 'Create a room',
                          );
                          const join = _ComingSoonCard(
                            icon: Icons.keyboard_outlined,
                            title: 'Join with a code',
                          );
                          if (constraints.maxWidth >= 560) {
                            return const Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: create),
                                SizedBox(width: 16),
                                Expanded(child: join),
                              ],
                            );
                          }
                          return const Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [create, SizedBox(height: 16), join],
                          );
                        },
                      ),
                    ],
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

/// A disabled, dimmed card for features that arrive in a later step.
class _ComingSoonCard extends StatelessWidget {
  const _ComingSoonCard({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      label: '$title, coming in the next step',
      child: ExcludeSemantics(
        child: Opacity(
          opacity: 0.55,
          child: Card(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 140),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                    const SizedBox(height: 16),
                    Text(
                      title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Coming in the next step',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
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
