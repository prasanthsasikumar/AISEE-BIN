import SwiftUI
import UIKit

struct NUSRootView: View {
    let viewModel: NavigationViewModel
    let guide: TourGuide
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingPlaces = false
    @State private var showingStaff = false
    /// The welcome screen is shown once, on the first launch; "About this tour" on the home screen brings it back.
    @AppStorage("nus.introSeen") private var introSeen = false
    @State private var showingIntro = false

    var body: some View {
        ZStack {
            if guide.phase == .home {
                NUSHomeView(viewModel: viewModel, guide: guide,
                            onChoose: { showingPlaces = true },
                            onStaff: { showingStaff = true },
                            onAbout: { showingIntro = true })
                    .transition(.opacity)
            } else {
                NUSGuideView(viewModel: viewModel, guide: guide, onStaff: { showingStaff = true })
                    .transition(.opacity)
            }
        }
        .overlay {
            if guide.phase == .home, !introSeen || showingIntro {
                NUSIntroView(viewModel: viewModel, guide: guide) {
                    viewModel.usage.log("intro.done", ["first": .bool(!introSeen)])
                    introSeen = true
                    showingIntro = false
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: guide.phase == .home)
        .animation(.easeInOut(duration: 0.25), value: introSeen || !showingIntro)
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
    let onAbout: () -> Void

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

            Spacer(minLength: 12)

            Image("SoCat")
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 190)
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
            .padding(.top, 16)

            Spacer(minLength: 16)

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

                Button("About this tour", action: onAbout)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(NUS.blue)
                    .frame(minHeight: 44)

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

// MARK: - Welcome (first launch): what this is, and the tour on a map

struct NUSIntroView: View {
    let viewModel: NavigationViewModel
    let guide: TourGuide
    let onDone: () -> Void

    private var hasMap: Bool { viewModel.localVersion != nil }

    var body: some View {
        let places = hasMap ? guide.places : []
        let levels = viewModel.engine.levels
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Image("NUSLogo").resizable().scaledToFit().frame(height: 40)
                        .accessibilityLabel("NUS Computing")
                    Text("Welcome to NUS Computing")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(NUS.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text(NUSTourOverview.summary(stops: places.count, floors: levels.levelHeights.count))
                        .font(.body)
                        .foregroundStyle(NUS.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if places.isEmpty {
                        Text("Getting the building map…")
                            .font(.subheadline)
                            .foregroundStyle(NUS.inkSecondary)
                            .frame(maxWidth: .infinity, minHeight: 160)
                            .background(NUS.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            NUSTourMap(map: viewModel.displayMap, levels: levels, places: places)
                            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                                      alignment: .leading, spacing: 8) {
                                ForEach(Array(places.enumerated()), id: \.element.id) { index, poi in
                                    HStack(spacing: 8) {
                                        Text("\(index + 1)")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.white)
                                            .frame(width: 22, height: 22)
                                            .background(NUSTourOverview.colour(level: levels.level(of: poi.id)), in: Circle())
                                        Text(poi.name).font(.subheadline).foregroundStyle(NUS.ink).lineLimit(1)
                                    }
                                    .accessibilityElement(children: .ignore)
                                    .accessibilityLabel("\(index + 1), \(poi.name)" + (levels.isMultiLevel ? ", Level \(levels.level(of: poi.id))" : ""))
                                }
                            }
                            if levels.isMultiLevel {
                                HStack(spacing: 14) {
                                    ForEach(1...levels.levelHeights.count, id: \.self) { level in
                                        HStack(spacing: 6) {
                                            Circle().fill(NUSTourOverview.colour(level: level)).frame(width: 10, height: 10)
                                            Text("Level \(level)").font(.caption.weight(.semibold)).foregroundStyle(NUS.inkSecondary)
                                        }
                                    }
                                }
                                .accessibilityHidden(true)
                            }
                        }
                        .padding(14)
                        .background(NUS.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                        Text("The tour starts from the stop nearest to you, and you can skip any stop.")
                            .font(.footnote)
                            .foregroundStyle(NUS.inkSecondary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 16)
            }
            Button(action: onDone) { Text("Got it") }
                .buttonStyle(NUSButtonStyle(fill: NUS.orange))
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
        }
        .background(NUS.canvas.ignoresSafeArea())
        .preferredColorScheme(.light)
        .onAppear { viewModel.usage.log("intro.shown", [:]) }
    }
}

/// Words, colours and layout the welcome map shares with Android (`TourOverview`).
enum NUSTourOverview {
    static func summary(stops: Int, floors: Int) -> String {
        let intro = "This is a self-guided tour of the School of Computing. Hold up your phone and follow the orange arrows on the floor"
        guard stops > 0 else { return intro + "." }
        let places = "\(stops) place\(stops == 1 ? "" : "s")" + (floors > 1 ? " across \(floors) floors" : "")
        return intro + " to \(places). The whole tour takes about ten minutes."
    }

    /// Level 1 is blue, every floor above it orange.
    static func colour(level: Int) -> Color { level <= 1 ? NUS.blue : NUS.orange }

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
}

/// The whole tour from above: every path, and the stops numbered in tour order.
struct NUSTourMap: View {
    let map: NavigationMap
    let levels: BuildingLevels
    let places: [NavigationPOI]

    var body: some View {
        Canvas { context, size in
            let all = map.pois.map(\.planarPosition)
            guard let minX = all.map(\.x).min(), let maxX = all.map(\.x).max(),
                  let minZ = all.map(\.y).min(), let maxZ = all.map(\.y).max() else { return }
            let pad: CGFloat = 18
            let span = CGFloat(max(maxX - minX, maxZ - minZ, 1))
            let scale = (min(size.width, size.height) - 2 * pad) / span
            let offset = CGPoint(x: (size.width - CGFloat(maxX - minX) * scale) / 2, y: (size.height - CGFloat(maxZ - minZ) * scale) / 2)
            func pt(_ p: SIMD2<Float>) -> CGPoint {
                CGPoint(x: offset.x + CGFloat(p.x - minX) * scale, y: offset.y + CGFloat(p.y - minZ) * scale)
            }
            let byID = Dictionary(map.pois.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            var paths = Path()
            for edge in map.edges {
                guard let a = byID[edge.from], let b = byID[edge.to] else { continue }
                paths.move(to: pt(a.planarPosition))
                paths.addLine(to: pt(b.planarPosition))
            }
            context.stroke(paths, with: .color(NUS.inkSecondary.opacity(0.3)), style: StrokeStyle(lineWidth: 4, lineCap: .round))

            let badges = NUSTourOverview.spread(places.map { pt($0.planarPosition) }, minDistance: 26)
            for (index, p) in badges.enumerated() {
                let badge = CGRect(x: p.x - 12, y: p.y - 12, width: 24, height: 24)
                context.fill(Path(ellipseIn: badge), with: .color(NUSTourOverview.colour(level: levels.level(of: places[index].id))))
                context.stroke(Path(ellipseIn: badge), with: .color(.white), lineWidth: 2)
                context.draw(Text("\(index + 1)").font(.caption.weight(.bold)).foregroundStyle(.white), at: p)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: 300)
        .frame(maxWidth: .infinity)
        .background(NUS.canvas, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement()
        .accessibilityLabel("Map of the tour with \(places.count) numbered stops")
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
