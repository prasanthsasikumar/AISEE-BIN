import simd
import SwiftUI

/// A small map over the camera view: the paths on the visitor's own floor, the
/// route, where it ends or leaves the floor, and the visitor in the middle
/// facing up the screen. Tap to see further.
///
/// One floor at a time: the upstairs corridors sit right above the ones below,
/// so drawing both would be unreadable.
struct NUSMiniMap: View {
    let map: NavigationMap
    let levels: BuildingLevels
    let pose: MapPose
    let cue: RouteCue?
    /// The place being walked to.
    let destinationID: String?
    @State private var wide = false

    var body: some View {
        let side: CGFloat = wide ? 300 : 150
        VStack(spacing: 0) {
            Canvas { context, size in draw(&context, size) }
                .frame(width: side, height: side)
            if levels.isMultiLevel {
                Text("Level \(level)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(NUS.inkSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 3)
                    .background(.white)
            }
        }
        .frame(width: side)
        .background(NUS.canvas.opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white, lineWidth: 2))
        .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.snappy) { wide.toggle() } }
        .accessibilityElement()
        .accessibilityLabel("Map")
        .accessibilityHint(wide ? "Shrinks the map" : "Enlarges the map")
        .accessibilityAddTraits(.isButton)
    }

    private var level: Int { cue?.userLevel ?? 1 }

    private func draw(_ context: inout GraphicsContext, _ size: CGSize) {
        let byID = Dictionary(map.pois.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        // The route on this floor ends at the place, or where it leaves the floor.
        var routeEnd: Int?
        if let cue, !cue.path.isEmpty {
            if case .onStairs(let run) = cue.stage { routeEnd = run.end }
            else if let run = cue.run ?? levels.stairRun(on: cue.path, heading: cue.target) { routeEnd = run.start }
            else { routeEnd = cue.path.count - 1 }
        }
        // Metres from the visitor to the top edge of the map. The small map
        // zooms in as the end of the route gets close, so the two never overlap.
        var range: Float = wide ? 34 : 15
        if !wide, let cue, let routeEnd, let poi = byID[cue.path[routeEnd]] {
            range = max(6, min(15, simd_distance(poi.planarPosition, pose.position) * 1.5))
        }
        let centre = CGPoint(x: size.width / 2, y: size.height * 0.62)
        let scale = (centre.y - 10) / CGFloat(range)
        // Heading h faces (sin h, −cos h) on (x, z); the visitor's right is (cos h, sin h).
        let forward = SIMD2(sin(pose.heading), -cos(pose.heading))
        let right = SIMD2(cos(pose.heading), sin(pose.heading))
        func pt(_ p: SIMD2<Float>) -> CGPoint {
            let d = p - pose.position
            return CGPoint(x: centre.x + CGFloat(simd_dot(d, right)) * scale,
                           y: centre.y - CGFloat(simd_dot(d, forward)) * scale)
        }
        /// Pulls a point that is off the map back onto its edge, so a far place still shows which way it is.
        func clamped(_ p: CGPoint, inset: CGFloat) -> CGPoint {
            let box = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
            guard !box.contains(p) else { return p }
            let dx = p.x - centre.x, dy = p.y - centre.y
            var t: CGFloat = 1
            if dx > 0 { t = min(t, (box.maxX - centre.x) / dx) }
            if dx < 0 { t = min(t, (box.minX - centre.x) / dx) }
            if dy > 0 { t = min(t, (box.maxY - centre.y) / dy) }
            if dy < 0 { t = min(t, (box.minY - centre.y) / dy) }
            return CGPoint(x: centre.x + dx * t, y: centre.y + dy * t)
        }
        func onFloor(_ id: String) -> Bool { levels.level(of: id) == level }

        // Paths on this floor.
        var paths = Path()
        for edge in map.edges where onFloor(edge.from) && onFloor(edge.to) {
            guard let a = byID[edge.from], let b = byID[edge.to] else { continue }
            paths.move(to: pt(a.planarPosition))
            paths.addLine(to: pt(b.planarPosition))
        }
        context.stroke(paths, with: .color(NUS.inkSecondary.opacity(0.28)), style: StrokeStyle(lineWidth: 5, lineCap: .round))

        // The route: from the visitor to the place, or to where it leaves this floor.
        var end: (point: CGPoint, id: String, leavesFloor: Bool)?
        if let cue, !cue.path.isEmpty {
            var line = Path()
            line.move(to: centre)
            let last = routeEnd ?? cue.path.count - 1
            if cue.target <= last {
                for i in cue.target...last {
                    guard let poi = byID[cue.path[i]] else { continue }
                    let p = pt(poi.planarPosition)
                    line.addLine(to: p)
                    end = (p, poi.id, last < cue.path.count - 1)
                }
            }
            context.stroke(line, with: .color(.white), style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
            context.stroke(line, with: .color(NUS.orange), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
        }

        // Places on this floor, named when there is room.
        for poi in map.pois where (poi.category == .destination || poi.category == .exhibit) && onFloor(poi.id) && poi.id != destinationID {
            let p = pt(poi.planarPosition)
            guard CGRect(origin: .zero, size: size).insetBy(dx: 6, dy: 6).contains(p) else { continue }
            let dot = CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)
            context.fill(Path(ellipseIn: dot), with: .color(NUS.blue))
            context.stroke(Path(ellipseIn: dot), with: .color(.white), lineWidth: 1.5)
            if wide {
                context.draw(Text(poi.name).font(.caption2.weight(.semibold)).foregroundStyle(NUS.ink),
                             at: CGPoint(x: p.x, y: p.y + 11), anchor: .top)
            }
        }

        // The visitor: a view wedge and a dot.
        var wedge = Path()
        wedge.move(to: centre)
        wedge.addArc(center: centre, radius: 26, startAngle: .degrees(-125), endAngle: .degrees(-55), clockwise: false)
        wedge.closeSubpath()
        context.fill(wedge, with: .color(NUS.blue.opacity(0.22)))
        let me = CGRect(x: centre.x - 7, y: centre.y - 7, width: 14, height: 14)
        context.fill(Path(ellipseIn: me), with: .color(.white))
        context.fill(Path(ellipseIn: me.insetBy(dx: 2.5, dy: 2.5)), with: .color(NUS.blue))

        // Where the route ends on this floor: the place, or the stairs.
        if let end {
            let p = clamped(end.point, inset: 16)
            let badge = CGRect(x: p.x - 13, y: p.y - 13, width: 26, height: 26)
            context.fill(Path(ellipseIn: badge), with: .color(end.leavesFloor ? NUS.blue : NUS.orange))
            context.stroke(Path(ellipseIn: badge), with: .color(.white), lineWidth: 2)
            let symbol: String
            if end.leavesFloor {
                symbol = cue?.run?.kind == .lift ? "arrow.up.arrow.down" : "figure.stairs"
            } else {
                symbol = "flag.fill"
            }
            context.draw(Text(Image(systemName: symbol)).font(.system(size: 12, weight: .bold)).foregroundStyle(.white), at: p)
            if end.leavesFloor, let run = cue?.run ?? cue.flatMap({ levels.stairRun(on: $0.path, heading: $0.target) }) {
                label(Text("\(run.up ? "Up" : "Down") to L\(run.toLevel)").foregroundStyle(NUS.blue))
            } else if let name = byID[end.id]?.name, !end.leavesFloor {
                label(Text(name).foregroundStyle(NUS.ink))
            }
            /// Above the badge, away from the visitor's dot; below it at the top edge.
            func label(_ text: Text) {
                let above = p.y > 34
                context.draw(text.font(.caption2.weight(.bold)),
                             at: CGPoint(x: min(max(p.x, 30), size.width - 30), y: above ? p.y - 15 : p.y + 15),
                             anchor: above ? .bottom : .top)
            }
        }
    }
}
