import ARKit
import SceneKit
import SwiftUI
import UIKit

/// The live camera with the way drawn on it: arrows on the floor along the next
/// few metres of the route, a pin over the place being walked to, and a small
/// 3D staircase where the route goes up or down a floor.
struct RouteARView: UIViewRepresentable {
    let viewModel: NavigationViewModel
    let guide: TourGuide
    /// Where the arrows are relative to the screen, for the "turn left" prompt.
    var onScreenHint: (RouteHint) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(viewModel: viewModel, guide: guide, onScreenHint: onScreenHint) }

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.session = viewModel.arManager.session
        view.automaticallyUpdatesLighting = true
        view.autoenablesDefaultLighting = true
        view.rendersContinuously = true
        view.scene.rootNode.addChildNode(context.coordinator.root)
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
        var onScreenHint: (RouteHint) -> Void
        weak var view: ARSCNView?
        let root = SCNNode()
        private var arrows: [SCNNode] = []
        private let pin = RouteModels.pin()
        private let stairsUp = RouteModels.stairs(up: true)
        private let stairsDown = RouteModels.stairs(up: false)
        private var link: CADisplayLink?
        private var clock: Float = 0
        private var lastTick = CACurrentMediaTime()
        private var lastHint = RouteHint.hidden

        /// Arrows start this far ahead of the visitor and run this far, metres.
        static let trailStart: Float = 1.2
        static let trailReach: Float = 8
        static let trailSpacing: Float = 0.8
        /// The pin and the staircase are drawn only within this distance, metres.
        static let landmarkRange: Float = 18

        init(viewModel: NavigationViewModel, guide: TourGuide, onScreenHint: @escaping (RouteHint) -> Void) {
            self.viewModel = viewModel
            self.guide = guide
            self.onScreenHint = onScreenHint
            super.init()
            let count = Int((Self.trailReach - Self.trailStart) / Self.trailSpacing) + 2
            for _ in 0..<count {
                let arrow = RouteModels.arrow()
                arrow.opacity = 0
                arrows.append(arrow)
                root.addChildNode(arrow)
            }
            for node in [pin, stairsUp, stairsDown] {
                node.opacity = 0
                root.addChildNode(node)
            }
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
            clock += dt
            let scene = layout()

            for (i, node) in arrows.enumerated() {
                guard i < scene.arrows.count else { fade(node, to: 0); continue }
                let mark = scene.arrows[i]
                node.simdPosition = mark.position + SIMD3(0, 0.03, 0)
                node.eulerAngles.y = Self.yaw(mark.facing)
                // A bright band runs forward along the trail; the far end fades out.
                let wave = 0.5 + 0.5 * sin(clock * 5 - mark.ahead * 1.6)
                let far = max(0, min(1, (Self.trailReach - mark.ahead) / 2))
                let near = max(0, min(1, (mark.ahead - 0.6) / 0.6))
                fade(node, to: CGFloat((0.45 + 0.55 * wave) * far * near))
            }
            place(pin, at: scene.pin, yaw: 0, bob: 0.06)
            place(stairsUp, at: scene.stairs?.up == true ? scene.stairs?.position : nil, yaw: scene.stairs?.yaw ?? 0, bob: 0.04)
            place(stairsDown, at: scene.stairs?.up == false ? scene.stairs?.position : nil, yaw: scene.stairs?.yaw ?? 0, bob: 0.04)

            report(hint(for: scene))
        }

        private func place(_ node: SCNNode, at position: SIMD3<Float>?, yaw: Float, bob: Float) {
            guard let position else { fade(node, to: 0); return }
            node.simdPosition = position + SIMD3(0, sin(clock * 2) * bob, 0)
            if node !== pin { node.eulerAngles.y = yaw }
            fade(node, to: 1)
        }

        private func fade(_ node: SCNNode, to opacity: CGFloat) {
            node.opacity += (opacity - node.opacity) * 0.2
            node.isHidden = node.opacity < 0.01 && opacity == 0
        }

        /// Turn about the vertical that points a model's forward (−z) along `facing` (x, z).
        private static func yaw(_ facing: SIMD2<Float>) -> Float { atan2(-facing.x, -facing.y) }

        // MARK: What to draw

        private struct Mark { var position: SIMD3<Float>; var facing: SIMD2<Float>; var ahead: Float }
        private struct Stairs { var position: SIMD3<Float>; var yaw: Float; var up: Bool }
        private struct Scene {
            var arrows: [Mark] = []
            var pin: SIMD3<Float>?
            var stairs: Stairs?
        }

        /// Everything in ARKit's session frame for this frame.
        private func layout() -> Scene {
            let vm = viewModel
            var scene = Scene()
            guard vm.localizationStatus.isReliable else { return scene }
            let graphCamera = vm.currentTransform
            let arCamera = vm.arManager.cameraTransform
            // Graph frame → session frame (identity with an ARKit world map; the
            // Immersal anchoring otherwise).
            let graphToAR = arCamera * graphCamera.inverse
            let levels = vm.engine.levels
            let cameraXZ = SIMD2(arCamera.columns.3.x, arCamera.columns.3.z)

            func toAR(_ p: SIMD3<Float>) -> SIMD3<Float> {
                let v = graphToAR * SIMD4(p.x, p.y, p.z, 1)
                return SIMD3(v.x, v.y, v.z)
            }
            func toARDirection(_ d: SIMD2<Float>) -> SIMD2<Float> {
                let v = graphToAR * SIMD4(d.x, 0, d.y, 0)
                return SIMD2(v.x, v.z)
            }
            func near(_ p: SIMD3<Float>) -> Bool {
                simd_distance(SIMD2(p.x, p.z), cameraXZ) < Self.landmarkRange
            }

            // Arrived: the pin stays over the place.
            if guide.phase == .arrived, let stop = guide.current, let node = vm.engine.node(named: stop.id) {
                let floor = levels.floorHeight(of: stop.id) ?? graphCamera.columns.3.y - BuildingLevels.cameraHeight
                scene.pin = toAR(SIMD3(node.position.x, floor, node.position.y))
                return scene
            }
            guard guide.phase == .leading, let cue = RouteCue(viewModel: vm) else { return scene }
            let path = cue.path

            // The staircase stands at the first step while the visitor walks up to it.
            if case .stairsAhead(let run, _) = cue.stage, let foot = vm.engine.node(named: path[run.start]) {
                var facing = SIMD2<Float>(0, -1)
                if run.start + 1 < path.count, let next = vm.engine.node(named: path[run.start + 1]) {
                    let d = next.position - foot.position
                    if simd_length(d) > 0.05 { facing = simd_normalize(d) }
                }
                let position = toAR(SIMD3(foot.position.x, cue.userFloorY + RouteModels.stairsHover(up: run.up), foot.position.y))
                if near(position) {
                    scene.stairs = Stairs(position: position, yaw: Self.yaw(toARDirection(facing)), up: run.up)
                }
            }
            // No arrows on the steps themselves: the route's heights there are
            // too rough to draw on, and the way is obvious.
            if case .onStairs = cue.stage { return scene }

            var stops: [GuidePlacement.Stop] = []
            for i in cue.target..<path.count {
                guard let node = vm.engine.node(named: path[i]) else { continue }
                let hold = cue.run.map { $0.start == i } ?? false
                // On the visitor's own floor the arrows lie on the floor under
                // the phone; marked heights vary by a few tens of centimetres.
                let sameFloor = levels.level(of: path[i]) == cue.userLevel
                stops.append(.init(planar: node.position, floorY: sameFloor ? cue.userFloorY : levels.floorHeight(of: path[i]), holdHere: hold))
                if hold { break }
            }
            let trail = GuidePlacement.trail(from: cue.user, userFloorY: cue.userFloorY, stops: stops,
                                             start: Self.trailStart, reach: Self.trailReach, spacing: Self.trailSpacing)
            scene.arrows = trail.map { mark in
                Mark(position: toAR(mark.position), facing: toARDirection(mark.facing),
                     ahead: simd_distance(SIMD2(mark.position.x, mark.position.z), cue.user))
            }
            // The pin marks the place itself once it is on this floor and close.
            if cue.run == nil, let last = path.last, let node = vm.engine.node(named: last),
               levels.level(of: last) == cue.userLevel {
                let position = toAR(SIMD3(node.position.x, cue.userFloorY, node.position.y))
                if near(position) { scene.pin = position }
            }
            return scene
        }

        // MARK: Which way to turn

        private func report(_ hint: RouteHint) {
            guard hint != lastHint else { return }
            lastHint = hint
            onScreenHint(hint)
        }

        /// Whether the nearest thing to follow is on screen, or which way to turn to see it.
        private func hint(for scene: Scene) -> RouteHint {
            guard let view, view.bounds.width > 0, let camera = view.pointOfView else { return .hidden }
            guard let focus = scene.arrows.first?.position ?? scene.stairs?.position ?? scene.pin else { return .hidden }
            let shown = scene.arrows.prefix(4).map(\.position) + [scene.stairs?.position, scene.pin].compactMap { $0 }
            let bounds = view.bounds.insetBy(dx: 10, dy: 30)
            for position in shown {
                let p = view.projectPoint(SCNVector3(position.x, position.y, position.z))
                if p.z > 0, p.z < 1, bounds.contains(CGPoint(x: CGFloat(p.x), y: CGFloat(p.y))) { return .visible }
            }
            let to = focus - camera.simdWorldPosition
            let forward = simd_dot(to, camera.simdWorldFront)
            let side = simd_dot(to, camera.simdWorldRight)
            // Straight ahead but off the bottom edge: the phone is held too high to see the floor.
            if forward > 0, abs(side) < forward * 0.5 { return .down }
            return side >= 0 ? .right : .left
        }
    }
}

/// Where the route's arrows are relative to the screen.
enum RouteHint: Equatable {
    case hidden, visible, left, right, down
}

/// The 3D shapes drawn on the camera view.
@MainActor
enum RouteModels {
    /// How far above the floor the staircase floats, metres.
    static func stairsHover(up: Bool) -> Float { up ? 0.4 : 0.5 }

    private static let orange = UIColor(red: 0xEF / 255, green: 0x7C / 255, blue: 0, alpha: 1)
    private static let blue = UIColor(red: 0, green: 0x3D / 255, blue: 0x7C / 255, alpha: 1)

    private static func flat(_ color: UIColor) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.lightingModel = .constant
        material.isDoubleSided = true
        return material
    }

    private static func lit(_ color: UIColor) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.emission.contents = color.withAlphaComponent(0.35)
        return material
    }

    /// A chevron lying on the floor, pointing along the node's −z.
    static func arrow() -> SCNNode {
        func chevron(width w: CGFloat, length l: CGFloat, notch: CGFloat) -> UIBezierPath {
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 0, y: l / 2))
            path.addLine(to: CGPoint(x: w / 2, y: -l / 2 + notch))
            path.addLine(to: CGPoint(x: w / 2, y: -l / 2))
            path.addLine(to: CGPoint(x: 0, y: l / 2 - notch))
            path.addLine(to: CGPoint(x: -w / 2, y: -l / 2))
            path.addLine(to: CGPoint(x: -w / 2, y: -l / 2 + notch))
            path.close()
            path.flatness = 0.001
            return path
        }
        let node = SCNNode()
        // A white rim under the orange so the arrow reads on any floor.
        for (path, color, lift) in [(chevron(width: 0.56, length: 0.44, notch: 0.20), UIColor.white, Float(0)),
                                    (chevron(width: 0.46, length: 0.34, notch: 0.14), orange, Float(0.004))] {
            let shape = SCNShape(path: path, extrusionDepth: 0.004)
            shape.materials = [flat(color)]
            let part = SCNNode(geometry: shape)
            part.eulerAngles.x = -.pi / 2      // from upright to lying flat, tip toward −z
            part.position.y = lift
            node.addChildNode(part)
        }
        return node
    }

    /// A map pin floating over the place, its tip about head height.
    static func pin() -> SCNNode {
        let node = SCNNode()
        let head = SCNNode(geometry: SCNSphere(radius: 0.14))
        head.geometry?.materials = [lit(orange)]
        head.position.y = 1.62
        let tip = SCNCone(topRadius: 0.11, bottomRadius: 0, height: 0.3)
        tip.materials = [lit(orange)]
        let tipNode = SCNNode(geometry: tip)
        tipNode.position.y = 1.4
        let dot = SCNNode(geometry: SCNSphere(radius: 0.055))
        dot.geometry?.materials = [flat(.white)]
        dot.position = SCNVector3(0, 1.62, 0)
        dot.scale = SCNVector3(1.02, 1.02, 2.6)   // pokes through both faces of the head
        let ring = SCNTorus(ringRadius: 0.32, pipeRadius: 0.018)
        ring.materials = [flat(orange)]
        let ringNode = SCNNode(geometry: ring)
        ringNode.position.y = 0.03
        for child in [head, tipNode, dot, ringNode] { node.addChildNode(child) }
        return node
    }

    /// Five steps with an arrow that keeps travelling the way to walk. Going
    /// up, the steps climb away from the viewer along −z. Going down they are
    /// turned side-on, like a stairs sign: seen from their top end, steps that
    /// really descend away hide each other and read as a flat slab.
    static func stairs(up: Bool) -> SCNNode {
        let steps = 5
        let depth: Float = 0.2, rise: Float = 0.14, width: Float = up ? 0.8 : 0.5
        let run = depth * Float(steps), height = rise * Float(steps)
        let outer = SCNNode()
        let node = SCNNode()
        outer.addChildNode(node)
        if !up { node.eulerAngles.y = .pi / 2 }   // climbs to the left, so it descends to the right
        for k in 0..<steps {
            let h = rise * Float(k + 1)
            let box = SCNBox(width: CGFloat(width), height: CGFloat(h), length: CGFloat(depth), chamferRadius: 0.008)
            let side = lit(blue)
            let tread = lit(.white)
            box.materials = [side, side, side, side, tread, side]   // front, right, back, left, top, bottom
            let step = SCNNode(geometry: box)
            step.simdPosition = SIMD3(0, h / 2, run / 2 - depth / 2 - Float(k) * depth)
            node.addChildNode(step)
        }
        // The arrow floats above the treads and runs from the near end to the far end.
        let clear: Float = 0.3
        let low = SIMD3<Float>(0, rise + clear, run / 2), high = SIMD3<Float>(0, height + clear, -run / 2)
        let from = up ? low : high, to = up ? high : low
        let slope = atan2(height - rise, run)
        let arrow = SCNNode()
        let head = SCNCone(topRadius: 0, bottomRadius: 0.11, height: 0.24)
        head.materials = [lit(orange)]
        let headNode = SCNNode(geometry: head)
        headNode.position.y = 0.12
        let shaft = SCNCylinder(radius: 0.04, height: 0.26)
        shaft.materials = [lit(orange)]
        let shaftNode = SCNNode(geometry: shaft)
        shaftNode.position.y = -0.13
        arrow.addChildNode(headNode)
        arrow.addChildNode(shaftNode)
        // Tip (the arrow's +y) along the way to walk: up the slope, or down it.
        arrow.eulerAngles.x = up ? slope - .pi / 2 : slope + .pi / 2
        arrow.simdPosition = from
        arrow.opacity = 0
        let travel = SCNAction.sequence([
            .group([.move(to: SCNVector3(from.x, from.y, from.z), duration: 0), .fadeIn(duration: 0.15)]),
            .move(to: SCNVector3(to.x, to.y, to.z), duration: 1.1),
            .fadeOut(duration: 0.2),
            .wait(duration: 0.15),
        ])
        arrow.runAction(.repeatForever(travel))
        node.addChildNode(arrow)
        return outer
    }
}
