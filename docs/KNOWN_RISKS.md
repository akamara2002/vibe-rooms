# Known risks

The full register, moved out of `CLAUDE.md`. Every item keeps its original number, so references such as "risk 41" in code comments, tests and commit messages still work. Items 1 to 85 are copied unchanged; 86 and later were added in the polish pass.

**Severity** is the risk that is left today, after any fix: **High** (fix before a public launch, could hurt people or the service), **Medium** (matters at scale or for some users) or **Low** (small, or already fixed). **Plan** says what to do: *fix before a public launch* or *accept for the demo*.

Totals: 92 items, 5 High, 38 Medium, 49 Low.

## Security and privacy

Who can read, write or learn what they should not.

### 6. [Medium] RLS and room join

**RLS and room join.** Every table needs RLS from step 2. Join-by-code should go through an RPC or a narrowly scoped policy, not a world-readable rooms table. 6-character codes need a uniqueness constraint and a retry on collision. Anonymous sign-in must be enabled in the Supabase dashboard.

**Severity:** Medium. **Plan:** fix before a public launch: RLS and RPCs are in place, add join rate limiting (see 13).

### 13. [High] Join-by-code is a bearer secret

**Join-by-code is a bearer secret.** Codes come from a CSPRNG, but there is no rate limit on `join_room` beyond Supabase's anonymous sign-in throttling. 32^6 (about 1 billion) codes make guessing slow, not impossible. Add rate limiting if the app goes public.

**Severity:** High. **Plan:** fix before a public launch: add rate limiting to join_room (or longer codes); today guessing is slow, not impossible.

### 14. [Medium] Profiles are readable by every signed-in user

**Profiles are readable by every signed-in user.** Anonymous sign-in is open, so display names and ids are effectively public. Do not store anything private in `profiles`.

**Severity:** Medium. **Plan:** accept for the demo: never store anything private in profiles; review before a launch.

### 17. [Low] Column grants are part of the contract

**Column grants are part of the contract.** Adding a client-writable column needs both an RLS policy check and a `grant ... (column)`. A client that sends `updated_at`, `host_id`, `sort_key` etc. gets a permission error, by design.

**Severity:** Low. **Plan:** accept: grants are part of the contract, tested by verify_behavior.sql.

### 18. [Medium] SQL was tested on a local PostgreSQL 16 with a stub of the Supabase auth schema, not on Su

**SQL was tested on a local PostgreSQL 16 with a stub of the Supabase `auth` schema**, not on Supabase itself. Run `verify_structure.sql` and `verify_behavior.sql` in the real project before relying on it.

**Severity:** Medium. **Plan:** fix before a public launch: run both verify scripts on the real project (they passed on local PostgreSQL 16 with an auth stub).

### 20. [Medium] New functions are executable by anon by default in Supabase

**New functions are executable by anon by default in Supabase.** Default privileges grant `execute` to `anon` and `authenticated`, so any function added later needs an explicit `revoke ... from public, anon`.

**Severity:** Medium. **Plan:** fix before a public launch: revoke execute from anon on every new function.

### 27. [Medium] Session tokens are stored in plain local storage (localStorage on web, SharedPreferences o

**Session tokens are stored in plain local storage** (`localStorage` on web, SharedPreferences on Android) by `supabase_flutter`. A cross-site scripting bug on web would expose them, and a rooted device can read them. Android auto-backup is disabled (`allowBackup="false"`) so tokens do not leave the device that way. Keep the web build free of untrusted HTML.

**Severity:** Medium. **Plan:** accept for the demo: tokens sit in local storage; keep the web build free of untrusted HTML.

### 28. [Low] Route guards are UX, not security

**Route guards are UX, not security.** The client redirect only decides which screen to show; real access control is Row Level Security in Postgres (tested by `verify_behavior.sql`). Never rely on a route guard to protect data.

**Severity:** Low. **Plan:** accept: route guards are UX, RLS is the real control.

### 29. [Low] Sign-up reveals whether an email is registered ("An account with this email already exists

**Sign-up reveals whether an email is registered** ("An account with this email already exists") when "Confirm email" is off, which is also what Supabase returns. Sign-in errors are deliberately generic. Anonymous sign-in has no CAPTCHA, so guest accounts can be created in bulk (limited only by Supabase's per-IP rate limit).

**Severity:** Low. **Plan:** accept: sign-up reveals registered emails (as Supabase does); sign-in errors are generic.

### 30. [Low] Never log request data

**Never log request data.** Auth code logs only error types and codes; error messages can contain emails and the project URL. Keep it that way, and keep the publishable key (never a `service_role` or secret key) in `env.json`; it is compiled into the app, which is safe only because of RLS.

**Severity:** Low. **Plan:** accept: a rule, enforced in code review (never log request data); the key is a publishable one.

### 32. [High] The room presence channel is public

**The room presence channel is public.** Private Realtime channels need RLS policies on `realtime.messages` (a SQL change). Anyone who knows a room's UUID can join `room:<id>`, read presence payloads (user id, display name, emoji) and spoof an entry for any user id. The UI only shows online dots for people on the member list, and room UUIDs are unguessable, but do not put anything private on this channel. Add private channels and policies before playback sync and reactions go public.

**Severity:** High. **Plan:** fix before a public launch: private Realtime channels with RLS on realtime.messages (presence is public today).

### 45. [Low] AUDIUS_API_KEY is optional and untested, and the key goes into the web bundle

**`AUDIUS_API_KEY` is optional and untested**, and the key goes into the web bundle. Use only a client-side key, never the bearer token.

**Severity:** Low. **Plan:** accept: the API key is optional and untested; use only a client-side key.

### 53. [Medium] The artwork URL in room_state is written by the host and every listener's client loads it

**The artwork URL in `room_state` is written by the host** and every listener's client loads it. The database caps it (https, 2048 characters) but cannot restrict the host, so a malicious host in a room could point it at a server that logs listener IPs. Audius content nodes run on many domains, so a client-side allowlist is not practical; track title and artist are only ever rendered as text.

**Severity:** Medium. **Plan:** fix before a public launch: a malicious host can point artwork at a logging server; proxy or allow-list artwork.

### 57. [Low] The five-tap debug unlock is not a security control; the panel shows only local sync numbe

**The five-tap debug unlock is not a security control**; the panel shows only local sync numbers, no ids or secrets.

**Severity:** Low. **Plan:** accept: the debug panel shows only local numbers, it is not a security control.

### 62. [Medium] Any member controls an artwork URL

**Any member controls an artwork URL.** A queue item's `artwork_url` is written by the adder (the database checks only https and 2048 characters), and every member's client loads it, so a member can point it at a server that logs the IPs of the whole room (extends risk 53, which was host-only). Titles and artists are only ever shown as `Text`.

**Severity:** Medium. **Plan:** fix before a public launch with 53: any member can point a queue item's artwork at a logging server.

### 69. [Medium] Not fixed (needs a decision): member-controlled artwork

**Not fixed (needs a decision): member-controlled artwork.** `artwork_url` in a queue row is chosen by whoever adds it (the database checks only https and length) and every member's client fetches it, so a member with a modified client can learn the IP address of everyone in the room. A client allowlist is not practical: in a sample of 150 Audius results the artwork came from more than 12 third-party content-node domains (`monophonic.digital`, `figment.io`, `audiusindex.org`, `open-audio-validator.com`, `theblueprint.xyz`, `audius.co`, ...) and the set changes. Options: an allowlist that blanks unknown hosts, or a database check when the SQL may change.

**Severity:** Medium. **Plan:** fix before a public launch: member-controlled artwork reveals every member's IP to a modified client (allow-list or database check).

### 70. [Medium] Member-written title, artist and track id are not tied to the audio

**Member-written title, artist and track id are not tied to the audio.** A member can queue a title that does not match the `track_id` that plays (the stream URL is built with path segments, so there is no path injection). The host's "Now playing" row shows what the row says. Re-resolving the track from the catalog on advance would fix it at the cost of one API request per advance.

**Severity:** Medium. **Plan:** fix before a public launch: re-resolve the track from the catalog on advance.

### 74. [Medium] The reactions channel is public

**The reactions channel is public.** Anyone who knows a room's UUID can join `reactions:<roomId>`, send reactions and read them; a broadcast carries no sender identity, so a reaction cannot be attributed or blocked. Strict payload validation and the receive caps (10 new per second, 30 alive) are the only defences. Receivers in a big room drop honest bursts too (the cap is per receiver, so everyone sees a different subset). Private channels would need RLS policies on `realtime.messages` (SQL), see risk 32.

**Severity:** Medium. **Plan:** fix before a public launch: the reactions channel is public (anyone with a room id can send and read); use private channels.

### 79. [Medium] Only control and bidi characters are stripped

**Only control and bidi characters are stripped.** Zalgo text, look-alike characters and long runs of spaces are not handled, and names (1 to 30 characters, no uniqueness) can be duplicated, so a member can impersonate another by display name.

**Severity:** Medium. **Plan:** fix before a public launch: display names are not unique, so a member can copy another's name (a host badge or unique names would help).

### 84. [Low] Fixed: sender names and avatar emoji (written by other members) are cleaned before display

**Fixed:** sender names and avatar emoji (written by other members) are cleaned before display (`sanitizeDisplayText`: one line, no control, bidi or invisible characters, 30 and 16 code points) and the name header is one line; bodies also drop zero-width characters (U+200B, U+2060, U+FEFF, U+00AD, U+3164; the joiners U+200C/D stay for emoji) and an invisible-only body counts as empty; the reaction parser checks that `emoji` is a short string before anything else; a reaction send with no listener opens no channel; a failed reaction channel open or send never reaches the room screen; a failed catch-up read after a rejoin is retried once after 5 s; `Message.toString` no longer prints the body.

**Severity:** Low. **Plan:** fixed: sender names and emoji are cleaned, invisible characters stripped, reaction payload type-checked first.

### 88. [Low] Unknown paths skip the login redirect

**Unknown paths skip the login redirect.** `authRedirect` leaves paths without a route alone, so a signed-out visitor sees "We could not find that page" instead of being sent to login. The page holds no data.

**Severity:** Low. **Plan:** accept: an unknown path shows the not-found page without a login redirect, and it holds no data.

### 91. [Low] The secrets guard scans files, not history

**The secrets guard scans files, not history.** It checks tracked and new files for key prefixes, JWT-like strings and the project URL from env.json.

**Severity:** Low. **Plan:** accept for the demo: tool/check_no_secrets.sh scans the working tree, not git history; run a history scanner (gitleaks) before a public repository.

## Sync

Playback sync, the host's control and the queue advance.

### 1. [Low] Clock skew and updated_at

**Clock skew and `updated_at`.** `updated_at` must be set by Postgres (a `now()` default plus a before-update trigger), never by the client. Clients also need a server-time offset (RPC returning `now()`, corrected by half the round trip). Computing position from the device clock breaks sync on any phone with a skewed clock.

**Severity:** Low. **Plan:** accept for the demo: the server-time offset removes device clock skew (tested at plus and minus 5 minutes).

### 2. [Medium] Seek and drift on streamed audio

**Seek and drift on streamed audio.** `just_audio` seeks on a not-yet-buffered Audius MP3 stream are imprecise and slow. Re-seek only when drift exceeds a threshold (about 300 ms) and ignore small drift, or playback will stutter.

**Severity:** Medium. **Plan:** accept for the demo: drift under 300 ms is left alone, larger drift is corrected with a thrash guard.

### 7. [Low] Concurrent control

**Concurrent control.** Two users pressing play or seek at once is last-write-wins. Decide in step 6 whether only the host controls playback (simplest, recommended for the demo).

**Severity:** Low. **Plan:** accept for the demo: playback is host-only by design.

### 11. [Low] Playback anchor vs foreign keys (fixed)

**Playback anchor vs foreign keys (fixed).** Deleting the playing queue item fires `on delete set null` on `room_state.queue_item_id`, which would run the `room_state_touch` trigger and reset `updated_at`, making every client jump back. The trigger skips the clock bump when `pg_trigger_depth() > 1`; `verify_behavior.sql` check (i) guards this.

**Severity:** Low. **Plan:** fixed: the room_state trigger skips the clock bump for foreign-key changes (guarded by a verify check).

### 15. [Medium] Stranded rooms

**Stranded rooms.** If the host leaves, nobody can control playback (there is no host transfer). Closed rooms still accept chat and queue writes from existing members; only `join_room` checks `closed_at`.

**Severity:** Medium. **Plan:** fix before a public launch: host transfer or a heartbeat; today a host who leaves strands the room.

### 47. [Low] Fixed in the design: the stale-event rule is "strictly older" (an equal updated_at can car

**Fixed in the design:** the stale-event rule is "strictly older" (an equal `updated_at` can carry a foreign-key change); drift is never corrected while the engine is loading or buffering (a stalled position would look like huge drift and cause a seek storm); a hard-limit seek still waits 1 s after the last seek; the one extra drift check after a load clears the thrash guard (it would otherwise block exactly that correction); a new host action clears the thrash guard; `playFrom` starts a measured seek cost ahead; a much worse clock measurement does not replace a good recent one; latency compensation is capped at 1.5 s and not applied to `setTrack`; the host also treats an engine that completed within 2.5 s of the end as the end (Audius `duration` and the real audio length can differ); the host's play and pick-track taps unlock web sound; `AudioEngine` gained `setVolume` for the local mute. Found in review: a failed host write undid the optimistic state even if a newer server row had arrived meanwhile (now it only undoes its own change).

**Severity:** Low. **Plan:** fixed: strictly-older stale rule, no seeks while loading, capped latency compensation.

### 48. [Low] Clock accuracy has a floor

**Clock accuracy has a floor.** The offset assumes the two legs of `server_now()` take equal time; an asymmetric mobile network can bias it by up to half the round trip (measured here: rtt 237 ms to Supabase). The smallest-rtt sample of five limits this but cannot remove it. The browser drift numbers (median 4 ms, max 97 ms) come from two sessions on ONE machine, so they share a device clock and a network path: clock skew is covered by unit tests (plus and minus 5 minutes), not by the browser run, and real phones on mobile data will be worse.

**Severity:** Low. **Plan:** accept: the clock offset has a floor of half the round trip on asymmetric networks.

### 49. [Low] Latency compensation uses the server_now() round trip as a proxy for the write's one-way d

**Latency compensation uses the `server_now()` round trip as a proxy** for the write's one-way delay. The write path (PostgREST, RLS, trigger) can be slower, so the host's write anchor is slightly early or late; the drift correction absorbs it above 300 ms only.

**Severity:** Low. **Plan:** accept: write-latency compensation uses the server_now() round trip as a proxy.

### 52. [Medium] A host who leaves or loses the connection strands the room (risk 15): the row keeps saying

**A host who leaves or loses the connection strands the room** (risk 15): the row keeps saying "playing", so listeners run to the end of the track and show "Ended". There is no heartbeat or host transfer.

**Severity:** Medium. **Plan:** fix before a public launch with 15: the row keeps saying playing when the host is gone (listeners now see a host-offline notice, see 86).

### 56. [Low] Seek cost compensation is an average of the last playFrom durations (capped at 1

**Seek cost compensation is an average** of the last `playFrom` durations (capped at 1.5 s). A track whose first seek is much slower than later ones can start late; the 1.5 s post-load check corrects it.

**Severity:** Low. **Plan:** accept: seek cost is an average; the post-load drift check corrects a slow first seek.

### 58. [Low] Fixed in the design: the advance writes the room row first and marks played second (the or

**Fixed in the design:** the advance writes the room row first and marks played second (the original "mark, write, roll back" could lose a song when the rollback itself failed); every advance also marks the item that just finished and the host reconciles an item that is playing but unmarked, so it cannot replay later; one shared `visibleUpcoming` hides the playing item for the list, the limits, the duplicate check and Next; the limit check reads a fresh list; `playItem` re-checks the item; a skip in flight makes the end-of-song hook answer `failed` (retry), a moved-on room answers `ignored` (never overwrite). Found in testing: a failed mark was remembered as done, so the reconcile never retried it.

**Severity:** Low. **Plan:** fixed: the advance writes the room row first, then marks played; one hidden-by-id rule.

### 60. [Medium] A double advance is guarded, not prevented

**A double advance is guarded, not prevented.** Two host tabs (or devices) are two clients that both detect the end of a song; the in-flight guard and the row comparison are per client. A database-side compare-and-swap (`.eq('updated_at', ...)`) was rejected: on web Dart has millisecond precision while Postgres has microseconds, any host write bumps `updated_at` (so a seek between decision and write would abort the advance), and nothing defines who retries. In the browser run, with two host tabs in one room, exactly one advance happened, but one run does not prove the race cannot occur.

**Severity:** Medium. **Plan:** accept for the demo: a double advance is guarded, not prevented (two host tabs); needs a compare-and-swap design.

### 61. [Medium] The advance runs only while the host's client does

**The advance runs only while the host's client does.** A backgrounded or throttled host tab or phone does not advance when the song ends, and the room sits in "Ended" until the host returns (extends risk 52).

**Severity:** Medium. **Plan:** fix before a public launch: advancing runs only while the host client runs; move it server side.

### 65. [Low] There is a gap between songs on listeners (they load the next track only when the row chan

**There is a gap between songs on listeners** (they load the next track only when the row changes; roughly 1 to 3 seconds). No preloading.

**Severity:** Low. **Plan:** accept for the demo: a 1 to 3 s gap between songs on listeners (no preloading).

### 68. [Low] Found by /review and /cso (fixed): a hung request froze the queue and the host's Next (tim

**Found by /review and /cso (fixed):** a hung request froze the queue and the host's Next (timeouts added); a member-written `duration_ms` of 1 made the host skip the whole queue, and a huge one stalled the room (length bounds added); a persistently failing mark could replay an item (the host now remembers what it started); the Queue tab dropped and rejoined the realtime channel on every tab switch.

**Severity:** Low. **Plan:** fixed: request timeouts, length bounds for queue items, the host remembers what it started.

## Realtime

Realtime channels, reconnects and what is delivered when.

### 5. [Medium] Realtime setup and reconnects

**Realtime setup and reconnects.** The playback table must be in the `supabase_realtime` publication. After any reconnect or app resume, re-read the row, because missed events are not replayed.

**Severity:** Medium. **Plan:** accept for the demo: every rejoin re-reads the row; only verified in a browser (see 33).

### 8. [Low] Reactions volume

**Reactions volume.** Emoji reactions should use Realtime Broadcast (ephemeral), not Postgres rows. Chat messages persist and need pagination or a limit.

**Severity:** Low. **Plan:** accept for the demo: reactions are Broadcast, not rows (but see 74).

### 12. [Medium] Realtime DELETE events

**Realtime DELETE events.** RLS is not applied to DELETE events, and the old record carries only the primary key. Remove rows by id (do not rely on a `room_id` filter for deletes). A `room_members` delete reveals `(room_id, user_id)` to anyone subscribed to that table.

**Severity:** Medium. **Plan:** accept for the demo: removals reload by id; before a launch move to private channels (see 32).

### 31. [Low] Fixed in the design: presence is re-announced after a reconnect (track runs in the subscri

**Fixed in the design:** presence is re-announced after a reconnect (`track` runs in the subscribe status callback); realtime streams guard against late callbacks and release their channel on cancel; presence and member changes use separate channel topics; members notice a closed room because the room is re-read when the member list changes; zero-row writes (RLS) are detected instead of treated as success; the profile is read once so editing it does not rejoin presence; leaving shows a spinner instead of flashing "not found"; `from` uses an allowlist and is dropped after an explicit sign-out. Found in review: widgets must not use `ref` after an `await` (the user may have dismissed the sheet or left the screen), so the sheets, the join screen and the leave flow capture the `ProviderContainer` first; and a room id taken from the URL is checked (`isPlausibleRoomId`) before it reaches a query or realtime filter.

**Severity:** Low. **Plan:** fixed: presence re-announces after a reconnect; channels are released on cancel.

### 34. [Low] Realtime DELETE events are filtered by room_id in practice (verified: a leave updates the

**Realtime DELETE events are filtered by `room_id` in practice** (verified: a leave updates the host's list live), but this is not guaranteed by the Realtime docs. If a member list ever goes stale after a leave, add an unfiltered DELETE binding that reloads when `old_record.room_id` matches.

**Severity:** Low. **Plan:** accept: DELETE events are filtered by room_id in practice; add an unfiltered binding if a list ever goes stale.

### 37. [Low] Every member change reloads the whole member list (debounced 250 ms)

**Every member change reloads the whole member list** (debounced 250 ms). Fine for rooms of dozens; page or patch the list for large rooms.

**Severity:** Low. **Plan:** accept for the demo: rooms of dozens are fine; page the list for big rooms.

### 55. [Low] room_state events are public to the realtime server's RLS only

**`room_state` events are public to the realtime server's RLS only.** Postgres Changes UPDATE events for `room_state` respect RLS (members only), unlike DELETE events (risk 12), and `room_state` rows are never deleted by clients. The presence channel is still public (risk 32).

**Severity:** Low. **Plan:** accept: room_state UPDATE events respect RLS and rows are never deleted by clients.

### 67. [Low] Reload-on-any-event costs one query per change (debounced 250 ms): fine for 50 rows, not f

**Reload-on-any-event costs one query per change** (debounced 250 ms): fine for 50 rows, not for large queues. Realtime DELETE events are not filtered by RLS (risk 12): they only trigger a reload.

**Severity:** Low. **Plan:** accept for the demo: one reload query per change, fine for 50 rows.

### 72. [Low] Fixed in the design: the realtime echo can arrive before send() returns, so both confirm t

**Fixed in the design:** the realtime echo can arrive before `send()` returns, so both confirm the same temp and everything dedupes by id in either order (echo matching prefers still-sending temps, a failed one only if nothing else matches); my unconfirmed messages are pinned at the bottom, so a skewed device clock cannot reorder them; the first join also re-reads (events before the subscribe are not replayed); a window-sized gap after a long absence replaces the history instead of leaving a hole; characters are counted as code points like the database; received bodies are cleaned too (bidi overrides, control characters, newline runs) and compared with the same normalisation as sent ones; a refused send does not consume the rate limit and does not clear the input; one ticker drives all floating emojis; the list is reversed so "at the bottom" is offset 0; every call has a 10 s timeout. Found in testing: `SelectableText(maxLines: 30)` made every one-line bubble 634 px tall. Found in the browser run: the real broadcast payload is flat (`{emoji, event, type}`), so a strict parser built on a guessed nested shape dropped every reaction.

**Severity:** Low. **Plan:** fixed: echo and send dedupe by id in either order, pinned pending messages, code-point counting.

### 75. [Low] If realtime_client changes the shape of a delivered broadcast payload, the strict parser d

**If `realtime_client` changes the shape of a delivered broadcast payload**, the strict parser drops everything silently and reactions stop working without an error. The parser has tests for the flat and the nested shape; re-check it after upgrading the package.

**Severity:** Low. **Plan:** accept: re-check the broadcast payload shape after upgrading realtime_client (the parser has tests for both shapes).

### 81. [Medium] Six realtime channels per client per room (presence, members, room state, queue, chat, rea

**Six realtime channels per client per room** (presence, members, room state, queue, chat, reactions). Check the Supabase plan's channel and connection quotas before a big demo.

**Severity:** Medium. **Plan:** accept for the demo: check the plan's channel quota (six channels per client per room).

### 86. [Low] The host-offline notice rests on presence

**The host-offline notice rests on presence.** Listeners see "The host is offline" when the host's user id has been missing from the online set for 10 seconds (a loading or failed presence stream does not count, and the host never sees it). Presence is public (risk 32).

**Severity:** Low. **Plan:** accept for the demo: the host-offline notice depends on the public presence channel. Someone who knows the room id can fake a presence entry for the host's user id and keep the notice away, and a listener with a bad connection can see it falsely after 10 seconds. It never changes playback..

## Audio and platforms

Audius, the audio engine, browsers and phones.

### 3. [Medium] Web autoplay policy

**Web autoplay policy.** Browsers block audio until a user gesture. A joiner on web cannot auto-start in sync, so show a "Tap to join the music" gate before the first play.

**Severity:** Medium. **Plan:** accept for the demo: the sound gate covers Chrome-style browsers; Safari needs the audio element unlocked inside the tap (see 40).

### 4. [Medium] Audius stream URLs

**Audius stream URLs.** Resolve a host from the Audius discovery endpoint at runtime, pass an app name, and expect redirects, occasional 4xx and rate limits. Handle a track that fails to load without crashing the room.

**Severity:** Medium. **Plan:** accept for the demo: failures show a Retry and never crash the room; re-check the Audius API before launch.

### 9. [Low] Android release build

**Android release build.** `flutter create` puts the INTERNET permission only in the debug and profile manifests. Add it to the main `AndroidManifest.xml` before building a release APK, or the app has no network. Local `flutter doctor` also reports unaccepted Android licenses.

**Severity:** Low. **Plan:** fixed: the INTERNET permission is in the main manifest; keep it that way.

### 33. [Medium] Reconnect and resume are covered by the client's automatic rejoin, but only verified in th

**Reconnect and resume are covered by the client's automatic rejoin, but only verified in the browser.** Android app resume after a long time in the background is untested.

**Severity:** Medium. **Plan:** fix before a public launch: test Android resume after a long background time.

### 36. [Medium] Invite links are web only

**Invite links are web only.** Android has no deep-link intent filter yet, so on a phone the invite is text plus a code. The join link uses the hash route (`/#/join/<CODE>`).

**Severity:** Medium. **Plan:** fix before a public launch: add an Android deep-link intent filter.

### 38. [Low] Dev-server note: the flutter run -d web-server page reloads in a loop when opened at 127

**Dev-server note:** the `flutter run -d web-server` page reloads in a loop when opened at `127.0.0.1` instead of `localhost`. For a second independent browser session, serve a release build (`flutter build web`) on another port.

**Severity:** Low. **Plan:** accept: a dev-server quirk (use localhost, not 127.0.0.1).

### 39. [Low] Fixed in the design: play() must not wait for the track to end (it would hang the controll

**Fixed in the design:** `play()` must not wait for the track to end (it would hang the controller); the engine is built by a factory so a disposed engine is never reused; superseded loads cannot clobber the new track; the sound gate is enforced in the controller; track text is cut by code point to match the database; `Track` cannot hold values the database rejects. Found in the browser run: the track rows and the sound gate were marked as buttons for screen readers but had no tap action (their `InkWell` is excluded from semantics), so a screen-reader user could see them but not activate them; the action now lives on the `Semantics` node, with tests that tap through the semantics tree.

**Severity:** Low. **Plan:** fixed: play() does not wait for the end, engines come from a factory, the sound gate is enforced in the controller.

### 40. [Medium] Safari and iOS web are untested

**Safari and iOS web are untested.** Safari wants each audio element's first `play()` inside a user gesture; the sound gate only covers Chrome-style sticky activation. If Safari matters, create and unlock the audio element inside the gate tap.

**Severity:** Medium. **Plan:** fix before a public launch if Safari or iOS matter: unlock the audio element inside the gate tap.

### 41. [High] Android background and audio focus are not handled (no just_audio_background): playback ma

**Android background and audio focus are not handled** (no `just_audio_background`): playback may continue or stop unpredictably when the app is backgrounded, and other apps' audio focus is not respected.

**Severity:** High. **Plan:** fix before a public launch: background playback and audio focus (just_audio_background).

### 42. [Medium] Seek precision on Android

**Seek precision on Android.** ExoPlayer seeks MP3 streams by an index or a constant-bitrate estimate, which can be imprecise for VBR files without a seek table. Synced playback needs a drift tolerance of a few hundred milliseconds and must measure the real position after a seek.

**Severity:** Medium. **Plan:** accept for the demo: ExoPlayer seeks on VBR MP3 can be imprecise; the drift check corrects it.

### 43. [Medium] The stream URL redirects (302) to a content node on every request, including each range re

**The stream URL redirects (302) to a content node on every request**, including each range request after a seek or rebuffer, so seeking costs API requests. The free plan allows 10 requests per second and 500,000 per month, with no rate-limit headers. A node that is down surfaces as a load error; Retry fetches again, which can resolve a different node.

**Severity:** Medium. **Plan:** accept for the demo: every load and seek costs an Audius request (10 per second on the free plan).

### 44. [High] Audius terms and per-track opt-out

**Audius terms and per-track opt-out.** Creators can opt tracks out of API access, and the API Terms and the Open Music License can change; the API Terms text itself could not be read (only the OML and the announcement post). Treat availability as not guaranteed, and re-read the terms before any commercial use.

**Severity:** High. **Plan:** fix before a public launch: re-read the Audius API Terms and the Open Music License, add the notices, handle opted-out tracks.

### 46. [Low] Response sizes and latency: a 20-result search is about 120 KB, and artwork takes 1 to 2

**Response sizes and latency:** a 20-result search is about 120 KB, and artwork takes 1 to 2.5 seconds to appear from content nodes (a placeholder shows meanwhile). `/browse` cannot hear audio, so playback was verified by the UI state and the real `<audio>` element (`paused`, `currentTime`), not by ear.

**Severity:** Low. **Plan:** accept: search answers are about 120 KB and artwork is slow to appear (a placeholder shows).

### 50. [Medium] Only the host's tap unlocks sound for the host

**Only the host's tap unlocks sound for the host.** A listener on web still needs the gate tap before audio starts (Safari and iOS untested, risks 3 and 40). Listeners in a background browser tab may have audio paused by the browser; the resume handler re-syncs when the tab returns.

**Severity:** Medium. **Plan:** accept for the demo: a web listener still needs one tap; background tabs may be paused by the browser.

### 51. [Medium] Android background playback and audio focus are still not handled (risk 41), so sync on a

**Android background playback and audio focus are still not handled** (risk 41), so sync on a locked phone is best effort. Android resume after a long time in the background is untested (risk 33); the resume handler re-measures the clock and re-reads the row.

**Severity:** Medium. **Plan:** fix before a public launch together with 41: sync on a locked phone is best effort.

### 54. [Medium] The Audius rate limit is shared by all listeners behind one IP

**The Audius rate limit is shared by all listeners behind one IP.** Each load and each seek costs a 302 request; the thrash guard limits one client to about one seek per 5 s, but a whole venue on one network joining at once can still trip 10 requests per second (a failed load is retried every 5 s).

**Severity:** Medium. **Plan:** accept for the demo: a whole venue behind one IP can trip the Audius rate limit.

### 83. [Medium] Untested on a phone: Enter-to-send is for web and desktop only; on Android and iOS Enter i

**Untested on a phone:** Enter-to-send is for web and desktop only; on Android and iOS Enter is a new line and the send button sends. Soft keyboards and IME composition were not tried.

**Severity:** Medium. **Plan:** fix before a public launch: Enter-to-send, IME and soft keyboards are untested on phones.

### 90. [Low] Icons and splash cover Android and web

**Icons and splash cover Android and web.** `tool/generate_icons.py` draws the artwork; `flutter_launcher_icons` and `flutter_native_splash` run with `ios: false`, and the web splash is the page background colour only.

**Severity:** Low. **Plan:** accept for the demo: icons and splash are generated for Android and web only; generate iOS assets before an iOS build.

## Abuse and limits

Limits, quotas and what a modified client can do.

### 16. [High] No size or rate limits on messages or queue items (beyond the 500-char message check), and

**No size or rate limits** on messages or queue items (beyond the 500-char message check), and anonymous users accumulate in `auth.users`. Fine for a demo; add limits and cleanup before real use.

**Severity:** High. **Plan:** fix before a public launch: server-side rate and size limits and cleanup of anonymous users.

### 19. [Low] Abuse limits are enforced in the schema (from /cso)

**Abuse limits are enforced in the schema (from /cso).** `avatar_emoji` is capped at 16 characters, `artwork_url` must be `https://` and at most 2048 characters, and `title`, `artist` and `track_id` are capped (300, 300, 100), because every member's client loads these values. Clients should still show artwork only from the Audius CDN to avoid leaking member IPs to arbitrary hosts.

**Severity:** Low. **Plan:** fixed: length and https caps are in the schema.

### 21. [Medium] Unbounded room creation per user is still possible (needs a counter table to limit); accep

**Unbounded room creation per user** is still possible (needs a counter table to limit); acceptable for the demo.

**Severity:** Medium. **Plan:** fix before a public launch: a counter table; the app now caps hosting at 5 rooms on the client only (see 87).

### 25. [Medium] Anonymous sign-in is rate limited per IP by Supabase, so many guests on one network (a dem

**Anonymous sign-in is rate limited per IP** by Supabase, so many guests on one network (a demo at a venue) can hit "Too many attempts".

**Severity:** Medium. **Plan:** accept for the demo: anonymous sign-in is rate limited per IP; plan for a venue network before a demo.

### 26. [Low] Test accounts accumulate in auth

**Test accounts accumulate** in `auth.users` from development and verification runs; delete them from the dashboard when needed.

**Severity:** Low. **Plan:** accept: delete test accounts from the dashboard now and then.

### 59. [Medium] The limits are client-side only (50 per room, 10 per user, no duplicate upcoming track)

**The limits are client-side only** (50 per room, 10 per user, no duplicate upcoming track). The SQL is frozen, so a modified client can add as many rows as it likes, and two members adding at the same moment can both pass the check. Add a trigger or check constraint when the SQL may change.

**Severity:** Medium. **Plan:** fix before a public launch: a database trigger or check for the queue limits.

### 63. [Low] Played rows are never deleted

**Played rows are never deleted.** `played_at` is set and the row stays, so a long-lived room accumulates rows (the `room_id, sort_key` index keeps the upcoming query cheap).

**Severity:** Low. **Plan:** accept: played rows stay; the upcoming query is indexed.

### 73. [Medium] The chat rate limit is client-side only (1 per second, 20 per minute)

**The chat rate limit is client-side only** (1 per second, 20 per minute). The database has no limit, so a modified client can insert unlimited messages (each at most 500 characters) and every member's client receives each one.

**Severity:** Medium. **Plan:** fix before a public launch: a database rate limit for chat (the client limit is 1 per second and 20 per minute).

### 85. [Medium] Not fixed (needs SQL or a decision): one flooder on the public reactions channel can fill

**Not fixed (needs SQL or a decision):** one flooder on the public reactions channel can fill the shared receive caps and hide honest reactions (risk 74); a member can copy another member's display name (risk 79; a host badge or id suffix would help); a retry after a lost response can post a message twice (risk 77); the sender-name lookup is tried once per user and a failure stays "Someone" for the visit; the "New messages" pill compares list lengths, so it stays hidden once 200 messages are held; a half-typed message is lost when switching tabs; rate limiters and reaction lifetimes use the wall clock, so a backwards clock step can block them until it catches up; a quick leave and re-enter can race the old channel's removal on the same topic (chat and reactions have no refetch for that); Enter during IME composition is untested.

**Severity:** Medium. **Plan:** accept for the demo: reaction flooding, duplicate names, duplicate sends and similar items need SQL or a decision.

### 87. [Medium] The hosted-room cap is client-side only

**The hosted-room cap is client-side only.** A user can host at most 5 open rooms; the check lives in the app (`RoomCreator`). A modified client, or two devices creating at the same moment, can exceed it. Risk 21 still applies.

**Severity:** Medium. **Plan:** fix before a public launch: enforce the 5-room cap in the database; the client check reads a fresh My rooms list but two devices creating at once can pass it.

## UX

Screens, copy and behaviours people notice.

### 10. [Low] Schedule

**Schedule.** Step 6 (synced playback) is the riskiest step. Timebox it, and keep steps 7 and 8 as the cuttable scope if the day runs short.

**Severity:** Low. **Plan:** accept: a schedule note from the build, nothing to fix in the product.

### 22. [Low] Fixed in the design: an unconfigured or failed Supabase

**Fixed in the design:** an unconfigured or failed `Supabase.initialize` no longer crashes the repositories (they are swapped for `Unconfigured…` ones); the auth stream's errors on a failed token refresh are swallowed so the router never gets an unhandled async error; sign-up with "Confirm email" on now says "check your email" instead of doing nothing; the profile cache is per user; a missing profile row is created on demand.

**Severity:** Low. **Plan:** fixed: unconfigured Supabase no longer crashes the app.

### 23. [Low] Deep links through login (fixed in the Rooms step)

**Deep links through login (fixed in the Rooms step).** A deep link opened while signed out now returns to the room after sign-in (see Rooms > Redirect rule).

**Severity:** Low. **Plan:** fixed: deep links return to the room after sign-in.

### 24. [Medium] Guest accounts live in local storage

**Guest accounts live in local storage.** Signing out, clearing site data, or opening the web app on another origin or port starts a new session and loses the guest account. There is no guest-to-email upgrade yet.

**Severity:** Medium. **Plan:** accept for the demo: guest accounts are lost on sign-out; add a guest-to-email upgrade before a launch.

### 35. [Medium] Closing a room stamps closed_at with the client's clock, and members who are already insid

**Closing a room** stamps `closed_at` with the client's clock, and members who are already inside only notice when the member list changes (the host's leave triggers it). The `rooms` table is not in the Realtime publication. Fine for a demo; publish `rooms` if instant close notices are needed. A host cannot leave without closing, so a host who disappears strands the room.

**Severity:** Medium. **Plan:** fix before a public launch: publish rooms so members see a close at once.

### 64. [Low] Adding a song to an idle or ended room does not start it

**Adding a song to an idle or ended room does not start it.** The host sees "Play next" (empty player) or "Next"; nothing auto-starts, by design.

**Severity:** Low. **Plan:** accept: adding a song to an idle room does not start it, by design.

### 66. [Low] The duplicate rule checks upcoming items only, so the song that is playing can be queued a

**The duplicate rule checks upcoming items only**, so the song that is playing can be queued again.

**Severity:** Low. **Plan:** accept: the playing song can be queued again.

### 71. [Low] remove and markPlayed of a row that is already gone look like a permission failure to the

**`remove` and `markPlayed` of a row that is already gone** look like a permission failure to the database contract (an empty result); `remove` now says "That song is no longer in the queue." Foreign-key races (23503) fall to "unknown" and are retried by the end-of-song handler.

**Severity:** Low. **Plan:** accept: remove/markPlayed of a row that is gone reads as a permission failure.

### 76. [Low] Only the newest 50 messages are loaded (and at most 200 kept in memory)

**Only the newest 50 messages are loaded** (and at most 200 kept in memory). There is no "load older", and after a long absence the history before the gap is replaced by the newest window.

**Severity:** Low. **Plan:** accept for the demo: only the newest 50 messages load; no load-older.

### 77. [Low] Send is not idempotent

**Send is not idempotent.** Clients cannot set the message id, so a lost response followed by Retry can post the message twice. The common case (the insert succeeded, the answer was lost) is repaired by the echo, which confirms the failed message; a real duplicate remains possible if the echo is also lost.

**Severity:** Low. **Plan:** accept for the demo: a retry after a lost response can post a message twice.

### 78. [Low] Messages are ordered by created_at (the transaction's start time)

**Messages are ordered by `created_at` (the transaction's start time).** Under concurrent inserts a message can become visible after a later one, so it can appear above messages already read; unread is counted by id, not by position.

**Severity:** Low. **Plan:** accept: messages order by created_at, concurrent inserts can appear out of order.

### 80. [Low] Names of senders: a realtime event has no profile, so a message from someone who is not on

**Names of senders: a realtime event has no profile**, so a message from someone who is not on the member list shows "Someone" until the lookup answers (and stays so if it fails). `profiles` is readable by every signed-in user (risk 14).

**Severity:** Low. **Plan:** accept: a message from someone not on the list shows Someone until a lookup answers.

### 82. [Low] "Chat is visible" means the Chat tab is selected

**"Chat is visible" means the Chat tab is selected.** A hidden browser tab or a locked phone with Chat selected does not count messages as unread. A message that arrives while the reader is scrolled up shifts the visible content (the list keeps its offset from the bottom); the pill offers the way down.

**Severity:** Low. **Plan:** accept: Chat is visible means the Chat tab is selected.

### 89. [Low] Chat drafts are in memory only

**Chat drafts are in memory only.** They survive switching tabs, and are cleared on send and on leaving the room.

**Severity:** Low. **Plan:** accept: the unsent chat message lives in memory and is gone after a reload or leaving the room (by design, nothing is stored on the device).

### 92. [Low] Row actions have generic labels

**Row actions have generic labels.** Their tooltips say what they do but not for which song.

**Severity:** Low. **Plan:** accept: per-row buttons (Play now, Remove, Add) are labelled by action only, not by song title, so a screen reader hears the same label on each row.
