# AISEE-BIN map editor (dashboard): redesign brief for Claude Design

Paste the **Prompt** section into Claude Design and attach everything in `screenshots/` plus
everything in `assets/`.
The rest of this file is the full feature inventory: paste it in too, or answer follow-up questions from it.

Screenshots were taken 2026-10-26 from the live editor at https://aiseebin.flowsxr.com (1440×900, @2x;
`17-mobile-390.png` is 390 wide). The live files match `web/` in the repo.

---

## Prompt

Redesign the **AISEE-BIN map editor**, the desktop web dashboard where staff build and maintain the
indoor navigation maps used by the AISEE-BIN apps (iPhone, Android and AiSee glasses). It works today; the
screenshots show its current, utilitarian state. **Keep every feature and behaviour listed below; redesign the
information architecture, layout, hierarchy, visual language and micro-interactions.**

**Who uses it.** A sighted staff member or FlowsXR engineer at a laptop, before or after a site visit.
They pick a venue map, look at the scanned point cloud from above, lay out a route network (places and the
paths between them), write what the app says at each place, line up several Immersal scans into one map,
fill in tour content for sighted visitors, and publish a new version that phones download automatically.
Sessions are long and fiddly (dragging nodes by centimetres), so it must be calm, dense and precise, like a
pro tool (Figma, Linear, a GIS editor), not a marketing dashboard.

**What is wrong today** (visible in the screenshots):
- Everything lives in one long right-hand column: map settings, three collapsible panels, node inspector,
  files and legend all stack, so the node form scrolls off screen and the panel you need is never where you
  look.
- Labels and edge lengths overlap each other on the canvas (see `01`, `11`); node names get clipped at the
  canvas edge.
- The canvas hint bar collides with the status footer at the bottom left.
- The version list repeats the selected version's note underneath itself.
- No sense of "which map, which version, unsaved changes, will this reach the phone" at a glance.
- Native `prompt()` / `confirm()` dialogs for new map, Immersal import, delete, and discard changes.
- The mobile layout is broken: the canvas covers the panels (`17`). Phone/tablet use is a nice-to-have,
  but a tablet on site would be useful.
- No branding: it should read as an **AiSee** product, with "built by FlowsXR" in the footer.

**Brand.** AiSee lavender `#9B87E8` with off-white `#F7F5FD` (logo attached). FlowsXR indigo `#5667CC`
as the secondary. A dark UI is preferred (point clouds read best on dark), with a light theme as a bonus.
Keep the AISEE-BIN apps' design language, so the phone app, glasses app and dashboard feel like one product.

**Deliverables.** 1440-wide desktop frames for: map overview (nothing selected); a place selected (the full
inspector, including the tour fields); a path segment selected; the "places not connected" warning state;
Path mode mid-draw; Scan view (height band + histogram); Immersal scans being aligned (several coloured
clouds, one selected, with transform controls); the 3D view; an empty map (scan only, no places); the
version history with a compare or restore affordance; save / publish with a note; replacements for every
native prompt/confirm dialog (new map, import from Immersal, add Immersal scan, delete place, discard
unsaved changes, save with disconnected places). Plus a tablet (1024) layout, a short style guide (tokens,
type, components: toolbar, mode switch, inspector field rows, version row, status bar, toasts, map legend,
canvas styling for places, paths, selection, announce radius and the warning ring), and the canvas visual
language for the four place types, which must not rely on colour alone.

---

## Feature inventory (everything the editor does today)

### Data model (what is being edited)
- A **map** has a slug (e.g. `flower-dome-1-oct`) and a display name. Each save creates a new immutable
  **version** (v1, v2…). Versions come from the iPhone app (`ios`, a full ARKit scan upload) or this
  editor (`web`).
- Each version holds a **graph**: places (nodes) and paths (edges), plus optional files: an ARWorldMap
  (the iPhone's relocalization map) and a **point cloud** (feature points from the scan, drawn on the
  canvas).
- Optional **Immersal alignment**: up to 8 Immersal scans (by numeric map id), each with a placement
  (turn, x, z, height), used by the glasses and the Android app to position themselves.
- Optional **Explore tour** content for sighted visitors: tour start, tour end, venue info, and per-place
  visit minutes, highlight, tags, "about" text and photo URL.
- Phones fetch the latest version of their map on launch. Saving here *publishes*.

### Header / toolbar (`01`)
- Title "AISEE-BIN map editor".
- **Map picker** (dropdown of every map on the server, shown as `Name (slug)`), with a last entry
  **"+ New map…"** (asks for a name and creates an empty local map; it exists on the server after the
  first save).
- **Refresh** (↻): reloads the map list and versions.
- **Import from Immersal…**: asks for an Immersal map id, downloads its sparse point cloud through the
  site's proxy, asks for a name, warns if that name already exists (then saves as its next version), and
  opens it as a new map drawn in Immersal's own frame, ready to add places to.
- **Mode switch**: Select · + Node · Connect · Path (one active at a time; Esc returns to Select).
  - *Select*: click a place or path to inspect it; drag a place to move it; drag empty space to pan.
  - *+ Node*: click empty canvas to add a place there.
  - *Connect*: click two places to add a path between them, or remove it if one exists.
  - *Path* (`11`): click along a corridor to lay waypoints joined by paths; clicking within 1 m of an
    existing place snaps to it; clicking an existing place ends the path there; Esc stops. The hint bar
    shows "Path from X…". Warns when a path is started on empty canvas ("remember to end it on a place").
- **Undo / Redo** (⌘Z, ⌘⇧Z / Ctrl+Y; 200 steps; a node drag is one step).
- **Fit** (fit the view to the content).
- Toggles: **points** (show the point cloud), **labels** (place names and path lengths).
- **3D**: opens the 3D point-cloud viewer.
- **"what changed?"** note field + **Save as new version** (shows `*` when there are unsaved changes;
  disabled with no map loaded).

### Left column: Versions (`01`)
- Newest first. Each row: version number, source (`web` / `ios`), date and time, the note, node count and
  point count. The selected row is highlighted.
- Clicking a row loads that version (asks "Discard unsaved changes?" if dirty). Loading an old version and
  saving makes it the newest again, which is the current way to roll back.
- Under the list, the selected version's summary is repeated (redundant today).
- Empty state: "No versions yet. Upload one from the app in Authoring mode."

### Canvas (centre)
- Top-down view, metres. Grid with x labels along the top and z labels down the left. x runs right,
  forward (−z) runs up. The origin is where the scan started, drawn as a small cross with a forward tick.
- **Point cloud** coloured by height (blue = floor, yellow = high), or by scan when Immersal scans are
  loaded (one colour per scan, `14`).
- **Places** as dots coloured by type: destination blue, junction grey (smaller), exhibit green,
  hazard red. Name label to the right.
- **Announce radius**: a dashed circle round exhibits and hazards showing how close a visitor must come
  before it is spoken; brighter when selected.
- **Paths** as lines with their length in metres at the midpoint. The selected path is yellow and thicker.
- Selected place: white ring. First place of a pending Connect/Path: yellow ring.
- **Disconnected place**: dashed yellow ring (`10`).
- Interactions: wheel zooms about the cursor; drag empty space, middle/right-drag or Shift-drag pans;
  drag a place to move it; Delete/Backspace removes the selected place or path (place delete confirms).
- **Live cursor coordinates** (`x 1.23  z −4.56`) in a corner.
- **Hint bar**: one line of instructions for the current mode.

### Right column: Map panel
- **Name** of the map (editable; renaming relabels the dropdown after save).
- Stats: `18 nodes · 17 edges`.
- **Explore tour (sighted visitors)**, collapsible (`06`): Tour start and Tour end (dropdowns of places;
  blank start means a place called `entrance`, blank end means back at the start), **Venue info** textarea
  (opening hours, toilets, café: used by the AI to answer visitor questions).
- **Scan view**, collapsible (`07`, `08`, `09`): a height band (two sliders, low and high, in metres) so
  only points in that band are drawn; presets **Everything / Floor / Walls & furniture**; a **density**
  toggle (clusters drawn as solid shapes); a **histogram of point heights** (0.25 m bins) coloured like the
  cloud. The band also applies in 3D.
- **Immersal maps (n)**, collapsible, only when the map has Immersal alignment (`14`, `15`): explanation
  text; a list of scans (colour swatch, name, Immersal id, "first" marks the reference scan, a visibility
  checkbox); **+ Add Immersal map…** (asks for id and a display name; max 8); for the selected scan:
  **Turn** slider (−180…180°) + number, **x / z / height** in metres, **Move scan** mode (drag the scan on
  the canvas, Alt/Option-drag rotates; arrow keys nudge 10 cm, Shift 1 m; `[` `]` turn 1°, Shift 5°),
  **Remove** (confirms; the last scan cannot be removed), and an **overlap readout** showing how well the
  selected scan lines up with the others.
- **Connectivity warning** (`10`): "⚠ 1 place not connected to the route network: Café. Guidance cannot
  reach them." plus **Auto-connect isolated places** (joins each to its nearest place, then asks you to
  check and save). Saving with disconnected places asks for confirmation.

### Right column: Place inspector (when a place is selected, `02`, `03`)
- Heading `Node <id>` (the stable id, e.g. `point-a`).
- **Name**.
- **Type**: Destination (navigable) · Junction (routing only) · Exhibit (navigable + announced) ·
  Hazard (announced, warning haptic).
- **Announce within** (exhibit and hazard only): slider 0.5–10 m + number field (up to 20 m), "Use
  default" link (2.5 m). "Spoken when a visitor comes this close."
- **Spoken description** (textarea: what the app says on arrival).
- **Aliases** (comma separated: other words visitors might say, e.g. "bathroom, toilet").
- Explore fields: **Visit minutes**, **Highlight** (Must see · Good · If there's time · Not a tour stop),
  **Tags** (comma separated), **About** (used by the AI to answer questions), **Photo URL**.
- **x (m) / z (m)** number fields.
- **Edges**: list of places this one connects to.
- **Delete node** (confirms).

### Right column: Path inspector (when a path is selected, `04`)
- Heading "Edge", "Place A ↔ Place B", length in metres, **Delete edge**.

### Right column: Files
- **Export graph JSON** (download), **Import graph JSON** (file picker; replaces the graph, then "Save to
  publish"), **Download ARWorldMap**, **Download point cloud (.f32)**.

### Right column: Legend
- The four place colours, and a note on axes and height colouring.

### 3D view (`13`)
- Full-screen overlay: orbit by drag, zoom by wheel or pinch, double-click to reset; **Reset view**,
  **Close** (or Esc). The Scan view height band applies. Places are shown as dots at floor height. Status
  line: `30304 points · nodes shown as dots at floor height`.

### Status bar (bottom)
- One line of feedback for every action: `Loaded v5: 18 nodes, 17 edges, 9234 points.`,
  `Saving…`, `Uploading 9234 points…`, `Saved as v6. The app fetches it on next launch.`,
  `Fetching Immersal map 151703…`, `4 Immersal scan(s) loaded.`, errors in red
  (`Save failed: …`, `Point cloud failed: …`, `Immersal localizes against at most 8 maps at once.`).

### Dialogs that are native browser prompts today (all need designed replacements)
- New map name · Immersal map id · name for an imported map · "map already exists, save as its next
  version?" · Immersal id + display name when adding a scan · "Delete <place> and its edges?" ·
  "Remove Immersal <id> from this map? Its scan stays on Immersal." · "Discard unsaved changes?" ·
  "N place(s) are not connected… Save anyway?"

### Constraints
- Static HTML/JS on our own server; no build step today (a small framework is fine if the design needs it).
- No login today: anyone with the URL can edit. A sign-in or read-only viewer state is welcome in the design
  but optional.
- Maps up to ~30 000 points and ~50 places today; the design should still read at 200 places.

### Ideas worth designing for (not built yet; label them as future)
- Version compare (what changed between v4 and v5) and an explicit **Restore** action.
- A "Publish" status: which version the phones are on, last sync.
- A place list / search beside the canvas (jump to a place by name).
- Tour preview: the Explore tour order drawn on the map with total minutes.

## Screenshot index
| File | Shows |
|---|---|
| `01-overview.png` | Flower Dome 1 Oct, v5, nothing selected |
| `02-node-selected.png` | Exhibit "Point A" selected, inspector top |
| `03-node-selected-scrolled.png` | Same, inspector scrolled to the explore fields, x/z, edges, delete |
| `04-edge-selected.png` | A path selected |
| `06-explore-tour-panel.png` | Explore tour panel open |
| `07-scan-view-panel.png` | Scan view panel with histogram |
| `08-scan-floor-band.png` | Floor preset applied |
| `09-density.png` | Density drawing on |
| `10-connectivity-warning-unsaved.png` | A disconnected place ("Café", added for the screenshot, not saved) |
| `11-path-mode.png` | Path mode active |
| `12-connect-mode.png` | Connect mode active |
| `13-3d-view.png` | 3D viewer (Flower Dome) |
| `14-immersal-maps-panel.png` | Flower Dome with four Immersal scans, one colour each |
| `15-immersal-scan-selected.png` | One scan selected: turn, x/z/height, Move scan, Remove |
| `16-empty-graph-scan-only.png` | A map with a scan and no places yet |
| `17-mobile-390.png` | Current (broken) narrow layout |
