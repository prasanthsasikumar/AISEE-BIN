import Foundation
import PosePlugin
import simd

/// Immersal's native plugin (`Vendor/Immersal/libPosePlugin.a`): maps loaded
/// into memory from their `.bytes` files, and localization computed on the
/// phone with no network and no token.
///
/// The plugin's thread safety is undocumented and Immersal's own SDK issues
/// one call at a time from a worker thread, so every call here is serialised
/// behind one lock. `localize` blocks for the solver's duration (tens to a few
/// hundred milliseconds): call it off the main actor.
///
/// On the simulator the library is replaced by stubs that fail every call,
/// which is also how a corrupt map behaves on a device.
final class ImmersalNative: @unchecked Sendable {

    static let shared = ImmersalNative()

    /// The device library is arm64-only; the simulator has stubs.
    static var isAvailable: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return true
        #endif
    }

    /// The plugin's `LocalizationMaxPixels`: the size the cloud path already
    /// sends, so a full ARKit plane costs the solver the same as a PNG did.
    static let maxPixels: Int32 = 960 * 720

    private let lock = NSLock()
    private var handles: [Int: Int32] = [:]
    private var ids: [Int32: Int] = [:]
    private var configured = false

    var loadedMapIDs: [Int] { lock.withLock { handles.keys.sorted() } }

    /// Loads `data` (an Immersal `.bytes` map) as `mapID`. Loading an id that
    /// is already loaded is a no-op. Returns whether the plugin accepted it.
    @discardableResult
    func load(mapID: Int, data: Data) -> Bool {
        lock.withLock {
            if handles[mapID] != nil { return true }
            let handle: Int32 = data.withUnsafeBytes { raw -> Int32 in
                guard let base = raw.baseAddress else { return -1 }
                return icvLoadMap(base.assumingMemoryBound(to: CChar.self))
            }
            guard handle >= 0 else { return false }
            handles[mapID] = handle
            ids[handle] = mapID
            return true
        }
    }

    func unload(mapID: Int) {
        lock.withLock {
            guard let handle = handles.removeValue(forKey: mapID) else { return }
            ids[handle] = nil
            _ = icvFreeMap(handle)
        }
    }

    func unloadAll() {
        lock.withLock {
            for handle in handles.values { _ = icvFreeMap(handle) }
            handles.removeAll()
            ids.removeAll()
        }
    }

    /// Localizes one packed gray frame against every loaded map. Blocking.
    func localize(_ frame: GrayFrame, intrinsics: CameraIntrinsics) -> ImmersalLocalizeResult {
        let started = Date()
        let info: LocalizeInfo = lock.withLock {
            if !configured {
                _ = icvSetInteger("LocalizationMaxPixels", Self.maxPixels)
                configured = true
            }
            var k: [Float] = [intrinsics.fx, intrinsics.fy, intrinsics.ox, intrinsics.oy]
            var rot: [Float] = [0, 0, 0, 1]
            var loaded = Array(handles.values)
            if loaded.isEmpty { loaded = [-1] }
            var pixels = frame.pixels
            return pixels.withUnsafeMutableBytes { raw -> LocalizeInfo in
                guard let base = raw.baseAddress else {
                    var none = LocalizeInfo(); none.handle = -1; return none
                }
                // n = 0: consider every loaded map, as Immersal's SDK does.
                return icvLocalize(0, &loaded, Int32(frame.width), Int32(frame.height),
                                   &k, base, 1, 0, &rot)
            }
        }
        let latency = Date().timeIntervalSince(started)
        let mapID = lock.withLock { ids[info.handle] }
        guard info.handle >= 0, let mapID else {
            return ImmersalLocalizeResult(success: false, error: "no match", mapID: nil, pose: nil,
                                          latency: latency, requestBytes: frame.pixels.count)
        }
        let q = simd_quatf(ix: info.rotation.x, iy: info.rotation.y, iz: info.rotation.z, r: info.rotation.w)
        let pose = Self.rawPose(position: SIMD3(info.position.x, info.position.y, info.position.z), rotation: q)
        return ImmersalLocalizeResult(success: pose.isWellFormed, error: pose.isWellFormed ? "none" : "malformed pose",
                                      mapID: mapID, pose: pose,
                                      latency: latency, requestBytes: frame.pixels.count)
    }

    /// The plugin's pose in the shape the REST client returns: `r00…r22` row
    /// major. Immersal's SDK builds the REST matrix into the same struct the
    /// plugin fills, so the two agree by construction and
    /// `ImmersalPose.cameraPoseInMap` reads both.
    static func rawPose(position: SIMD3<Float>, rotation q: simd_quatf) -> ImmersalRawPose {
        let m = simd_float3x3(q)   // m[col][row]
        return ImmersalRawPose(px: position.x, py: position.y, pz: position.z,
                               r: [m[0][0], m[1][0], m[2][0],
                                   m[0][1], m[1][1], m[2][1],
                                   m[0][2], m[1][2], m[2][2]])
    }
}
