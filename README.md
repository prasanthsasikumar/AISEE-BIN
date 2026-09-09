# AISEE-BIN — AISEE Botanic Indoor Navigation (iOS MVP)

Hands-free indoor navigation for botanical greenhouses. The iPhone rides in a
forward-facing chest or lanyard mount; ARKit world tracking provides position,
GameplayKit A\* provides the route, and `AVSpeechSynthesizer` + Core Haptics
provide turn-by-turn guidance so the user never has to look at the screen.

## Layout

```
AISEEBIN/
  AISEEBINApp.swift                 App entry; owns the single NavigationViewModel
  Info.plist                        Camera / microphone / speech permissions, ARKit requirement, portrait lock
  Models/
    NavigationMap.swift             NavigationPOI (category, details, aliases) / NavigationEdge / NavigationMap
    SampleGreenhouseMap.swift       6-node sample layout, used until a map is authored
    NavigationInstruction.swift     TurnDirection buckets + spoken / banner text
  Managers/
    ARNavigationManager.swift       ARSession, tracking state, FPS, feature density, ARWorldMap capture/load, POI anchors
    MapStore.swift                  Local bundle: world map, graph JSON, point cloud, version record
    MapSyncService.swift            Supabase REST/Storage client: latest version, parallel chunked download, upload
    GzipCodec.swift                 gzip container over the system DEFLATE codec, for stored blobs
    PointCloudCodec.swift           Float32 xyz encoding of ARWorldMap feature points
    PathfindingEngine.swift         GKGraph + GKGraphNode2D, A* findPath, nearestNode, guidanceVector, nearby()
    NavigationGeometry.swift        Pose → planar position / heading / relative bearing helpers
    RouteTracker.swift              Advances along a path; node-reached, arrived, off-route
    GuidancePolicy.swift            Pure throttling: decides *when* to speak
    GuidanceManager.swift           AVSpeechSynthesizer + CHHapticEngine: decides *how*
    ProximityAnnouncer.swift        Passive "Titan Arum on your left" commentary with hysteresis
    CommandParser.swift             Transcript → VoiceCommand (fuzzy POI matching, aliases)
    VoiceCommandRecognizer.swift    SFSpeechRecognizer push-to-talk, on-device, silence timeout
    MapAuthoringSession.swift       Pure editing model for the mapper (nodes, chained edges)
  Intents/
    AISEEIntents.swift              App Intents: "Listen" (Action Button) and "Navigate to <destination>" (Siri)
    AppCommandBus.swift             Queues intent invocations for the view model
  ViewModels/
    NavigationViewModel.swift       Mode toggle, server sync, per-frame orchestration, voice commands, commentary
    MapAuthoringViewModel.swift     Mark-here, connect, save bundle, upload / import
  Views/
    ContentView.swift               Talk button, status badge, destination picker, live banner, debug overlay
    AuthoringView.swift             Mapper's screen: scan preview, node list, mark / edit / connect / save
    ARPreviewView.swift             ARSCNView wrapper for the camera feed
AISEEBINTests/                      99 XCTest cases for the pure-logic layer
web/                                Map editor (static HTML/JS) served at https://aiseebin.flowsxr.com
server/schema.sql                   Supabase table, RLS policies and storage bucket
docs/superpowers/specs/             Design notes
project.yml                         XcodeGen spec (regenerates AISEE-BIN.xcodeproj)
```

Data flow per camera frame:

`ARNavigationManager` → `ARFrameSnapshot` → `NavigationViewModel.handle` →
`RouteTracker.update` (reached / arrived / off-route) → `PathfindingEngine.guidanceVector`
→ `NavigationInstruction` → `GuidancePolicy.evaluate` → `GuidanceCue?` → `GuidanceManager.deliver`.

## Xcode setup

1. **Open the project.** `AISEE-BIN.xcodeproj` is checked in. If you edit
   `project.yml`, regenerate with `brew install xcodegen && xcodegen generate`.
2. **Signing.** Select the `AISEEBIN` target → *Signing & Capabilities* → pick
   your team. Bundle id is `com.flowsxr.aiseebin`; change it if it collides.
3. **Frameworks.** Nothing to add manually: ARKit, SceneKit, GameplayKit,
   AVFoundation, CoreHaptics and Observation are imported directly and linked
   automatically. Minimum deployment target is iOS 17.
4. **Info.plist** (already in `AISEEBIN/Info.plist`):
   - `NSCameraUsageDescription` — required, ARKit will crash without it.
   - `UIRequiredDeviceCapabilities` = `arkit` — blocks install on unsupported hardware.
   - `UISupportedInterfaceOrientations` = portrait only — matches the chest mount.
5. **Run on a real device.** ARKit world tracking does not run in the
   Simulator; the app shows "ARKit not supported" there. Any iPhone with an A12
   or newer works, iPhone Pro (LiDAR) relocalizes fastest.
6. **Tests.** `⌘U`, or:
   ```
   xcodebuild test -project AISEE-BIN.xcodeproj -scheme AISEEBIN \
     -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
   ```

## Two modes

A segmented control at the top switches between **Navigate** and **Author**.
Switching to Author stops guidance and voice; switching back reloads the local
map, restarts tracking, and checks the server for a newer version.

## Server and web editor

- **Data**: Supabase Cloud project `djfpemdkeguztyuerxqc` (ap-southeast-1),
  table `ab_map_versions` and public bucket `aiseebin-maps` (`server/schema.sql`).
  Every upload or web save appends a new version; nothing is overwritten.
  Moved here from the self-hosted db.flowsxr.com on 2026-09-09 — see *Transfer
  speed* below. The old backend is still running and still holds a copy;
  builds shipped before that date keep reading from it.
- **Editor**: https://aiseebin.flowsxr.com (static files in `web/`, deployed
  to `/var/www/aiseebin` on the VPS, served by Caddy). It draws the scanned
  feature-point cloud top-down with the graph on top. You can drag nodes,
  rename them, set type / description / aliases, add and delete nodes and
  edges, import/export JSON, and save as a new version.
- **Map names vs. slugs**: a map has a display **name** (`graph.name`, editable
  on the phone when publishing and in the editor's Name field) and a server
  **slug** (`map_slug`, the key every version is filed under). The slug is
  derived from the name at a map's first publish and never changes afterwards,
  so renaming a map keeps its whole version history. The Map dropdown lists
  maps by name, with the slug in brackets when the two differ. Maps published
  before naming existed live under the slug `default`.
- **What you can and cannot edit**: the `ARWorldMap` is an opaque binary of
  visual features and cannot be edited; it is only visualised. The graph JSON
  is the editable part, and its coordinates are authoritative in the app.
- **App behaviour**: Navigate mode fetches the newest version on launch (and
  on *⋯ → Check Server for Map Updates*). A web-sourced version reuses the
  world map already on the device; an iOS-sourced version replaces it.
- **Transfer speed**: installing a map used to take over ten minutes. Measured
  from Auckland, the self-hosted VPS sat 266 ms away and gave a single
  connection ~40 KB/s, so the 31.7 MB world map took **629 s**. Four changes,
  in descending order of what they bought:
  - **Moving to Supabase Cloud**, whose Storage is CDN-fronted. Same map,
    now gzipped to 23.1 MB: **4.4 s**. REST queries went 1141 ms -> 300 ms.
    This is the one that mattered; the rest are what make it cheap and robust.
  - **Blobs stored gzipped** (`GzipCodec`), named `*.arworldmap.gz` and
    `*.points.f32.gz`. The world map goes 31.7 MB -> 23.1 MB (72.7%; an
    ARWorldMap is already dense, so do not expect more). This also doubles how
    many installs fit in the free tier's 5 GB/month egress. Paths without `.gz`
    are read as-is, so older versions keep working.
  - **`Cache-Control: public, max-age=31536000, immutable`** on upload. Storage
    paths embed the version (`<slug>/v<n>/...`), so objects never change once
    written. Supabase defaults to `no-cache`, which defeats the CDN entirely.
  - **Parallel Range requests**: `MapSyncService.download` issues
    `downloadConcurrency` (6) chunks at once and reassembles them in offset
    order. This was worth 3.7-5.4x on the old slow origin; on the CDN it is
    largely redundant but still helps on a weak greenhouse Wi-Fi link.

  Free-tier ceilings to keep in mind: **50 MB max upload** (caps a world map at
  about 68 MB raw once gzipped) and **suspension after a week of inactivity**,
  which a daily keepalive cron on the VPS prevents. Details in `../SUPABASE.md`.

## Mapping a space (sighted mapper)

Switch to **Author**. Every POI is stored as a named `ARAnchor` (`poi:<id>`)
inside the `ARWorldMap` and, authoritatively, as coordinates in the graph JSON.

1. *⋯ → Start Fresh Scan* at the entrance. Walk every corridor slowly, sweeping
   the camera across foliage and fixtures until `mapping` reads `extending`
   or `mapped`.
2. Stand at each place of interest and tap **Mark here**. Give it a name, a
   type and, optionally, a spoken description:
   - **Destination**: navigable (entrance, restrooms, a house).
   - **Junction**: routing only, never spoken.
   - **Exhibit**: navigable *and* announced with its description when passed within 2.5 m.
   - **Hazard**: never a destination; announced with a warning haptic within 2.5 m.
3. Consecutive marks are linked automatically (the path you walked). Swipe a
   node right to **Connect** it to another node (close loops) or **Chain from**
   it (when you walk back to a junction and head down a new corridor). Swipe
   left to delete. Tap to edit.
4. Tap **Save** to keep the bundle locally, or **Upload** to publish it: the
   world map, feature-point cloud and graph go up as a new version. The upload
   dialog asks for a **Map name** (what the map is called in the web editor's
   Map dropdown) and an optional note describing what changed in this version.
   Then open the web editor to fine-tune positions, names and descriptions and
   save again (that creates another version, reusing the same world map).
5. The ⋯ menu over the camera preview has **Import Latest From Server** (pull a
   version down to extend it here) and **Continue Existing Scan** (relocalize
   against the local world map before marking more nodes).

On later launches the badge shows **Relocalizing…** until ARKit matches the
environment, then **Tracking Ready** with a map icon. The debug overlay's
`anchored nodes` count confirms the POI anchors were restored.

## Hands-free use (blind user)

Everything is spoken and buzzed; the screen is never required.

**Triggers**
- **Action Button** (iPhone 15 Pro and later): Settings → Action Button →
  Shortcut → AISEE-BIN → **Listen**. One press opens the app and listens.
- **Siri**: "Take me to the Orchid Display in AISEE-BIN", "Listen in AISEE-BIN".
- **On-screen**: the large *Tap to talk* button fills the bottom of the screen.

**Commands** (matched fuzzily, so "the orchids" works)
| Say | Result |
|-----|--------|
| "take me to / go to / navigate to <place>" | starts guidance; waits for tracking if needed |
| "where am I" | nearest node, distance and side |
| "what's nearby / around me" | up to three POIs within 10 m with left/right/ahead |
| "repeat / say that again" | current instruction |
| "stop / cancel" | ends guidance |

A single firm tap means "listening"; a double tap means "heard you". Listening
ends after 4 s of silence (10 s max). Speech output is cut when listening
starts so the app never hears itself. After two unrecognised commands it reads
out the available commands and destinations.

## Sample graph (metres, ARKit world frame)

```
         z = -14                 [Orchid Display]
                                        |
         z =  -8    [Tropical House]---[Central Junction]---[Palm Conservatory]
                                              |                     |
         z =  -2                              |                 [Restrooms]
                                              |                /
         z =   0                        [Main Entrance]-------
                    x = -6                  x = 0            x = +6
```

| id        | name              | x  | z   | destination |
|-----------|-------------------|----|-----|-------------|
| entrance  | Main Entrance     | 0  | 0   | yes |
| junction  | Central Junction  | 0  | -8  | no (routing only) |
| tropical  | Tropical House    | -6 | -8  | yes |
| orchid    | Orchid Display    | -6 | -14 | yes |
| palm      | Palm Conservatory | 6  | -8  | yes |
| restrooms | Restrooms         | 6  | -2  | yes |

Edges: entrance–junction, junction–tropical, tropical–orchid, junction–palm,
palm–restrooms, restrooms–entrance. The loop lets A\* choose: from the entrance
to the Palm Conservatory it picks the restrooms side (≈12.3 m) over the
junction side (14 m).

## Guidance behaviour

| Trigger | Voice | Haptic |
|---------|-------|--------|
| Route started | "Starting route to the Orchid Display. In 8 meters, continue straight toward the Central Junction." | — |
| ≤ 3.0 m from next node (once per node) | "In 3 meters, turn slight right toward the Palm Conservatory." | two soft taps = left, one long buzz = right |
| ≤ 1.5 m: node reached | next instruction | one firm tap |
| Destination reached | "You have arrived at the Orchid Display." | rising triple tap |
| Every 12 s on a long leg | reassurance with updated distance | — |
| > 2.5 m from current leg (max every 8 s) | "You are off route. Recalculating." then re-plans from nearest node | three low rumbles |
| Tracking lost (max every 8 s) | "Tracking lost. Please pause and turn slowly…" | three low rumbles |

All thresholds live in `GuidanceThresholds`.

## Known limitations / next steps

- **DNS**: aiseebin.flowsxr.com resolves to the VPS; any new subdomain needs an A record at NS1
  (added by hand) before Caddy can issue its certificate.
- **Access control**: the publishable key allows anyone to append versions.
  Add Supabase Auth (or a header-checked RLS policy) before public release.
- **Always-listening / wake word** is deferred; push-to-talk is the only mode.
- **Relocalization robustness**: greenhouses change hourly. Plan to add printed
  reference images or QR signs at POIs as `ARReferenceImage` anchors for an
  absolute re-fix when the world map drifts.
- Heading is unfiltered; a chest mount sways, so a short low-pass filter on the
  relative angle would stop banner flicker near nodes.
- One map per install. Multi-greenhouse support needs a map registry.
- Apple Watch as an extra push-to-talk trigger (WatchConnectivity).
