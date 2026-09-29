# AISEE-BIN for Android (glasses prototype)

A glasses-only visitor app: the AiSee glasses' camera positions the visitor with
Immersal, and the app answers "where am I" by voice. The phone stays in a pocket;
its own camera and ARCore are not used, so phones without ARCore (the Huawei
Nova 5T it was built on) work. Maps are authored on iPhone or in the web editor
and read from the same Supabase table.

Started 2026-09-29. Out of scope here: routing and turn-by-turn guidance, Author
mode, and phone-only positioning.

## How it fits together

| Piece | Where | Notes |
|---|---|---|
| Glasses link | `glasses/GlassesController.kt` | Realtek SmartWear SDK 1.8.48. Classic-Bluetooth control link, with the camera on the glasses' Wi-Fi hotspot (`WIFI_AP`, RTSP at 192.168.43.1:554). The SDK joins the hotspot with a network request, so the phone's default network is untouched. |
| Frames | `cpp/aiseebin.cpp`, `glasses/GlassesFrames.kt` | Decoded frames arrive from the SDK's native player (`rtk_player_set_video_frame_callback`, YUV420P). We keep the latest Y plane. |
| Localizing | `immersal/Localizers.kt` | `AutoLocalizer` uses the cloud (`/localizeb64`) when the default network has internet, and Immersal's on-device plugin otherwise. The on-device path needs the map file, which the app caches when a map is picked. |
| Pose → map | `immersal/Immersal.kt`, `map/NavigationMap.kt` | Same conventions as iOS: row-major, CV camera, `ImmersalAlignment`. |
| "Where am I" | `map/NavigationMap.kt` (`LocationDescriber`), `Speaker.kt` | Same wording as iOS. It triggers on a glasses button press or the on-screen button. |
| Announcing places | `positioning/Walking.kt` (`ProximityAnnouncer`, `FixGate`), `positioning/Odometer.kt` | Exhibits and hazards are spoken on entering their radius, set per place in the web editor (default 2.5 m). A hazard interrupts speech and buzzes; an exhibit waits its turn. A fix that jumps further than the step counter says you walked is dropped, and the filter re-anchors after 3 in a row. The step counter needs the Physical-activity permission; without it, walking pace is assumed. |
| Screen | `MainActivity.kt`, `ui/MapCanvas.kt` | One Compose screen: glasses, map, positioning, settings and log. |

## Building

- **Requirements:** Android SDK with NDK 27.3.13750724 and CMake 3.31.6 (both installable with `sdkmanager`), plus Android Studio's JDK.
- **Build and install:**
  ```
  cd android
  JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ./gradlew :app:installDebug
  ```
- **Immersal token:** baked in from `~/.config/aiseebin/immersal_pro_token`, as on iOS. It's never in the repo. A token typed in Settings overrides it.
- **Immersal's native plugin** (`libPosePlugin.so`, SDK 2.4.0) may not be redistributed. The build downloads it from Immersal's public Unity SDK repo and checks its sha256, the way iOS uses `Vendor/Immersal/fetch.sh`. Without it the app uses the cloud only.
- **Realtek libraries** are vendored in `app/libs`, as delivered (they have no Maven coordinates). The vendor's reference app and guides are in `~/Downloads`, in `Android_AIGlass_APP_Sourcecode_v0.5.55(235038) (1).zip` and `smartwear-lib-v1.8.48 2.zip`.

## Testing on the phone

1. **Pair the glasses** in Android's Bluetooth settings. They show up as `AiSee-G1_xxxx`.
2. **Open AISEE-BIN** and grant the permissions it asks for.
3. **Glasses → Connect…** and pick `AiSee-G1_xxxx`. Next time the app reconnects by itself.
4. **Map:** it picks the first map with an Immersal alignment and caches its Immersal file for offline use. Use **Choose map…** to pick the space you're standing in: `husselindoor`, `kunalresort` or `kunalresort2`.
5. **Start camera.** Keep the app on screen, and tap **Connect** on Android's "connect to device" Wi-Fi prompt. Android only lets a foreground app join the glasses' hotspot.
6. **Start positioning,** then look around slowly. The first fix is announced. After that, a glasses button press or **Where am I?** speaks the position.

**Debug builds** can be driven over USB, even with the phone locked:

```
adb shell am broadcast -a com.flowsxr.aiseebin.DEBUG -p com.flowsxr.aiseebin --es cmd <command>
```

- **Commands:** `connect`, `disconnect`, `camera`, `stopcamera`, `position`, `stopposition`, `whereami`, `devices`, `fakefix --ef x <m> --ef z <m> --ef h <rad>`.
- **Map:** `map --es slug <slug>`.
- **Self-test:** `selftest --es pattern flat|noise|file`. `file` reads `files/test.png` from the app's external files directory.
- **Fake frames:** `fakeframes --es pattern file` feeds positioning a still image in place of the camera.

Logs go to logcat under `AISEEBIN`, `Glasses` and `aiseebin-native`. The app's own log is on screen under **Log**.

## Verified on the Nova 5T (2026-09-29, phone locked, no SIM)

- **Glasses link:** connect, SDK init and auto-reconnect to `AiSee-G1_0162` all work.
- **Maps:** the server map list and map loading work. Map 151658 was cached for offline use (token-first `/map` query).
- **Immersal plugin:** it loads (`libPosePlugin.so`, 2.4.0).
- **On-device localize:** a flat frame took 1.3 s. A real photo took 3.4–3.8 s with 4 threads, and 4.4 s with the default thread count. Both were "no match", as expected, because the frames weren't of the mapped space.
- **Cloud localize:** a 960-wide photo took 0.9–2.7 s, "no match" as expected.
- **Camera start:** the glasses bring up their hotspot. Joining it needs the app in the foreground to tap Android's Wi-Fi prompt, so it was **not verified** with the phone locked.

**Your first field session (2026-09-29, PSK room, map 151810):** 25 fixes in 168 tries. On-device fixes had a median of 288 ms (207 ms and up). No-match tries took 0.45–0.7 s. Announcements were checked on the phone with injected positions (`fakefix --ef x --ef z --ef h`).

**Still owed:**
- A real fix against a mapped space.
- The live preview and frame callback with the stream running.
- How the temple button presses arrive: every event is logged as `button: …` and `key event …`.
- Whether the on-device path keeps up while walking.
