import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/gradient_background.dart';
import 'room_sheets.dart';

/// Full-screen message for a room that does not exist, that I am not in, or
/// that has been closed. The database reveals nothing beyond that.
class RoomNotAvailable extends StatelessWidget {
  const RoomNotAvailable({
    super.key,
    required this.title,
    required this.message,
    this.onRetry,
  });

  final String title;
  final String message;

  /// Set for a failure that may be temporary (not for "not found").
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      Icons.meeting_room_outlined,
                      size: 56,
                      color: scheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 28),
                    if (onRetry != null) ...[
                      FilledButton(
                        onPressed: onRetry,
                        child: const Text('Try again'),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: () => context.go('/home'),
                        child: const Text('Back to home'),
                      ),
                    ] else
                      FilledButton(
                        onPressed: () => context.go('/home'),
                        child: const Text('Back to home'),
                      ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () => showJoinRoomSheet(context),
                      child: const Text('Join with a code'),
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
