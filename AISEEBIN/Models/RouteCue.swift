import Foundation
import simd

/// Where the visitor is on the active route, worked out once and read by the
/// floor arrows, the small map and the instruction card so they always agree.
struct RouteCue {
    enum Stage: Equatable {
        /// Walking on one floor.
        case walk
        /// Stairs or a lift are close: `metres` along the route to the first step.
        case stairsAhead(StairRun, metres: Float)
        /// Between the first and last step (or in the lift).
        case onStairs(StairRun)
    }

    /// How close the stairs have to be before the app starts talking about them.
    static let stairsNotice: Float = 10

    /// Route node ids, start to destination.
    var path: [String] = []
    /// Index in `path` of the node the visitor is heading to.
    var target = 0
    var stage: Stage = .walk
    /// The visitor's floor, 1-based.
    var userLevel = 1
    /// Floor height under the visitor.
    var userFloorY: Float = 0
    var user = SIMD2<Float>(0, 0)

    var run: StairRun? {
        switch stage {
        case .walk: return nil
        case .stairsAhead(let run, _), .onStairs(let run): return run
        }
    }

    /// "Take the stairs up to Level 2", or nil when no stairs are near.
    var stairsText: String? {
        switch stage {
        case .walk: return nil
        case .stairsAhead(let run, _):
            return run.kind == .lift ? "Take the lift \(run.up ? "up" : "down") to Level \(run.toLevel)"
                                     : "Take the stairs \(run.up ? "up" : "down") to Level \(run.toLevel)"
        case .onStairs(let run):
            return run.kind == .lift ? "Ride the lift to Level \(run.toLevel)"
                                     : "Keep going \(run.up ? "up" : "down") to Level \(run.toLevel)"
        }
    }

    /// For the screen: from the map pose, which changes a few times a second.
    /// (Reading the camera itself would redraw the whole screen every frame.)
    @MainActor
    init?(viewModel vm: NavigationViewModel, pose: MapPose?) {
        guard vm.isNavigating, !vm.routePath.isEmpty, let pose else { return nil }
        self.init(path: vm.routePath, routeLeg: vm.routeLeg, user: pose.position, cameraY: pose.height,
                  levels: vm.engine.levels) { vm.engine.node(named: $0)?.position }
    }

    /// For the camera view: from this frame's camera.
    @MainActor
    init?(viewModel vm: NavigationViewModel) {
        guard vm.isNavigating, !vm.routePath.isEmpty, vm.localizationStatus.isReliable else { return nil }
        let camera = vm.currentTransform
        self.init(path: vm.routePath, routeLeg: vm.routeLeg,
                  user: NavigationGeometry.planarPosition(of: camera), cameraY: camera.columns.3.y,
                  levels: vm.engine.levels) { vm.engine.node(named: $0)?.position }
    }

    init(path: [String], routeLeg: Int, user: SIMD2<Float>, cameraY: Float, levels: BuildingLevels,
         position: (String) -> SIMD2<Float>?) {
        self.path = path
        self.user = user
        target = max(0, min(routeLeg - 1, path.count - 1))
        userLevel = levels.level(forHeight: cameraY)
        userFloorY = cameraY - BuildingLevels.cameraHeight
        guard let run = levels.stairRun(on: path, heading: target) else { return }
        if target > run.start {
            stage = .onStairs(run)
            return
        }
        // Along the route from the visitor to the first step.
        var metres: Float = 0
        var from = user
        for i in target...run.start {
            guard let p = position(path[i]) else { continue }
            metres += simd_distance(from, p)
            from = p
        }
        if metres <= Self.stairsNotice { stage = .stairsAhead(run, metres: metres) }
    }
}
