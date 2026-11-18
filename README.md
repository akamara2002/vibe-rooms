# Vibe Rooms

Friends join a room with a 6-character code and listen to the same [Audius](https://audius.co) track in sync, with a shared queue, live chat and emoji reactions. Built with Flutter and Supabase (Auth, Postgres, Realtime). Android is the main target; web works for quick testing.

> Status: project foundation only. The three screens (`/login`, `/home`, `/room/:id`) are placeholders.

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

## Develop

```
flutter analyze
flutter test
```

See [CLAUDE.md](CLAUDE.md) for conventions, build order and known risks.
