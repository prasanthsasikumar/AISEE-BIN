import SwiftUI

/// Hidden staff screen (5 quick taps on the NUS logo): which map, positioning
/// state, and the switches a demo needs.
struct NUSStaffView: View {
    let viewModel: NavigationViewModel
    let guide: TourGuide
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Map") {
                    LabeledContent("On this phone", value: viewModel.localVersion.map { "\($0.slug) v\($0.version)" } ?? "none")
                    LabeledContent("Name", value: viewModel.mapName)
                    LabeledContent("Places", value: "\(guide.places.count) stops · \(viewModel.displayMap.pois.count) nodes")
                    LabeledContent("Levels", value: levelsText)
                    if !viewModel.syncState.label.isEmpty { Text(viewModel.syncState.label).font(.footnote) }
                    Button("Check for map updates") { Task { await viewModel.checkForMapUpdate() } }
                }
                Section("Published NUS maps") {
                    if viewModel.isListingMaps { ProgressView() }
                    if let error = viewModel.mapListError { Text(error).foregroundStyle(.red).font(.footnote) }
                    ForEach(viewModel.serverMaps) { map in
                        Button {
                            Task { await viewModel.switchMap(to: map.slug) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(map.name).foregroundStyle(.primary)
                                    Text("\(map.slug) · v\(map.version)").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if viewModel.switchingToSlug == map.slug { ProgressView() }
                                else if viewModel.localVersion?.slug == map.slug { Image(systemName: "checkmark") }
                            }
                        }
                    }
                    if !viewModel.isListingMaps && viewModel.serverMaps.isEmpty {
                        Text("No maps named nus-… yet. Publish one from AISEE-BIN's Author mode.").font(.footnote)
                    }
                }
                Section("Positioning") {
                    LabeledContent("Status", value: viewModel.localizationStatus.label)
                    LabeledContent("Tracking", value: viewModel.debug.trackingState)
                    LabeledContent("Height", value: String(format: "%.2f m (Level %d)", viewModel.currentTransform.columns.3.y,
                                                           viewModel.engine.levels.level(forHeight: viewModel.currentTransform.columns.3.y)))
                    if let immersal = viewModel.phoneImmersalSummary { Text(immersal).font(.footnote) }
                    Button("Restart positioning") { viewModel.reloadMapAndRestart() }
                }
                Section("Guide") {
                    Toggle("Voice guidance", isOn: Binding(get: { guide.voiceOn }, set: { guide.voiceOn = $0 }))
                }
                Section {
                    Text("NUS Computing Tour \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""))")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Staff")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await viewModel.loadServerMaps() }
        }
    }

    private var levelsText: String {
        let heights = viewModel.engine.levels.levelHeights
        guard !heights.isEmpty else { return "no heights on this map" }
        return heights.enumerated().map { "L\($0.offset + 1) \(String(format: "%.1f", $0.element)) m" }.joined(separator: " · ")
    }
}
