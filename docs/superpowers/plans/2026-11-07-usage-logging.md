# Usage Logging and Session Review Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Both apps record a detailed per-session event stream, queue it on the phone, upload it to Supabase, and the web editor gets a Sessions page that lists and replays sessions.

**Architecture:** A small `UsageLog` core per platform (session lifecycle, append-only on-disk JSONL queue, batch uploader with retry) with a one-line `UsageLog.log(type, data)` call used at existing hook points. Two insert-only Supabase tables plus a summary view. A pure `web/sessions.js` module (parsing, path segments, timeline, CSV) tested with `node --test`, and the page code in `web/app.js` routing (`#/sessions`, `#/sessions/<id>`).

**Tech Stack:** Swift 5 / SwiftUI / XCTest (XcodeGen project); Kotlin / JUnit 4 / org.json; Supabase PostgREST; vanilla JS + `node --test`.

**Spec:** `docs/superpowers/specs/2026-11-07-usage-logging-design.md`

## Global Constraints

- Supabase project `djfpemdkeguztyuerxqc` (AISEE-BIN's own). URL and publishable key: iOS `ServerConfig` (`AISEEBIN/Managers/MapSyncService.swift:12`), Android `FieldResults.BASE/KEY`, web `SUPABASE_URL` in `web/app.js`. Reuse them; add no new keys.
- Tables are **insert-only** for anon: select + insert policies, no update/delete. Duplicates are dropped with `on_conflict` + `Prefer: resolution=ignore-duplicates` (ON CONFLICT DO NOTHING needs insert privilege only).
- Text and numbers only. No images, audio, or base64 blobs in any event.
- Logging never runs on the main thread for I/O, never throws into callers, never blocks speech/AR/guidance. Every `log` call is fire-and-forget.
- Event names and payload keys below are **identical on iOS and Android**. Keys are snake_case. Positions are map-graph metres `x`, `z` (the editor's `p.x`, `p.z`), heading in radians as the app already uses.
- Session = launch → background/terminate; returning to foreground after **> 300 s** in background starts a new session.
- Pose sampled at **1 Hz** while positioning runs.
- Debug, simulator, and release builds all log; each session row carries `build_config` (`debug`|`release`) and `simulator` (bool).
- Install ID: iOS reuses `ExploreConfig.installID` (`AISEEBIN/Explore/ExploreClient.swift:9`); Android stores a UUID in its existing prefs under `usage.installID`.
- Tests: iOS `xcodebuild test -project AISEE-BIN.xcodeproj -scheme AISEEBIN -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:AISEEBINTests/<Class>` (if xcodebuild fails on the licence shim, see memory note "Xcode licence shim workaround"); run `xcodegen generate` after adding files. Android `cd android && ./gradlew :app:testDebugUnitTest --tests '<Class>'`. Web `node --test web/*.test.js`.

### Event catalogue (the contract)

| type | data keys |
|---|---|
| `app.launch` | `unclean_previous` (session id or null) |
| `app.foreground` / `app.background` / `app.terminate` | — / `seconds_active` / — |
| `staff.unlock` / `staff.exit` | — |
| `settings.changed` | `key`, `old`, `new` |
| `map.loaded` | `slug`, `version`, `name`, `source` (`cache`\|`network`\|`bundle`), `ms` |
| `map.download` | `slug`, `version`, `bytes`, `ms`, `ok`, `error` |
| `mode.enter` / `mode.leave` | `mode` / `mode`, `seconds` |
| `positioning.start` / `positioning.stop` | `source` (`phone`\|`lanyard`\|`glasses`), `localizer` / `source`, `attempts`, `fixes` |
| `speech.heard` | `text`, `via` (`phone`\|`glasses`) |
| `speech.intent` | `text`, `intent`, `args` (object) |
| `speech.said` | `text`, `voice` (`clip`\|`system`), `interrupt` |
| `beacon` | `on` |
| `nav.request` | `to_id`, `to_name`, `path_m` |
| `nav.start` / `nav.off_route` / `nav.reroute` / `nav.waypoint` | — / `distance_m` / `path_m` / `id` |
| `nav.arrived` / `nav.cancel` | `to_id`, `seconds`, `walked_m` / same + `reason` |
| `pose` | `x`, `z`, `heading`, `tracking` (`normal`\|`limited`\|`none`), `localized` |
| `loc.attempt` | `source`, `localizer`, `ok`, `error`, `map_id`, `ms`, `bytes`, `jump_m`, `accepted` |
| `glasses.connect` / `glasses.disconnect` | `battery` / `reason` |
| `explore.plan` | `utterance`, `minutes`, `interests`, `must_see`, `ms`, `ok`, `error` |
| `explore.ask` | `question`, `answer`, `had_image`, `ms`, `ok`, `error` |
| `explore.stop` | `poi_id`, `poi_name` |
| `author.scan` / `author.publish` | `phase` (`start`\|`stop`), `photos` / `slug`, `version`, `ok`, `error` |
| `field.result` | `kind`, `point_id`, `payload` (copy of what goes to `ab_field_results`) |
| `ar.tracking` | `state`, `reason` |
| `error` | `where`, `message` |
| `diag` | `line` |

## Review Focus

1. **App killed mid-session / phone offline for hours** — expected: every event written before the kill reaches Supabase on a later launch, once. Pinned by the queue-survives-reopen and retry-no-duplicate tests (Tasks 2, 5).
2. **Upload fails half-way (HTTP 500/timeout)** — expected: the batch stays queued and is retried; nothing deleted. Pinned in Tasks 2, 5.
3. **Huge or odd payload values** (very long utterance/answer, NaN/infinite floats, non-JSON types) — expected: event still encodes; non-finite numbers become `null`; strings over 4,000 chars truncated. Pinned in Tasks 2, 5.
4. **Session with events but whose header row never arrived, or events out of order** — expected: the page still lists and replays it, ordering by `seq`. Pinned in Task 7.
5. **Map switched mid-session / pose before localisation** — expected: the replay draws each path stretch on the map version loaded at the time and skips `localized: false` samples. Pinned in Task 7.

---

### Task 1: Supabase tables and view

**Files:**
- Modify: `server/schema.sql` (append)

**Interfaces:**
- Produces: tables `ab_sessions(session_id uuid pk, install_id text, platform text, device text, os_version text, app_version text, build_config text, simulator bool, staff bool, started_at timestamptz, received_at timestamptz default now())`, `ab_events(id bigserial pk, session_id uuid not null, seq int not null, t timestamptz not null, type text not null, data jsonb not null default '{}', received_at timestamptz default now(), unique(session_id, seq))`, index on `ab_events(session_id, seq)` and `ab_events(t)`; view `ab_session_summary` (`security_invoker = on`) with `session_id`, all header columns (left join so header-less sessions still appear — build the view from `ab_events` grouped by session_id, left-joined to `ab_sessions`), `first_t`, `last_t`, `duration_s`, `event_count`, `maps text[]` (distinct `data->>'slug'` of `map.loaded`), `modes text[]` (distinct `data->>'mode'` of `mode.enter`), `utterances int`, `arrivals int`, `cancels int`, `fixes int` (`loc.attempt` with `ok`), `attempts int`, `errors int`.
- RLS: select + insert to anon/authenticated on both tables; grant select on the view; grant sequence usage.

- [ ] **Step 1:** Append the SQL to `server/schema.sql` in the style of `ab_field_results` (drop-if-exists policies, comments).
- [ ] **Step 2:** Apply it live: psql through the pooler `aws-0-ap-southeast-1.pooler.supabase.com` **port 6543**, user `postgres.djfpemdkeguztyuerxqc` (password: `flowsxr-hq/infra/README.md` / SUPABASE.md notes).
- [ ] **Step 3: Verify with the publishable key via curl:**
  - POST one `ab_sessions` row and two `ab_events` rows (`session_id` = a fresh UUID, `type` `_probe`) → 201.
  - POST the same events again with `?on_conflict=session_id,seq` and `Prefer: resolution=ignore-duplicates` → 201, and `select count(*)` still 2.
  - PATCH and DELETE on `ab_events` → 0 rows affected / denied.
  - GET `ab_session_summary?session_id=eq.<id>` → one row, `event_count` 2.
  - Remove the probe rows with psql.
- [ ] **Step 4: Commit** `git add server/schema.sql && git commit -m "Usage logging: ab_sessions, ab_events, ab_session_summary"`

### Task 2: iOS UsageLog core

**Files:**
- Create: `AISEEBIN/Usage/UsageLog.swift` (public facade + session lifecycle), `AISEEBIN/Usage/UsageQueue.swift` (on-disk JSONL queue), `AISEEBIN/Usage/UsageUploader.swift` (batch POSTs), `AISEEBIN/Usage/UsageValue.swift`
- Test: `AISEEBINTests/UsageLogTests.swift` (use `TestURLStub.swift` for HTTP)

**Interfaces:**
- Produces:
  - `enum UsageValue: Codable, Equatable` (`string, number, bool, array, object, null`) with `ExpressibleBy…Literal` conformances so call sites write `["slug": "x", "ms": 12]`. Non-finite numbers encode as `null`; strings truncated to 4,000 chars. (Move/reuse `FieldTestClient.JSONValue`: make `FieldTestClient.JSONValue` a typealias of `UsageValue`.)
  - `protocol UsageLogging { func log(_ type: String, _ data: [String: UsageValue]) }` (Task 3 injects it into view models).
  - `final class UsageLog: UsageLogging` with `static let shared`; `func log(_ type: String, _ data: [String: UsageValue] = [:])` (thread-safe, non-blocking, assigns `seq` and `t`), `func appDidLaunch()`, `func appDidEnterForeground()`, `func appDidEnterBackground()`, `func appWillTerminate()`, `var sessionID: UUID`, `func flush() async`.
  - `init(directory: URL, uploader: UsageUploading, now: @escaping () -> Date, header: SessionHeader)` for tests.
  - `struct SessionHeader: Encodable` matching `ab_sessions` columns.
  - `protocol UsageUploading { func upload(sessions: [SessionHeader], events: [QueuedEvent]) async throws }`; `UsageUploader` POSTs sessions then events to `rest/v1/ab_sessions?on_conflict=session_id` and `rest/v1/ab_events?on_conflict=session_id,seq` with `Prefer: resolution=ignore-duplicates,return=minimal`.
  - `UsageQueue(directory:)`: `append(_ line: Data)`, `peekBatch(max: Int) -> [Data]`, `drop(count: Int)`; files under `Application Support/usage/`. Batch size 500 events; flush every 30 s while foreground, on background (with `beginBackgroundTask`), and on launch.
  - Unclean-exit marker: a `running` file holding the session ID, written at launch/foreground, removed on background/terminate; if present at launch, `app.launch.unclean_previous` = its contents.

- [ ] **Step 1: Write failing tests** in `UsageLogTests`:
  - `testSeqIsMonotonicAndTypesRecorded` — log 3 events, flush to a fake uploader → seq 1,2,3 (after `app.launch` = seq 0 if logged by `appDidLaunch`), types in order.
  - `testQueueSurvivesReopen` — log 2 events with an uploader that throws, create a new `UsageLog` on the same directory with a working fake, flush → both events delivered once.
  - `testFailedUploadKeepsBatch` — stub returns 500 → queue still holds all events; next flush with 201 empties it.
  - `testRetryIsIdempotent` — the uploader request carries `on_conflict=session_id,seq` and `Prefer` contains `resolution=ignore-duplicates` (inspect the stubbed `URLRequest`).
  - `testNewSessionAfterLongBackground` — background at t, foreground at t+301 s → new `sessionID`, seq restarts; at t+299 s → same session.
  - `testUncleanExitReported` — launch, no background, launch again → second `app.launch` has `unclean_previous` = first session ID.
  - `testValueEncoding` — `Double.nan` → `null`; 5,000-char string → 4,000 chars.
- [ ] **Step 2:** `xcodegen generate`, run `-only-testing:AISEEBINTests/UsageLogTests` → FAIL (types missing).
- [ ] **Step 3:** Implement the four files to the interfaces above.
- [ ] **Step 4:** Run tests → PASS. Run the full test target once → no regressions (`FieldTestClient` still compiles).
- [ ] **Step 5: Commit** `git commit -m "iOS: UsageLog core (queue, sessions, uploader)"`

### Task 3: iOS instrumentation — app, map, mode, settings, diag

**Files:**
- Modify: `AISEEBIN/Views/ContentView.swift:66` (scenePhase → `appDidEnterForeground/Background`), `AISEEBIN/AISEEBINApp.swift` (`appDidLaunch` in `init`, `UIApplication.willTerminateNotification` → `appWillTerminate`), `AISEEBIN/ViewModels/NavigationViewModel.swift` (`didChange(mode:from:)` :1009 → `mode.leave`/`mode.enter` with seconds; `unlockStaff` :567 / `exitStaffMode` :573; `install(_:)` :616 and `switchMap` :515 → `map.download`/`map.loaded`; `startPositioning` :391 / `stopSession` :740 → `positioning.start/stop`; `didChange(positioningSource:)` :480), `AISEEBIN/Views/SettingsView.swift` (every setting change → `settings.changed`), `AISEEBIN/Managers/Immersal/DiagnosticsLog.swift` (`write` also calls `UsageLog.shared.log("diag", ["line": .string(line)])`).

**Interfaces:**
- Consumes: `UsageLog.shared.log(_:_:)`, lifecycle methods (Task 2).

- [ ] **Step 1: Write failing test** `UsageInstrumentationTests.testModeChangeLogsLeaveAndEnter` — inject a fake `UsageLog` (add `var usage: UsageLogging = UsageLog.shared` to `NavigationViewModel`), set `mode = .explore` from `.navigation` → recorded `mode.leave{mode:"Navigate"}` then `mode.enter{mode:"Explore"}`. Also `testDiagnosticsLogMirrorsToUsage` — `DiagnosticsLog.write("x")` → a `diag` event with `line` "x" (DiagnosticsLog takes an injectable sink).
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Add the calls listed under Files; payload keys exactly per the catalogue.
- [ ] **Step 4:** Run tests → PASS; build for device (`-destination generic/platform=iOS`) succeeds.
- [ ] **Step 5: Commit** `git commit -m "iOS: log app lifecycle, map, mode, settings, diagnostics"`

### Task 4: iOS instrumentation — speech, navigation, pose, positioning, glasses, Explore, authoring

**Files:**
- Modify:
  - `AISEEBIN/Managers/GuidanceManager.swift:85` `speak` → `speech.said` (`voice` = clip if `VoiceClips` played it); beacon on/off → `beacon`.
  - `NavigationViewModel`: `handle(transcript:)` :894 and `handleWelcome(transcript:)` :544 → `speech.heard`; `handle(command:)` :919 / `handle(appCommand:)` :905 → `speech.intent` (unrecognised → `intent: "unknown"`); `startNavigation` :775 → `nav.request` + `nav.start`; `stopNavigation` :822 → `nav.cancel` (`reason`: `user`/`mode_change`/`map_change`); `finishNavigation` :1165 → `nav.arrived`; `replanRoute` :1154 → `nav.reroute`; RouteTracker events in `handle(_ snapshot:)` :1052 → `nav.off_route`, `nav.waypoint`; pose sampler in `handle(_ snapshot:)` throttled to 1 Hz → `pose` (`x`,`z` from `NavigationGeometry.planarPosition` of the anchored transform — verify `.x/.y` map to graph `x/z` against `LiveMapView` drawing; `localized` = `snapshot.trackingReliable`); ARKit tracking state changes → `ar.tracking`. Walked distance = sum of pose-to-pose distances while navigating.
  - `AISEEBIN/Managers/Immersal/PhoneImmersalLocalizer.swift:204` and glasses-fix paths :236–248, `AISEEBIN/Glasses/GlassesFixFeed.swift` → `loc.attempt`.
  - `AISEEBIN/Glasses/GlassesService.swift` connect/disconnect → `glasses.connect/disconnect`.
  - `AISEEBIN/Explore/ExploreClient.swift` `plan` :76 / `ask` :38 → `explore.plan`/`explore.ask` (log on both success and failure; `had_image` = jpeg != nil, never the bytes); `ExploreViewModel` arrival → `explore.stop`.
  - `AISEEBIN/ViewModels/MapAuthoringViewModel.swift` scan start/stop + publish → `author.scan`/`author.publish`; `FieldTestClient.post` → `field.result`.
  - `catch` sites that already surface an error string to the UI → `error`.

**Interfaces:**
- Consumes: `UsageLogging` (Task 3).
- Produces: `struct PoseSampler { init(interval: TimeInterval = 1); mutating func shouldSample(at: Date) -> Bool }` in `AISEEBIN/Usage/PoseSampler.swift`.

- [ ] **Step 1: Write failing tests** in `UsageInstrumentationTests`:
  - `testPoseSamplerOnePerSecond` — samples at 0, 0.4, 1.0, 1.5, 2.1 s → true, false, true, false, true.
  - `testStartAndStopNavigationLogged` — with a test map (as in `NavigationMapTests`), select a POI, `startNavigation()`, `stopNavigation()` → `nav.request{to_id}`, `nav.start`, `nav.cancel{reason:"user"}`.
  - `testHeardAndIntentLogged` — feed transcript "take me to the exit" → `speech.heard{text}` then `speech.intent{intent}`.
  - `testExploreAskLogsFailure` — `ExploreClient.ask` with stub 500 → `explore.ask{ok:false, error, had_image:false}`.
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Add the calls listed under Files.
- [ ] **Step 4:** Run full test target → PASS; device build succeeds.
- [ ] **Step 5: Commit** `git commit -m "iOS: log speech, navigation, pose, positioning, glasses, Explore, authoring"`

### Task 5: Android UsageLog core

**Files:**
- Create: `android/app/src/main/java/com/flowsxr/aiseebin/usage/UsageLog.kt`, `UsageQueue.kt`, `UsageUploader.kt`
- Test: `android/app/src/test/java/com/flowsxr/aiseebin/UsageLogTest.kt`

**Interfaces:**
- Produces: `object Usage { lateinit var log: UsageLog }` initialised in `AiseeApp.onCreate` (main process only); `class UsageLog(dir: File, uploader: UsageUploading, now: () -> Long, header: SessionHeader, executor: Executor)` with `fun log(type: String, data: JSONObject = JSONObject())`, `onForeground()`, `onBackground()`, `onLaunch()`, `fun flushBlocking()`; `interface UsageUploading { fun upload(sessions: List<JSONObject>, events: List<JSONObject>) }`; `UsageUploader` reuses `FieldResults.BASE/KEY` and sends the same `on_conflict` / `Prefer` as iOS. Same queue semantics, batch size, 30 s cadence, 300 s session rule, 4,000-char truncation, NaN → null, unclean-exit marker. Foreground/background from `ProcessLifecycleOwner` (add `androidx.lifecycle:lifecycle-process` if not present).

- [ ] **Step 1: Write failing tests** mirroring Task 2: `seqMonotonic`, `queueSurvivesReopen`, `failedUploadKeepsBatch`, `newSessionAfterLongBackground` (301 s vs 299 s), `uncleanExitReported`, `valueEncoding` (NaN → JSON null, 5,000 → 4,000 chars), `uploaderSendsIgnoreDuplicates` (fake connection factory captures URL and headers).
- [ ] **Step 2:** `./gradlew :app:testDebugUnitTest --tests 'com.flowsxr.aiseebin.UsageLogTest'` → FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Tests → PASS; `./gradlew :app:assembleDebug` succeeds.
- [ ] **Step 5: Commit** `git commit -m "Android: UsageLog core (queue, sessions, uploader)"`

### Task 6: Android instrumentation

**Files:**
- Modify: `android/app/src/main/java/com/flowsxr/aiseebin/AppModel.kt` — `setSource` :78 / `setLocalizerMode` :120 / `setAnnouncePlaces` :510 / `setTokenOverride` :543 (log key only, value `"set"`) → `settings.changed`; `setStaff` :133 → `staff.unlock/exit`; `setVisitorMode` :146 → `mode.leave/enter` (`Navigate`/`Explore`, same strings as iOS); `selectMap` :248 / `downloadMaps` :274 → `map.loaded`/`map.download`; `startPositioning` :290 / `stopPositioning` :404 → `positioning.start/stop`; `handleFix` :209 and failed attempts → `loc.attempt`, and a 1 Hz `pose` from accepted fixes and ARCore frames (`onArFrame` :518) using `PoseSampler`-equivalent logic; `whereAmI` :411 → `speech.intent{intent:"where_am_i", args:{trigger}}`; `speak` :427 → `speech.said`; `check` :453 → `field.result`; `append` :550 → `diag`. `android/.../Speaker.kt` / voice recognition entry → `speech.heard`. Glasses connect/disconnect in `glasses/` → `glasses.connect/disconnect`. Bump `versionCode` to 6, `versionName` `0.2.2`.

**Interfaces:**
- Consumes: `Usage.log.log(type, data)` (Task 5).
- Produces: `class PoseSampler(private val intervalMs: Long = 1000) { fun shouldSample(atMs: Long): Boolean }` in `usage/PoseSampler.kt`.

- [ ] **Step 1: Write failing test** in `UsageLogTest`: `poseSamplerOnePerSecond` (same timings as iOS), and in `CoreLogicTest` style a test that `AppModel`'s pure helper `usageForVisitorMode(old, new)` returns `mode.leave{mode:"Navigate"}`, `mode.enter{mode:"Explore"}` (extract this helper so it's testable without Android).
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Add calls.
- [ ] **Step 4:** Unit tests → PASS; `assembleDebug` succeeds; install on the OnePlus 6 (`adb install -r`), open, switch modes, background, wait 35 s → rows appear in `ab_events` for that session (curl `ab_session_summary?platform=eq.android&order=last_t.desc&limit=1`).
- [ ] **Step 5: Commit** `git commit -m "Android 0.2.2 (versionCode 6): usage logging"`

### Task 7: Web — session data module

**Files:**
- Create: `web/sessions.js` (UMD like `web/align.js`: `module.exports` under node, `window.Sessions` in the browser), `web/sessions.test.js`

**Interfaces:**
- Produces:
  - `sortEvents(events) -> events` (by `seq`).
  - `pathSegments(events) -> [{slug, version, points: [{x, z, t}]}]` — splits at each `map.loaded`, drops `pose` with `localized === false`, and also splits when consecutive localized poses are > 10 s apart (so gaps aren't drawn as straight lines).
  - `fixMarkers(events) -> [{x, z, t, ok, accepted}]` — position = nearest following localized `pose` within 2 s, else omitted.
  - `timeline(events) -> [{t, seq, kind, text}]` with `kind` in `heard|said|nav|mode|loc|explore|error|app|other` and human text (e.g. `Heard: “take me to the exit”`, `Said: “Turn left”`, `Arrived at Exit after 3 m 10 s`).
  - `toCSV(events) -> string` (columns `session_id,seq,t,type,data` with `data` as JSON, RFC 4180 quoting) and `summaryCSV(rows) -> string` for the list.

- [ ] **Step 1: Write failing tests** in `web/sessions.test.js`:
  - out-of-order input → `sortEvents` yields seq 0..n.
  - `pathSegments`: `map.loaded{slug:a,version:1}`, 3 poses, `map.loaded{slug:b,version:2}`, 2 poses → two segments with slugs a/b and 3/2 points; a `localized:false` pose is absent; poses at t=0,1,15 s → split into two segments.
  - header-less session events still produce a timeline (no throw when no `app.launch`).
  - `timeline` text for `speech.heard`, `speech.said`, `nav.arrived{seconds:190}` → `Arrived at … after 3 m 10 s`.
  - `toCSV` quotes a field containing `"`, `,` and a newline.
- [ ] **Step 2:** `node --test web/sessions.test.js` → FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** `node --test web/*.test.js` → all PASS.
- [ ] **Step 5: Commit** `git commit -m "Web: session parsing, paths, timeline, CSV"`

### Task 8: Web — Sessions page, deploy

**Files:**
- Modify: `web/index.html` (a `Sessions` entry in the home header/menu; `<section id="sessions" hidden>` with list view and replay view; `<script src="sessions.js">`), `web/app.js` (`route()` :226 handles `#/sessions` and `#/sessions/<uuid>`; `showView` :231 knows `sessions`), `web/style.css` (v2 look, reuse existing tokens/classes).

**Interfaces:**
- Consumes: `Sessions.*` (Task 7); `rest()` :115, `fetchMaybeGzipped` :138, the map-version fetch in `loadVersion` :324 for drawing a graph.

Behaviour:
- **List:** `GET ab_session_summary?order=last_t.desc&limit=200` (+ "Load more"); columns: started (local time), duration, platform, device, app version, maps, modes, utterances, arrivals/cancels, fixes/attempts, errors; filters (date range, platform, map, mode, install ID, hide debug/simulator — default on); "Export CSV" of the filtered list.
- **Replay:** fetch all events for the session (`ab_events?session_id=eq.<id>&order=seq` paged 1,000 at a time). For each path segment load that map version's graph (`ab_map_versions?map_slug=eq.<slug>&version=eq.<v>`) and draw edges + places on a canvas (reuse the editor's `toScreen` math or a local copy), the walked path as a polyline, fixes as dots (accepted filled, rejected hollow, failed attempts listed only in the timeline). Map selector when the session has more than one segment. Timeline beside it; a scrubber/ clicking a timeline row moves a "you are here" marker to the nearest pose at that time. "Export CSV" and "Export JSON" of the session's events.
- Works at phone width (timeline stacks under the map).

- [ ] **Step 1:** Implement; serve locally (`cd web && python3 -m http.server 8000`) and load a real session produced in Task 4/6 or a probe session inserted with curl containing two maps, unlocalised poses and an error.
- [ ] **Step 2: Verify in a browser** (screenshot): list shows the session with correct counts; replay draws both path segments on the right maps, skips the unlocalised stretch, timeline shows heard/said/error rows; clicking a row moves the marker; CSV downloads open in Numbers with one row per event; 375 px width has no horizontal scroll.
- [ ] **Step 3:** `node --test web/*.test.js` → PASS.
- [ ] **Step 4: Deploy:** back up (`ssh root@104.168.48.121 'cp -a /var/www/aiseebin /var/www/aiseebin.bak-2026-11-07-sessions'`), then `scp -r web/{index.html,app.js,sessions.js,immersal.js,explore.js,align.js,style.css,assets} root@104.168.48.121:/var/www/aiseebin/`; open https://aiseebin.flowsxr.com/#/sessions → loads.
- [ ] **Step 5: Commit** `git commit -m "Web editor: Sessions list and replay"`

### Task 9: End-to-end check and handover

- [ ] **Step 1:** iOS: build and install a Debug build on P.S.K (tokens as in memory `aiseebin-glasses-test-plan`), run a 5-minute session: Welcome → speak a destination → walk → arrive → Explore ask → background. Wait 35 s.
- [ ] **Step 2:** On the Sessions page the session appears with platform ios, the right counts, and the replay shows the walk. Record the real data volume: `select pg_size_pretty(sum(pg_column_size(e.*))) from ab_events e where session_id = '<id>'` → note MB/hour vs the spec's 0.5 MB/hour estimate.
- [ ] **Step 3:** Airplane-mode check: start a session offline, use it 2 min, kill the app, go online, relaunch → the offline session's events arrive once (`event_count` unchanged after a second relaunch).
- [ ] **Step 4:** Update the spec's volume estimate with the measured number, and README's test/run section with the Sessions page URL. Bump iOS build number (`CFBundleVersion`) for the next TestFlight upload.
- [ ] **Step 5: Commit** `git commit -m "Usage logging: measured volume, docs"`
