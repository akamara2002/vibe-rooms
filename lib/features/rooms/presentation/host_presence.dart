import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'rooms_providers.dart';

/// How long the host must be missing from the room's presence before listeners
/// are told. Presence flickers while a client reconnects, so a short absence
/// is not an absence.
const hostOfflineGrace = Duration(seconds: 10);

/// Overridable in tests.
final hostOfflineGraceProvider = Provider<Duration>((_) => hostOfflineGrace);

typedef HostWatchArgs = ({String roomId, String hostId, bool isHost});

/// True when a LISTENER has seen the host missing from the online set for
/// [hostOfflineGrace]. It never turns true for the host, and a loading or
/// failing presence stream proves nothing: only a real set that lacks the host
/// starts the clock. It never touches playback.
final hostOfflineProvider = NotifierProvider.autoDispose
    .family<HostOfflineNotifier, bool, HostWatchArgs>(HostOfflineNotifier.new);

class HostOfflineNotifier extends Notifier<bool> {
  HostOfflineNotifier(this.args);

  final HostWatchArgs args;
  Timer? _timer;

  @override
  bool build() {
    ref.onDispose(() => _timer?.cancel());
    if (args.isHost) return false; // the host never sees the notice
    ref.listen<AsyncValue<Set<String>>>(onlineUsersProvider(args.roomId), (
      _,
      next,
    ) {
      final online = next.value;
      if (online == null) return; // loading or error: unknown, not offline
      if (online.contains(args.hostId)) {
        _timer?.cancel();
        _timer = null;
        state = false;
      } else if (!state && _timer == null) {
        _timer = Timer(ref.read(hostOfflineGraceProvider), () {
          _timer = null;
          state = true;
        });
      }
    }, fireImmediately: true);
    return false;
  }
}
