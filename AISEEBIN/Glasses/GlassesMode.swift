import Foundation

/// How the glasses are used once they connect: the phone in a pocket (the
/// glasses position alone, with the pedometer and gyro between fixes) or on a
/// lanyard (ARKit on the phone tracks; both cameras send fixes). Remembered,
/// so the auto-switch on connect goes to the mode the user chose last.
enum GlassesMode: String, CaseIterable {
    case pocket, lanyard

    static let key = "positioning.glassesMode"

    static func load(from defaults: UserDefaults = .standard) -> GlassesMode {
        defaults.string(forKey: key).flatMap(GlassesMode.init(rawValue:)) ?? .pocket
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.key)
    }

    var source: PositioningSource {
        self == .pocket ? .glasses : .lanyard
    }

    init?(source: PositioningSource) {
        switch source {
        case .glasses: self = .pocket
        case .lanyard: self = .lanyard
        case .phone: return nil
        }
    }

    var label: String {
        self == .pocket ? "Glasses, phone in pocket" : "Lanyard + glasses"
    }
}
