import SwiftUI
import UIKit

struct NUSRootView: View {
    let viewModel: NavigationViewModel
    let guide: TourGuide
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingPlaces = false
    @State private var showingStaff = false

    var body: some View {
        ZStack {
            if guide.phase == .home {
                NUSHomeView(viewModel: viewModel, guide: guide,
                            onChoose: { showingPlaces = true },
                            onStaff: { showingStaff = true })
                    .transition(.opacity)
            } else {
                NUSGuideView(viewModel: viewModel, guide: guide, onStaff: { showingStaff = true })
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: guide.phase == .home)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            viewModel.startSession()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-openPlaces") { showingPlaces = true }
            if ProcessInfo.processInfo.arguments.contains("-openStaff") { showingStaff = true }
            if ProcessInfo.processInfo.arguments.contains("-startTour") { guide.startTour() }
            #endif
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { UsageLog.shared.appDidEnterBackground() }
            if phase == .active { UsageLog.shared.appDidEnterForeground() }
            if phase == .active, viewModel.localizationStatus == .notStarted { viewModel.startSession() }
        }
        .sheet(isPresented: $showingPlaces) {
            NUSPlacesSheet(guide: guide) { poi in
                showingPlaces = false
                guide.go(to: poi)
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingStaff) {
            NUSStaffView(viewModel: viewModel, guide: guide)
        }
    }
}

// MARK: - Header logo: the NUS Computing lockup (5 taps opens the staff screen)

struct NUSLogoMark: View {
    var size: CGFloat = 40
    let onStaff: () -> Void

    var body: some View {
        Image("NUSLogo")
            .resizable()
            .scaledToFit()
            .frame(height: size)
            .staffTaps(onStaff)
            .accessibilityLabel("NUS Computing")
    }
}

/// Five quick taps open the staff screen.
private struct StaffTaps: ViewModifier {
    let onStaff: () -> Void
    @State private var taps: [Date] = []

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onTapGesture {
                let now = Date()
                taps = taps.filter { now.timeIntervalSince($0) < 3 } + [now]
                if taps.count >= 5 { taps = []; onStaff() }
            }
    }
}

extension View {
    func staffTaps(_ onStaff: @escaping () -> Void) -> some View { modifier(StaffTaps(onStaff: onStaff)) }
}

// MARK: - Home

struct NUSHomeView: View {
    let viewModel: NavigationViewModel
    let guide: TourGuide
    let onChoose: () -> Void
    let onStaff: () -> Void

    private var hasMap: Bool { viewModel.localVersion != nil }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                NUSLogoMark(onStaff: onStaff)
                Spacer()
                Button { guide.voiceOn.toggle() } label: {
                    Image(systemName: guide.voiceOn ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .font(.title3)
                        .foregroundStyle(NUS.blue)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(guide.voiceOn ? "Voice on" : "Voice off")
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            Spacer(minLength: 8)

            Image("SoCat")
                .resizable()
                .scaledToFit()
                .frame(maxHeight: hasMap ? 104 : 190)
                .padding(.horizontal, 40)
                .accessibilityHidden(true)

            VStack(spacing: 10) {
                Text("Hi! I'm \(NUS.mascot).")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(NUS.ink)
                Text("Let me show you around NUS Computing. Hold up your phone and follow the arrows on the floor.")
                    .font(.body)
                    .foregroundStyle(NUS.inkSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 28)
            .padding(.top, 12)

            if hasMap, !guide.places.isEmpty {
                NUSTourCloud(map: viewModel.displayMap, levels: viewModel.engine.levels, places: guide.places,
                             pointData: viewModel.mapStore.loadPointCloud())
                    .frame(maxWidth: .infinity, minHeight: 140, maxHeight: 250)
                    .background(Color(dsHex: TourScene.background), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
            }

            Spacer(minLength: 14)

            VStack(spacing: 14) {
                Button {
                    guide.startTour()
                } label: {
                    Label(hasMap ? "Start the tour (\(guide.places.count) stops)" : "Start the tour", systemImage: "figure.walk")
                }
                .buttonStyle(NUSButtonStyle(fill: NUS.orange))
                .disabled(!hasMap || guide.places.isEmpty)

                Button(action: onChoose) {
                    Label("Choose a place", systemImage: "list.bullet")
                }
                .buttonStyle(NUSButtonStyle(fill: NUS.blue))
                .disabled(!hasMap || guide.places.isEmpty)

                Text(statusLine)
                    .font(.footnote)
                    .foregroundStyle(NUS.inkSecondary)
                    .multilineTextAlignment(.center)
                    .frame(minHeight: 20)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .background(NUS.canvas.ignoresSafeArea())
        .preferredColorScheme(.light)
    }

    private var statusLine: String {
        switch viewModel.syncState {
        case .checking where !hasMap: return "Getting the building map…"
        case .downloading: return "Downloading the building map… \(Int(viewModel.syncProgress * 100))%"
        case .failed(let reason) where !hasMap: return "Couldn't get the map: \(reason)"
        case .offlineSample where !hasMap: return "No building map has been published yet."
        default:
            return hasMap ? viewModel.mapName : "No map yet. Connect to the internet to get the building map."
        }
    }
}

// MARK: - The tour in 3D on the home screen

/// The building as the scan's point cloud, with the paths and the numbered
/// stops. It turns for three seconds when it appears, then rests seen from
/// above at a slight angle. Tap to play it again.
struct NUSTourCloud: View {
    let map: NavigationMap
    let levels: BuildingLevels
    let places: [NavigationPOI]
    /// Raw little-endian float triplets (x, y, z), as `MapStore` keeps them.
    let pointData: Data?
    @State private var scene: TourScene?
    @State private var started = Date()
    @State private var settled = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: settled || scene == nil)) { timeline in
            Canvas { context, size in
                guard let scene else { return }
                let elapsed = reduceMotion ? .infinity : timeline.date.timeIntervalSince(started)
                // The stops' names fade in once the map has come to rest.
                let names = max(0, min(1, (elapsed - TourScene.seconds) / 0.5))
                draw(scene, progress: min(1, elapsed / TourScene.seconds), names: names, &context, size)
                if names >= 1, !settled { DispatchQueue.main.async { settled = true } }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { started = Date(); settled = false }
        .task(id: "\(map.name)-\(map.pois.count)-\(pointData?.count ?? 0)") {
            let map = map, levels = levels, data = pointData
            scene = await Task.detached(priority: .userInitiated) { TourScene(map: map, levels: levels, pointData: data) }.value
            started = Date(); settled = false
        }
        .accessibilityElement()
        .accessibilityLabel("Map of the tour from above, with \(places.count) numbered stops")
    }

    private func draw(_ scene: TourScene, progress: Double, names: Double, _ context: inout GraphicsContext, _ size: CGSize) {
        let view = scene.view(progress: Float(progress), width: Float(size.width), height: Float(size.height))
        func pt(_ p: SIMD3<Float>) -> CGPoint { let q = view.project(p); return CGPoint(x: CGFloat(q.x), y: CGFloat(q.y)) }
        // The cloud, coloured by height: blue at the bottom, yellow at the top.
        var bands = [Path](repeating: Path(), count: TourScene.bandColours.count)
        for p in scene.points {
            let q = pt(p)
            bands[scene.band(of: p.y)].addRect(CGRect(x: q.x - 0.65, y: q.y - 0.65, width: 1.3, height: 1.3))
        }
        let fade = min(1, progress / 0.15)
        for (band, path) in bands.enumerated() {
            context.fill(path, with: .color(Color(dsHex: TourScene.bandColours[band]).opacity(0.85 * fade)))
        }

        var paths = Path()
        for (a, b) in scene.edges {
            paths.move(to: pt(a)); paths.addLine(to: pt(b))
        }
        context.stroke(paths, with: .color(.white.opacity(0.9)), style: StrokeStyle(lineWidth: 2, lineCap: .round))

        let badges = NUSTourOverview.spread(scene.stops.map { pt($0.position) }, minDistance: 21)
        for (index, p) in badges.enumerated() {
            let badge = CGRect(x: p.x - 10, y: p.y - 10, width: 20, height: 20)
            context.fill(Path(ellipseIn: badge), with: .color(scene.stops[index].level <= 1 ? NUS.blue : NUS.orange))
            context.stroke(Path(ellipseIn: badge), with: .color(.white), lineWidth: 1.5)
            context.draw(Text("\(index + 1)").font(.system(size: 11, weight: .bold)).foregroundStyle(.white), at: p)
        }

        guard names > 0 else { return }
        let texts = scene.stops.map { context.resolve(Text($0.name).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white)) }
        let sizes = texts.map { text -> CGSize in
            let s = text.measure(in: CGSize(width: 400, height: 40))
            return CGSize(width: s.width + 10, height: s.height + 4)
        }
        let boxes = NUSTourOverview.placeLabels(badges: badges, sizes: sizes, radius: 10, gap: 3, in: size)
        context.opacity = names
        for (index, box) in boxes.enumerated() {
            guard let box else { continue }
            context.fill(Path(roundedRect: box, cornerRadius: 6), with: .color(Color(dsHex: TourScene.background).opacity(0.78)))
            context.draw(texts[index], at: CGPoint(x: box.midX, y: box.midY))
        }
    }
}

/// What the home screen's 3D map draws, worked out once per map. The same numbers as Android's `TourScene`.
struct TourScene: Sendable {
    static let seconds = 3.0
    static let maxPoints = 36_000
    /// The card behind the cloud, and the cloud's colours from the lowest points to the highest.
    static let background: UInt32 = 0x0D1017
    static let bandColours: [UInt32] = [0x3F6FD8, 0x7F9BD6, 0xBFC3A0, 0xE3C85A, 0xF5C518]

    struct Stop: Sendable { let position: SIMD3<Float>; let level: Int; let name: String }
    let points: [SIMD3<Float>]
    let edges: [(SIMD3<Float>, SIMD3<Float>)]
    let stops: [Stop]
    let centre: SIMD3<Float>
    /// The larger of the map's width and depth, metres.
    let span: Float
    /// The heights the colours run between.
    let lowest: Float, highest: Float

    func band(of y: Float) -> Int {
        let t = (y - lowest) / max(highest - lowest, 0.1)
        return max(0, min(Self.bandColours.count - 1, Int(t * Float(Self.bandColours.count))))
    }

    init?(map: NavigationMap, levels: BuildingLevels, pointData: Data?) {
        guard !map.pois.isEmpty else { return nil }
        let xs = map.pois.map(\.x), zs = map.pois.map(\.z)
        // Floor heights: places are marked at camera height.
        func floor(_ poi: NavigationPOI) -> Float { levels.floorHeight(of: poi.id) ?? 0 }
        let ys = map.pois.map(floor)
        let lo = SIMD3(xs.min()!, ys.min()!, zs.min()!), hi = SIMD3(xs.max()!, ys.max()!, zs.max()!)
        centre = (lo + hi) / 2
        span = max(hi.x - lo.x, hi.z - lo.z, 1)
        lowest = lo.y - 0.5
        highest = hi.y + 4
        let byID = Dictionary(map.pois.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        func at(_ poi: NavigationPOI) -> SIMD3<Float> { SIMD3(poi.x, floor(poi), poi.z) }
        edges = map.edges.compactMap { e in
            guard let a = byID[e.from], let b = byID[e.to] else { return nil }
            return (at(a), at(b))
        }
        stops = map.pois.filter { ($0.category == .destination || $0.category == .exhibit) && $0.id != map.tourStart }
            .map { Stop(position: at($0), level: levels.level(of: $0.id), name: $0.name) }
        points = Self.sample(pointData, centre: centre, span: span, minY: lo.y - 1, maxY: hi.y + 6)
    }

    /// An even sample of the cloud, kept to the area of the paths and to sensible heights.
    static func sample(_ data: Data?, centre: SIMD3<Float>, span: Float, minY: Float, maxY: Float) -> [SIMD3<Float>] {
        guard let data, data.count >= 12 else { return [] }
        let count = data.count / 12
        let stride = max(1, count / (maxPoints * 5 / 4))
        var out: [SIMD3<Float>] = []
        out.reserveCapacity(maxPoints)
        data.withUnsafeBytes { raw in
            var i = 0
            while i < count, out.count < maxPoints {
                let p = SIMD3(raw.loadUnaligned(fromByteOffset: i * 12, as: Float.self),
                              raw.loadUnaligned(fromByteOffset: i * 12 + 4, as: Float.self),
                              raw.loadUnaligned(fromByteOffset: i * 12 + 8, as: Float.self))
                if abs(p.x - centre.x) < span * 0.62, abs(p.z - centre.z) < span * 0.62, p.y > minY, p.y < maxY { out.append(p) }
                i += stride
            }
        }
        return out
    }

    /// The camera at `progress` 0…1: it swings round and rises, easing to rest.
    func view(progress: Float, width: Float, height: Float) -> View {
        let e = 1 - pow(1 - max(0, min(1, progress)), 3)
        return View(centre: centre, yaw: (1 - e) * -1.92, pitch: 0.42 + e * (0.92 - 0.42),
                    scale: min(width / (span * 1.45), height / (span * 1.02)), width: width, height: height)
    }

    struct View {
        let centre: SIMD3<Float>
        /// Radians about the vertical; 0 has the map's −z at the top.
        let yaw: Float
        /// Radians down from the horizon; π/2 is straight down.
        let pitch: Float
        let scale: Float
        let width: Float, height: Float

        func project(_ p: SIMD3<Float>) -> SIMD2<Float> {
            let d = p - centre
            let x = d.x * cos(yaw) - d.z * sin(yaw)
            let z = d.x * sin(yaw) + d.z * cos(yaw)
            return SIMD2(width / 2 + x * scale, height / 2 + (z * sin(pitch) - d.y * cos(pitch)) * scale)
        }
    }
}

/// Layout the home map shares with Android (`TourOverview`).
enum NUSTourOverview {
    /// Moves badges that would overlap apart, a little at a time, so each number can be read.
    static func spread(_ points: [CGPoint], minDistance: CGFloat) -> [CGPoint] {
        var p = points
        for _ in 0..<12 {
            for i in p.indices {
                for j in p.indices where j > i {
                    var dx = p[j].x - p[i].x, dy = p[j].y - p[i].y
                    var d = hypot(dx, dy)
                    guard d < minDistance else { continue }
                    if d < 0.01 { dx = 1; dy = 0; d = 1 }
                    let push = (minDistance - d) / 2
                    p[i].x -= dx / d * push; p[i].y -= dy / d * push
                    p[j].x += dx / d * push; p[j].y += dy / d * push
                }
            }
        }
        return p
    }

    /// Where each badge's name goes: beside it on the right, else the left,
    /// below or above, wherever it fits inside the card without covering a
    /// badge or a name already placed. Nil when there is no room.
    static func placeLabels(badges: [CGPoint], sizes: [CGSize], radius: CGFloat, gap: CGFloat, in card: CGSize) -> [CGRect?] {
        var taken = badges.map { CGRect(x: $0.x - radius, y: $0.y - radius, width: radius * 2, height: radius * 2) }
        let inside = CGRect(origin: .zero, size: card).insetBy(dx: 2, dy: 2)
        return badges.indices.map { i in
            let b = badges[i], w = sizes[i].width, h = sizes[i].height
            let options = [
                CGRect(x: b.x + radius + gap, y: b.y - h / 2, width: w, height: h),
                CGRect(x: b.x - radius - gap - w, y: b.y - h / 2, width: w, height: h),
                CGRect(x: b.x - w / 2, y: b.y + radius + gap, width: w, height: h),
                CGRect(x: b.x - w / 2, y: b.y - radius - gap - h, width: w, height: h),
            ]
            let box = options.first { o in inside.contains(o) && !taken.contains { $0.intersects(o) } }
            if let box { taken.append(box) }
            return box
        }
    }
}

// MARK: - Places

struct NUSPlacesSheet: View {
    let guide: TourGuide
    let onPick: (NavigationPOI) -> Void

    var body: some View {
        NavigationStack {
            List(guide.places) { poi in
                Button { onPick(poi) } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.title2)
                            .foregroundStyle(NUS.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(poi.name).font(.headline).foregroundStyle(NUS.ink)
                            if let details = poi.details, !details.isEmpty {
                                Text(details).font(.subheadline).foregroundStyle(NUS.inkSecondary).lineLimit(2)
                            }
                        }
                        Spacer()
                        if let level = guide.levelName(of: poi.id) {
                            Text(level)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(NUS.blue.opacity(0.1), in: Capsule())
                                .foregroundStyle(NUS.blue)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            .navigationTitle("Where to?")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
