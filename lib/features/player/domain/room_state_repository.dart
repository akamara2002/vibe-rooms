import 'room_state.dart';
import 'track.dart';

enum RoomStateFailureKind { notAllowed, network, unknown }

class RoomStateFailure implements Exception {
  const RoomStateFailure(this.kind);
  final RoomStateFailureKind kind;

  String get message => switch (kind) {
    RoomStateFailureKind.notAllowed => 'Only the host can control the music.',
    RoomStateFailureKind.network => 'Connection problem. Trying again.',
    RoomStateFailureKind.unknown => 'Something went wrong. Try again.',
  };

  @override
  String toString() => 'RoomStateFailure(${kind.name})';
}

/// What the host writes. Never contains `updated_at`, `updated_by` or
/// `room_id`: the server sets those.
class RoomStateUpdate {
  const RoomStateUpdate._(this._json);

  /// Play, pause or seek: only these two columns change.
  RoomStateUpdate.playback({required bool isPlaying, required int positionMs})
    : this._({'is_playing': isPlaying, 'position_ms': positionMs});

  /// A new track, playing from the start.
  factory RoomStateUpdate.track(Track track) => RoomStateUpdate._(
    // The same shape as RoomState.toUpdateJson, so there is one definition of
    // what the host may write.
    RoomState(
      roomId: '',
      trackId: track.id,
      title: track.title,
      artist: track.artist,
      artworkUrl: track.artworkUrl,
      durationMs: track.durationMs,
      isPlaying: true,
      positionMs: 0,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    ).toUpdateJson(),
  );

  final Map<String, dynamic> _json;

  Map<String, dynamic> toJson() => Map.unmodifiable(_json);
}

abstract class RoomStateRepository {
  Future<RoomState?> get(String roomId);

  /// The current row, then every change. Re-reads after a reconnect, ignores
  /// events older than the newest seen, and reports connection trouble as a
  /// stream error (the stream stays open).
  Stream<RoomState> watch(String roomId);

  /// Host only. Throws [RoomStateFailure] (notAllowed when no row changed).
  Future<void> hostUpdate(String roomId, RoomStateUpdate update);
}

/// Asks the database for its clock (`server_now()`).
abstract class ServerTimeSource {
  Future<DateTime> serverNow();
}
