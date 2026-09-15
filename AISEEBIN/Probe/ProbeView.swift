#if DEBUG
import ARKit
import SwiftUI

// THROWAWAY — see ImmersalPose.swift.

/// The measurement screen: configure once, then walk the route tapping the
/// place you are standing at.
///
/// Plain system styling on purpose — this is an instrument, not part of the
/// product, and it should never be mistaken for it. The stamp buttons are large
/// because they get pressed while walking and looking at a greenhouse rather
/// than at the phone.
struct ProbeView: View {
    let arManager: ARNavigationManager
    let places: [NavigationPOI]
    @Environment(\.dismiss) private var dismiss

    @State private var session = ProbeSession()
    @State private var token = ProbeConfig.token
    @State private var mapIDsText = ProbeConfig.mapIDsText
    @State private var showingProtocol = false

    var body: some View {
        NavigationStack {
            Form {
                switch session.state {
                case .idle:      configuration
                case .running:   liveWalk
                case .finished(let url): results(url)
                }
            }
            .navigationTitle("Immersal vs ARKit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .disabled(session.state == .running)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Protocol") { showingProtocol = true }
                }
            }
            .sheet(isPresented: $showingProtocol) { WalkProtocolView() }
            .onAppear {
                arManager.onDebugFrame = { [session] frame, trackingState in
                    session.consume(frame: frame, trackingState: trackingState)
                }
            }
            .onDisappear { arManager.onDebugFrame = nil }
        }
    }

    // MARK: - Idle

    private var configuration: some View {
        Group {
            Section {
                SecureField("Immersal developer token", text: $token)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Map ids, comma separated", text: $mapIDsText)
                    .keyboardType(.numbersAndPunctuation)
                    .autocorrectionDisabled()
            } header: {
                Text("Credentials")
            } footer: {
                Text("Stored in UserDefaults on this device only — never written to the repo. "
                     + "Map ids come from the Developer Portal after the Mapper app’s maps finish "
                     + "constructing. Up to 8; list the interior map first, then the doorway map.")
            }

            Section {
                LabeledContent("Localize every", value: "\(Int(ProbeSession.localizeInterval)) s")
                LabeledContent("ARKit samples", value: "\(Int(1 / ProbeSession.arSampleInterval)) Hz")
                LabeledContent("Image", value: "grayscale PNG, ÷\(ProbeFrameEncoder.downscale)")
                LabeledContent("ARKit world map", value: arManager.isUsingSavedWorldMap ? "loaded" : "none")
                LabeledContent("ARKit state", value: arManager.localizationStatus.label)
            } header: {
                Text("Setup")
            } footer: {
                Text(arManager.isUsingSavedWorldMap
                     ? "Both systems will be measured on the same frames of this session."
                     : "No saved ARWorldMap is loaded, so ARKit has nothing to relocalize against — "
                       + "install or scan a map first, or the comparison only measures Immersal.")
            }

            Section {
                Button {
                    ProbeConfig.token = token
                    ProbeConfig.mapIDsText = mapIDsText
                    session.start()
                } label: {
                    Text("Start walk").font(.headline)
                }
                .disabled(token.isEmpty || mapIDsText.immersalMapIDs.isEmpty)
            } footer: {
                if let error = session.lastError { Text(error).foregroundStyle(.red) }
            }
        }
    }

    // MARK: - Running

    private var liveWalk: some View {
        Group {
            Section("Standing at") {
                ForEach(places) { place in
                    Button {
                        session.stamp(placeID: place.id, name: place.name)
                    } label: {
                        HStack {
                            Text(place.name).font(.title3)
                            Spacer()
                            if session.lastStampLabel == place.name {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            }
                        }
                        .frame(minHeight: 44)
                    }
                }
            }

            Section("Protocol markers") {
                marker("Stepped outside", "arrow.up.forward.square")
                marker("Back inside", "arrow.down.left.square")
                marker("Lens covered", "eye.slash")
                marker("Lens uncovered", "eye")
            }

            Section("Live") {
                LabeledContent("Fixes", value: "\(session.successes) / \(session.attempts)")
                LabeledContent("Latency", value: session.lastLatencyMS.map { "\($0) ms" } ?? "—")
                LabeledContent("Answered by map", value: session.lastMapID.map(String.init) ?? "—")
                LabeledContent("Odometry disagreement") {
                    Text(session.lastDisagreement.map { String(format: "%.2f m", $0) } ?? "—")
                        .foregroundStyle((session.lastDisagreement ?? 0) > 1 ? .red : .primary)
                }
                LabeledContent("ARKit", value: arManager.localizationStatus.label)
                LabeledContent("Rows", value: "\(session.rowCount)")
                if session.pendingCount > 0 {
                    LabeledContent("Queued offline", value: "\(session.pendingCount)")
                }
                if let error = session.lastError {
                    Text(error).font(.footnote).foregroundStyle(.secondary)
                }
            }

            Section {
                Button("Finish walk") { session.finish() }
            } footer: {
                Text("Disagreement is the honest stand-in for a confidence score: Immersal’s "
                     + "reported motion minus ARKit’s, between consecutive fixes. Large while you "
                     + "are barely moving means a confidently wrong fix.")
            }
        }
    }

    private func marker(_ label: String, _ icon: String) -> some View {
        Button {
            session.marker(label)
        } label: {
            Label(label, systemImage: icon).frame(minHeight: 40)
        }
    }

    // MARK: - Finished

    private func results(_ url: URL) -> some View {
        Group {
            Section("Walk complete") {
                LabeledContent("Fixes", value: "\(session.successes) / \(session.attempts)")
                LabeledContent("Rows", value: "\(session.rowCount)")
                LabeledContent("File", value: url.lastPathComponent)
            }
            if session.pendingCount > 0 {
                Section {
                    Button(session.isReplaying ? "Sending…" : "Send \(session.pendingCount) queued frames") {
                        Task { await session.replayPending() }
                    }
                    .disabled(session.isReplaying)
                } footer: {
                    Text("Frames the network dropped during the walk. Their poses are still valid; "
                         + "their latencies are not, and are marked “replayed” in the log.")
                }
            }
            Section {
                ShareLink(item: url) { Label("Export CSV", systemImage: "square.and.arrow.up") }
                Button("New walk") { session = ProbeSession() }
            }
        }
    }
}

/// The walk, written down, because a comparison is only worth reporting if it
/// was run the same way twice.
private struct WalkProtocolView: View {
    @Environment(\.dismiss) private var dismiss

    private let steps = [
        ("Cold start at the entrance", "Launch with the ARWorldMap installed and stand still. Both systems are now racing for a first fix; do not walk until one lands."),
        ("Walk the fixed loop", "Normal walking pace. Stop at each place, stand on the spot, tap its name. The tap is the only ground truth there is."),
        ("Cover the lens, twice", "Mid-loop, tap “Lens covered”, cover it for five seconds, uncover, tap “Lens uncovered”. Repeat once more later in the loop."),
        ("Out through the doorway", "Tap “Stepped outside”, walk ~15 m along the path, turn around, come back, tap “Back inside”."),
        ("Re-stamp two interior places", "Return to the first two places and stamp them again. This is what exposes drift accumulated outside."),
        ("Finish", "Tap Finish walk, then export the CSV before closing the app."),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("One walk measures both systems, because both read the same ARKit frames. "
                         + "Repeat the whole walk at a different time of day if there is time — "
                         + "sun angle is the variable most likely to separate them.")
                    .font(.footnote)
                }
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    Section("\(index + 1). \(step.0)") { Text(step.1).font(.callout) }
                }
            }
            .navigationTitle("Walk protocol")
            .toolbar { ToolbarItem(placement: .primaryAction) { Button("Done") { dismiss() } } }
        }
    }
}
#endif
