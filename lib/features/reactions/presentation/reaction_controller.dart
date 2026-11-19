import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase_client.dart';
import '../../player/presentation/sync_providers.dart';
import '../data/supabase_reaction_service.dart';
import '../domain/reaction.dart';
import '../domain/reaction_service.dart';

/// At most this many floating emojis at once (extras are dropped).
const maxAliveReactions = 30;

/// At most this many NEW floating emojis from other people per second.
const maxIncomingPerSecond = 10;

/// At most this many reactions SENT per second (extra taps still animate).
const maxSendsPerSecond = 5;

/// How long an emoji floats.
const reactionLifetime = Duration(milliseconds: 2000);

final reactionServiceProvider = Provider<ReactionService>((ref) {
  if (!ref.watch(supabaseReadyProvider)) {
    return const UnconfiguredReactionService();
  }
  return SupabaseReactionService(
    SupabaseReactionTransport(Supabase.instance.client),
  );
});

/// One floating emoji.
class FloatingReaction {
  const FloatingReaction({
    required this.id,
    required this.type,
    required this.bornAt,
    required this.drift,
  });

  final int id;
  final ReactionType type;
  final DateTime bornAt;

  /// Horizontal drift, -1 to 1 (times a few dozen pixels).
  final double drift;
}

class ReactionState {
  const ReactionState({
    this.alive = const [],
    this.pulseCount = 0,
    this.pulseType,
  });

  final List<FloatingReaction> alive;

  /// Counts every reaction seen (sent or received): lets the reaction bar show
  /// a brief static pulse where floating is turned off.
  final int pulseCount;
  final ReactionType? pulseType;
}

/// Sends my reactions (throttled) and turns incoming ones into floating
/// emojis (capped).
class ReactionController extends Notifier<ReactionState> {
  ReactionController(this.roomId);

  final String roomId;

  late ReactionService _service;
  late DateTime Function() _now;
  StreamSubscription<Reaction>? _subscription;
  Timer? _pruneTimer;
  bool _disposed = false;
  int _nextId = 0;
  final _sent = <DateTime>[];
  final _received = <DateTime>[];

  @override
  ReactionState build() {
    _service = ref.read(reactionServiceProvider);
    _now = ref.read(localClockProvider);
    ref.onDispose(() {
      _disposed = true;
      _pruneTimer?.cancel();
      unawaited(_subscription?.cancel());
    });
    _subscription = _service
        .incoming(roomId)
        .listen(
          (reaction) => _spawn(reaction.type, remote: true),
          onError: (Object _) {},
        );
    return const ReactionState();
  }

  /// A tap on a reaction button: it animates at once, and is sent unless more
  /// than [maxSendsPerSecond] were sent in the last second.
  void tap(ReactionType type) {
    _spawn(type, remote: false);
    final now = _now();
    _sent.removeWhere((t) => now.difference(t) >= const Duration(seconds: 1));
    if (_sent.length >= maxSendsPerSecond) return;
    _sent.add(now);
    // Best effort: a lost reaction is fine.
    unawaited(_service.send(roomId, type).catchError((Object _) {}));
  }

  void _spawn(ReactionType type, {required bool remote}) {
    if (_disposed) return;
    final now = _now();
    if (remote) {
      _received.removeWhere(
        (t) => now.difference(t) >= const Duration(seconds: 1),
      );
      if (_received.length >= maxIncomingPerSecond) return;
      _received.add(now);
    }
    final pulse = ReactionState(
      alive: state.alive,
      pulseCount: state.pulseCount + 1,
      pulseType: type,
    );
    if (state.alive.length >= maxAliveReactions) {
      state = pulse;
      return;
    }
    final id = _nextId++;
    state = ReactionState(
      alive: [
        ...state.alive,
        FloatingReaction(
          id: id,
          type: type,
          bornAt: now,
          // Deterministic spread: no random number generator needed.
          drift: ((id * 37) % 100) / 50 - 1,
        ),
      ],
      pulseCount: pulse.pulseCount,
      pulseType: type,
    );
    _pruneTimer ??= Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => _prune(),
    );
  }

  void _prune() {
    if (_disposed) return;
    final now = _now();
    final alive = state.alive
        .where((r) => now.difference(r.bornAt) < reactionLifetime)
        .toList();
    if (alive.length != state.alive.length) {
      state = ReactionState(
        alive: alive,
        pulseCount: state.pulseCount,
        pulseType: state.pulseType,
      );
    }
    if (alive.isEmpty) {
      _pruneTimer?.cancel();
      _pruneTimer = null;
    }
  }
}

final reactionControllerProvider = NotifierProvider.autoDispose
    .family<ReactionController, ReactionState, String>(ReactionController.new);
