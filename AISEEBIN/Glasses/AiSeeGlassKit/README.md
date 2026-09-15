# AiSeeGlassKit

Drop-in layer for the AiSee glasses (Realtek RTKAIDeviceConnection 1.6.4). Copy this folder verbatim.

Entry points: `AiSeeConnectionService` (scan/connect/battery), `AiSeeDeviceCoordinator` (`attach`/`detach` to bind a device connection, `capturePhoto` for still photos, `startLiveStream`/`stopLiveStream` for H.264 video with frame callbacks, `startMicrophone`/`stopMicrophone` for 16 kHz Int16 PCM — the only start/stop caller, and the only place the FINDINGS ordering rules are enforced).

Vendor-free files (no `RTKAIDeviceConnection` import, so they compile for the simulator too): `AiSeeSequencing`, `AiSeePCM` (in `AiSeePCMAdapter.swift`), `AiSeeH264Decoder`, `AiSeeTypes`. Of those, two are covered by the standalone `swiftc` suites in `tests/` — `AiSeeSequencing` and `AiSeePCM`. `AiSeeTypes` and `AiSeeH264Decoder` are not "pure": they pull in UIKit/CoreImage and VideoToolbox respectively.

Host requirements
- Link + embed the frameworks in `Vendor/RTK` for `iphoneos` only; gate search paths with `[sdk=iphoneos*]` if the host also builds for the simulator. All SDK code here is behind `#if canImport(RTKAIDeviceConnection)`; the `#else` stubs keep the host compiling.
- Info.plist: `NSBluetoothAlwaysUsageDescription`, `NSMicrophoneUsageDescription`, `NSLocalNetworkUsageDescription`, `UIBackgroundModes` `bluetooth-central` + `audio`.
- **The host must call `coordinator.attach()` on every connection change** (and `detach()` when it goes away). Nothing else binds the coordinator to a device; a stale binding is how a capture ends up talking to a dead connection.
- **The kit takes exclusive ownership of `connection.onAudioStreamStartedHandler` / `onAudioStreamFinishedHandler` / `onAudioStreamCancelledHandler`.** `AiSeeMicrophone` reinstalls them on every start (the SDK drops stream targets each time), so a host that sets them will have them overwritten — and overwriting the kit's will break the PCM chain.
- Never deactivate/reactivate `AVAudioSession` around `capturePhoto()` (FINDINGS §F).
- `AiSeeError.deviceWedged` means a power cycle is required; the coordinator latches `unavailableUntilReconnect` and fails every later `capturePhoto()` until a new connection is attached.
