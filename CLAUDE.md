# Vibe Rooms

Flutter app where friends join a room with a 6-character code and listen to the same Audius track in sync, with a shared queue, live chat and emoji reactions. Must be demo-ready in one day: keep scope tight.

## Stack
- Flutter (Android primary, web for quick testing), Dart
- Supabase: Auth, Postgres, Realtime (`supabase_flutter`)
- State: `flutter_riverpod`; routing: `go_router`
- Audio: `just_audio`; Audius via `http`; images via `cached_network_image`
- Tests: `flutter_test`, `mocktail`

## Playback sync design
One Postgres row per room holds playback state (`track_id`, `is_playing`, `position_ms`, server-side `updated_at`). Every client listens through Supabase Realtime and computes its own position from the server timestamp.

## Folder conventions
Feature-first. Each feature (`auth`, `rooms`, `player`, `queue`, `chat`) lives in `lib/features/<name>/` with:
- `data/`: repositories and data sources
- `domain/`: models and pure logic
- `presentation/`: screens, widgets, providers

Shared code is in `lib/core/` (`config.dart`, `router.dart`, `theme.dart`, `supabase_client.dart`, `widgets/`). Keep a `.gitkeep` in empty folders.

## Rules
- **All Supabase calls go through repository classes in each feature's `data/` folder, never directly from widgets.**
- Riverpod for state. No business logic in widgets.
- Never commit secrets. `env.json` is git-ignored; `env.example.json` is the template.
- The app must not crash when Supabase is unconfigured (`config.isConfigured` is false): screens show a banner.

## Commands
- Run: `flutter run --dart-define-from-file=env.json` (web: add `-d web-server --web-port 8080` or `-d chrome`)
- Analyze: `flutter analyze` (must report zero issues)
- Test: `flutter test`
- Format: `dart format lib test`

## Commits
Conventional commits: `feat:`, `fix:`, `chore:`, `docs:`, `refactor:`, `test:`.

## Build order
1. Setup
2. Schema
3. Auth
4. Rooms
5. Audio
6. Synced playback
7. Queue
8. Chat and reactions
9. Polish and ship

Do not expand scope beyond this list.

## Known risks

Raised by /plan-eng-review (condensed, risks-only run; design and build order accepted unchanged).

1. **Clock skew and `updated_at`.** `updated_at` must be set by Postgres (a `now()` default plus a before-update trigger), never by the client. Clients also need a server-time offset (RPC returning `now()`, corrected by half the round trip). Computing position from the device clock breaks sync on any phone with a skewed clock.
2. **Seek and drift on streamed audio.** `just_audio` seeks on a not-yet-buffered Audius MP3 stream are imprecise and slow. Re-seek only when drift exceeds a threshold (about 300 ms) and ignore small drift, or playback will stutter.
3. **Web autoplay policy.** Browsers block audio until a user gesture. A joiner on web cannot auto-start in sync, so show a "Tap to join the music" gate before the first play.
4. **Audius stream URLs.** Resolve a host from the Audius discovery endpoint at runtime, pass an app name, and expect redirects, occasional 4xx and rate limits. Handle a track that fails to load without crashing the room.
5. **Realtime setup and reconnects.** The playback table must be in the `supabase_realtime` publication. After any reconnect or app resume, re-read the row, because missed events are not replayed.
6. **RLS and room join.** Every table needs RLS from step 2. Join-by-code should go through an RPC or a narrowly scoped policy, not a world-readable rooms table. 6-character codes need a uniqueness constraint and a retry on collision. Anonymous sign-in must be enabled in the Supabase dashboard.
7. **Concurrent control.** Two users pressing play or seek at once is last-write-wins. Decide in step 6 whether only the host controls playback (simplest, recommended for the demo).
8. **Reactions volume.** Emoji reactions should use Realtime Broadcast (ephemeral), not Postgres rows. Chat messages persist and need pagination or a limit.
9. **Android release build.** `flutter create` puts the INTERNET permission only in the debug and profile manifests. Add it to the main `AndroidManifest.xml` before building a release APK, or the app has no network. Local `flutter doctor` also reports unaccepted Android licenses.
10. **Schedule.** Step 6 (synced playback) is the riskiest step. Timebox it, and keep steps 7 and 8 as the cuttable scope if the day runs short.
