import simd
import SwiftUI

/// Top-down sketch of the graph with the visitor on it, for the sighted helper
/// walking alongside: paths, named places, the active route and the announce
/// circles, fitted to the map and the visitor's position every redraw. The
/// same picture as the Android app's map. x runs right and graph −z (ahead of
/// the scan origin) runs up the screen.
struct LiveMapView: View {
    let map: NavigationMap
    let pose: MapPose?
    let routePath: [String]
    let selectedID: String?

    var body: some View {
        Canvas { context, size in
            draw(in: &context, size: size)
        }
        .padding(10)
        .background(DS.N.panel, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .dsStroke(DS.N.hairline, radius: 20)
        // The spoken and on-screen panels already say where the visitor is.
        .accessibilityHidden(true)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        var points = map.pois.map(\.planarPosition)
        if let pose { points.append(pose.position) }
        guard let first = points.first else { return }
        var lo = first, hi = first
        for p in points { lo = simd_min(lo, p); hi = simd_max(hi, p) }
        let pad: Float = 1.2
        lo -= SIMD2(pad, pad); hi += SIMD2(pad, pad)
        let spanX = max(hi.x - lo.x, 1), spanZ = max(hi.y - lo.y, 1)
        let scale = min(Float(size.width) / spanX, Float(size.height) / spanZ)
        let offX = (Float(size.width) - spanX * scale) / 2
        let offY = (Float(size.height) - spanZ * scale) / 2
        func pt(_ p: SIMD2<Float>) -> CGPoint {
            CGPoint(x: CGFloat(offX + (p.x - lo.x) * scale), y: CGFloat(offY + (p.y - lo.y) * scale))
        }

        let byID = Dictionary(uniqueKeysWithValues: map.pois.map { ($0.id, $0) })

        // Announce circles first, underneath everything.
        for poi in map.pois where poi.announceRadius > 0 {
            let r = CGFloat(poi.announceRadius * scale)
            let c = pt(poi.planarPosition)
            let circle = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
            context.stroke(circle, with: .color(color(for: poi).opacity(0.35)),
                           style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }

        for edge in map.edges {
            guard let a = byID[edge.from], let b = byID[edge.to] else { continue }
            var line = Path(); line.move(to: pt(a.planarPosition)); line.addLine(to: pt(b.planarPosition))
            context.stroke(line, with: .color(DS.N.inkMuted.opacity(0.55)), lineWidth: 2)
        }

        if routePath.count > 1 {
            var route = Path()
            for (i, id) in routePath.enumerated() {
                guard let poi = byID[id] else { continue }
                if i == 0 { route.move(to: pt(poi.planarPosition)) } else { route.addLine(to: pt(poi.planarPosition)) }
            }
            context.stroke(route, with: .color(DS.N.accent),
                           style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
        }

        for poi in map.pois {
            let c = pt(poi.planarPosition)
            if poi.category == .junction {
                let r: CGFloat = 3
                context.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                             with: .color(DS.N.inkMuted))
                continue
            }
            let r: CGFloat = 6
            context.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                         with: .color(color(for: poi)))
            if poi.id == selectedID {
                let ring: CGFloat = 10
                context.stroke(Path(ellipseIn: CGRect(x: c.x - ring, y: c.y - ring, width: 2 * ring, height: 2 * ring)),
                               with: .color(DS.N.ink), lineWidth: 2)
            }
            context.draw(Text(poi.name).font(.caption2.weight(.semibold)).foregroundStyle(DS.N.inkSecondary),
                         at: CGPoint(x: c.x + 10, y: c.y - 8), anchor: .leading)
        }

        if let pose {
            let c = pt(pose.position)
            // Heading h faces (sin h, −cos h) in (x, z); screen y follows z.
            let d = CGVector(dx: CGFloat(sin(pose.heading)), dy: CGFloat(-cos(pose.heading)))
            var arrow = Path()
            arrow.move(to: CGPoint(x: c.x + d.dx * 22, y: c.y + d.dy * 22))
            arrow.addLine(to: CGPoint(x: c.x - d.dy * 9, y: c.y + d.dx * 9))
            arrow.addLine(to: CGPoint(x: c.x + d.dy * 9, y: c.y - d.dx * 9))
            arrow.closeSubpath()
            context.fill(arrow, with: .color(DS.N.hearing))
            let r: CGFloat = 8
            let dot = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
            context.fill(dot, with: .color(DS.N.hearing))
            context.stroke(dot, with: .color(DS.N.ink), lineWidth: 2)
        }
    }

    private func color(for poi: NavigationPOI) -> Color {
        switch poi.category {
        case .hazard: return DS.N.warnText
        case .exhibit: return DS.N.okText
        case .destination: return DS.N.accent
        case .junction: return DS.N.inkMuted
        }
    }
}
