import Foundation

/// One way of turning a camera frame into an Immersal fix. The phone
/// localizer and glasses positioning depend on this and nothing else, so
/// whether the answer came from the phone or from Immersal's servers is
/// invisible to them.
protocol ImmersalLocalizer: Sendable {
    /// For status screens: `"on device"` or `"cloud"`.
    var name: String { get }
    func localize(_ frame: GrayFrame, intrinsics: CameraIntrinsics) async -> ImmersalLocalizeResult
}

/// The native plugin, run off the main actor so a 200 ms solve never stalls
/// the UI or the ticker.
struct NativeImmersalLocalizer: ImmersalLocalizer {
    var native: ImmersalNative = .shared
    var name: String { "on device" }

    func localize(_ frame: GrayFrame, intrinsics: CameraIntrinsics) async -> ImmersalLocalizeResult {
        let native = self.native
        return await Task.detached(priority: .userInitiated) {
            native.localize(frame, intrinsics: intrinsics)
        }.value
    }
}

/// `/localizeb64`: the frame is PNG-encoded and posted. Behaviour as before
/// this protocol existed.
struct CloudImmersalLocalizer: ImmersalLocalizer {
    var token: String
    var mapIDs: [Int]
    var session: URLSession = .shared
    var name: String { "cloud" }

    func localize(_ frame: GrayFrame, intrinsics: CameraIntrinsics) async -> ImmersalLocalizeResult {
        guard let png = ImmersalFrameEncoder.png(from: frame) else {
            return ImmersalLocalizeResult(success: false, error: "encode", mapID: nil, pose: nil,
                                          latency: 0, requestBytes: 0)
        }
        var client = ImmersalClient(token: token, mapIDs: mapIDs)
        client.session = session
        return await client.localize(pngData: png, fx: intrinsics.fx, fy: intrinsics.fy,
                                     ox: intrinsics.ox, oy: intrinsics.oy)
    }
}
