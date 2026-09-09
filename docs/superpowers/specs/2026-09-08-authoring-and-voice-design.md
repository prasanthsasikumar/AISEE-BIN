# AISEE-BIN Phase 2: Space authoring + push-to-talk voice

Approved 2026-09-08 (chat). Push-to-talk first; always-listening deferred.

## Goals
1. A sighted mapper can scan a greenhouse and annotate what is where, on device, without editing code.
2. A blind user can drive the app by voice, triggered by the Action Button, Siri, or a large on-screen button.
3. Annotations produce passive commentary (exhibits, hazards) while walking, not only routing targets.

## Map storage
- Each POI is stored as a named `ARAnchor` (`poi:<id>`) inside the `ARWorldMap`, so positions relocalize with the map.
- A sidecar JSON (`NavigationMap`, Codable) stores names, descriptions, categories, edges, and the last-known `x/z`
  (used as fallback in tests and when an anchor is missing).
- `MapStore` reads/writes the pair: `Documents/greenhouse.arworldmap` + `Documents/greenhouse.map.json`.
- On session start with a saved map, anchors from the world map override the JSON coordinates.
- Without a saved map the bundled `SampleGreenhouseMap` is used.

## POI model
`NavigationPOI` gains `category` (`destination`, `junction`, `exhibit`, `hazard`), `details: String?`,
`announceRadius: Float` (default 2.5 m for exhibit/hazard, 0 otherwise). `isDestination` becomes derived
from category (`destination` and `exhibit` are selectable; `junction`/`hazard` are not).

## Authoring mode (sighted mapper)
- Toggle from the ⋯ menu. Shows AR preview, world-mapping status, list of marked nodes.
- "Mark here": drops an anchor at the current camera pose, prompts for name / category / details.
  Edges: auto-link to the previously marked node (walk order). "Connect to…" links to any existing node.
  Delete node removes anchor + edges.
- "Save map" writes world map + JSON. Requires `.mapped` or `.extending`.
- Pure logic (`MapAuthoringSession`): add node, chain edge, connect, remove, produce `NavigationMap`. Unit tested.

## Voice (blind user)
- Trigger: `StartListeningIntent` (App Intent, bindable to Action Button and Siri), on-screen push-to-talk button.
  `NavigateToIntent` with an `AppEntity` of POIs so Siri can route directly by name.
- Recognition: `SFSpeechRecognizer`, on-device where available, single utterance, 4 s silence timeout, 10 s hard cap.
  Speech output is stopped when listening starts; recognition never runs while the synthesizer speaks.
- Parsing: `CommandParser` (pure, tested). Verbs: take me to / navigate to / go to <poi>; where am I;
  what's around / nearby; repeat; stop / cancel. POI matching is case-insensitive token overlap with a threshold,
  so "the orchids" matches "Orchid Display".
- Responses: whereAmI → nearest node + distance; whatsNearby → up to 3 POIs within 10 m with left/right/ahead;
  repeat → last instruction; unknown → "I didn't catch that" + list of destinations on second failure.

## Passive commentary
`ProximityAnnouncer` (pure, tested): when the user enters `announceRadius` of an exhibit/hazard, announce once
with side ("on your left"); re-arms after leaving 1.5× radius. Hazards use the off-route haptic; exhibits no haptic.
Runs whether or not navigating, but never while tracking is unreliable.

## Permissions
`NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription` added.

## Out of scope (next)
Always-listening / wake word, Apple Watch trigger, image-marker re-anchoring, multi-map registry.
