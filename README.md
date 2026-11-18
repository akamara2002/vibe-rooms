# Vibe Rooms

Friends join a room with a 6-character code and listen to the same [Audius](https://audius.co) track in sync, with a shared queue, live chat and emoji reactions. Built with Flutter and Supabase (Auth, Postgres, Realtime). Android is the main target; web works for quick testing.

> Status: foundation and database layer. The three screens (`/login`, `/home`, `/room/:id`) are still placeholders.

## Setup

1. Install [Flutter](https://docs.flutter.dev/get-started/install) (stable) and run `flutter doctor`. For Android, install the Android SDK and accept licenses (`flutter doctor --android-licenses`).
2. Create a project at [supabase.com](https://supabase.com). In Project Settings > API, copy the project URL and the anon (publishable) key.
3. Copy the example config and fill in your keys:
   ```
   cp env.example.json env.json
   ```
   `env.json` is git-ignored. Never commit it.
4. `flutter pub get`

Without real keys the app still runs and shows a "Supabase is not configured" banner.

## Run

Android (device or emulator):
```
flutter run --dart-define-from-file=env.json
```

Web:
```
flutter run -d chrome --dart-define-from-file=env.json
```
or, without a local Chrome window: `flutter run -d web-server --web-port 8080 --dart-define-from-file=env.json` and open http://localhost:8080.

## Database setup

Run these steps by hand, once per Supabase project:

1. Open the Supabase SQL editor.
2. Run `supabase/migrations/0001_init.sql`.
3. Run `supabase/tests/verify_structure.sql` and read the table: every table should say "RLS on", the app functions should be "security definer", the four realtime tables should be "in supabase_realtime", and "anon grants" should say "none (good)".
4. Run `supabase/tests/verify_behavior.sql` and expect an error starting with `VERIFY_OK`. That error is intentional: the test rolls itself back. An error starting with `VERIFY_FAIL` names the check that failed.
5. Enable Authentication > Sign In / Providers > Allow anonymous sign-ins.
6. Turn off "Confirm email" for development.
7. Copy the Project URL and the publishable key into `env.json` (never the secret or `service_role` key).

To start over during development, run `supabase/migrations/0000_reset_dev.sql` (it deletes all app data), then run `0001_init.sql` again.

## Sign-in

The app opens on a login screen with two ways in:

- **Quick start:** type a display name and tap "Continue as guest". A guest account lives only in this browser or app; signing out loses it.
- **Email:** sign in, or switch to "Create account" (also asks for a display name). If your Supabase project has "Confirm email" on, creating an account asks you to confirm by email first; for development, turn it off (see Database setup).

Your display name and avatar emoji live in your profile: tap the chip at the top right of the home screen to edit them or sign out. Without a configured `env.json` the login screen explains what is missing and sign-in is disabled.

## Develop

```
flutter analyze
flutter test
```

See [CLAUDE.md](CLAUDE.md) for conventions, build order and known risks.
