import Foundation

/// Pinhole model for a camera nobody calibrated.
///
/// The AiSee glasses publish no intrinsics, so the principal point is taken as
/// the image centre and a single focal length serves both axes. `focalPx` is
/// expressed at `referenceWidth` and scaled to whatever size the stream
/// actually delivers, because the H.264 stream negotiates its resolution and a
/// focal length in pixels only means something at one resolution.
///
/// The default corresponds to roughly 70° horizontal at 1280 px, a typical
/// wearable camera; `FocalCalibration` replaces it with a measured value.
struct GlassesCamera: Codable, Equatable {
    static let referenceWidth = 1280
    static let defaultFocalPx: Float = 900

    var focalPx: Float = defaultFocalPx

    var horizontalFOVDegrees: Float {
        2 * atan(Float(Self.referenceWidth) / (2 * focalPx)) * 180 / .pi
    }

    /// Intrinsics for an image of `width`×`height` pixels.
    func intrinsics(width: Int, height: Int) -> (fx: Float, fy: Float, ox: Float, oy: Float) {
        // The focal length is quoted against the frame's long edge, so a portrait
        // stream (Ray-Ban Meta, 720x1280) and a landscape one (AiSee, 1280x720)
        // share one definition.
        let f = focalPx * Float(max(width, height)) / Float(Self.referenceWidth)
        return (fx: f, fy: f, ox: Float(width) / 2, oy: Float(height) / 2)
    }

    // MARK: - Persistence

    /// Each kind of glasses has its own lens, so its own calibrated value.
    /// AiSee keeps the key it has always used.
    static func key(for kind: GlassesKind) -> String {
        kind == .aisee ? "glasses.camera.focalPx" : "glasses.camera.focalPx.\(kind.rawValue)"
    }

    /// The camera of the glasses currently chosen on the Glasses screen.
    static func load(from defaults: UserDefaults = .standard) -> GlassesCamera {
        load(kind: .load(from: defaults), from: defaults)
    }

    static func load(kind: GlassesKind, from defaults: UserDefaults = .standard) -> GlassesCamera {
        let stored = defaults.float(forKey: key(for: kind))
        return GlassesCamera(focalPx: stored > 0 ? stored : defaultFocalPx)
    }

    func save(to defaults: UserDefaults = .standard) {
        save(kind: .load(from: defaults), to: defaults)
    }

    func save(kind: GlassesKind, to defaults: UserDefaults = .standard) {
        defaults.set(focalPx, forKey: Self.key(for: kind))
    }
}
