import SwiftUI

/// The Settings tab: everything a sighted helper sets up once, in one place
/// that is impossible to miss. Immersal credentials arrive prefilled from the
/// build so a tester never pastes a token; the glasses sheet and the
/// measurement walk open from here.
///
/// Plain system styling, like the sheets it opens: set-up, not the hands-free
/// loop. Switching here leaves tracking and any guidance running.
struct SettingsView: View {
    @Bindable var viewModel: NavigationViewModel

    @State private var token = ImmersalConfig.token
    @State private var mapIDsText = ImmersalConfig.mapIDsText
    @State private var showingGlasses = false
    @State private var showingProbe = false
    @State private var cachedMapIDs: [Int] = []
    @State private var mapDownloadState: String?
    @State private var mapDownloadError: String?

    var body: some View {
        NavigationStack {
            Form {
                immersalSection
                glassesSection
                measurementSection
                aboutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: token) { _, value in ImmersalConfig.token = value }
            .onChange(of: mapIDsText) { _, value in ImmersalConfig.mapIDsText = value; refreshCachedMaps() }
            .onAppear { refreshCachedMaps() }
        }
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
            Text(ImmersalConfig.hasBundledToken
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

    // MARK: - Glasses

    private var glassesSection: some View {
        Section {
            Button {
                showingGlasses = true
            } label: {
                LabeledContent {
                    Text(glassesSummary).foregroundStyle(.secondary)
                } label: {
                    Label("AiSee Glasses…", systemImage: "eyeglasses")
                }
            }
        } footer: {
            Text("Connect, stream live video, calibrate the lens and let the glasses take over positioning.")
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
