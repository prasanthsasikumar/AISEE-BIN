import SwiftUI

/// Settings, artboard H of the Claude Design canvas, split by audience: what a
/// visitor might change, what staff set per phone, and one level down the
/// developer set-up (Immersal token, map ids, tests) new staff never need.
///
/// A sheet over whatever is running: tracking and any guidance carry on.
struct SettingsView: View {
    @Bindable var viewModel: NavigationViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var token = ImmersalConfig.token
    @State private var mapIDsText = ImmersalConfig.mapIDsText
    @State private var showingGlasses = false
    @State private var showingProbe = false
    @State private var cachedMapIDs: [Int] = []
    @State private var mapDownloadState: String?
    @State private var mapDownloadError: String?
    @State private var localizerMode = ImmersalConfig.localizerMode
    @AppStorage(SpeakingRate.key) private var speakingRate = SpeakingRate.normal.rawValue

    var body: some View {
        NavigationStack {
            Form {
                visitorSection
                if viewModel.isStaff {
                    phoneSection
                    Section {
                        NavigationLink { developerPage } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Developer")
                                    Text("Immersal token · map ids · tests").font(.footnote.monospaced()).foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "chevron.left.forwardslash.chevron.right")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    AppLogo(isStaff: viewModel.isStaff,
                            onHome: { dismiss(); viewModel.mode = .home },
                            onUnlock: { viewModel.unlockStaff() },
                            onExitStaff: { dismiss(); viewModel.exitStaffMode() })
                        .scaleEffect(0.7)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.light)
        .sheet(isPresented: $showingGlasses) {
            GlassesView(viewModel: viewModel)
        }
        .fullScreenCover(isPresented: $showingProbe) {
            ProbeView(arManager: viewModel.arManager,
                      mapStore: viewModel.mapStore,
                      places: viewModel.mapStore.loadMap()?.pois ?? SampleGreenhouseMap.map.pois,
                      onAlignmentSaved: { viewModel.reloadMapKeepingSession() })
        }
    }

    // MARK: - Visitor experience

    private var visitorSection: some View {
        Section {
            Toggle("Beep guidance", isOn: $viewModel.beaconEnabled)
            Button {
                showingGlasses = true
            } label: {
                LabeledContent("Smart glasses") {
                    Text(glassesSummary)
                }
            }
            .foregroundStyle(.primary)
            Picker("Speaking rate", selection: $speakingRate) {
                ForEach(SpeakingRate.allCases) { Text($0.label).tag($0.rawValue) }
            }
        } header: {
            Text("Visitor experience")
        } footer: {
            Text("Beeps: while a route is active, a steady high tick means you are heading along the route. A low pattern means turn: two short beeps for left, one long beep for right. Silence means your position is not known. Say \"beeps on\" or \"beeps off\" any time. Speaking rate changes the system voice; recorded phrases keep their pace.")
        }
    }

    // MARK: - This phone (staff)

    private var phoneSection: some View {
        Section {
            Picker("Visitors see", selection: $viewModel.visitorMode) {
                Text("Both").tag(AppMode.welcome)
                Text("Navigate").tag(AppMode.navigation)
                Text("Explore").tag(AppMode.explore)
            }
            .pickerStyle(.segmented)
            Button("Exit staff mode") {
                dismiss()
                viewModel.exitStaffMode()
            }
            .foregroundStyle(.primary)
        } header: {
            Text("This phone")
        } footer: {
            Text("Both opens on a welcome screen where visitors talk or choose: plan a timed visit, or be guided to one place. Navigate or Explore skips straight to that mode. Tap the AiSee logo five times quickly to switch between staff and visitor mode.")
        }
    }

    // MARK: - Developer

    private var developerPage: some View {
        Form {
            immersalSection
            exploreSection
            measurementSection
            aboutSection
        }
        .navigationTitle("Developer")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: token) { _, value in ImmersalConfig.token = value }
        .onChange(of: mapIDsText) { _, value in ImmersalConfig.mapIDsText = value; refreshCachedMaps() }
        .onAppear { refreshCachedMaps() }
    }

    private var exploreSection: some View {
        Section {
            LabeledContent("Ask token", value: ExploreConfig.token.isEmpty ? "Missing: questions will fail" : "Set")
                .foregroundStyle(ExploreConfig.token.isEmpty ? .red : .primary)
        } header: {
            Text("Explore (public visitors)")
        }
    }

    // MARK: - Immersal

    private var immersalSection: some View {
        Section {
            LabeledContent("Map ids") {
                TextField(ImmersalConfig.mapIDsPlaceholder, text: $mapIDsText)
                    .keyboardType(.numbersAndPunctuation)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.trailing)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Developer token").foregroundStyle(.secondary).font(.footnote)
                TextField("Immersal developer token", text: $token, axis: .vertical)
                    .font(.footnote.monospaced())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .lineLimit(2...3)
            }
            Picker("Localization", selection: $localizerMode) {
                ForEach(ImmersalLocalizerMode.allCases) { Text($0.label).tag($0) }
            }
            .onChange(of: localizerMode) { _, mode in
                ImmersalConfig.localizerMode = mode
                viewModel.reselectImmersalLocalizer()
            }
            LabeledContent("Cached on this phone",
                           value: cachedMapIDs.isEmpty ? "none" : cachedMapIDs.map(String.init).joined(separator: ", "))
            Button(mapDownloadState ?? "Download maps for offline use") {
                downloadMaps()
            }
            .disabled(mapDownloadState != nil || ImmersalConfig.token.isEmpty || offlineMapIDs.isEmpty)
            if let mapDownloadError {
                Text(mapDownloadError).font(.footnote).foregroundStyle(.red)
            }
            if ImmersalConfig.hasBundledToken || !ImmersalConfig.defaultMapIDsText.isEmpty {
                Button("Reset to this build's defaults") {
                    ImmersalConfig.token = ""
                    ImmersalConfig.mapIDsText = ""
                    token = ImmersalConfig.token
                    mapIDsText = ImmersalConfig.mapIDsText
                }
            }
        } header: {
            Text("Immersal")
        } footer: {
            Text("Localization: Auto and On phone work on the phone when this map is cached, and use the server otherwise; Immersal server always sends frames to Immersal (needs internet). ")
            + Text(ImmersalConfig.hasBundledToken
                 ? "Filled in by this build; edit only to try another account or map. Map ids come from the Immersal Mapper app once a scan finishes constructing. Stored on this device only. A map cached on this phone is localized on the phone, with no network."
                 : "Map ids come from the Immersal Mapper app once a scan finishes constructing. Stored on this device only. A map cached on this phone is localized on the phone, with no network.")
        }
    }

    /// The maps positioning actually uses: the loaded map's own, else the typed ids.
    private var offlineMapIDs: [Int] { ImmersalConfig.mapIDs(for: viewModel.mapAlignment) }

    private func refreshCachedMaps() {
        let cache = ImmersalMapCache()
        cachedMapIDs = offlineMapIDs.filter { cache.contains($0) }
    }

    private func downloadMaps() {
        let ids = offlineMapIDs
        let token = ImmersalConfig.token
        mapDownloadState = "Downloading…"
        mapDownloadError = nil
        Task {
            do {
                try await ImmersalMapCache().fetch(ids, token: token)
            } catch {
                mapDownloadError = "Download failed: \(error.localizedDescription)"
            }
            mapDownloadState = nil
            refreshCachedMaps()
        }
    }

    private var glassesSummary: String {
        switch viewModel.glasses.connection.state {
        case .connected(let name):
            return viewModel.positioningSource == .glasses ? "\(name) · positioning" : name
        case .connecting:
            return "Connecting…"
        default:
            return "Not connected"
        }
    }

    // MARK: - Measurement walk

    private var measurementSection: some View {
        Section {
            Button {
                showingProbe = true
            } label: {
                Label("Immersal vs ARKit walk…", systemImage: "ruler")
            }
        } footer: {
            Text("Measures both positioning systems on the same walk and can save an Immersal alignment into this map.")
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: Self.versionString)
            LabeledContent("Map", value: viewModel.mapName)
        }
    }

    private static var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
