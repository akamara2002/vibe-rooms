import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/reaction.dart';
import '../domain/reaction_service.dart';

/// Reactions have their own channel topic (a channel can be subscribed once).
String reactionsTopic(String roomId) => 'reactions:$roomId';

/// One open broadcast channel.
abstract class ReactionChannel {
  Future<void> send(Map<String, dynamic> payload);
  Future<void> close();
}

/// Opens broadcast channels, so the service's rules can be tested without a
/// network.
abstract class ReactionTransport {
  ReactionChannel connect(
    String roomId, {
    required void Function(Object? payload) onPayload,
  });
}

class SupabaseReactionTransport implements ReactionTransport {
  SupabaseReactionTransport(this._client);

  final SupabaseClient _client;

  @override
  ReactionChannel connect(
    String roomId, {
    required void Function(Object? payload) onPayload,
  }) {
    // `self: false`: my own reactions are not echoed back to me.
    final channel = _client.channel(
      reactionsTopic(roomId),
      opts: const RealtimeChannelConfig(self: false),
    );
    channel.onBroadcast(event: reactionEvent, callback: onPayload).subscribe((
      status,
      error,
    ) {
      // The client rejoins by itself after a reconnect; nothing to replay.
      if (status == RealtimeSubscribeStatus.channelError ||
          status == RealtimeSubscribeStatus.timedOut) {
        debugPrint('Reactions channel ${status.name}');
      }
    });
    return _SupabaseReactionChannel(_client, channel);
  }
}

class _SupabaseReactionChannel implements ReactionChannel {
  _SupabaseReactionChannel(this._client, this._channel);

  final SupabaseClient _client;
  final RealtimeChannel _channel;

  @override
  Future<void> send(Map<String, dynamic> payload) async {
    // The client adds keys to the map it is given: hand it a copy.
    await _channel.sendBroadcastMessage(
      event: reactionEvent,
      payload: Map<String, dynamic>.of(payload),
    );
  }

  @override
  Future<void> close() async {
    try {
      await _client.removeChannel(_channel);
    } catch (error) {
      debugPrint('Removing reactions channel failed (${error.runtimeType})');
    }
  }
}

class SupabaseReactionService implements ReactionService {
  SupabaseReactionService(this._transport);

  final ReactionTransport _transport;
  final _channels = <String, ReactionChannel>{};
  final _controllers = <String, StreamController<Reaction>>{};

  ReactionChannel _ensure(String roomId) => _channels.putIfAbsent(
    roomId,
    () => _transport.connect(
      roomId,
      onPayload: (payload) {
        final reaction = parseReactionPayload(payload);
        if (reaction != null) _controllers[roomId]?.add(reaction);
      },
    ),
  );

  @override
  Stream<Reaction> incoming(String roomId) {
    late final StreamController<Reaction> controller;
    controller = StreamController<Reaction>.broadcast(
      onListen: () {
        _controllers[roomId] = controller;
        try {
          _ensure(roomId);
        } catch (error) {
          // Reactions are best effort: never take the room screen down.
          debugPrint('Opening reactions channel failed (${error.runtimeType})');
          controller.addError(error);
        }
      },
      onCancel: () async {
        if (_controllers[roomId] != controller) {
          return; // a newer listener owns it
        }
        _controllers.remove(roomId);
        final channel = _channels.remove(roomId);
        await channel?.close();
      },
    );
    return controller.stream;
  }

  @override
  Future<void> send(String roomId, ReactionType type) async {
    // Only while someone listens: otherwise a late tap would open a channel
    // that nothing closes.
    final channel = _channels[roomId];
    if (channel == null) return;
    try {
      await channel.send({'emoji': type.key});
    } catch (error) {
      debugPrint('Sending a reaction failed (${error.runtimeType})');
    }
  }
}

/// Used when Supabase is not configured.
class UnconfiguredReactionService implements ReactionService {
  const UnconfiguredReactionService();

  @override
  Stream<Reaction> incoming(String roomId) => const Stream.empty();

  @override
  Future<void> send(String roomId, ReactionType type) async {}
}
