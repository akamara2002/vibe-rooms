import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../config.dart';

const configBannerMessage =
    'Supabase is not configured: copy env.example.json to env.json and fill in your keys';

class _BannerDismissed extends Notifier<bool> {
  @override
  bool build() => false;

  void dismiss() => state = true;
}

final configBannerDismissedProvider = NotifierProvider<_BannerDismissed, bool>(
  _BannerDismissed.new,
);

/// Provider so tests can override whether Supabase counts as configured.
final configProvider = Provider<AppConfig>((_) => config);

/// Dismissible warning shown while Supabase config is missing.
class ConfigBanner extends ConsumerWidget {
  const ConfigBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configured = ref.watch(configProvider).isConfigured;
    final dismissed = ref.watch(configBannerDismissedProvider);
    if (configured || dismissed) return const SizedBox.shrink();

    return MaterialBanner(
      content: const Text(configBannerMessage),
      leading: const Icon(Icons.warning_amber_rounded),
      actions: [
        TextButton(
          onPressed: () =>
              ref.read(configBannerDismissedProvider.notifier).dismiss(),
          child: const Text('Dismiss'),
        ),
      ],
    );
  }
}
