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
    let mapStore: MapStore
    let places: [NavigationPOI]
    /// Called after an alignment is written into the saved map.
    var onAlignmentSaved: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @State private var alignmentMessage: String?
    @State private var alignmentSaved = false

    @State private var session = ProbeSession()
    @State private var token = ImmersalConfig.token
    @State private var mapIDsText = ImmersalConfig.mapIDsText
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
                arManager.onProbeFrame = { [session] frame, trackingState in
                    session.consume(frame: frame, trackingState: trackingState)
                }
            }
            .onDisappear { arManager.onProbeFrame = nil }
        }
    }

    // MARK: - Idle

    private var configuration: some View {
        Group {
            Section {
                TextField(ImmersalConfig.mapIDsPlaceholder, text: $mapIDsText)
                    .keyboardType(.numbersAndPunctuation)
                    .autocorrectionDisabled()
                SecureField(ImmersalConfig.hasBundledToken ? "Immersal token (built in; type to override)" : "Immersal developer token",
                            text: $token)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Credentials")
            } footer: {
                Text("A measurement walk uploads camera images to Immersal’s cloud service "
                     + "(Hexagon) to ask where the phone is. Nothing is uploaded unless you start "
                     + (ImmersalConfig.hasBundledToken
                        ? "a walk. A developer token is built into this build; anything typed here overrides it, on this device only.\n\n"
                        : "a walk. The token is stored on this device only.\n\n")
                     + "Map ids come from the Immersal Developer Portal once the Mapper app’s maps "
                     + "finish constructing. Up to 8; list the interior map first.")
            }

            Section {
                LabeledContent("Localize every", value: "\(Int(ProbeSession.localizeInterval)) s")
                LabeledContent("ARKit samples", value: "\(Int(1 / ProbeSession.arSampleInterval)) Hz")
                LabeledContent("Image", value: "grayscale PNG, ÷\(ImmersalFrameEncoder.downscale)")
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
                    ImmersalConfig.token = token
                    ImmersalConfig.mapIDsText = mapIDsText
                    session.start()
                } label: {
                    Text("Start walk").font(.headline)
                }
                .disabled(ImmersalConfig.resolveToken(stored: token, bundled: ImmersalConfig.bundledToken).isEmpty
                          || ImmersalConfig.resolveMapIDsText(stored: mapIDsText, bundled: ImmersalConfig.defaultMapIDsText).immersalMapIDs.isEmpty)
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

            Section {
                marker("Stepped outside", "arrow.up.forward.square")
                marker("Back inside", "arrow.down.left.square")
                marker("Lens covered", "eye.slash")
                marker("Lens uncovered", "eye")
            } header: {
                Text("Protocol markers")
            } footer: {
                Text("These only write a timestamp into the walk log for the analysis; nothing changes on screen except the tick.")
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
                LabeledContent("Alignment pairs", value: "\(session.alignmentPairs.count)")
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

    private var alignmentFooter: String {
        guard arManager.isUsingSavedWorldMap else {
            return "No saved ARWorldMap was loaded, so this session's frame is not the map's frame "
                + "and an alignment fitted here would be meaningless."
        }
        let pairs = ImmersalAlignment.minimumPairs
        let spread = Int(ImmersalAlignment.minimumSpread)
        return "Fits Immersal map space onto this map's ARKit frame from the fixes above, so the "
            + "glasses can position a visitor on it. Needs at least \(pairs) fixes spread over "
            + "\(spread) m while ARKit was tracking normally."
    }

    private func saveAlignment() {
        do {
            let alignment = try session.fitAlignment()
            var map = mapStore.loadMap() ?? SampleGreenhouseMap.map
            map.immersalAlignment = alignment
            try mapStore.saveMap(map)
            alignmentSaved = true
            alignmentMessage = String(format: "%d pairs, %.2f m RMS, yaw %.0f°. Upload the map from Author to publish it.",
                                      alignment.pairCount, alignment.rmsError, alignment.yaw * 180 / .pi)
            onAlignmentSaved()
        } catch {
            alignmentMessage = error.localizedDescription
        }
    }

    private func marker(_ label: String, _ icon: String) -> some View {
        Button {
            session.marker(label)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } label: {
            HStack {
                Label(label, systemImage: icon)
                Spacer()
                if let last = session.lastMarker, last.label == label {
                    Text(String(format: "%d:%02d", Int(last.elapsed) / 60, Int(last.elapsed) % 60)).font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
            }
            .frame(minHeight: 40)
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
                LabeledContent("Usable pairs", value: "\(session.alignmentPairs.count)")
                Button(alignmentSaved ? "Alignment saved" : "Save alignment to map") { saveAlignment() }
                    .disabled(alignmentSaved || !arManager.isUsingSavedWorldMap)
                if let message = alignmentMessage {
                    Text(message).font(.footnote).foregroundStyle(alignmentSaved ? Color.secondary : Color.red)
                }
            } header: {
                Text("Glasses alignment")
            } footer: {
                Text(alignmentFooter)
            }
            Section {
                ShareLink(item: url) { Label("Export CSV", systemImage: "square.and.arrow.up") }
                Button("New walk") { session = ProbeSession(); alignmentSaved = false; alignmentMessage = nil }
            }
        }
    }
}

/// The walk, written down, because a comparison is only worth reporting if it
/// was run the same way twice.
private struct WalkProtocolView: View {
    @Environment(\.dismiss) private var dismiss

    private let steps = [
        ("Cold start where the scan began", "Stand still with the map loaded. Both systems are racing for a first fix; do not walk until Tracking Ready and at least one Immersal fix."),
        ("Walk a loop past every place", "Normal walking pace. At each place, stand on the exact spot, face what it is, and tap its name under Standing at. Those taps are the only ground truth there is."),
        ("Cover the lens, twice", "Mid-loop, tap Lens covered, cover the camera for five seconds, uncover, tap Lens uncovered. Repeat once more later in the loop."),
        ("Leave the mapped area, if you can", "Optional, for spaces with an exit: tap Stepped outside, walk about 15 m away, turn around, come back, tap Back inside. Skip this in a single room."),
        ("Stamp the first two places again", "Return to the first two places and tap them again. This is what exposes drift accumulated on the way round."),
        ("Finish", "Tap Finish walk. Save alignment to map if offered, then export the CSV before closing the app."),
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
