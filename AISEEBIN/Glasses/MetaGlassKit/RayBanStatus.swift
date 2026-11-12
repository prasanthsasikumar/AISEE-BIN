//
// RayBanStatus.swift — MetaGlassKit
//
// The parts of the Ray-Ban Meta connection that need no SDK: how the raw
// facts combine into the one status the Glasses screen shows, and what the app
// does when the glasses go away. Foundation only, so the tests cover it.
//

import Foundation

/// Where the Ray-Ban Meta connection stands. The Glasses screen shows the one
/// step that is still missing.
enum RayBanStatus: Equatable {
    /// The Meta AI app is not on this phone; nothing can be done from here.
    case metaAppMissing
    /// This app has not been approved in the Meta AI app yet.
    case needsRegistration
    case registering
    /// Registered, but the wearer has not allowed the camera.
    case needsCameraPermission
    /// Everything is allowed, but no glasses are linked right now.
    case noDevice
    case ready(name: String)
    /// Linked, but the glasses have suspended our session (taken off, "Hey Meta").
    case paused(name: String)

    /// What the rest of the app means by "the glasses are connected".
    var isConnected: Bool {
        switch self {
        case .ready, .paused: return true
        default: return false
        }
    }

    var deviceName: String? {
        switch self {
        case .ready(let name), .paused(let name): return name
        default: return nil
        }
    }
}

/// The raw facts `MetaGlassesLink` collects from the SDK.
struct RayBanInputs: Equatable {
    enum Registration: Equatable { case unavailable, available, registering, registered }

    var metaAppMissing = false
    var registration = Registration.unavailable
    var cameraGranted = false
    var deviceName: String?
    var linked = false
    var sessionPaused = false
}

extension RayBanStatus {
    static func resolve(_ i: RayBanInputs) -> RayBanStatus {
        if i.metaAppMissing { return .metaAppMissing }
        switch i.registration {
        case .registering: return .registering
        case .unavailable, .available: return .needsRegistration
        case .registered: break
        }
        guard i.cameraGranted else { return .needsCameraPermission }
        guard i.linked else { return .noDevice }
        let name = i.deviceName ?? "Ray-Ban Meta"
        return i.sessionPaused ? .paused(name: name) : .ready(name: name)
    }
}

/// What to do when Ray-Ban Meta glasses stop delivering, fed once a second
/// while they are the positioning source.
///
/// - The link is gone for `grace` seconds: fall back to the phone camera.
/// - Still linked but no frames for `grace` seconds (taken off, "Hey Meta",
///   another app): say so once and keep going on step counting. The phone is
///   in a pocket, so its camera would see nothing.
struct GlassesLossPolicy {
    static let grace: TimeInterval = 10

    enum Event: Equatable { case fallBackToPhone, announcePaused, announceBack }

    private var unlinkedSince: TimeInterval?
    private var framelessSince: TimeInterval?
    private var fellBack = false
    private var announcedPause = false
    /// A camera that has not delivered yet is starting, not paused.
    private var hasDelivered = false

    mutating func update(linked: Bool, framesFlowing: Bool, now: TimeInterval) -> [Event] {
        guard linked else {
            framelessSince = nil
            let since = unlinkedSince ?? now
            unlinkedSince = since
            if !fellBack, now - since >= Self.grace {
                fellBack = true
                announcedPause = false
                return [.fallBackToPhone]
            }
            return []
        }
        unlinkedSince = nil
        fellBack = false

        if framesFlowing {
            hasDelivered = true
            framelessSince = nil
            if announcedPause {
                announcedPause = false
                return [.announceBack]
            }
            return []
        }
        guard hasDelivered else { return [] }
        let since = framelessSince ?? now
        framelessSince = since
        if !announcedPause, now - since >= Self.grace {
            announcedPause = true
            return [.announcePaused]
        }
        return []
    }
}
