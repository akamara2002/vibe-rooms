import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/gradient_background.dart';
import '../domain/room_code.dart';
import '../domain/room_failure.dart';
import 'rooms_providers.dart';

/// `/join/:code`: joins the room, then replaces itself with `/room/<id>`.
class JoinScreen extends ConsumerStatefulWidget {
  const JoinScreen({super.key, required this.code});

  final String code;

  @override
  ConsumerState<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends ConsumerState<JoinScreen> {
  bool _started = false;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addPostFrameCallback((_) => _join());
  }

  Future<void> _join() async {
    if (_started || !mounted) return;
    _started = true; // joining is idempotent, but never run it twice from here
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    final repo = container.read(roomRepositoryProvider);
    final code = normalizeRoomCode(widget.code);

    void fail(RoomFailure failure) {
      if (!mounted) return;
      router.go('/home');
      messenger.showSnackBar(SnackBar(content: Text(failure.message)));
    }

    if (!isValidRoomCode(code)) {
      fail(const RoomFailure(RoomFailureKind.roomNotFound));
      return;
    }
    try {
      final room = await repo.joinRoom(code);
      // `ref` must not be used here: the user may have left this screen.
      container.invalidate(myRoomsProvider);
      // The user may have navigated away while the request ran.
      if (mounted) router.go('/room/${room.id}');
    } on RoomFailure catch (failure) {
      fail(failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 20),
              Text('Joining room…', style: theme.textTheme.titleMedium),
            ],
          ),
        ),
      ),
    );
  }
}
