import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart' hide EnginePhase;
import 'package:vibe_rooms/app.dart';
import 'package:vibe_rooms/core/supabase_client.dart';
import 'package:vibe_rooms/features/auth/domain/auth_failure.dart';
import 'package:vibe_rooms/features/auth/domain/auth_repository.dart';
import 'package:vibe_rooms/features/auth/domain/profile.dart';
import 'package:vibe_rooms/features/auth/domain/profile_repository.dart';
import 'package:vibe_rooms/features/auth/presentation/auth_providers.dart';
import 'package:vibe_rooms/features/player/domain/audio_engine.dart';
import 'package:vibe_rooms/features/player/domain/audius_failure.dart';
import 'package:vibe_rooms/features/player/domain/music_catalog.dart';
import 'package:vibe_rooms/features/player/domain/room_state.dart';
import 'package:vibe_rooms/features/player/domain/room_state_repository.dart';
import 'package:vibe_rooms/features/player/domain/track.dart';
import 'package:vibe_rooms/features/player/presentation/player_providers.dart';
import 'package:vibe_rooms/features/player/presentation/sync_providers.dart';
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

Track fakeTrack({
  String id = 't1',
  String title = 'Song One',
  String artist = 'Artist One',
  int durationMs = 180000,
  String? artworkUrl,
  String? permalinkUrl,
}) => Track(
  id: id,
  title: title,
  artist: artist,
  durationMs: durationMs,
  artworkUrl: artworkUrl,
  permalinkUrl: permalinkUrl,
);

/// An [AudioEngine] driven by the test. No audio, no plugins.
///
/// With [clock] set, the position advances while playing, like a real engine.
/// [loadDelay] and [seekDelay] make loads and seeks take time.
class FakeAudioEngine implements AudioEngine {
  final calls = <String>[];
  final _phases = StreamController<EnginePhase>.broadcast();
  final _positions = StreamController<Duration>.broadcast();
  final _durations = StreamController<Duration?>.broadcast();

  EnginePhase _phase = EnginePhase.idle;
  Duration _position = Duration.zero;
  DateTime? _playingSince;
  Duration? _duration;
  int _generation = 0;

  DateTime Function()? clock;
  Duration loadDelay = Duration.zero;
  Duration seekDelay = Duration.zero;

  Uri? loadedUrl;
  Duration? loadedInitialPosition;
  bool disposed = false;

  /// Operations running right now, and the most that ever ran at once.
  int inFlight = 0;
  int maxInFlight = 0;

  /// While set, load() waits for it (to test cancellation).
  Completer<void>? loadGate;

  /// If true, the next load() ends in the error phase.
  bool failNextLoad = false;

  Future<void> _op(Future<void> Function() body) async {
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    try {
      await body();
    } finally {
      inFlight--;
    }
  }

  void emitPhase(EnginePhase phase) {
    final now = clock?.call();
    if (_phase == EnginePhase.playing && now != null && _playingSince != null) {
      _position += now.difference(_playingSince!);
    }
    _phase = phase;
    _playingSince = phase == EnginePhase.playing ? now : null;
    _phases.add(phase);
  }

  void emitPosition(Duration position) {
    _position = position;
    if (_phase == EnginePhase.playing) _playingSince = clock?.call();
    _positions.add(position);
  }

  void emitDuration(Duration? duration) {
    _duration = duration;
    _durations.add(duration);
  }

  @override
  Future<void> load(Uri url, {Duration? initialPosition}) => _op(() async {
    calls.add(
      'load:${url.pathSegments.length > 2 ? url.pathSegments[2] : url}',
    );
    final generation = ++_generation;
    loadedUrl = url;
    loadedInitialPosition = initialPosition;
    _position = Duration.zero;
    emitPhase(EnginePhase.loading);
    if (loadGate != null) await loadGate!.future;
    if (loadDelay > Duration.zero) await Future<void>.delayed(loadDelay);
    if (generation != _generation || disposed) return;
    if (failNextLoad) {
      failNextLoad = false;
      emitPhase(EnginePhase.error);
      return;
    }
    emitPhase(EnginePhase.ready);
  });

  @override
  Future<void> play() async {
    calls.add('play');
    emitPhase(EnginePhase.playing);
  }

  @override
  Future<void> playFrom(Duration position) => _op(() async {
    calls.add('playFrom:${position.inMilliseconds}');
    if (seekDelay > Duration.zero) await Future<void>.delayed(seekDelay);
    emitPosition(position);
    emitPhase(EnginePhase.playing);
  });

  @override
  Future<void> pause() async {
    calls.add('pause');
    emitPhase(EnginePhase.paused);
  }

  @override
  Future<void> seek(Duration position) => _op(() async {
    calls.add('seek:${position.inMilliseconds}');
    if (seekDelay > Duration.zero) await Future<void>.delayed(seekDelay);
    emitPosition(position);
  });

  @override
  Future<void> setSpeed(double speed) async => calls.add('speed:$speed');

  double volume = 1;

  @override
  Future<void> setVolume(double volume) async {
    this.volume = volume;
    calls.add('volume:$volume');
  }

  @override
  Duration get position {
    final now = clock?.call();
    if (_phase == EnginePhase.playing && now != null && _playingSince != null) {
      return _position + now.difference(_playingSince!);
    }
    return _position;
  }

  @override
  Stream<Duration> get positionStream => _positions.stream;
  @override
  EnginePhase get phase => _phase;
  @override
  Stream<EnginePhase> get phaseStream => _phases.stream;
  @override
  Duration? get duration => _duration;
  @override
  Stream<Duration?> get durationStream => _durations.stream;

  @override
  Future<void> dispose() async {
    calls.add('dispose');
    disposed = true;
    _generation++;
  }
}

/// A [MusicCatalog] with canned results. No network.
class FakeMusicCatalog implements MusicCatalog {
  FakeMusicCatalog({
    List<Track>? trendingTracks,
    Map<String, List<Track>>? results,
  }) : trendingTracks = trendingTracks ?? [],
       results = results ?? {};

  List<Track> trendingTracks;
  Map<String, List<Track>> results;
  AudiusFailure? trendingFailure;
  AudiusFailure? searchFailure;

  /// If set for a query, search() for it waits for the completer.
  final searchGates = <String, Completer<void>>{};
  final calls = <String>[];

  @override
  Future<List<Track>> search(String query, {int limit = 20}) async {
    calls.add('search:$query');
    final gate = searchGates[query];
    if (gate != null) await gate.future;
    if (searchFailure != null) throw searchFailure!;
    return results[query] ?? [];
  }

  @override
  Future<List<Track>> trending({int limit = 20}) async {
    calls.add('trending');
    if (trendingFailure != null) throw trendingFailure!;
    return trendingTracks;
  }

  @override
  Uri streamUri(String trackId) =>
      Uri.parse('https://audio.test/v1/tracks/$trackId/stream');
}

/// A playback row. Defaults to a room with no track.
RoomState fakeRoomState({
  String roomId = 'room-1',
  String? trackId,
  String? title,
  String? artist,
  int? durationMs,
  bool isPlaying = false,
  int positionMs = 0,
  DateTime? updatedAt,
}) => RoomState(
  roomId: roomId,
  trackId: trackId,
  title: title,
  artist: artist,
  durationMs: durationMs,
  isPlaying: isPlaying,
  positionMs: positionMs,
  updatedAt: updatedAt ?? DateTime.utc(2026, 11, 18, 12),
);

/// An in-memory [RoomStateRepository]. The test plays the server: it emits
/// rows, and (with [autoEcho]) turns each host write into a new row stamped
/// with [serverNow].
class FakeRoomStateRepository implements RoomStateRepository {
  FakeRoomStateRepository({this.current, DateTime Function()? serverNow})
    : serverNow = serverNow ?? (() => DateTime.now().toUtc());

  RoomState? current;
  DateTime Function() serverNow;
  final _controller = StreamController<RoomState>.broadcast();
  final writes = <Map<String, dynamic>>[];
  int watchCount = 0;
  int cancelCount = 0;
  bool autoEcho = true;

  /// If set, the next write fails with this.
  RoomStateFailure? failNext;

  void emit(RoomState state) {
    current = state;
    _controller.add(state);
  }

  void emitError() => _controller.addError(
    const RoomStateFailure(RoomStateFailureKind.network),
  );

  @override
  Future<RoomState?> get(String roomId) async => current;

  @override
  Stream<RoomState> watch(String roomId) {
    watchCount++;
    late final StreamController<RoomState> out;
    StreamSubscription<RoomState>? sub;
    out = StreamController<RoomState>(
      onListen: () {
        final now = current;
        if (now != null) out.add(now);
        sub = _controller.stream.listen(out.add, onError: out.addError);
      },
      onCancel: () {
        cancelCount++;
        return sub?.cancel();
      },
    );
    return out.stream;
  }

  @override
  Future<void> hostUpdate(String roomId, RoomStateUpdate update) async {
    final failure = failNext;
    if (failure != null) {
      failNext = null;
      throw failure;
    }
    final json = update.toJson();
    writes.add(json);
    final row = current;
    if (!autoEcho || row == null) return;
    emit(
      RoomState.fromJson({
        ...row.toJson(),
        ...json,
        'updated_at': serverNow().toUtc().toIso8601String(),
      }),
    );
  }
}

/// A server clock for tests: `server_now()` answers after [rtt] / 2 each way.
class FakeServerTimeSource implements ServerTimeSource {
  FakeServerTimeSource({
    required this.localNow,
    this.skew = Duration.zero,
    this.rtt = const Duration(milliseconds: 40),
  });

  /// The (fake) device clock.
  final DateTime Function() localNow;

  /// Server time minus device time.
  Duration skew;
  Duration rtt;
  int calls = 0;
  bool failing = false;

  DateTime get serverTime => localNow().toUtc().add(skew);

  @override
  Future<DateTime> serverNow() async {
    calls++;
    await Future<void>.delayed(rtt ~/ 2);
    if (failing) throw StateError('offline');
    final answer = serverTime;
    await Future<void>.delayed(rtt ~/ 2);
    return answer;
  }
}

/// Pumps the whole app on a phone-sized surface with the given fakes.
Future<void> pumpApp(
  WidgetTester tester, {
  required FakeAuthRepository auth,
  FakeProfileRepository? profiles,
  FakeRoomRepository? rooms,
  FakeRoomPresence? presence,
  FakeAudioEngine? engine,
  FakeMusicCatalog? catalog,
  FakeRoomStateRepository? roomState,
  bool debugPanel = true,
  bool soundGate = false,
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
        audioEngineFactoryProvider.overrideWithValue(
          () => engine ?? FakeAudioEngine(),
        ),
        musicCatalogProvider.overrideWithValue(catalog ?? FakeMusicCatalog()),
        soundGateRequiredProvider.overrideWithValue(soundGate),
        debugPanelDefaultProvider.overrideWithValue(debugPanel),
        roomStateRepositoryProvider.overrideWithValue(
          roomState ?? FakeRoomStateRepository(),
        ),
        serverTimeSourceProvider.overrideWithValue(
          FakeServerTimeSource(localNow: DateTime.now, rtt: Duration.zero),
        ),
      ],
      child: const VibeRoomsApp(),
    ),
  );
  await tester.pumpAndSettle();
}
