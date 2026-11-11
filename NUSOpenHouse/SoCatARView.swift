import ARKit
import SceneKit
import SwiftUI
import UIKit

/// The live camera with SoCat standing on the floor a few metres ahead on the
/// route. SoCat is a flat sprite (placeholder art until NUS supplies SoCat)
/// that always turns to face the camera.
struct SoCatARView: UIViewRepresentable {
    let viewModel: NavigationViewModel
    let guide: TourGuide
    /// Where SoCat is relative to the screen, for the "SoCat is over there" arrow.
    var onScreenHint: (SoCatHint) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(viewModel: viewModel, guide: guide, onScreenHint: onScreenHint) }

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.session = viewModel.arManager.session
        view.automaticallyUpdatesLighting = true
        view.autoenablesDefaultLighting = true
        view.rendersContinuously = true
        view.scene.rootNode.addChildNode(context.coordinator.cat)
        context.coordinator.view = view
        context.coordinator.start()
        return view
    }

    func updateUIView(_ view: ARSCNView, context: Context) {
        context.coordinator.onScreenHint = onScreenHint
    }

    static func dismantleUIView(_ view: ARSCNView, coordinator: Coordinator) {
        coordinator.stop()
    }

    @MainActor
    final class Coordinator: NSObject {
        let viewModel: NavigationViewModel
        let guide: TourGuide
        var onScreenHint: (SoCatHint) -> Void
        weak var view: ARSCNView?
        let cat = SCNNode()
        private let sprite = SCNNode()
        private var link: CADisplayLink?
        private var shown: SIMD3<Float>?
        private var lastTick = CACurrentMediaTime()
        private var phase: Float = 0
        private var waving = false
        private var lastHint = SoCatHint.hidden

        /// Sprite height on the floor, metres.
        static let height: Float = 0.55
        /// How far ahead of the visitor SoCat walks, metres.
        static let lookAhead: Float = 2.5
        /// Fastest SoCat moves to catch up, metres per second.
        static let maxSpeed: Float = 2.2

        init(viewModel: NavigationViewModel, guide: TourGuide, onScreenHint: @escaping (SoCatHint) -> Void) {
            self.viewModel = viewModel
            self.guide = guide
            self.onScreenHint = onScreenHint
            super.init()
            setSprite(named: "SoCat")
            let billboard = SCNBillboardConstraint()
            billboard.freeAxes = .Y
            cat.constraints = [billboard]
            cat.addChildNode(sprite)
            cat.opacity = 0
        }

        private func setSprite(named name: String) {
            let image = UIImage(named: name) ?? UIImage(named: "SoCat")
            let aspect = image.map { Float($0.size.width / max($0.size.height, 1)) } ?? 1
            let plane = SCNPlane(width: CGFloat(Self.height * aspect), height: CGFloat(Self.height))
            let material = SCNMaterial()
            material.diffuse.contents = image
            material.isDoubleSided = true
            material.lightingModel = .constant
            material.writesToDepthBuffer = false
            plane.materials = [material]
            sprite.geometry = plane
            sprite.position = SCNVector3(0, Self.height / 2, 0)   // feet on the node's origin
        }

        func start() {
            let link = CADisplayLink(target: self, selector: #selector(tick))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
            link.add(to: .main, forMode: .common)
            self.link = link
        }

        func stop() { link?.invalidate(); link = nil }

        @objc private func tick() {
            let now = CACurrentMediaTime()
            let dt = Float(min(now - lastTick, 0.1))
            lastTick = now
            guard let target = targetPosition() else {
                fade(to: 0)
                shown = nil
                report(.hidden)
                return
            }
            // Ease toward the target, no faster than a brisk walk; jump if far (a fix moved us).
            var position = shown ?? target.position
            let delta = target.position - position
            let distance = simd_length(delta)
            if distance > 6 { position = target.position }
            else if distance > 0.001 { position += delta * min(1, Self.maxSpeed * dt / distance) }
            shown = position
            let moving = distance > 0.05 && !target.waiting
            phase += dt * (moving ? 9 : 2.5)
            let hop = moving ? abs(sin(phase)) * 0.05 : sin(phase) * 0.01
            cat.simdPosition = position + SIMD3(0, hop, 0)
            // Face the way SoCat walks: mirror the sprite when travel is to the screen's left.
            if let camera = view?.pointOfView, simd_length(target.facing) > 0.1 {
                let right = camera.simdWorldRight
                let side = right.x * target.facing.x + right.z * target.facing.y
                sprite.simdScale = SIMD3(side < 0 ? -1 : 1, 1, 1)
            }
            if target.wave != waving {
                waving = target.wave
                setSprite(named: waving ? "SoCatWave" : "SoCat")
            }
            fade(to: 1)
            report(hint(for: position))
        }

        private func fade(to opacity: CGFloat) {
            cat.opacity += (opacity - cat.opacity) * 0.15
        }

        private func report(_ hint: SoCatHint) {
            guard hint != lastHint else { return }
            lastHint = hint
            onScreenHint(hint)
        }

        private func hint(for position: SIMD3<Float>) -> SoCatHint {
            guard let view, view.bounds.width > 0 else { return .hidden }
            let p = view.projectPoint(SCNVector3(position.x, position.y + Self.height / 2, position.z))
            let onScreen = p.z > 0 && p.z < 1 && view.bounds.insetBy(dx: 20, dy: 40).contains(CGPoint(x: CGFloat(p.x), y: CGFloat(p.y)))
            if onScreen { return .visible }
            // Behind the camera, or off an edge: which way to turn.
            guard let camera = view.pointOfView else { return .hidden }
            let toCat = position - camera.simdWorldPosition
            let side = simd_dot(toCat, camera.simdWorldRight)
            return side >= 0 ? .right : .left
        }

        private struct Target { var position: SIMD3<Float>; var facing: SIMD2<Float>; var waiting: Bool; var wave: Bool }

        /// SoCat's spot in ARKit's session frame, or nil when it should not be drawn.
        private func targetPosition() -> Target? {
            let vm = viewModel
            guard vm.localizationStatus.isReliable else { return nil }
            let graphCamera = vm.currentTransform
            let arCamera = vm.arManager.cameraTransform
            // Graph frame → session frame (identity with an ARKit world map; the
            // Immersal anchoring otherwise).
            let graphToAR = arCamera * graphCamera.inverse
            let levels = vm.engine.levels
            let user = NavigationGeometry.planarPosition(of: graphCamera)
            let userFloorY = graphCamera.columns.3.y - BuildingLevels.cameraHeight

            func toAR(_ p: SIMD3<Float>) -> SIMD3<Float> {
                let v = graphToAR * SIMD4(p.x, p.y, p.z, 1)
                return SIMD3(v.x, v.y, v.z)
            }
            func toARDirection(_ d: SIMD2<Float>) -> SIMD2<Float> {
                let v = graphToAR * SIMD4(d.x, 0, d.y, 0)
                return SIMD2(v.x, v.z)
            }

            // Arrived: sit at the place and wave.
            if guide.phase == .arrived, let stop = guide.current, let node = vm.engine.node(named: stop.id) {
                let y = levels.floorHeight(of: stop.id) ?? userFloorY
                return Target(position: toAR(SIMD3(node.position.x, y, node.position.y)), facing: .zero, waiting: true, wave: true)
            }
            guard guide.phase == .leading, vm.isNavigating, !vm.routePath.isEmpty else { return nil }
            let targetIndex = max(0, min(vm.routeLeg - 1, vm.routePath.count - 1))
            let ids = Array(vm.routePath[targetIndex...])
            // Stairs or lift: wait at the foot (or the lift door) on the visitor's
            // own floor until the phone is on the new level. Walking the straight
            // line between floors would float SoCat through the stairwell.
            if targetIndex > 0,
               levels.levelChange(from: vm.routePath[targetIndex - 1], to: ids[0]) != nil,
               levels.level(forHeight: graphCamera.columns.3.y) != levels.level(of: ids[0]),
               let door = vm.engine.node(named: vm.routePath[targetIndex - 1]) {
                return Target(position: toAR(SIMD3(door.position.x, userFloorY, door.position.y)), facing: .zero, waiting: true, wave: false)
            }
            var stops: [GuidePlacement.Stop] = []
            for (i, id) in ids.enumerated() {
                guard let node = vm.engine.node(named: id) else { continue }
                let next = i + 1 < ids.count ? ids[i + 1] : nil
                stops.append(.init(planar: node.position, floorY: levels.floorHeight(of: id),
                                   holdHere: next.map { levels.levelChange(from: id, to: $0) != nil } ?? false))
            }
            guard let placed = GuidePlacement.place(from: user, userFloorY: userFloorY, stops: stops, lookAhead: Self.lookAhead) else { return nil }
            return Target(position: toAR(placed.position), facing: toARDirection(placed.facing), waiting: placed.waiting, wave: false)
        }
    }
}

/// Where SoCat is relative to the screen.
enum SoCatHint: Equatable {
    case hidden, visible, left, right
}
