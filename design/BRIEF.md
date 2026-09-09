# AISEE-BIN — UI design brief for Claude Design

Paste the **Prompt** section into Claude Design and attach everything in `screenshots/` and `assets/`.
The rest of this file is reference detail you can paste in or answer follow-up questions from.

---

## Prompt

Design the UI for **AISEE-BIN** (AiSee Botanic Indoor Navigation), an iOS app and a companion web map editor, built by **FlowsXR** for **AiSee**. The functionality exists and works; the screenshots show the current unstyled state. Keep every element and behaviour, redesign the look, layout, hierarchy and micro-interactions.

**What the product does.** A blind or low-vision visitor wears an iPhone Pro in a chest or lanyard mount inside a botanical greenhouse. The phone tracks its position with ARKit and gives turn-by-turn guidance by voice and haptics. The visitor talks to the app (push-to-talk button, the iPhone Action Button, or Siri): "take me to the orchids", "where am I", "what's nearby", "repeat", "stop". A sighted staff member scans the space once in an Authoring mode and marks places; the map is uploaded to a server and fine-tuned in a web editor; the phone downloads the latest version automatically.

**Three audiences, three surfaces:**
1. **Navigate mode (iPhone)** — primary user is blind. The screen is secondary to audio, but it must be usable by a sighted helper at a glance and fully VoiceOver-accessible. Very large tap targets, one enormous push-to-talk control, unambiguous state (listening / speaking / relocalizing / tracking ready / navigating / arrived / off-route), high contrast, works in bright greenhouse light. Minimal text, big type.
2. **Author mode (iPhone)** — sighted mapper. Camera preview with scan quality, list of marked places, "Mark here", type picker (Destination / Junction / Exhibit / Hazard), description field, connect / chain / delete, Save, Upload with a real progress bar, Import latest. Dense but calm, like a pro tool.
3. **Web map editor (desktop browser, dark UI acceptable)** — top-down canvas of the scanned feature-point cloud with the navigation graph drawn on top; version list; node inspector (name, type, spoken description, aliases, x/z); modes Select / +Node / Connect / Path; Undo/Redo; Fit; save as new version with a note; warnings for places not connected to the route network.

**Brand.** AiSee: lavender purple `#9B87E8` with the off-white "hand" glyph `#F7F5FD` (see `assets/aisee-logo.png`, `aisee-logo-white.png`, `aisee-app-icon.png`). FlowsXR: indigo `#5667CC` (see `assets/flowsxr-logo-dark.svg`, `flowsxr-logo-light.svg`, `flowsxr-mark.png`). AiSee is the product brand and should lead; FlowsXR appears as "built by FlowsXR" in settings/about and the editor footer. Please propose an app icon for AISEE-BIN derived from the AiSee glyph with a navigation/botanic cue (leaf, path or waypoint).

**Accessibility is the design constraint, not a checklist item.** WCAG AA contrast minimum (AAA preferred on the Navigate screen), Dynamic Type up to accessibility sizes without truncating instructions, targets ≥ 60 pt on Navigate, no meaning carried by colour alone (pair with icon + label), reduced-motion variants, and a layout that survives being read top to bottom by VoiceOver. The visitor may never look at the phone; the helper may glance for one second.

**Deliverables.** iPhone 17 Pro frames for: Navigate idle (no destination), Navigate relocalizing, Navigate listening, Navigate active route (instruction banner + distance + arrow), Navigate arrived, Navigate off-route, Author scanning (empty), Author with marked places, Author uploading (progress), Node form sheet, "Something went wrong" alert. Web editor: desktop 1440-wide layout with a node selected, plus the connectivity warning state. A short style guide: colour tokens (light + dark), type scale, component set (status pill, progress card, talk button, instruction banner, destination picker, node row, toolbar), iconography, haptic/voice state legend.

---

## Reference: current screens and every element on them

### Navigate mode (iPhone)
Top: segmented control **Navigate | Author**.
Over a live rear-camera view (black in the simulator screenshot):
- **Localization status pill**: dot + text. States: `Initializing…` (yellow), `Relocalizing…` (yellow), `Tracking Ready` (green, with a map icon when relocalized to a saved map), `Limited: Moving too fast` / `Limited: Not enough visual detail` (red), `ARKit not supported`, `Not started`.
- **Sync line**: `Checking server for map updates…`, `Map v4 (latest)`, `Updated to map v4`, `Sync failed: …`, or a **download progress card** `Downloading map v4 — 37%` with a bar.
- **Navigation banner** (only while navigating): big turn arrow (straight / slight left / left / sharp left / slight right / right / sharp right / U-turn), instruction text (`Turn left toward Window`), `3 m to next · 12 m total`. Turns orange with `Off route — recalculating` when off route.
- **Status message** (when not navigating): e.g. `Arrived at Window.`, `Heard: "take me to the window"`, `No route to Window. The Window is not connected to any path on this map.`
- **Debug overlay** (optional, monospaced): fps, tracking state, feature count, mapping status, x/z, heading, sub-goal, anchored nodes, route node list, last spoken text.
Bottom card:
- **Talk button** (largest control): idle `Tap to talk` with example phrases; listening state turns red, shows a waveform and the live transcript.
- **Destination picker** (menu): leaf icon + `Choose destination` / chosen name.
- **Start Guidance** (primary, disabled until tracking is ready and a destination is chosen) / **Stop** (destructive) while navigating.
- **⋯ menu**: Check Server for Map Updates, Restart Tracking, Discard Local Map, Mute Voice, Debug Overlay.

Voice/haptic vocabulary (design a legend for it): one firm tap = "listening"; double tap = "heard you"; two soft taps = turn left; long buzz = turn right; three low rumbles = off route or tracking lost; rising triple tap = arrived. Spoken prompts: `In 3 meters, turn slight right toward the Palm Conservatory.`, `You have arrived at the Orchid Display.`, `You are between the Window and the Main Entrance, about 7 meters from the Window, ahead.`, `Nearby: Laptop, 2 meters on your right. Window, 5 meters ahead.`

### Author mode (iPhone)
- Camera preview (240 pt tall) with feature points, overlaid monospaced scan status: tracking state, `mapping: limited|extending|mapped`, feature count, x/z, `trail: N pts`.
- ⋯ over the preview: Import Latest From Server, Continue Existing Scan (relocalize), Start Fresh Scan (destructive, confirm).
- **Progress card** (blue tint) with stage text, spinner or bar + percent: `Capturing world map…`, `Archiving world map…`, `Uploading world map v5 (31.7 MB) — 64%`, `Publishing version record…`, `Downloading world map v4…`.
- Orange warning: `Mapping is still limited; keep scanning for a more reliable map.`
- Status line, e.g. `Marked Orchid Display at x -6.0, z -14.0. Added 2 waypoints along the walked path.` / `Published as version 5.`
- **Marked nodes (N)** list; each row: name, type label, `x/z → neighbours`, description, link icon when it is the chain origin. Swipe right: Connect, Chain from. Swipe left: Delete. Tap: edit.
- Bottom bar: **Mark here** (primary), **Save** / **Save\***, **Upload** (shows spinner while busy).
- **Node form sheet**: Name, Type picker (Destination = navigable; Junction = routing only, never spoken; Exhibit = navigable and announced with description within 2.5 m; Hazard = never a destination, announced with warning haptic), Spoken description (multi-line), Cancel / Save. A hint line explains the chosen type.
- **Alert** `Something went wrong` with the error text and OK.

### Web map editor (desktop)
Header: `AISEE-BIN map editor`, Map dropdown (`default`, `+ New map…`), refresh, modes **Select / + Node / Connect / Path**, **Undo / Redo**, **Fit**, checkboxes `points` `labels`, note field `what changed?`, **Save as new version** (primary, asterisk when dirty).
Left: **Versions** list (`v4 web · date · note · 8 nodes · 13104 pts`), active highlighted, detail line below.
Centre: canvas. Grid with axis labels (x right, forward −z up), origin cross with forward tick, point cloud coloured by height (blue floor → yellow high), edges with length labels (`3.8 m`), nodes as coloured dots (destination blue `#2f80ed`, junction grey `#9aa0a6`, exhibit green `#27ae60`, hazard red `#eb5757`), dashed announce radius on exhibits/hazards, selection ring, yellow ring on the path/connect origin, dashed yellow ring on **disconnected places**. Bottom-left hint line, bottom-right live coordinates.
Right: **Map** (name, `8 nodes · 7 edges`, connectivity warning + `Auto-connect isolated places`), **Node** inspector (id, name, type select, spoken description, aliases, x, z, edges list, Delete node), **Edge** inspector (A ↔ B, length, Delete edge), **Files** (Export graph JSON, Import graph JSON, Download ARWorldMap, Download point cloud), **Legend**, explanatory text.
Footer status line (`Loaded v4: 8 nodes, 7 edges, 13104 points.`, errors in red, warnings in yellow).

### Assets included
- `assets/aisee-logo.png`, `assets/aisee-logo-white.png` — AiSee glyph (lavender / white).
- `assets/aisee-app-icon.png` — current AiSee app icon (dev variant, lavender background).
- `assets/flowsxr-logo-dark.svg`, `assets/flowsxr-logo-light.svg`, `assets/flowsxr-mark.png` — FlowsXR wordmark and mark.
- `screenshots/app-navigate-idle.png`, `screenshots/app-author.png` — current iPhone screens (simulator, so the camera area is black; on device it is the live camera).
- `screenshots/web-editor-scan.png` — editor with a real scan (point cloud + graph), `web-editor-sample-graph.png` — editor with a clean sample graph, `web-editor-mobile.png` — editor at phone width (stacked layout).
