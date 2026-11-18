import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/domain/auth_repository.dart';
import '../features/auth/presentation/auth_providers.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/rooms/presentation/home_screen.dart';
import '../features/rooms/presentation/room_screen.dart';

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

/// Signed out: only /login. Signed in: everything except /login.
///
/// The two rules are mutually exclusive, so a redirect can never loop.
String? authRedirect({required bool signedIn, required String location}) {
  final onLogin = location == '/login';
  if (!signedIn && !onLogin) return '/login';
  if (signedIn && onLogin) return '/home';
  return null;
}

GoRouter createRouter(AuthRepository auth, Listenable refresh) {
  return GoRouter(
    initialLocation: '/login',
    refreshListenable: refresh,
    redirect: (_, state) => authRedirect(
      signedIn: auth.isSignedIn,
      location: state.matchedLocation,
    ),
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
      GoRoute(
        path: '/room/:id',
        builder: (_, state) => RoomScreen(id: state.pathParameters['id']!),
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
