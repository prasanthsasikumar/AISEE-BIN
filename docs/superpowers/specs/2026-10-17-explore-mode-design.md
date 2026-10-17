# Explore mode: a timed, ask-anything visit for sighted visitors

Status: approved 2026-10-17 (build today, test on site today). Branch `explore-mode` (worktree `../AISEE-BIN-explore`).

## Intent

AiSee want a second Flower Dome proof of concept, this time for **sighted members of the public**. A visitor
walks in at the entrance, says how much time they have, gets a short custom tour that fits that time, and is
guided stop to stop. At any moment they can point the phone at something, tap, and ask about it out loud.

The current app is built for blind visitors: voice first, phone on the chest, a dark high-contrast screen.
Explore mode reuses everything underneath (maps, positioning, routing, the web editor, the Supabase backend)
and puts a completely different face on it: **clean, light, simple, and readable at a glance by anyone who
has never seen the app.**

## Goals

1. Anyone can start a visit at the entrance in two taps or one sentence ("I've got about 20 minutes").
2. The app plans a route through the Flower Dome's highlights that fits the time, shows it, and lets the
   visitor drop or add stops before starting.
3. It guides them stop to stop with a map and a short line of direction, and introduces each stop on arrival.
4. Tap, point, speak: the visitor asks a question about what the camera sees and gets a short answer, both
   spoken and shown, within about 3 seconds to the first words.
5. Answers about the Flower Dome come from content AiSee and Flower Dome write in the web editor, not from
   the model's imagination.

## Non-goals (this POC)

- Glasses. Phone only. The design keeps a seam for them (below) but builds nothing for them.
- Android.
- Languages other than English.
- Accounts, sign-in, payments, analytics dashboards.
- Changing how the blind-visitor Navigate mode behaves.

## Anti-goals (a failure even if it works)

- **Confidently wrong facts** about a plant or exhibit. A wrong answer said with authority is worse than "I'm
  not sure, but it looks like…".
- **A cluttered or technical screen.** No positioning badges, version numbers, debug text or mode switchers
  in front of the public.
- **Breaking the existing app.** Navigate, Author, Field Test and glasses work must behave exactly as before.
- **The Claude API key inside the app.** It must never ship in a build.
- **Collisions with the glasses testing work** happening in parallel on `glasses-frame-quality`.

## Constraints

- iOS 17, SwiftUI, the existing project (`project.yml` is the source of truth; the `.pbxproj` is generated).
- Positioning is whatever the phone already does: ARKit world map, or Immersal on the phone anchoring ARKit.
  The visitor holds the phone in front of them, which suits both.
- Backend is the existing Supabase Cloud project (`djfpemdkeguztyuerxqc`, Singapore). Maps come from
  `ab_map_versions` as today.
- Content (descriptions, durations, highlights) is written by AiSee and Flower Dome in the existing web
  editor. They are not developers, so every new field must be obvious in that editor.
- A separate Claude Code session is changing `AISEEBIN/Glasses/**`,
  `AISEEBIN/Managers/Immersal/ImmersalFrameEncoder.swift` and the `.pbxproj` right now.

## What was decided with Prasanth

- Flower Dome first. Phone only for now, glasses possibly later.
- Built **into the existing app**, not a new app.
- AiSee and Flower Dome add the descriptions.
- Every visit starts at the entrance, and the first thing asked is how much time they have.
- After planning, the visitor **sees the route first** and can adjust it before starting.
- Asking is **tap and speak, no typing**.
- The four-screen flow in the mockup (welcome → route preview → walking → asking) was approved:
  light theme, AiSee purple, one big Ask button while walking, answer spoken and shown as a caption over
  the camera.
- Use "one of our AI keys"; Prasanth left the choice to me (see §6).
- Map: **`labeltransfertest`** (the 1 Oct places on Yvonne's Immersal scan 151933) for now; a fresh whole-dome
  scan comes later.
- The tour **starts at Point A and ends at Point 3** for now, because the dome is only mapped that far.
- Build now; test on site today.

## How it works

### 1. Entry and isolation from the rest of the app

- A new `AppMode.explore`. When the app is in Explore it shows **only** the Explore screens: no
  `ModeSwitcher`, light colour scheme, no debug overlay.
- *Builder's call (mine):* a setting **"Start in Explore"** (UserDefaults, off by default) makes the app
  launch straight into Explore, for the phones handed to the public. Staff get back to the normal app with a
  hidden gesture: a long press (3 s) on the AiSee logo on the welcome screen. Navigate mode gets an
  "Explore" entry in the mode switcher so staff can open it.
- All new code lives in **`AISEEBIN/Explore/`** (views, view model, planner, AI client) and
  **`AISEEBINTests/Explore*`**. Changes to shared files are limited to:
  - `NavigationMap.swift`: new optional POI fields and map fields, decoded with defaults so old maps load
    unchanged.
  - `NavigationViewModel.swift` / `ContentView.swift`: the new mode case, and whatever small hooks the
    Explore view model needs to read position and drive guidance (see §4).
  - `project.yml`: nothing should be needed if `AISEEBIN/` is already a folder source; regenerate the
    `.pbxproj` with `xcodegen` rather than hand-merging it.
  - `web/index.html`, `web/app.js`: new editor fields.
- **Nothing under `AISEEBIN/Glasses/` or `AISEEBIN/Managers/Immersal/` changes.**

### 2. Screens

Light theme (`DS.A` tokens, AiSee purple `#6B4FD8` as the one accent), large type, generous spacing, one
primary action per screen. Every screen works one-handed.

1. **Welcome** (at the entrance). Eyebrow "Flower Dome", headline "How much time do you have?", four big
   buttons: 10, 20, 30, 45+ min. Below them, a microphone row: "Or just say it". The primary button is
   "Plan my visit". While positioning is still finding its feet, this screen is the place to wait: it does
   not block, but "Plan my visit" plans from the entrance node regardless of the live fix.
2. **Route preview.** A small map with the numbered stops and the path, then the list of stops, each with its
   minutes and an ✕ to drop it. A "+ Add a stop" row opens a sheet of the remaining exhibits. The button
   reads "Start · about 19 min" and updates as stops change. Over budget shows the total in amber with
   "a bit over your time", but still lets them start.
3. **Walking.** Top: "⏱ 14 min left" and "Stop 2 of 4". Middle: the map with a blue dot, the route line and
   the next stop. Card: "Next · 25 m ahead", stop name, one line of direction. Bottom: a large round **Ask**
   button, "Tap and ask about anything you see". A small "End visit" control in a corner.
4. **Arrived at a stop.** The card becomes the stop: name, photo if there is one, the short description
   (also spoken), and a "Next stop" button. Ask stays available.
5. **Asking.** Full-screen camera with a soft framing guide. Tap Ask (or tap anywhere on the camera) to
   start listening; listening shows a live waveform and the words as they are recognised. The answer appears
   as a caption card at the bottom, streamed in as it arrives, and is read aloud. Tap the card or swipe
   down to go back. A follow-up question can be asked straight away.
6. **Visit complete.** "That's your visit" with the stops seen, and Ask still available.

### 3. Planning a timed route

- **Input:** minutes from a button, or speech. Speech goes to the AI proxy's `plan` endpoint, which returns
  structured JSON: `{ minutes: Int, interests: [String], mustSee: [poiID] }`, using Claude structured
  outputs against the list of exhibit names and tags it is given. If speech fails or is unclear, fall back to
  the buttons; the buttons need no network.
- **Candidates:** POIs with `category == .exhibit` that are connected to the graph, except the tour start and
  end and any place whose Highlight is set to "Not a tour stop" (`highlight: 0`), which is how Door B and
  Door C stay out of the stop list.
- **Cost of a stop:** walking time + dwell time. Walking time is the A* path length between consecutive
  stops (from `PathfindingEngine`) divided by a stroll pace of **0.7 m/s** (*my call*, tune on site). Dwell
  time is the POI's `minutes` field, default 3.
- **Value of a stop:** its `highlight` level (1 = must see, 2 = good, 3 = if there's time, 0 = not a stop;
  default 2),
  boosted when its tags match the visitor's interests and forced in when it is in `mustSee`.
- **Start and end:** the map gets two new optional map-level fields, `tourStart` and `tourEnd` (POI ids),
  picked from dropdowns in the editor's map panel (*my call*). If `tourStart` is missing, the planner uses a
  POI with id `entrance`, and failing that the first destination. If `tourEnd` is missing, the tour ends
  back at the start.
- **Algorithm:** the venue has well under 30 exhibits, so a deterministic local search is enough: greedy
  insertion by value per minute, then 2-opt on the order, keeping total time ≤ 90% of the budget (a 10%
  buffer). Runs on the phone, instantly, with no network. **The model never computes the route.**
- **Editing in preview:** dropping a stop removes it and re-optimises the order; adding one inserts it at its
  cheapest position. The total is always recomputed from real path lengths.
- **Timing during the visit:** the clock starts at "Start". If the visitor falls more than 3 minutes behind
  the plan, the walking card offers "Running late: skip Olive grove?" (the lowest-value remaining stop). It
  is an offer, never automatic.

### 4. Guiding a multi-stop visit

- Today `RouteTracker` and `NavigationViewModel.startNavigation()` handle one destination. Explore needs an
  ordered list of stops. *Builder's call:* either an `ExploreViewModel` that owns a list of stops and starts
  one leg at a time through the existing navigation machinery, or a small multi-leg wrapper around
  `RouteTracker`. Whichever touches `NavigationViewModel` least wins.
- Positioning, A*, off-route replanning and arrival detection are reused as they are.
- **Sighted defaults:** Explore applies its own settings for the length of its session only and never writes
  over the saved Navigate settings (`guidance.beacon` and friends) (*my call*). No beeps (beacon off), no hazard-style alerts, light haptics only. Spoken cues are
  limited to stop introductions and arrivals; turn-by-turn speech is **off by default** with a "Voice
  directions" toggle on the walking screen. The screen carries the direction text.
- Arrival at a stop shows the stop card (§2.4) and speaks its short description. Moving on is the visitor's
  choice ("Next stop"); there is no auto-advance.

### 5. Asking about what the camera sees

- **Microphone:** `VoiceCommandRecognizer` already does push-to-talk with on-device recognition; Explore uses
  it in a free-dictation way (the transcript goes to the AI, not to `CommandParser`). Its 4 s silence timeout
  may need to be shorter for questions; that is a parameter, not a new recogniser.
- **Camera frame:** ARKit already owns the camera, so the frame comes from the current `ARFrame`
  (`capturedImage`), rotated upright, downscaled so the long edge is about 1024 px, JPEG ~0.7. No second
  camera session. The frame source sits behind a small protocol so the glasses can supply frames later.
- **Context sent with each question** (built on the phone):
  - the visitor's question;
  - the image;
  - the nearest few POIs (within ~15 m, nearest first, the one in front of the camera flagged), each with
    name, `details` and `about`;
  - the venue info text for the map;
  - the last few questions and answers of this visit (up to 3, younger than 5 minutes) so follow-ups like
    "how old is it?" work.
- **Model behaviour (system prompt):** a friendly Flower Dome guide; 2–3 short sentences; facts about the
  Flower Dome and its exhibits only from the supplied content; may describe and identify what is clearly
  visible from general knowledge, but says so plainly when unsure; never invents names, ages or numbers; if
  the question is unrelated or unsafe, a polite one-line redirect.
- **Delivery:** the answer streams back; text appears as it arrives and is spoken sentence by sentence with
  the system voice (`GuidanceManager.speak`). ElevenLabs is not used for dynamic answers (as today).
- **Latency target:** first spoken words within ~3 s of the visitor finishing the question, on Flower Dome
  Wi-Fi or 4G.
- **Failure:** no network or a timeout after 10 s → "Sorry, I couldn't answer that just now." spoken and
  shown; the visit continues unaffected.

### 6. The AI proxy (my pick)

- **Provider:** the Claude API. The key is the existing Anthropic key already on the FlowsXR VPS (used by
  Hermes, verified working); it is copied into the proxy's own env file. Later it should move to a dedicated
  key on the FlowsXR Console account, whose Claude API credits cover it.
- **Where:** a small Node service in a Docker container on the FlowsXR VPS, behind Caddy at
  `https://aiseebin.flowsxr.com/explore/ask` and `/explore/plan`, alongside the existing Immersal proxy. Why
  not a Supabase Edge Function: there is no Supabase Cloud access token to deploy one, and the VPS is already
  ours. Latency is a wash: Anthropic's API is in the US either way, and the VPS is in Buffalo, NY.
- Source lives in the repo under `server/explore/` (Dockerfile, `server.mjs`, tests), deployed by a script.
- The app sends an anonymous per-install id and a shared app token header (`X-Explore-Token`, baked in the
  build); the token stops casual drive-by use, not a determined attacker.
- **Model:** `claude-opus-5-5`, low effort, for both routes; the model id and effort come from the env file
  so they can change without a new build.
- `ask` streams the answer back to the app as plain-text chunks. `plan` returns JSON via structured outputs.
- **Limits (*my call*, fine for a POC):** 60 questions per install per hour, 2,000 calls per day overall, and
  `EXPLORE_ENABLED=0` in the env file switches both routes off between test days.
- **Logging for review:** each question, answer, map slug, nearby POI ids and latency are appended to a JSONL
  file on the VPS (`/var/lib/aiseebin-explore/log-YYYY-MM-DD.jsonl`). **Images are not stored.** Files older
  than 30 days are deleted by the service at start-up and daily. The welcome screen carries one small line:
  "Your questions are answered by AI. We keep the words, not the photos, to improve the guide." AiSee should
  confirm Flower Dome is happy with this before a public test.

### 7. Content in the web editor

New fields in the place panel, shown for exhibits:

| Field | JSON key | Meaning | Default |
|---|---|---|---|
| Visit minutes | `minutes` | How long a visitor typically spends here | 3 |
| Highlight | `highlight` | 1 must see · 2 good · 3 if there's time · 0 not a tour stop | 2 |
| Tags | `tags` | Comma-separated, e.g. `orchids, desert, kids` | none |
| About (for questions) | `about` | Longer facts the guide may use to answer questions | none |
| Photo | `photo` | Optional image shown on the stop card | none |

The existing **Description** (`details`) stays the short text spoken on arrival. A map-level **Venue info**
box (`venueInfo`) holds general facts (opening hours, toilets, café, the dome itself), next to the
**Tour start** and **Tour end** dropdowns (§3).

All new keys are optional and ignored by older app builds. Photos go to the existing `aiseebin-maps` bucket.
The editor's last-write-wins save caveat still applies; tell AiSee to edit from one browser at a time.

### 8. The glasses seam (not built)

The `ask` request takes "an image and a question"; it does not care where the image came from. The frame
source protocol (§5) and the microphone input (`VoiceCommandRecognizer.Input.external` already exists) are
the two places the glasses will plug in later.

## Build order (*my call*)

Built in three stages so there is something demonstrable early, each stage merged-ready on its own:

1. Content fields in the editor and app model, the planner, the welcome / preview / walking / arrived /
   complete screens with button-only planning and multi-stop guidance.
2. The proxy's `ask` route and the Ask screen.
3. The `plan` route and spoken time input.

## Testing

- Unit tests (XCTest, alongside the existing ones): the planner (fits the budget, honours must-see, start and
  end nodes, drop/add re-optimises, unreachable exhibits ignored), the POI decoding with and without the new
  fields, the context builder (nearest POIs, history window), and the late-running offer.
- Web editor: `node --test` for any new pure helpers.
- Proxy: `node --test` for its pure parts (limits, prompt building, log pruning) and a curl check against the deployed service with a sample image.
- Simulator: the welcome, preview and visit-complete screens render in the simulator with the sample map.
  ARKit and the camera need a device.
- On site at the Flower Dome: a 10-minute and a 20-minute visit, ten questions at different stops, with
  first-word latency noted.

## Left to the builder

- The exact split between `ExploreViewModel` and `NavigationViewModel` (§4).
- Planner internals, as long as they are deterministic and tested.
- Visual details within the approved mockup and the `DS` tokens.
- Prompt wording within §5's rules.

## Today's map setup

Publish a new `labeltransfertest` version with `tourStart: point-a`, `tourEnd: point-3`, Door B and Door C at
`highlight: 0`, and sensible `minutes` for the remaining exhibits, so today's test has a working tour before
AiSee's descriptions arrive. "Start in Explore" phones load `labeltransfertest` by default
(`ServerConfig.mapSlug` stays as it is; Explore picks its own default slug).
