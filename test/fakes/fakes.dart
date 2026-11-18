import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibe_rooms/app.dart';
import 'package:vibe_rooms/core/supabase_client.dart';
import 'package:vibe_rooms/features/auth/domain/auth_failure.dart';
import 'package:vibe_rooms/features/auth/domain/auth_repository.dart';
import 'package:vibe_rooms/features/auth/domain/profile.dart';
import 'package:vibe_rooms/features/auth/domain/profile_repository.dart';
import 'package:vibe_rooms/features/auth/presentation/auth_providers.dart';
import 'package:vibe_rooms/features/rooms/domain/room.dart';
import 'package:vibe_rooms/features/rooms/domain/room_failure.dart';
import 'package:vibe_rooms/features/rooms/domain/room_member.dart';
import 'package:vibe_rooms/features/rooms/domain/room_presence.dart';
import 'package:vibe_rooms/features/rooms/domain/room_repository.dart';
import 'package:vibe_rooms/features/rooms/domain/room_summary.dart';
import 'package:vibe_rooms/features/rooms/presentation/rooms_providers.dart';

/// An in-memory [AuthRepository] with controllable results. No network.
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({this.signedIn = false, this.anonymous = false});

  final _changes = StreamController<bool>.broadcast();
  bool signedIn;
  bool anonymous;

  /// If set, the next sign-in/up/out call fails with this.
  AuthFailure? failNext;

  /// If set, calls wait for it before finishing (to observe loading states).
  Completer<void>? gate;

  final calls = <String>[];

  void setSignedIn(bool value) {
    signedIn = value;
    _changes.add(value);
  }

  Future<void> _act(String call, {bool? signedInAfter}) async {
    calls.add(call);
    if (gate != null) await gate!.future;
    final failure = failNext;
    if (failure != null) {
      failNext = null;
      throw failure;
    }
    if (signedInAfter != null) setSignedIn(signedInAfter);
  }

  @override
  Stream<bool> get signedInChanges => _changes.stream;
  @override
  bool get isSignedIn => signedIn;
  @override
  bool get isAnonymous => anonymous;
  @override
  String? get userId => signedIn ? 'user-1' : null;

  @override
  Future<void> signInAsGuest(String displayName) {
    anonymous = true;
    return _act('guest:$displayName', signedInAfter: true);
  }

  @override
  Future<void> signUpWithEmail(
    String email,
    String password,
    String displayName,
  ) => _act('signUp:$email:$displayName', signedInAfter: true);

  @override
  Future<void> signInWithEmail(String email, String password) =>
      _act('signIn:$email', signedInAfter: true);

  @override
  Future<void> signOut() => _act('signOut', signedInAfter: false);
}

class FakeProfileRepository implements ProfileRepository {
  FakeProfileRepository([Profile? initial])
    : profile =
          initial ??
          const Profile(id: 'user-1', displayName: 'Ana', avatarEmoji: '🎧');

  Profile profile;
  AuthFailure? failUpdate;
  final updates = <({String? displayName, String? avatarEmoji})>[];

  @override
  Future<Profile> getMyProfile() async => profile;

  @override
  Future<Profile> updateMyProfile({
    String? displayName,
    String? avatarEmoji,
  }) async {
    updates.add((displayName: displayName, avatarEmoji: avatarEmoji));
    if (failUpdate != null) throw failUpdate!;
    profile = Profile(
      id: profile.id,
      displayName: displayName ?? profile.displayName,
      avatarEmoji: avatarEmoji ?? profile.avatarEmoji,
    );
    return profile;
  }
}

Room fakeRoom({
  String id = 'room-1',
  String code = 'ABC234',
  String name = 'Test Room',
  String hostId = 'user-1',
  DateTime? closedAt,
}) => Room(
  id: id,
  code: code,
  name: name,
  hostId: hostId,
  createdAt: DateTime.utc(2026, 11, 18),
  closedAt: closedAt,
);

RoomMember fakeMember(
  String userId,
  String name, {
  String roomId = 'room-1',
  bool isHost = false,
  String emoji = '🎧',
  int order = 0,
}) => RoomMember(
  roomId: roomId,
  userId: userId,
  joinedAt: DateTime.utc(2026, 11, 18, 10, order),
  displayName: name,
  avatarEmoji: emoji,
  isHost: isHost,
);

class FakeRoomRepository implements RoomRepository {
  FakeRoomRepository({
    List<RoomSummary>? myRoomsList,
    Map<String, Room>? roomsById,
    Map<String, List<RoomMember>>? members,
  }) : mine = myRoomsList ?? [],
       rooms = roomsById ?? {},
       membersByRoom = members ?? {};

  List<RoomSummary> mine;
  Map<String, Room> rooms;
  Map<String, List<RoomMember>> membersByRoom;

  /// If set, joinRoom fails with this.
  RoomFailure? joinFailure;
  RoomFailure? createFailure;

  /// What joinRoom/createRoom return on success.
  Room? joinResult;
  Room? createResult;

  Completer<Room>? joinGate;
  Completer<Room>? createGate;
  final calls = <String>[];

  @override
  Future<Room> createRoom(String name) async {
    calls.add('create:$name');
    if (createGate != null) return createGate!.future;
    if (createFailure != null) throw createFailure!;
    return createResult ?? fakeRoom(name: name);
  }

  @override
  Future<Room> joinRoom(String code) async {
    calls.add('join:$code');
    if (joinGate != null) return joinGate!.future;
    if (joinFailure != null) throw joinFailure!;
    return joinResult ?? fakeRoom(code: code);
  }

  @override
  Future<List<RoomSummary>> myRooms() async => mine;

  @override
  Future<Room?> getRoom(String id) async => rooms[id];

  @override
  Stream<List<RoomMember>> watchMembers(String roomId) =>
      Stream.value(membersByRoom[roomId] ?? const []);

  @override
  Future<void> leaveRoom(String roomId) async {
    calls.add('leave:$roomId');
    mine = mine.where((s) => s.room.id != roomId).toList();
  }

  @override
  Future<void> closeRoom(String roomId) async {
    calls.add('close:$roomId');
    mine = mine.where((s) => s.room.id != roomId).toList();
  }
}

class FakeRoomPresence implements RoomPresence {
  FakeRoomPresence([this.online = const {}]);

  Set<String> online;

  @override
  Stream<Set<String>> watchOnlineUserIds(String roomId, Profile me) =>
      Stream.value(online);
}

/// Pumps the whole app on a phone-sized surface with the given fakes.
Future<void> pumpApp(
  WidgetTester tester, {
  required FakeAuthRepository auth,
  FakeProfileRepository? profiles,
  FakeRoomRepository? rooms,
  FakeRoomPresence? presence,
  bool ready = true,
}) async {
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        supabaseReadyProvider.overrideWithValue(ready),
        authRepositoryProvider.overrideWithValue(auth),
        profileRepositoryProvider.overrideWithValue(
          profiles ?? FakeProfileRepository(),
        ),
        roomRepositoryProvider.overrideWithValue(rooms ?? FakeRoomRepository()),
        roomPresenceProvider.overrideWithValue(presence ?? FakeRoomPresence()),
      ],
      child: const VibeRoomsApp(),
    ),
  );
  await tester.pumpAndSettle();
}
