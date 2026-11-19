import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../player/presentation/sync_providers.dart';
import 'reaction_controller.dart';

/// Emojis rising over the player card: about 120 px with a small drift, fading
/// out over about 2 seconds. It never takes a tap, and nothing floats where the
/// system asks for reduced motion.
///
/// One ticker drives every emoji (no animation controller each), and nothing
/// ticks while nothing floats.
class ReactionOverlay extends ConsumerStatefulWidget {
  const ReactionOverlay({super.key, required this.roomId});

  final String roomId;

  @override
  ConsumerState<ReactionOverlay> createState() => _ReactionOverlayState();
}

class _ReactionOverlayState extends ConsumerState<ReactionOverlay>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker((_) => setState(() {}));

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _syncTicker(bool anyAlive) {
    if (anyAlive && !_ticker.isActive) {
      _ticker.start();
    } else if (!anyAlive && _ticker.isActive) {
      _ticker.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(reactionControllerProvider(widget.roomId));
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final show = !reduceMotion && state.alive.isNotEmpty;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncTicker(show);
    });
    if (!show) return const SizedBox.shrink();

    final now = ref.read(localClockProvider)();
    return IgnorePointer(
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  for (final reaction in state.alive)
                    _floating(reaction, now, width),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _floating(FloatingReaction reaction, DateTime now, double width) {
    final elapsed = now.difference(reaction.bornAt).inMilliseconds;
    final t = (elapsed / reactionLifetime.inMilliseconds).clamp(0.0, 1.0);
    return Positioned(
      left: width / 2 - 16 + reaction.drift * 40 * (0.4 + t),
      bottom: 12 + 120 * Curves.easeOut.transform(t),
      child: Opacity(
        opacity: (1 - t * t).clamp(0.0, 1.0),
        child: Text(reaction.type.emoji, style: const TextStyle(fontSize: 32)),
      ),
    );
  }
}
