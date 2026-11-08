# Usage logging and session review — design

Date: 2026-11-07. Status: draft for Prasanth's approval.

## Why

AISEE-BIN is a proof of concept. The real product will be built next year, and the
main thing this POC can hand forward is evidence of how people actually use it: who
opens it, which mode, what they say, where they walk, where positioning fails, where
guidance confuses them. Today almost nothing is recorded centrally — the only usage
data are 9 Explore proxy calls in VPS logs and the map publish history. On-device
`DiagnosticsLog` text files exist but have to be pulled off a phone by cable.

Prasanth's brief: **log as much as possible, for review later.** It's a POC, so no
consent screen, no anonymising, no privacy filtering of content. The log is what
will drive the next design.

## Goals

1. Every run of the iOS app and the Android app records a detailed, timestamped
   event stream and uploads it to the AISEE-BIN Supabase Cloud project
   (`djfpemdkeguztyuerxqc`), tolerant of no connectivity in the dome.
2. A **Sessions** page in the web editor (aiseebin.flowsxr.com) to review it:
   list of sessions, and a replay of one session — walked path drawn on the map,
   Immersal fixes marked, and a timeline of what the visitor said, what the app
   said, and errors.
3. CSV / JSON export of a session (and of the session list) for own analysis.

## Non-goals

- Camera frames, photos, audio recordings. Text and numbers only (Claude's call,
  accepted: storage and upload cost on the free tier).
- Consent, privacy notice, opt-out, PII scrubbing (Prasanth: POC, not needed).
- Live dashboards, aggregate charts, alerting. Review is per-session; aggregates
  can come from the export or SQL.
- Changing app behaviour. Logging must never alter guidance, positioning or UI.

## Anti-goals (would make this a failure even if it "works")

- Logging slows the app, drops ARKit frames, or delays speech/beeps.
- Events are lost when the phone is offline, the app is killed, or upload fails.
- A logging crash or a Supabase outage breaks the app.
- The data can't be tied together: events without a session, sessions without
  map/version, positions in a frame that can't be drawn on the map.

## What gets logged

Each event: `session_id`, `seq` (per session, monotonic), `t` (device time, ms
precision), `type`, `data` (JSON). Each session also carries: anonymous install ID
(reuse the existing `explore.installID` on iOS; same idea on Android), platform,
device model, OS version, app version + build, staff mode on/off at start.

A **session** = one app launch to background/termination. (Claude's call: a
foreground return after more than 5 minutes in the background starts a new session.)

Event families (builder fills in exact type names; the coverage is what matters):

| Family | Examples |
|---|---|
| App | launch, foreground/background, terminate, staff unlock/exit, settings changed (old→new), permission states |
| Map | map loaded (slug, version, source cache/network), map download timing, offline Immersal cache hit/miss |
| Mode | mode entered/left (Welcome, Navigate, Explore, Home, Author, Field test), position source (phone / lanyard / glasses), localizer (on-device / server) |
| Speech in | every recognised utterance (final text, partials optional), parsed command / intent, unrecognised |
| Speech out | every phrase spoken (text, clip vs system voice), beeps/haptics at a coarse level (beacon on/off, not every beep) |
| Navigation | route requested (from, to, path length), started, off-route, rerouted, waypoint reached, arrived, abandoned/cancelled, duration, distance walked |
| Position | pose sample ~1 Hz in **map graph coordinates** (x, y, heading, tracking state), plus every localisation attempt: success/fail, error, map ID, latency, request bytes, jump size, accepted/rejected |
| Glasses | connect/disconnect, battery, frame quality, fix feed, gyro heading |
| Explore | plan request + result, ask question + answer, tour stop arrivals, visit clock |
| Author / field test | scan started/stopped, photo counts, publish attempt/result, field-test checks/marks (already partly in `ab_field_results`) |
| Errors | caught errors with context, ARKit tracking lost/limited, network failures, crash marker on next launch |

Existing `DiagnosticsLog.write(...)` call sites should also flow into the event
stream (as a `diag` event with the line) so nothing currently logged is lost.

Rough volume (Claude's estimate): ~1 Hz pose at ~150 B ≈ 0.5 MB per hour of
use per phone before compression. Fine for the 500 MB free-tier database for a
POC; the builder should check and note the real number after a test session.

## How it's built (decided)

- **On-device first.** Events are appended to a local file/queue immediately
  (off the main thread), then uploaded in batches when online. Upload retries
  with backoff; a batch is deleted locally only after the server confirms it.
  Survives app kill and offline days.
- **Supabase, same project, same pattern as `ab_field_results`:** new tables in
  `server/schema.sql`, RLS with anon insert + anon select (the editor has no auth
  and reads with the publishable key — the same accepted exposure as maps and
  field results; anyone with the editor URL can read the logs).
  Claude's call on shape: an `ab_sessions` table (one row per session, inserted
  once with the session header) and an `ab_events` table (one row per event,
  `jsonb data`, plus a server `received_at`), unique on `(session_id, seq)` so
  retried batches don't duplicate (insert with ignore-duplicates). **Insert-only,
  like the existing tables:** no anon update or delete policy, so nobody with
  the publishable key can overwrite logs. Summary fields (duration, last event
  time, event counts, maps used, arrivals) come from a view over `ab_events`.
- **Maps can change mid-session** (`switchMap`): the map slug + version go on
  every map-loaded event, and the replay draws each stretch of path against the
  graph version loaded at that time.
- **Position before localisation:** log the same map-frame position the guidance
  code uses, with a localised / tracking flag; the replay leaves unlocalised
  stretches unplotted rather than drawing wrong positions.
- **Debug and simulator runs are logged too**, tagged with build config
  (debug/release) and simulator flag, so they can be filtered out in review.
- **Both apps:** iOS (Swift, `AISEEBIN/`) and Android (Kotlin, `android/`).
  Same event names and payload shapes on both.
- **Sessions page in the web editor** (`web/`, plain JS like the rest, deployed by
  scp as in the infra notes): session list with filters (date, platform, map,
  mode, install ID), session replay (map + walked path + fixes + scrubbable
  timeline synced to the path), export buttons.

## Left to the builder

- Exact event type names and payload fields, as long as both platforms match and
  the table above is covered.
- Local queue format (JSONL file vs SQLite) and batch size/interval.
- Whether pose sampling is time-based or distance-based, as long as the path
  replays smoothly.
- Sessions page layout details, matching the editor's v2 look.
- Retention: keep everything for now; note how to prune.
- Tests: unit tests for the queue/upload logic and event encoding on both
  platforms; the web page tested against a recorded session.

## Verification

Verified 2026-11-08 on the iOS Simulator (iPhone 17, debug build, no device):

- A launch followed by backgrounding produced a session row (`platform=ios`, `simulator=true`, `build_config=debug`) in `ab_session_summary` with 11 events; `seq` 0 was `app.launch` and `app.background` was present.
- Terminating the app without backgrounding, then relaunching, gave a new session whose `app.launch` carried `unclean_previous` equal to the terminated session's id. The terminated session's events were present once; counts did not change across further relaunch and background cycles (duplicates dropped by `on_conflict`).
- The Sessions page replay (`#/sessions/<id>`) rendered the simulator session with its timeline and stats.

Still owed:

- A real walk on a device, to measure the actual data volume (MB/hour) against the 0.5 MB/hour estimate above. The estimate is unchanged until then.
- The offline/airplane-mode test (events queued offline arrive once after reconnecting).
- An Android device check of logging.
