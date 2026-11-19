import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../domain/hosted_cap.dart';
import '../domain/room.dart';
import '../domain/room_failure.dart';
import '../domain/room_repository.dart';
import 'rooms_providers.dart';

/// Creates a room, unless I already host [maxHostedRooms] open ones.
///
/// The count comes from a FRESH read of "My rooms" (the cached list may be
/// stale, for example right after closing a room on another device).
class RoomCreator {
  RoomCreator(this._repo, this._myId);

  final RoomRepository _repo;
  final String? Function() _myId;

  Future<Room> create(String name) async {
    final mine = await _repo.myRooms();
    if (hostedRoomCount(mine, _myId()) >= maxHostedRooms) {
      throw const RoomFailure(RoomFailureKind.tooManyHosted);
    }
    return _repo.createRoom(name);
  }
}

final roomCreatorProvider = Provider<RoomCreator>(
  (ref) => RoomCreator(
    ref.watch(roomRepositoryProvider),
    () => ref.read(authRepositoryProvider).userId,
  ),
);
