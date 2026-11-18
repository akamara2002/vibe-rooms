import '../domain/room_state.dart';
import '../domain/room_state_repository.dart';

/// Used when Supabase is not configured: nothing to read, nothing to write.
class UnconfiguredRoomStateRepository implements RoomStateRepository {
  const UnconfiguredRoomStateRepository();

  @override
  Future<RoomState?> get(String roomId) async => null;

  @override
  Stream<RoomState> watch(String roomId) => const Stream.empty();

  @override
  Future<void> hostUpdate(String roomId, RoomStateUpdate update) =>
      Future.error(const RoomStateFailure(RoomStateFailureKind.unknown));
}

class UnconfiguredServerTimeSource implements ServerTimeSource {
  const UnconfiguredServerTimeSource();

  @override
  Future<DateTime> serverNow() => Future.error(StateError('not configured'));
}
