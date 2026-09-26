# Immersal native plugin

On-device visual positioning against Immersal maps, so a visitor's phone
localizes with no network. See `docs/superpowers/specs/2026-09-26-offline-immersal-design.md`.

- `PosePlugin.h` — the plugin's C interface (MIT, from Immersal's iOS samples).
- `libPosePlugin.a` — Immersal SDK 2.4.0, arm64 device slice only. **Not
  committed**: Immersal's licence forbids redistribution. `fetch.sh` downloads
  it from Immersal's public SDK repository and checks its sha256; the Xcode
  project runs it as a pre-build step. Using it requires an Immersal licence
  (the project has a Pro account).
- `ImmersalNativeStubs.c` — simulator stand-ins so tests link.

Maps are downloaded per id from `GET https://api.immersal.com/map` into
`Documents/immersal-maps/<id>.bytes` by `ImmersalMapCache`.
