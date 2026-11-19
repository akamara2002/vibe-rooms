import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../domain/reaction.dart';
import 'reaction_controller.dart';

/// Six reaction buttons, under the player card, for everyone.
class ReactionBar extends ConsumerStatefulWidget {
  const ReactionBar({super.key, required this.roomId});

  final String roomId;

  @override
  ConsumerState<ReactionBar> createState() => _ReactionBarState();
}

class _ReactionBarState extends ConsumerState<ReactionBar> {
  /// Where floating is turned off (reduced motion), the button of the latest
  /// reaction is highlighted for a moment instead.
  ReactionType? _pulsed;
  Timer? _pulseTimer;

  @override
  void dispose() {
    _pulseTimer?.cancel();
    super.dispose();
  }

  void _pulse(ReactionType? type) {
    if (type == null) return;
    setState(() => _pulsed = type);
    _pulseTimer?.cancel();
    _pulseTimer = Timer(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _pulsed = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final controller = ref.read(
      reactionControllerProvider(widget.roomId).notifier,
    );
    ref.listen(reactionControllerProvider(widget.roomId), (previous, next) {
      if (MediaQuery.disableAnimationsOf(context) &&
          next.pulseCount != previous?.pulseCount) {
        _pulse(next.pulseType);
      }
    });
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (final type in ReactionType.values)
          Semantics(
            button: true,
            label: 'Send ${type.label} reaction',
            onTap: () => controller.tap(type),
            child: ExcludeSemantics(
              child: Material(
                color: _pulsed == type
                    ? scheme.primaryContainer
                    : scheme.surfaceContainerHigh,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => controller.tap(type),
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: Center(
                      child: Text(
                        type.emoji,
                        style: const TextStyle(fontSize: 24),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
