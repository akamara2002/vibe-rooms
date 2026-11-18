/// Where to send the user after sign-in, taken from `/login?from=...`.
///
/// Only a small allowlist of in-app paths is accepted, so a crafted link can
/// never bounce a user to another site or to an unexpected route:
/// `/home`, `/room/<id>` and `/join/<code>`. Anything else returns null.
final _safeTarget = RegExp(
  r'^/(home|room/[A-Za-z0-9_-]{1,64}|join/[A-Za-z0-9]{1,12})$',
);

String? safeRedirectTarget(String? from) {
  if (from == null) return null;
  return _safeTarget.hasMatch(from) ? from : null;
}

/// The auth redirect rule for go_router.
///
///  * Signed out on a protected path: go to `/login`. A deep link opened while
///    signed out is kept as `?from=` (when it is a safe target). After an
///    explicit sign-out ([wasSignedIn]) it is not kept, so the next person to
///    sign in on this device is not sent to the previous person's room.
///  * Signed in on `/login`: go to `from` if safe, else `/home`.
///
/// The two rules never apply to the same location, so they cannot loop.
String? authRedirect({
  required bool signedIn,
  required Uri uri,
  bool wasSignedIn = false,
}) {
  final onLogin = uri.path == '/login';
  if (!signedIn) {
    if (onLogin) return null;
    final from = '${uri.path}${uri.hasQuery ? '?${uri.query}' : ''}';
    if (wasSignedIn || safeRedirectTarget(from) == null || from == '/home') {
      return '/login';
    }
    return '/login?from=${Uri.encodeQueryComponent(from)}';
  }
  if (onLogin) {
    return safeRedirectTarget(uri.queryParameters['from']) ?? '/home';
  }
  return null;
}
