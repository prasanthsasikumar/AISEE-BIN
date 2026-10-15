import CoreMotion
import Foundation
import simd

/// The body's turn about the vertical since `start`, in radians,
/// clockwise-positive like the graph heading. Abstracted so positioning can
/// be tested with a scripted turn. 0 when no sensor is available.
protocol TurnSource: AnyObject, Sendable {
    var turn: Float { get }
    func start()
    func stop()
}

/// Pure integrator. The rotation rate projected on gravity, both in the
/// device frame, is the rate of turn about the vertical whatever way the
/// phone sits in a pocket. A right-handed rotation about *up* is a left turn
/// and gravity points *down*, so `ω · ĝ` is clockwise-positive as it is.
struct TurnIntegrator: Equatable {
    private(set) var turn: Float = 0
    private var lastTime: TimeInterval?

    mutating func reset() {
        turn = 0
        lastTime = nil
    }

    /// `rotationRate` in rad/s and `gravity` in any unit, both in the device
    /// frame. A sample whose time is not after the last accepted one is dropped.
    mutating func add(rotationRate: SIMD3<Double>, gravity: SIMD3<Double>, time: TimeInterval) {
        guard let last = lastTime else {
            lastTime = time
            return
        }
        guard time > last else { return }
        let g = simd_length(gravity)
        guard g > 1e-6 else { return }
        let rate = simd_dot(rotationRate, gravity / g)
        turn += Float(rate * (time - last))
        lastTime = time
    }
}

/// `CMMotionManager` device motion at 30 Hz. Needs no permission (unlike the
/// pedometer) and keeps delivering in the background while the app is alive
/// for audio or Bluetooth.
final class DeviceMotionTurn: TurnSource, @unchecked Sendable {
    private let motion = CMMotionManager()
    private let queue = OperationQueue()
    private let lock = NSLock()
    private var integrator = TurnIntegrator()

    var turn: Float { lock.withLock { integrator.turn } }

    func start() {
        guard motion.isDeviceMotionAvailable else { return }
        lock.withLock { integrator.reset() }
        motion.deviceMotionUpdateInterval = 1.0 / 30
        motion.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: queue) { [weak self] data, _ in
            guard let self, let data else { return }
            let rate = SIMD3(data.rotationRate.x, data.rotationRate.y, data.rotationRate.z)
            let gravity = SIMD3(data.gravity.x, data.gravity.y, data.gravity.z)
            self.lock.withLock { self.integrator.add(rotationRate: rate, gravity: gravity, time: data.timestamp) }
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
    }
}
