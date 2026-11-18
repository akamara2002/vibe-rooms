import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'player_providers.dart';

/// "Tap to turn on sound": browsers refuse to play audio before the user has
/// interacted with the page, so on web nothing plays until this is tapped.
/// Renders nothing once sound is on (or where no gate is needed).
class SoundGate extends ConsumerWidget {
  const SoundGate({super.key, this.message = 'Tap to turn on sound'});

  /// "Music is playing. Tap to join in" for a late joiner.
  final String message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watching here keeps the provider alive for the whole room visit.
    final enabled = ref.watch(soundEnabledProvider);
    if (enabled) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Semantics(
        button: true,
        label: message,
        // The InkWell below is excluded from semantics, so the tap action
        // must be declared here for screen readers.
        onTap: () => ref.read(soundEnabledProvider.notifier).enable(),
        child: ExcludeSemantics(
          child: Material(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => ref.read(soundEnabledProvider.notifier).enable(),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.volume_up, color: scheme.onPrimaryContainer),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          message,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: scheme.onPrimaryContainer,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        color: scheme.onPrimaryContainer,
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
