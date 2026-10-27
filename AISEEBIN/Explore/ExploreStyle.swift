import simd
import SwiftUI

/// Explore's look: light, calm, one purple accent. Built on the `DS.A` tokens.
enum EX {
    static let accent = Color(dsHex: 0x6B4FD8)
    static let accentSoft = Color(dsHex: 0xEFEAFF)
    static let canvas = DS.A.canvas
    static let card = DS.A.card
    static let ink = DS.A.ink
    static let inkSecondary = DS.A.inkSecondary
    static let inkMuted = DS.A.inkMuted
    static let hairline = DS.A.hairline
    static let you = Color(dsHex: 0x2F7BF6)
    static let mapGround = Color(dsHex: 0xE6F4EA)
}

/// The AiSee logo that tops every Explore screen. Five quick taps hand the phone
/// back to staff; to a visitor it is just the logo.
struct EXLogo: View {
    var height: CGFloat = 30
    let onUnlock: () -> Void
    @State private var taps: [Date] = []

    var body: some View {
        Image("AiSeeLogo")
            .renderingMode(.template)
            .resizable().scaledToFit()
            .foregroundStyle(EX.accent)
            .frame(height: height)
            .padding(10).contentShape(Rectangle()).padding(-10)
            .onTapGesture(perform: tapped)
            .accessibilityHidden(true)
    }

    private func tapped() {
        let now = Date()
        taps = taps.filter { now.timeIntervalSince($0) < 3 } + [now]
        guard taps.count >= 5 else { return }
        taps = []
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onUnlock()
    }
}

/// An optional pill or button on the right. The logo and map chip sit above
/// it in the app's shared header, which also carries the five-tap unlock.
struct EXHeader<Trailing: View>: View {
    let model: ExploreViewModel
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center) {
            Spacer(minLength: 12)
            trailing
        }
    }
}

extension EXHeader where Trailing == EmptyView {
    init(model: ExploreViewModel) { self.init(model: model) { EmptyView() } }
}

/// A round icon button with a caption under it, for either side of the Ask button.
struct EXSideButton: View {
    let systemImage: String
    let title: String
    var on = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(on ? .white : EX.inkSecondary)
                    .frame(width: 56, height: 56)
                    .background(on ? EX.accent : EX.card, in: Circle())
                    .overlay(Circle().strokeBorder(on ? .clear : EX.hairline))
                Text(title).font(.dsFootnote.weight(.semibold)).foregroundStyle(EX.inkSecondary)
            }
        }
        .buttonStyle(.plain)
    }
}

/// The big full-width purple button.
struct EXPrimaryButton: View {
    let title: String
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.dsHeadline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(enabled ? EX.accent : EX.inkMuted.opacity(0.5),
                            in: RoundedRectangle(cornerRadius: DS.R.field, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// A white rounded card.
struct EXCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(EX.card, in: RoundedRectangle(cornerRadius: DS.R.panel, style: .continuous))
            .dsStroke(EX.hairline, radius: DS.R.panel)
    }
}

/// Small rounded label: "⏱ 14 min left".
struct EXPill: View {
    let systemImage: String
    let text: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.dsSubhead.weight(.semibold))
            .foregroundStyle(EX.ink)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(EX.card, in: Capsule())
            .overlay(Capsule().strokeBorder(EX.hairline))
    }
}

/// The round Ask button.
struct EXAskButton: View {
    var listening = false
    var size: CGFloat = 104
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: listening ? "waveform" : "mic.fill")
                    .font(.system(size: size * 0.28, weight: .semibold))
                    .symbolEffect(.variableColor.iterative, isActive: listening)
                Text(listening ? "Listening" : "Ask").font(.dsHeadline)
            }
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(EX.accent, in: Circle())
            .overlay(Circle().stroke(EX.accent.opacity(0.18), lineWidth: 12).padding(-6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(listening ? "Listening. Tap to send." : "Ask about what you see")
    }
}

/// Top-down tour map in Explore's light style: paths, numbered stops, the route
/// and the visitor's blue dot. x runs right and graph −z runs up, like LiveMapView.
struct TourMapView: View {
    let map: NavigationMap
    let stopIDs: [String]
    let routePath: [String]
    var pose: MapPose?
    var highlightID: String?
    var startID: String?
    var endID: String?

    var body: some View {
        Canvas { context, size in draw(&context, size) }
            .background(EX.mapGround, in: RoundedRectangle(cornerRadius: DS.R.panel, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: DS.R.panel, style: .continuous))
            .accessibilityHidden(true)
    }

    private func draw(_ context: inout GraphicsContext, _ size: CGSize) {
        let byID = Dictionary(map.pois.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        // Fit the tour (or the whole map if there is no tour yet) and the visitor.
        var points = (routePath.count < 2 ? map.pois.map(\.id) : routePath).compactMap { byID[$0]?.planarPosition }
        if let pose { points.append(pose.position) }
        guard let first = points.first else { return }
        var lo = first, hi = first
        for p in points { lo = simd_min(lo, p); hi = simd_max(hi, p) }
        let pad: CGFloat = 26
        let span = max(hi.x - lo.x, hi.y - lo.y, 4)
        let scale = min((size.width - 2 * pad), (size.height - 2 * pad)) / CGFloat(span)
        let mid = (lo + hi) / 2
        func pt(_ p: SIMD2<Float>) -> CGPoint {
            CGPoint(x: size.width / 2 + CGFloat(p.x - mid.x) * scale,
                    y: size.height / 2 + CGFloat(p.y - mid.y) * scale)
        }

        var paths = Path()
        for e in map.edges {
            guard let a = byID[e.from], let b = byID[e.to] else { continue }
            paths.move(to: pt(a.planarPosition)); paths.addLine(to: pt(b.planarPosition))
        }
        context.stroke(paths, with: .color(EX.inkMuted.opacity(0.35)), style: StrokeStyle(lineWidth: 3, lineCap: .round))

        var route = Path()
        for (i, id) in routePath.enumerated() {
            guard let p = byID[id] else { continue }
            if i == 0 { route.move(to: pt(p.planarPosition)) } else { route.addLine(to: pt(p.planarPosition)) }
        }
        context.stroke(route, with: .color(EX.accent), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))

        for (id, label) in [(startID, "Start"), (endID, "End")] where id != nil {
            guard let p = byID[id!] else { continue }
            let c = pt(p.planarPosition)
            let dot = Path(ellipseIn: CGRect(x: c.x - 7, y: c.y - 7, width: 14, height: 14))
            context.fill(dot, with: .color(EX.ink))
            context.stroke(dot, with: .color(.white), lineWidth: 2)
            context.draw(Text(label).font(.caption2.weight(.bold)).foregroundStyle(EX.ink),
                         at: CGPoint(x: c.x, y: c.y + 16))
            if startID == endID { break }
        }

        for (i, id) in stopIDs.enumerated() {
            guard let p = byID[id] else { continue }
            let c = pt(p.planarPosition)
            let r: CGFloat = id == highlightID ? 13 : 11
            let dot = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
            context.fill(dot, with: .color(EX.accent))
            context.stroke(dot, with: .color(.white), lineWidth: 2)
            context.draw(Text("\(i + 1)").font(.caption.weight(.bold)).foregroundStyle(.white), at: c)
        }

        if let pose {
            let c = pt(pose.position)
            let dir = CGPoint(x: CGFloat(sin(pose.heading)), y: CGFloat(-cos(pose.heading)))
            var cone = Path()
            cone.move(to: c)
            cone.addLine(to: CGPoint(x: c.x + dir.x * 26 - dir.y * 10, y: c.y + dir.y * 26 + dir.x * 10))
            cone.addLine(to: CGPoint(x: c.x + dir.x * 26 + dir.y * 10, y: c.y + dir.y * 26 - dir.x * 10))
            cone.closeSubpath()
            context.fill(cone, with: .color(EX.you.opacity(0.25)))
            let dot = Path(ellipseIn: CGRect(x: c.x - 9, y: c.y - 9, width: 18, height: 18))
            context.fill(dot, with: .color(EX.you))
            context.stroke(dot, with: .color(.white), lineWidth: 3)
        }
    }
}
