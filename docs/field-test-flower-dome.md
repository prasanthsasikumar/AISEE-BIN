# Flower Dome field test — tester guide

**Goal:** test how well AISEE-BIN knows where you are along the tour route, from the entrance through Point 4,
with AiSee glasses (iPhone and Android) and with an iPhone alone. Every result uploads to the team automatically.

## Before you go

- **iPhone:** install the latest AISEE-BIN build from TestFlight.
- **Android:** install the latest release. Uninstall any older test copy first.
- **Glasses:** charge them fully, and pair them with the phone in Bluetooth settings.
- **Choose the map:**
  - **iPhone:** open the **Author** tab, tap **⋯ → Import Map From Server…**, pick **Flower Dome**, then go back to **Navigate**.
  - **Android:** go to Map → Choose map… → **Flower Dome**.
- **Download the map while you have good internet:** on the iPhone, Settings → Immersal → Download maps for offline use. Android downloads it automatically when you pick the map.
- **Mobile data:** the iPhone needs mobile data on site for step 1.

## 1. Link the scans (iPhone, about 10 minutes)

The route was scanned in several pieces. This walk lines them up exactly.

1. Use the phone, not the glasses: on the Glasses screen (**⋯ → Glasses…**), **Use glasses for positioning** must be off.
2. Open **⋯ → Field Test…**.
3. Under **1 · Link scans**, tap **Start walk**.
4. Walk the whole route from the entrance to Point 4 **slowly**, holding the phone up at chest height and pointing it along the path.
   - Pause for about 10 seconds wherever one scanned area meets the next.
   - Check the fix counts under Start walk: every scan should get some.
5. Tap **Stop walk**. Each scan should say *placed via …* with a spread in green.
6. Tap **Publish linked placements**.

## 2. Mark the points (iPhone, about 10 minutes)

1. Walk the route again with the phone. Wait until **Position** shows numbers, not *not found yet*.
2. At each point (A, Door B, Door C, Flower Dome, Point 1, Point 2, Point 3, Bottle trees, Point 4):
   1. Stand **exactly** on the spot.
   2. Tap **Mark**.
   3. Keep still for 5 seconds.
3. Tap **Publish N marks** at the end.

Marks are kept if you close the screen. If the map changes before you publish them (for example after step 1), they're cleared so you can mark again. Mark in phone mode: it's steadier than the glasses.

## 3. Walk the tour

1. Put the glasses on.
2. Start positioning with the glasses:
   - **iPhone:** on the Glasses screen, connect them and turn on **Use glasses for positioning**.
   - **Android:** connect, tap **Start camera** and then **Start positioning**.
3. Walk the route. Each point's short cue plays as you arrive; Doors B and C warn you to stop.
4. Press the glasses' button any time to hear "where am I".

Do this once with an iPhone and once with an Android phone. On the iPhone, also try it once with the phone alone, in phone mode.

## 4. Accuracy checks

At each point, stand on the spot and tap **I'm here**. The app listens for 10 seconds, then shows how far off it was.

- **iPhone:** ⋯ → Field Test… → **3 · Accuracy check**.
- **Android:** the **Field test** card. Tap **Reload map** first, so it has the points marked on the iPhone, then start positioning again.

Do the checks in each setup:
- iPhone with the glasses
- Android with the glasses
- iPhone alone

## 5. Finish

Tap **Send log** on every phone you used: at the bottom of Field Test on the iPhone, or in the Field test card on Android.

**If something goes wrong,** note the time and what you did, and send the log anyway.
