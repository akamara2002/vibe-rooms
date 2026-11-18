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

/// Pumps the whole app on a phone-sized surface with the given fakes.
Future<void> pumpApp(
  WidgetTester tester, {
  required FakeAuthRepository auth,
  FakeProfileRepository? profiles,
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
      ],
      child: const VibeRoomsApp(),
    ),
  );
  await tester.pumpAndSettle();
}
