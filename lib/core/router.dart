import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/domain/auth_repository.dart';
import '../features/auth/presentation/auth_providers.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/rooms/presentation/home_screen.dart';
import '../features/rooms/presentation/join_screen.dart';
import '../features/rooms/presentation/room_screen.dart';
import 'redirect.dart';

/// Tells the router to re-run its redirect whenever the auth state changes.
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(Stream<bool> changes) {
    _subscription = changes.listen((_) => notifyListeners());
  }

  late final StreamSubscription<bool> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

GoRouter createRouter(AuthRepository auth, Listenable refresh) {
  var wasSignedIn = auth.isSignedIn;
  return GoRouter(
    initialLocation: '/login',
    refreshListenable: refresh,
    redirect: (_, state) {
      final signedIn = auth.isSignedIn;
      final target = authRedirect(
        signedIn: signedIn,
        uri: state.uri,
        wasSignedIn: wasSignedIn,
      );
      if (signedIn) wasSignedIn = true;
      return target;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
      GoRoute(
        path: '/room/:id',
        builder: (_, state) => RoomScreen(id: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/join/:code',
        builder: (_, state) => JoinScreen(code: state.pathParameters['code']!),
      ),
    ],
  );
}

final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authRepositoryProvider);
  final refresh = _AuthRefresh(auth.signedInChanges);
  final router = createRouter(auth, refresh);
  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
});
