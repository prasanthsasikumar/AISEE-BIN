# NUS Open House Guide — design

Date: 2026-11-10. Status: approved with the demo cut below (Prasanth, 2026-11-10: demo to NUS on 11 Nov, lift routes wanted, NUS will supply SoCat/logo art later, use placeholder images).

Everything below marked **(Prasanth)** he decided; everything marked **(Claude's call)**
is a default he can overturn.

## Demo cut for 11 Nov (supersedes the details below where they differ)

Prasanth demos to NUS on 2026-11-11, so v1 is what can be built and tested in one day:

- **App shape (Claude's call, changed):** the NUS target compiles the AISEE-BIN sources (minus `AISEEBINApp.swift`)
  with a `NUS_APP` compile flag and its own `@main`, Info.plist, assets and screens, driving the existing
  `NavigationViewModel` in phone mode. It does not link the RTK glasses frameworks (the kit's stub path, as on the
  simulator). No slim view model yet.
- **Floors without editor work (Claude's call):** POIs gain optional `y` (camera height when marked). Author writes it
  from now on; for the scan made today a one-off script reads the anchor heights out of the published world map and
  publishes a new version with `y`. Nearest-node snapping weighs height (planar distance + 3 × |dy|), so the node on
  the other floor never wins. Levels are found by clustering node heights (gap > 2 m), lowest = Level 1. No `floor`
  field, no `floors` list, no editor floor switcher in v1.
- **Stairs and lifts (Prasanth: lifts wanted):** a cross-level edge is a lift if either end's name contains "lift" or
  "elevator", otherwise stairs. Guidance says "Take the lift/stairs up to Level 2". In a lift SoCat waits at the lift
  door; on the new floor the app shows "Look around to find your position" until tracking or an Immersal fix returns.
- **Tour order:** the order destinations were marked in the map (POI array order), editable later by `tourOrder`.
- **SoCat:** placeholder image(s) (Prasanth: "use images for placeholders"), billboard sprite in the AR view.
- **Usage:** `app` column on `ab_sessions` and an app filter on the Sessions page.
- **Not in v1:** editor floor UI, `tourOrder` editor, Android, external TestFlight (internal group only until NUS OKs
  their marks).

## Why

NUS wants a wayfinding demo for its Open House: visitors find their way to five
locations inside one building. NUS has a mascot, **SoCat**, and the idea is that a
cartoon cat walks ahead of the visitor on the phone's camera view and leads them
there. Prasanth needs a working iPhone app to show NUS, built on what AISEE-BIN
already does: map a building on a phone walk, then work out where the phone is and
route it between places.

This is a demo for NUS first. If they take it up, the same app may be used by
visitors on the day.

## Goals

1. An iPhone app, **NUS Open House Guide** (Prasanth), bundle id
   `com.flowsxr.nusopenhouse` (App Store Connect app 6832900126, TestFlight groups
   "NUS Open House Testers": internal and external, with a public link).
2. Two ways to use it (Prasanth):
   - **Tour:** visit all 5 locations in a fixed order. SoCat leads to the next
     stop after each arrival.
   - **Pick one:** a list of the 5 locations. SoCat leads to the one chosen.
3. **SoCat walks ahead** (Prasanth): on the live camera view, a cat stands on
   the floor a few metres ahead along the route. It walks along the route,
   waits at turns and floor changes if the visitor stops, and turns to face
   the visitor on arrival.
4. **Two floors** (Prasanth): one office building with two floors. Routes
   cross between them by the stairs. SoCat climbs the stairs too.
5. **Icon** (Prasanth): an adapted NUS logo for the app icon, plus the
   in-app header mark.
6. Same backend as AISEE-BIN (Claude's call), and the same usage logging.

## Non-goals

- Android in this round (Prasanth: iPhone first, Android after). The data
  format must not block it: floors and tour order live in the map JSON, not in
  iOS-only state.
- AiSee glasses, lanyard mode, beep beacon, Explore's camera Q&A, and the field
  test tools. Positioning is phone-only (Claude's call).
- Outdoor or campus-wide navigation. It covers one building only.
- A public App Store release. TestFlight only.
- Accessibility features for blind users (that is AISEE-BIN's job). Speech is
  kept as captions plus an optional voice.

## Anti-goals (a failure even if it "works")

- SoCat walking through walls or floating in mid-air, or standing on the wrong
  floor. A cat in the wrong place is worse than no cat.
- After climbing the stairs, the app still routes as if the visitor were
  downstairs. This happens because the two floors overlap in plan view: see
  "Floors" below.
- Breaking AISEE-BIN. The shared code changes must leave the Flower Dome app
  and its maps working exactly as before, with its tests green.
- NUS branding reaching a public TestFlight link before NUS says yes. See
  Risks.

## How it works today (read from the code)

- **Map model.** `AISEEBIN/Models/NavigationMap.swift`:
  - A `NavigationMap` is `pois`, undirected `edges` and optional Explore fields.
  - Each `NavigationPOI` has only **`x` and `z`**, no height. It also has a
    category: `destination | junction | exhibit | hazard`.
  - The JSON is written by both the app and the web editor, and both
    round-trip unknown-but-declared optional fields.
- **Anchors.**
  - `ARNavigationManager.apply(anchors:)` in `AISEEBIN/Managers/ARNavigationManager.swift`
    overwrites each POI's x and z from its `poi:<id>` `ARAnchor`, using
    `NavigationGeometry.planarPosition`, which reads `columns.3.x/z`.
    **The anchor's `y` is available there and thrown away.**
  - `MapAuthoringViewModel.markHere` drops the anchor at the camera pose, about
    1.3 m above the floor. The ARWorldMap therefore already carries every
    place's height, including scans made today with build 16.
- **Routing.** `AISEEBIN/Managers/PathfindingEngine.swift`:
  - GameplayKit `GKGraphNode2D` A*, with cost equal to planar distance.
  - `nearestNode(to:)` is planar. On two stacked floors, the node directly
    above or below can win. **This is the main bug to design out.**
- **AR view.** `AISEEBIN/Views/ARPreviewView.swift` is a bare **SceneKit
  `ARSCNView`** on the shared session, used for setup and debug only. Nothing
  is rendered into the scene today. SoCat would be an `SCNNode` added to this
  view's scene. No RealityKit is used anywhere.
- **Map choice.**
  - `ServerConfig` in `AISEEBIN/Managers/MapSyncService.swift` has
    `mapSlug = "default"` and `starterMapSlug = "labeltransfertest"`.
  - `MapSyncService.availableMaps()` lists every slug's newest version.
  - `NavigationViewModel.loadServerMaps()` feeds Home and the map chip:
    `HomeView.swift:50`, `AppHeader.swift:280`.
  - `switchMap(to:)` installs a slug's newest version.
  - First launch downloads `starterMapSlug`.
- **Tour.**
  - `AISEEBIN/Explore/TourPlanner.swift` plans a *timed* visit, choosing and
    ordering stops by budget.
  - `NavigationMap.tourStart/tourEnd` exist.
  - There is no fixed stop order.
- **Editor.** `web/app.js`:
  - Draws nodes on a 2D canvas: `toScreen(x, z)`, `draw()`.
  - `loadMaps()` lists every slug on Home.
  - It already has a **height band** over the point cloud (`state.band`,
    `computeHeights`, and the Scan-view sliders "floor"/"all"). That is the
    natural seed for a floor switcher.
  - Nodes have no floor today, so two floors' nodes would draw on top of each
    other.
- **Branding is AISEE-specific in:**
  - `AISEEBIN/Info.plist`: the display name and every usage string mentions
    AISEE-BIN, the greenhouse or the glasses.
  - `Assets.xcassets`: `AppIcon` and `AiSeeLogo`.
  - `Views/AppHeader.swift` and `Explore/ExploreStyle.swift`: the logo, plus
    5 taps to enter staff mode.
  - `Views/DesignSystem.swift`: colour tokens.
  - `Explore/ExploreView.swift`: "Flower Dome".
  - `Views/SettingsView.swift`.
  - `Intents/AISEEIntents.swift`.
  - `voice/clips`: Flower Dome ElevenLabs phrases.
- **Usage logging.** `ab_sessions` in `server/schema.sql` has no app column.
  `UsageLog` builds the session header (`SessionHeader.current()`).

## Decisions

### App shape (Claude's call)

- **A second app target, `NUSOpenHouse`, in this repo's `project.yml`.** It
  shares the source files it needs: Models, routing, `ARNavigationManager`,
  `MapStore`, `MapSyncService`, the phone Immersal localizer, `GuidanceManager`
  and policies, and Usage. Its own app entry, views and assets go under
  `NUSOpenHouse/`.
- It does **not** link the RTK glasses frameworks. That drops the Bluetooth,
  contacts, location and hotspot permissions and their App Review risk.
- Shared code that currently reaches into glasses or Explore types is the
  builder's problem to cut cleanly. Two acceptable routes:
  - a slim `GuideViewModel` that composes the managers; or
  - compile flags around the glasses/Explore paths in `NavigationViewModel`.

  The builder picks one and says why. The slim view model is preferred:
  `NavigationViewModel` is about 1,500 lines and glasses-heavy.
- **Scanning stays in AISEE-BIN.**
  - Prasanth maps the building with AISEE-BIN's Author mode (build 16 or
    later) and names the map `nus-<something>`.
  - The NUS app has no Author mode.
  - It keeps a hidden staff screen, reached with 5 taps on the header logo as
    in AISEE-BIN. The screen offers: choose map, reload map, positioning
    status, send log.

### Maps and backend (Claude's call)

- Same Supabase project, bucket, `ab_map_versions` and editor at
  aiseebin.flowsxr.com.
- **The NUS app lists only slugs starting with `nus-`.** Its starter map is the
  newest `nus-` map, or a fixed `ServerConfig` value set once the scan is
  published.
- **AISEE-BIN hides `nus-` slugs** from Home and the map chip. Its Author
  "continue a saved scan" list still shows them, so the scan can be
  re-walked.
- The prefix rule lives in one shared function with a test, so both apps agree
  on it.
- **Usage logging:**
  - Add `app text` (default `'aiseebin'`) to `ab_sessions`, and to the
    session header on iOS and Android, then reload PostgREST
    (`notify pgrst, 'reload schema'`).
  - The NUS app sends `app: "nus-open-house"`.
  - The Sessions page gets an app filter.
  - The event catalogue is unchanged. New event types:
    - `tour.start`, `tour.stop_arrived`, `tour.end`, `tour.abandon`;
    - `socat.state`: walking, waiting, climbing or arrived. Log it on change
      only, not per frame.

### Floors (Claude's call)

- **POIs gain optional `y`** (metres, ARKit world frame, as captured by the
  anchor) **and optional `floor`** (an integer label, e.g. 1 or 2).
  - The app overwrites `y` from the anchor in the same place it overwrites
    x and z.
  - Old maps without either field behave exactly as today, as one floor.
- **The map gains optional `floors: [{floor, name, y}]`**: the floor's typical
  camera height.
  - The phone's **current floor** = the entry whose `y` is nearest the camera
    `y`, with hysteresis of about 0.8 m so walking up a few stairs does not
    flip it.
  - With no `floors`, everything is on one floor.
- **Snapping and "nearest node" consider only nodes on the current floor.**
  This also applies to the route tracker and arrival.
- Stair nodes are tagged with their own floor. The edge between the bottom and
  top stair node is the only cross-floor edge.
- **Routing cost:**
  - A cross-floor edge costs its planar length plus 10 m.
  - All stairs routes are fine.
  - Lifts are not routed in v1 (see Risks).
- **Edges gain an optional `kind: "stairs" | "lift"`.**
  - It is set on the cross-floor edge.
  - Guidance turns it into "Take the stairs up to Level 2". Use the floor name
    from `floors`.
  - SoCat interpolates its height along it to climb.
- **Editor:**
  - **Floor:** a floor field in the node inspector, and a floor switcher in the
    header (All / 1 / 2) that dims other floors' nodes and edges and sets the
    point-cloud height band to that floor.
  - **Floors list:** a "Floors" section in map settings to name each floor and
    record its y. Fill it from the median height of that floor's nodes.
  - **Assign floors from height:** one button that sets every node's floor by
    clustering its `y`.
  - **Stair link:** an edge `kind` selector.
  - **Prerequisite:** the editor only knows `y` if the app has written it, so
    the NUS app (or AISEE-BIN's publish) must publish `y` back. The builder
    adds `y` to what Author publishes and to a one-off "write heights from
    anchors" staff action, so the scan made today gets heights without
    re-walking.

### The scan (Claude's call; Prasanth is doing it now)

- **One continuous Author walk covering both floors, going up and down the
  stairs**, so both floors share one ARKit frame.
- Mark these places:
  - the 5 locations, as destinations, with their real names;
  - the tour start (e.g. the entrance), as a destination;
  - the bottom and top of the stairs, as junctions;
  - junctions at corridor turns.
- Walk the corridors between them rather than every room. That keeps the
  world map small (see Risks).
- If the publish is too big, fallback (not built in v1): one map per floor
  with a hand-over at the stairs.

### Tour and pick-one (Prasanth for both; details are Claude's call)

- **Fixed order:**
  - The map gains optional `tourOrder: [poiID]`, set in the editor as a
    reorderable list.
  - Without it, order by nearest-neighbour from `tourStart`.
  - `TourPlanner`'s timed planning is not used.
- **Tour flow:**
  1. Start.
  2. Find position. Show "Look around slowly…" until the phone is localised.
  3. SoCat leads to stop 1.
  4. On arrival, show a stop card with the name and short `details` text,
     with a "Next stop" button.
  5. Repeat to stop 5.
  6. Finish with "Tour complete".
- **Skipping:** stops can be skipped, and the visitor can leave the tour at
  any time.
- **Pick one:** the list of destinations (not junctions, not stairs), showing
  "Level 1 / Level 2" next to each. Tap one and SoCat leads there.
- **Home screen:** two big buttons: "Start the tour" and "Choose a place".

### SoCat (Prasanth: walks ahead; how is Claude's call)

- **Rendered as a 2D billboard sprite in SceneKit** (an `SCNPlane` with
  `SCNBillboardConstraint` on its Y axis only, so the feet stay on the floor).
  It plays a short frame animation: walk, idle and wave.
  - **Why a sprite:** NUS will most likely hand over 2D SoCat art, a drawn
    sprite swaps in without any 3D modelling, and it reads well on a phone.
- **Asset slot:** `NUSOpenHouse/Assets.xcassets/SoCat/` holds `walk_0…walk_N`,
  `idle_0…`, `wave_0…`.
  - Until NUS supplies art, Claude draws a **placeholder cat**: a simple
    original silhouette in NUS blue and orange, plainly a stand-in, not a copy
    of SoCat.
  - Swapping in real art is only an asset change.
- **Placement:**
  - SoCat stands on the route polyline (current position → remaining route
    nodes), about **2.5 m ahead** of the visitor.
  - Its height is the floor: camera y minus 1.35 m on flat floor. On a stair
    edge, it interpolates between the stair nodes' floor heights.
  - It faces the direction of travel.
- **Behaviour:**
  - SoCat moves at most at walking pace, eased.
  - If the visitor stops, SoCat stops at the next turn and switches to idle,
    looking back.
  - On arrival, SoCat sits at the destination and waves.
  - If positioning is lost or limited, SoCat fades out and the screen says
    "Finding your position…". It never stands somewhere unverified.
- **Fallback when the visitor can't see SoCat:** an on-screen arrow at the edge
  of the camera view points toward it, plus the existing turn captions.
- **Voice:** off by default, with a toggle. It uses the system voice; there are
  no ElevenLabs clips in v1.

### Look and branding (Prasanth: adapted NUS logo; details Claude's)

- **Colours:** NUS blue `#003D7C` and orange `#EF7C00` as the NUS target's
  accent tokens. These are an NUS-target override of `DesignSystem`, not a
  change to AISEE-BIN's.
- **App icon:** the NUS logo adapted (Claude draws it). Use official NUS files
  if Prasanth provides them in `design/nus/`. Otherwise use the public logo.
  The icon goes in the NUS target's own `AppIcon`.
- **Info.plist:**
  - Its own plist with display name "NUS Open House".
  - Camera usage: "NUS Open House Guide uses the camera to find where you are
    in the building and show SoCat leading the way."
  - Microphone and speech strings only if voice commands are kept (Claude's
    call: no voice input in v1, so no microphone or speech permissions).
- **Header:** the NUS mark top-left; 5 quick taps opens the staff screen.

## Risks

1. **Lifts.**
   - **The problem:** inside a moving lift the camera sees a still box while
     the motion sensors feel movement, so ARKit tracking typically goes
     limited or drifts, and the height jump is lost.
   - **v1 handling:** routes use the stairs only.
   - **If NUS needs lift routing:**
     - add a lift edge marked "relocalise after";
     - SoCat waits at the lift doors on the other floor;
     - the app asks the visitor to look around after leaving the lift.

     This needs on-site testing, and is not promised.
2. **World-map size.**
   - **The limit:** a 2-floor walk could be large. The Flower Dome world map
     was 31.7 MB raw and 23 MB gzipped. Supabase's free tier caps an upload at
     **50 MB**, which is about 68 MB raw after gzip.
   - **Mitigation:**
     - walk the corridors, not every room;
     - check the size shown in Author before publishing;
     - fall back to per-floor maps if needed.
3. **Wrong-floor snapping.** Covered by the floor filter above. It needs a
   unit test with two stacked nodes and an on-site check after climbing the
   stairs.
4. **SoCat art and the NUS logo.**
   - **Ownership:** both belong to NUS. There are no SoCat assets yet, so the
     placeholder is our own.
   - **The external TestFlight link:** Apple's beta review can reject an app
     that uses another organisation's marks without permission, and the link
     is open to anyone.
   - **Rule:** builds with NUS marks go to **internal testers only** until NUS
     confirms in writing that we may use the logo and SoCat.
5. **Relocalisation time and lighting.**
   - **What happens:** an office with repetitive corridors can relocalise
     slowly or wrongly, the same failure seen in the Flower Dome tests.
   - **Mitigation:**
     - The "Look around…" screen tells the visitor what to do.
     - The tour start should be a visually distinctive spot.
     - If the scan uploaded Immersal photos, the phone Immersal localizer is
       a second source of fixes, same as AISEE-BIN phone mode.
6. **Shared-code regressions in AISEE-BIN.** All AISEE-BIN tests
   (about 356 iOS) must stay green. The new optional fields must decode on old
   builds: they are ignored, and the editor round-trips them.

## Left to the builder

- Slim view model vs compile flags (see App shape). State the choice and why.
- The exact SceneKit set-up for SoCat: plane size (about 0.5 m tall), easing,
  and animation frame rate.
- The hysteresis and clustering thresholds for floors. They should be
  measured on the real scan's heights.
- The NUS target's screens, which follow `DesignSystem` with the NUS
  colours. Claude mocks them up before building.
- How the "write heights from anchors" staff action publishes: through
  `MapSyncService.publishEdit`, as Field Test edits do.
- Tests:
  - map decoding with and without `y`, `floor`, `floors`, `tourOrder` and edge
    `kind`;
  - floor detection with hysteresis;
  - same-floor nearest node;
  - route across floors, and guidance text for a stairs edge;
  - tour sequencing: next, skip and finish;
  - SoCat placement along a polyline, including on a stair edge;
  - the `nus-` slug filter in both apps;
  - the editor's floor filter (`node --test`).

## Verification

- **Simulator:** the app launches, lists only `nus-` maps, and runs a tour on a
  test map with two floors by stepping through it with the debug launch args.
  AISEE-BIN no longer lists `nus-` maps.
- **On site, on an iPhone:**
  - a full tour of 5 stops including a floor change;
  - after the stairs, the route and SoCat are on the new floor;
  - SoCat never stands in a wall for more than a moment;
  - arrival triggers within about 2 m;
  - record the relocalisation time at the start.
- **Data:** the session appears on the Sessions page with `app = nus-open-house`
  and the tour events present.
- **TestFlight:** the first build goes to the internal group, and to the
  external group only after NUS's OK (Risk 4).
