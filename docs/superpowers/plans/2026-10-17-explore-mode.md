# Explore Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A light, public-facing Explore mode in the iOS app: pick a time, get a planned Flower Dome tour, be guided stop to stop, and tap-and-ask about what the camera sees.

**Architecture:** New code in `AISEEBIN/Explore/` drives the existing `NavigationViewModel` (positioning, A*, route tracking) through four small hooks. A pure `TourPlanner` picks and orders stops. A Node proxy on the FlowsXR VPS (`server/explore/`) holds the Claude key and serves `/explore/ask` (streamed text) and `/explore/plan` (JSON).

**Tech Stack:** Swift 5 / SwiftUI / ARKit / XCTest; Node 22 + `@anthropic-ai/sdk`, `node --test`, Docker, Caddy; vanilla JS web editor.

**Spec:** `docs/superpowers/specs/2026-10-17-explore-mode-design.md`

## Global Constraints

- iOS 17, SwiftUI, `project.yml` is the source of truth; regenerate with `xcodegen generate`, never hand-edit the `.pbxproj`.
- Do not modify anything under `AISEEBIN/Glasses/` or `AISEEBIN/Managers/Immersal/`.
- Navigate, Author, Field Test and Settings must behave exactly as before. Explore never writes to `guidance.beacon` or any other saved Navigate setting.
- All new map JSON keys are optional; old maps decode unchanged and re-encode without the new keys when absent.
- Light theme (`DS.A` tokens), one accent `#6B4FD8` (`DS.N.talk`), no debug text, badges or mode switcher on Explore screens.
- Model `claude-opus-5-5`, effort `low`; model id and effort come from the proxy env (`EXPLORE_MODEL`, `EXPLORE_EFFORT`).
- Proxy limits: 60 asks per install per hour, 2,000 calls per day overall, `EXPLORE_ENABLED=0` disables both routes (HTTP 503).
- Images are never stored. Logs: `/var/lib/aiseebin-explore/log-YYYY-MM-DD.jsonl`, files older than 30 days deleted.
- Stroll pace 0.7 m/s; default dwell 3 min; default highlight 2; plan to ≤ 90% of the budget; late offer when > 3 min behind.
- Welcome-screen notice, verbatim: "Your questions are answered by AI. We keep the words, not the photos, to improve the guide."
- Deviation from spec, today only: Explore uses whatever map is installed; staff load `labeltransfertest` with the existing Author map picker before handing the phone over.

## Review Focus

1. A map with no `tourStart`, no `entrance` id and no exhibits (e.g. the bundled sample) → Explore still opens, says "This map has no tour yet", never crashes.
2. Budget smaller than the walk from start to end → plan with zero stops that still goes start → end, preview shows "Straight to the end · about N min".
3. Ask pressed before positioning is reliable → the question still goes out with no nearby places, and the answer still arrives.
4. Proxy down / 503 / 10 s timeout → "Sorry, I couldn't answer that just now." shown and spoken; the visit continues.
5. Visitor taps Ask while a guidance or stop description is being spoken → speech stops, listening starts; answer speech is cancelled when the Ask screen closes.

---

### Task 1: Map content fields

**Files:**
- Modify: `AISEEBIN/Models/NavigationMap.swift`
- Test: `AISEEBINTests/ExploreMapFieldsTests.swift`

**Interfaces:**
- Produces on `NavigationPOI`: `var minutes: Double?`, `var highlight: Int?`, `var tags: [String]` (default `[]`), `var about: String?`, `var photo: String?`; computed `var visitMinutes: Double { minutes ?? 3 }`, `var highlightLevel: Int { highlight ?? 2 }`. JSON keys: `minutes`, `highlight`, `tags`, `about`, `photo`.
- Produces on `NavigationMap`: `var tourStart: String?`, `var tourEnd: String?`, `var venueInfo: String?` (same JSON keys), encoded with `encodeIfPresent`.

- [ ] **Step 1: Write failing tests**: `testOldPOIJSONDecodesWithDefaults` (no new keys → `visitMinutes == 3`, `highlightLevel == 2`, `tags == []`); `testNewPOIFieldsRoundTrip` (`minutes: 4.5, highlight: 0, tags: ["orchids"], about: "x", photo: "p.jpg"` survive encode→decode); `testMapTourFieldsRoundTrip` (`tourStart: "point-a", tourEnd: "point-3", venueInfo: "v"`); `testMapWithoutTourFieldsEncodesWithoutKeys` (encoded JSON has no `tourStart` key). POI encoding is synthesized today: add the new keys to `CodingKeys` and make sure absent optionals are not written as `null` (custom `encode(to:)` with `encodeIfPresent`, `tags` only when non-empty).
- [ ] **Step 2: Run, expect FAIL:** `xcodebuild test -project AISEE-BIN.xcodeproj -scheme AISEEBIN -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:AISEEBINTests/ExploreMapFieldsTests`
- [ ] **Step 3: Implement** the fields, coding keys, decoding defaults and `encodeIfPresent`.
- [ ] **Step 4: Run the new tests plus `NavigationMapTests`, expect PASS.**
- [ ] **Step 5: Commit** `Explore: tour and content fields on places and maps`

### Task 2: TourPlanner

**Files:**
- Create: `AISEEBIN/Explore/TourPlanner.swift`
- Test: `AISEEBINTests/TourPlannerTests.swift`

**Interfaces:**
- Consumes: Task 1 fields; `PathfindingEngine(map:)`, `findPath(from:to:) -> [GKGraphNode2D]` (positions via `node.position`).
- Produces:
  ```swift
  struct TourRequest { var minutes: Double; var interests: [String] = []; var mustSee: [String] = [] }
  struct TourPlan: Equatable { var startID: String; var endID: String; var stopIDs: [String]; var walkMinutes: Double; var dwellMinutes: Double; var totalMinutes: Double { walkMinutes + dwellMinutes } }
  struct TourPlanner {
      static let strollSpeed: Double = 0.7     // m/s
      static let budgetFraction: Double = 0.9
      init(map: NavigationMap)
      var startID: String? ; var endID: String?          // resolved per spec §3
      var candidates: [NavigationPOI]                    // exhibits, connected, not start/end, highlight != 0
      func plan(_ request: TourRequest) -> TourPlan?     // nil only when there is no start
      func evaluate(stopIDs: [String]) -> TourPlan?      // keeps the given order; nil if a leg is unreachable
      func removing(_ id: String, from plan: TourPlan) -> TourPlan
      func adding(_ id: String, to plan: TourPlan) -> TourPlan   // cheapest insertion position
  }
  ```
- Start: `tourStart` if it names a POI, else POI id `entrance`, else first destination by name. End: `tourEnd` if valid, else the start.
- Value: highlight 1 → 3, 2 → 2, 3 → 1; +1 per tag matching an interest (case-insensitive substring either way); `mustSee` are inserted first regardless of budget.
- Algorithm: greedy insertion (repeatedly insert the candidate with the best value / added-minutes at its cheapest position while total ≤ `minutes * budgetFraction`), then 2-opt on the stop order. Walk minutes = path length (sum of segment lengths of `findPath`) / `strollSpeed` / 60. Leg lengths memoised per pair.

- [ ] **Step 1: Write failing tests** against a hand-built line map `S—a—b—c—E` (10 m spacing, all exhibits, minutes 3, `tourStart: "S"`, `tourEnd: "E"`):
  - `testTwentyMinutesFitsBudget`: `plan(.init(minutes: 20))!.totalMinutes <= 18`, and stops non-empty.
  - `testTinyBudgetGoesStraightToEnd`: `minutes: 1` → `stopIDs == []`, `startID == "S"`, `endID == "E"`.
  - `testMustSeeAlwaysIncluded`: `minutes: 1, mustSee: ["c"]` → `stopIDs == ["c"]`.
  - `testHighlightZeroExcluded`: `b.highlight = 0` → `!candidates.contains(b)`; big budget plan never contains `"b"`.
  - `testStartFallsBackToEntranceThenEndToStart`: no tour fields, POI id `entrance` exists → `startID == "entrance"`, `endID == "entrance"`.
  - `testOrderFollowsTheLine`: `minutes: 60` → `stopIDs == ["a","b","c"]`.
  - `testRemovingAndAddingRecompute`: removing `"b"` drops dwell by 3; adding it back restores `["a","b","c"]`.
  - `testUnreachableExhibitIgnored`: exhibit `z` with no edges → never in `candidates`.
  - `testNoStartReturnsNil`: map with only junctions → `plan` returns `nil`.
- [ ] **Step 2: Run, expect FAIL** (`-only-testing:AISEEBINTests/TourPlannerTests`).
- [ ] **Step 3: Implement** `TourPlanner`.
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit** `Explore: timed tour planner`

### Task 3: Explore proxy on the VPS

**Files:**
- Create: `server/explore/server.mjs`, `server/explore/lib.mjs`, `server/explore/lib.test.mjs`, `server/explore/package.json`, `server/explore/Dockerfile`, `server/explore/deploy.sh`, `server/explore/README.md`

**Interfaces:**
- `POST /explore/ask` — headers `X-Explore-Token`, `X-Install-Id`; JSON body `{ question: string, imageJPEGBase64?: string, mapSlug: string, places: [{id,name,details?,about?,distance,inView}], venueInfo?: string, history: [{q,a}] }` → `200 text/plain; charset=utf-8`, chunked, the answer text as it streams. Errors: 401 bad token, 429 limit, 503 disabled, 502 upstream.
- `POST /explore/plan` — same headers; body `{ utterance: string, exhibits: [{id,name,tags}] }` → `200 application/json` `{ minutes: number, interests: string[], mustSee: string[] }` (structured outputs, `mustSee` constrained to given ids by filtering server side).
- `lib.mjs` exports pure helpers: `buildAskSystemPrompt()`, `buildAskContent(body)`, `RateLimiter({perInstallPerHour, perDay, now})` with `.take(installId) -> true|false`, `pruneLogs(dir, now, days=30)`, `logPath(dir, date)`.
- Env (`/etc/aiseebin-explore.env`, chmod 600): `ANTHROPIC_API_KEY`, `EXPLORE_TOKEN`, `EXPLORE_MODEL=claude-opus-5-5`, `EXPLORE_EFFORT=low`, `EXPLORE_ENABLED=1`, `PORT=8787`.
- System prompt rules (spec §5): friendly Flower Dome guide; 2–3 short sentences, plain spoken English, no lists or markdown; Flower Dome facts only from the supplied places and venue info; may identify what is clearly visible from general knowledge and says so when unsure; never invents names, ages or numbers; one polite line for unrelated or unsafe questions.
- Request to Claude: `client.messages.stream({ model, max_tokens: 400, output_config: { effort }, system, messages: [{ role: "user", content: [image?, text] }] })`; place/venue context in the text block. Do not send `thinking` (Opus 5.5 is always adaptive).

- [ ] **Step 1: Write failing `node --test` tests**: rate limiter allows 60 then refuses the 61st for one install within an hour, resets after an hour, refuses everyone after 2,000 per day; `buildAskContent` includes the image block only when given, lists places nearest first and marks `inView`, includes up to 3 history pairs; `pruneLogs` deletes a 31-day-old file and keeps a 29-day-old one.
- [ ] **Step 2: Run** `cd server/explore && npm install && node --test`, expect FAIL.
- [ ] **Step 3: Implement** `lib.mjs` and `server.mjs` (Node `http`, no framework; 1.5 MB body cap; log one JSONL line per call without the image).
- [ ] **Step 4: Run** `node --test`, expect PASS.
- [ ] **Step 5: Deploy.** `deploy.sh` rsyncs the folder to `root@104.168.48.121:/opt/aiseebin-explore`, builds the image, runs it `--restart unless-stopped -p 127.0.0.1:8787:8787 -v /var/lib/aiseebin-explore:/data --env-file /etc/aiseebin-explore.env`. Create the env file once on the VPS, copying `ANTHROPIC_API_KEY` from `/root/.hermes/.env` without printing it and generating `EXPLORE_TOKEN` with `openssl rand -hex 24`. Back up `/etc/caddy/Caddyfile` to `Caddyfile.bak-explore-2026-10-17`, add `handle /explore/* { reverse_proxy 127.0.0.1:8787 { flush_interval -1 } }` inside the `aiseebin.flowsxr.com` block before `file_server`, `caddy validate` then `systemctl reload caddy`.
- [ ] **Step 6: Verify** with curl: `/explore/ask` with a small JPEG and "What is this?" streams text within ~3 s; wrong token → 401; `/explore/plan` with "I've got about 20 minutes and I love orchids" → `{"minutes":20,"interests":["orchids"],...}`.
- [ ] **Step 7: Commit** `Explore: Claude proxy for questions and spoken plans` (never commit the token or key).

### Task 4: iOS Explore client and question context

**Files:**
- Create: `AISEEBIN/Explore/ExploreClient.swift`, `AISEEBIN/Explore/AskContext.swift`, `AISEEBIN/Explore/FrameGrabber.swift`
- Test: `AISEEBINTests/AskContextTests.swift`

**Interfaces:**
- `enum ExploreConfig { static let baseURL = URL(string: "https://aiseebin.flowsxr.com/explore")!; static var token: String /* Info.plist EXPLORE_TOKEN, from build setting */; static var installID: String /* UUID in UserDefaults "explore.installID" */ }`
- `struct AskPlace: Codable, Equatable { let id, name: String; let details, about: String?; let distance: Float; let inView: Bool }`
- `struct AskHistory { mutating func add(q: String, a: String, at: Date); func recent(now: Date) -> [(q: String, a: String)] }` — at most 3, each younger than 300 s.
- `enum AskContext { static func places(map: NavigationMap, position: SIMD2<Float>?, heading: Float, radius: Float = 15, limit: Int = 4) -> [AskPlace] }` — skips junctions; nearest first; `inView` for the nearest place within ±30° of heading; empty when `position == nil`.
- `final class ExploreClient { func ask(question: String, jpeg: Data?, mapSlug: String, places: [AskPlace], venueInfo: String?, history: [(q: String, a: String)]) -> AsyncThrowingStream<String, Error>; func plan(utterance: String, exhibits: [NavigationPOI]) async throws -> TourRequest }` — `URLSession.bytes(for:)` for the stream, 10 s timeout to first byte.
- `enum FrameGrabber { static func jpeg(from frame: ARFrame, longEdge: CGFloat = 1024, quality: CGFloat = 0.7) -> Data? }` — `CIImage(cvPixelBuffer:)` rotated `.right` (portrait), scaled, `CIContext().jpegRepresentation`.
- Build setting `EXPLORE_TOKEN` in `project.yml` target settings (value empty in the repo) → `Info.plist` key `ExploreToken: $(EXPLORE_TOKEN)`; local builds pass it on the `xcodebuild` command line, like `IMMERSAL_DEFAULT_TOKEN`.

- [ ] **Step 1: Write failing tests**: `testPlacesNearestFirstSkipsJunctions`, `testInViewMarksPlaceAhead` (place 5 m ahead at heading 0 is `inView`, one behind is not), `testNoPositionGivesNoPlaces`, `testRadiusAndLimit`, `testHistoryKeepsThreeRecent` (4 added → 3 returned; one 301 s old dropped). Check `NavigationGeometry.heading` conventions before writing the in-view assertion.
- [ ] **Step 2: Run, expect FAIL** (`-only-testing:AISEEBINTests/AskContextTests`).
- [ ] **Step 3: Implement** the four files.
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit** `Explore: question context and proxy client`

### Task 5: NavigationViewModel hooks and the Explore visit model

**Files:**
- Modify: `AISEEBIN/ViewModels/NavigationViewModel.swift`
- Create: `AISEEBIN/Explore/ExploreViewModel.swift`, `AISEEBIN/Explore/VisitClock.swift`
- Test: `AISEEBINTests/VisitClockTests.swift`

**Interfaces (hooks, the only changes to `NavigationViewModel`):**
- `case explore = "Explore"` in `AppMode`; `didChange(mode:)`: `.explore` → `break` (positioning keeps running); `.navigation` guard becomes `previous != .settings && previous != .explore`; leaving Explore (`previous == .explore`) sets `quietGuidance = false`, `transcriptOverride = nil`, `onArrived = nil`.
- `var quietGuidance = false` (not persisted): when true, `handle(_ snapshot:)` skips `guidance.deliver`, the delayed cue, `updateBeacon` and `announceProximity`, but still finishes on `.arrived` and replans on `.offRoute`; `startNavigation` skips its "Starting route…" speech.
- `@ObservationIgnored var onArrived: ((String) -> Void)?` called with the POI id when a route arrives (both the `.arrived` cue and the immediate-finish branch of `startNavigation`).
- `@ObservationIgnored var transcriptOverride: ((String) -> Void)?`: when set, `handle(transcript:)` passes the transcript there instead of the command parser.
- `func navigate(to poiID: String)` — public wrapper around the existing `.navigate` command handling.

**Interfaces (visit model):**
- `struct VisitClock { init(plan: TourPlan, startedAt: Date); mutating func arrived(at stopIndex: Int, now: Date); func minutesLeft(budget: Double, now: Date) -> Double; func behindBy(now: Date) -> Double /* minutes behind plan, ≥ 0 */; func lateOffer(plan: TourPlan, map: NavigationMap, now: Date, nextIndex: Int) -> String? /* id of the lowest-value remaining stop when behind > 3 min */ }`
- `@Observable final class ExploreViewModel { enum Phase { case welcome, preview, walking, arrived(stopIndex: Int), complete }; init(nav: NavigationViewModel); var phase; var plan: TourPlan?; var budgetMinutes: Double; func choose(minutes: Double); func plan(fromSpeech:) async; func drop(_ id: String); func add(_ id: String); func start(); func nextStop(); func endVisit(); var askState: AskState /* idle, listening, thinking, answering(String), failed */; func ask() /* toggles listening */; func closeAsk(); var voiceDirections: Bool /* sets nav.quietGuidance = !value */ }`
- Legs: `start()` sets `nav.quietGuidance = true`, `nav.onArrived`, then `nav.navigate(to: stopIDs[0])`; arrival at a stop → `.arrived(i)` and speaks the POI `details` (or its name); `nextStop()` navigates to the next stop, then to `endID`, then `.complete`.
- Ask: stops guidance speech, sets `nav.transcriptOverride`, calls `nav.recognizer.startListening()`; on transcript grabs `nav.arManager.session.currentFrame` via `FrameGrabber`, builds `AskContext.places` from `nav.mapPose` (nil position when unreliable), streams `ExploreClient.ask`, appends text, and speaks each completed sentence with `nav.guidance.speak(_, interrupt: false)`. Failure or 10 s timeout → "Sorry, I couldn't answer that just now." `closeAsk()` stops speech and listening.

- [ ] **Step 1: Write failing tests**: `testMinutesLeftCountsDown` (budget 20, 5 min elapsed → 15); `testNotBehindWhenOnSchedule`; `testLateOfferAfterThreeMinutesBehind` (planned arrival at stop 0 at minute 4, still not arrived at minute 8 → offer is the lowest-highlight remaining stop id); `testNoLateOfferWithNoRemainingStops`.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement** the hooks, `VisitClock` and `ExploreViewModel`.
- [ ] **Step 4: Run the whole test suite** (`xcodebuild test … -destination 'platform=iOS Simulator,name=iPhone 17'`), expect all PASS, including the existing Navigate tests.
- [ ] **Step 5: Commit** `Explore: visit model and navigation hooks`

### Task 6: Explore screens and entry

**Files:**
- Create: `AISEEBIN/Explore/ExploreView.swift` (phase switch + light theme), `ExploreWelcomeView.swift`, `ExplorePreviewView.swift`, `ExploreWalkingView.swift`, `ExploreAskView.swift`
- Modify: `AISEEBIN/Views/ContentView.swift` (route `.explore`, hide `ModeSwitcher` and force light scheme in Explore), `AISEEBIN/Views/SettingsView.swift` ("Start in Explore" toggle, `@AppStorage("explore.startInExplore")`), `AISEEBIN/AISEEBINApp.swift` or `NavigationViewModel.init` (launch into `.explore` when the toggle is on)

**Interfaces:** consumes Task 5's `ExploreViewModel` only; map drawing reuses `LiveMapView(map:pose:routePath:selectedID:framed:)` with a light card background.

- Screens and copy follow spec §2 and the approved mockup exactly: Welcome (eyebrow "Flower Dome", "How much time do you have?", buttons 10 / 20 / 30 / 45+ (45+ plans 45), mic row "Or just say it", primary "Plan my visit", the AI notice line, long-press 3 s on the AiSee logo → `nav.mode = .navigation`); Preview (map, stop rows with minutes and ✕, "+ Add a stop" sheet, button "Start · about N min", amber "a bit over your time" when over budget, "Straight to the end · about N min" for zero stops); Walking ("⏱ N min left", "Stop i of n", map, next-stop card with distance and `currentInstruction` text, round Ask button "Tap and ask about anything you see", "Voice directions" toggle, "End visit"); Arrived (stop name, photo when `photo` is set, `details`, "Next stop"); Ask (full-screen `ARPreviewView`, framing guide, live transcript, streamed caption card, tap card / swipe down to close); Complete ("That's your visit", stops seen, Ask). Running-late offer appears on the walking card: "Running late: skip <name>?" with Skip / Keep.
- No map tour → Welcome shows "This map has no tour yet" instead of the buttons.

- [ ] **Step 1: Build for the simulator** with `-startMode`-style launch argument `-exploreDemo` that opens Explore on the sample map; screenshot Welcome, Preview and Complete with `xcrun simctl io booted screenshot`.
- [ ] **Step 2: Check** screenshots against the mockup; fix layout.
- [ ] **Step 3: Run the full test suite**, expect PASS.
- [ ] **Step 4: Commit** `Explore: screens and entry`

### Task 7: Web editor fields

**Files:**
- Modify: `web/index.html`, `web/app.js`
- Test: `web/explore-fields.test.js` (if a pure helper is added, e.g. `parseTags`)

- Place panel, exhibits only: Visit minutes (number, placeholder 3), Highlight (select: Must see / Good / If there's time / Not a tour stop → 1/2/3/0, default Good writes nothing), Tags (comma list), About (textarea, label "About (used to answer questions)"), Photo URL (text). Map panel: Tour start and Tour end (selects of places, blank allowed), Venue info (textarea). Empty inputs delete the key. Bindings follow the existing `bindNode` pattern.

- [ ] **Step 1:** Add the fields; `node --test web/*.test.js` PASS.
- [ ] **Step 2:** Serve `web/` locally, open `labeltransfertest`, set and clear each field, confirm the saved JSON (devtools) has the keys only when set.
- [ ] **Step 3:** Deploy: `scp web/{index.html,app.js} root@104.168.48.121:/var/www/aiseebin/` after backing up the current files to `/var/www/aiseebin/.bak-2026-10-17-explore/`.
- [ ] **Step 4: Commit** `Editor: tour and content fields for Explore`

### Task 8: Today's map version and device build

- [ ] **Step 1:** Publish `labeltransfertest` v3 from v2 (same rows the editor writes): `tourStart: "point-a"`, `tourEnd: "point-3"`, `door-b` and `door-c` `highlight: 0`, `minutes` 2 for `point-1`, `point-1-2`, `point-2`, `node-2`; nothing else changed. Verify by fetching the latest row.
- [ ] **Step 2:** Build and install on the connected iPhone (Debug, `EXPLORE_TOKEN` and `IMMERSAL_DEFAULT_TOKEN` passed on the command line), load `labeltransfertest` in Author, switch to Explore, run a 10-minute plan indoors to see the screens and one question answered.
- [ ] **Step 3:** Merge-readiness: `git fetch`, rebase onto `main` if it moved, full test suite, then hand back for on-site testing.
