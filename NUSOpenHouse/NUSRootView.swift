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

// MARK: - Header logo (5 taps opens the staff screen)

struct NUSLogoMark: View {
    var size: CGFloat = 44
    let onStaff: () -> Void
    @State private var taps: [Date] = []

    var body: some View {
        Image("NUSLogo")
            .resizable()
            .scaledToFit()
            .frame(height: size)
            .contentShape(Rectangle())
            .onTapGesture {
                let now = Date()
                taps = taps.filter { now.timeIntervalSince($0) < 3 } + [now]
                if taps.count >= 5 { taps = []; onStaff() }
            }
            .accessibilityLabel("NUS")
    }
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
                VStack(alignment: .leading, spacing: 0) {
                    Text("NUS").font(.headline.weight(.heavy)).foregroundStyle(NUS.blue)
                    Text("Computing").font(.subheadline.weight(.semibold)).foregroundStyle(NUS.orange)
                }
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
                Text("Follow me around for a tour of NUS Computing. Hold up your phone and I'll walk ahead of you.")
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
