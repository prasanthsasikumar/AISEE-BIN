import SwiftUI

/// Everything about the glasses in one sheet: connect, stream, calibrate the
/// lens, and hand positioning over to them.
///
/// Plain system styling, like the probe: this is set-up done by a sighted
/// helper before the visitor starts walking, not part of the hands-free loop.
struct GlassesView: View {
    @Bindable var viewModel: NavigationViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var calibration = FocalCalibrationRunner()
    @State private var token = ImmersalConfig.token
    @State private var mapIDsText = ImmersalConfig.mapIDsText
    @State private var streamBusy = false
    @State private var streamError: String?

    private var glasses: GlassesService { viewModel.glasses }
    private var positioning: GlassesPositioning { viewModel.glassesPositioning }

    var body: some View {
        NavigationStack {
            Form {
                connectionSection
                if glasses.isConnected {
                    streamSection
                    positioningSection
                    calibrationSection
                }
                immersalSection
                if !glasses.log.isEmpty { logSection }
            }
            .navigationTitle("AiSee Glasses")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) { Button("Done") { dismiss() } }
            }
            .onAppear {
                if !glasses.isConnected { glasses.startScan() }
            }
            .onDisappear { glasses.stopScan() }
            // Saved as typed, so the calibration button and the positioning
            // status react without closing the sheet first.
            .onChange(of: token) { _, value in ImmersalConfig.token = value }
            .onChange(of: mapIDsText) { _, value in ImmersalConfig.mapIDsText = value }
        }
    }

    // MARK: - Connection

    private var connectionSection: some View {
        Section {
            switch glasses.connection.state {
            case .connected(let name):
                LabeledContent("Connected", value: name)
                if let battery = glasses.connection.battery {
                    LabeledContent("Battery", value: "\(battery)%")
                }
                Button("Disconnect", role: .destructive) { glasses.disconnect() }
            case .connecting:
                HStack { ProgressView(); Text("Connecting…").padding(.leading, 8) }
            case .scanning, .disconnected:
                if !glasses.connection.bluetoothReady {
                    Label("Bluetooth is off", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
                ForEach(glasses.connection.discovered) { device in
                    Button {
                        glasses.connect(device.id)
                    } label: {
                        HStack {
                            Text(device.name)
                            Spacer()
                            if device.rssi != 0 {
                                Text("\(device.rssi) dBm").font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if glasses.connection.discovered.isEmpty {
                    HStack {
                        if case .scanning = glasses.connection.state { ProgressView() }
                        Text("Looking for glasses…").foregroundStyle(.secondary).padding(.leading, 8)
                    }
                }
                Button("Scan again") { glasses.startScan() }
            }
        } header: {
            Text("Connection")
        } footer: {
            Text("Power the glasses on and keep them near the phone. Already-paired glasses appear without advertising.")
        }
    }

    // MARK: - Stream

    private var streamSection: some View {
        Section {
            if let image = glasses.previewImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .listRowInsets(EdgeInsets())
            }
            Toggle(isOn: Binding(get: { glasses.isStreaming }, set: { setStreaming($0) })) {
                LabeledContent("Live video", value: glasses.isStreaming ? "\(glasses.framesPerSecond) fps" : "off")
            }
            .disabled(streamBusy)
            if let error = streamError ?? glasses.lastStreamError {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
        } header: {
            Text("Camera")
        } footer: {
            Text("Video arrives over the glasses’ own Wi-Fi hotspot; iOS asks to join it the first time. Internet goes over cellular while it runs.")
        }
    }

    private func setStreaming(_ on: Bool) {
        guard !streamBusy else { return }
        streamBusy = true
        streamError = nil
        Task {
            defer { streamBusy = false }
            if on {
                do { try await glasses.startStreaming() } catch { streamError = error.localizedDescription }
            } else {
                await glasses.stopStreaming()
            }
        }
    }

    // MARK: - Positioning

    private var positioningSection: some View {
        Section {
            Toggle("Use glasses for positioning",
                   isOn: Binding(get: { viewModel.positioningSource == .glasses },
                                 set: { viewModel.positioningSource = $0 ? .glasses : .phone }))
                .disabled(!glasses.isConnected)
            if viewModel.positioningSource == .glasses {
                LabeledContent("Status", value: positioning.localizationStatus.label)
                LabeledContent("Fixes", value: "\(positioning.fixes) / \(positioning.attempts)")
                if positioning.rejectedFixes > 0 {
                    LabeledContent("Rejected", value: "\(positioning.rejectedFixes)")
                }
                LabeledContent("Latency", value: positioning.lastLatencyMS.map { "\($0) ms" } ?? "—")
                LabeledContent("Walked", value: String(format: "%.1f m", positioning.walkedMetres))
                if let age = positioning.secondsSinceFix {
                    LabeledContent("Last fix", value: String(format: "%.0f s ago", age))
                }
                if let error = positioning.lastError {
                    Text(error).font(.footnote).foregroundStyle(.secondary)
                }
            }
            ForEach([GlassesService.KeyAction.talk, .whereAmI, .stopGuidance], id: \.label) { action in
                Label(action.label, systemImage: "button.horizontal.top.press")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            Text("Positioning")
        } footer: {
            if let reason = viewModel.glassesBlockedReason {
                Text(reason)
            } else {
                Text("The phone camera is paused while the glasses position you. Switch back to hand the phone to a helper.")
            }
        }
    }

    // MARK: - Calibration

    private var calibrationSection: some View {
        Section {
            LabeledContent("Focal length") {
                Text("\(Int(positioning.camera.focalPx)) px · \(Int(positioning.camera.horizontalFOVDegrees))°")
            }
            switch calibration.state {
            case .idle, .finished, .failed:
                Button("Calibrate against the map") { runCalibration() }
                    .disabled(calibrationBlockedReason != nil)
                if let reason = calibrationBlockedReason {
                    Text(reason).font(.footnote).foregroundStyle(.secondary)
                }
            case .running(let round, let candidate):
                HStack {
                    ProgressView()
                    Text("Round \(round) of \(FocalCalibrationRunner.rounds), candidate \(candidate) of \(FocalCalibration.candidates.count)")
                        .padding(.leading, 8)
                    Spacer()
                    Button("Stop") { calibration.cancel() }
                }
            }
            switch calibration.state {
            case .finished(let best):
                Text(best.map { "Best focal length: \(Int($0)) px, saved." }
                     ?? "Nothing localized at any focal length. Stand somewhere the map covers and try again.")
                    .font(.footnote)
            case .failed(let message):
                Text(message).font(.footnote).foregroundStyle(.red)
            default:
                EmptyView()
            }
            if !calibration.samples.isEmpty {
                ForEach(calibration.scores, id: \.focalPx) { score in
                    LabeledContent("\(Int(score.focalPx)) px") {
                        Text("\(score.successes)/\(score.attempts)" + (score.spread > 0 ? String(format: " · ±%.2f m", score.spread) : ""))
                            .monospacedDigit()
                    }
                    .font(.footnote)
                }
            }
        } header: {
            Text("Lens calibration")
        } footer: {
            Text("Stand still somewhere the Immersal map covers. The same frame is tried at each focal length; the one the map recognises most wins.")
        }
    }

    private var calibrationBlockedReason: String? {
        if !glasses.isStreaming { return "Turn on Live video above first." }
        if token.isEmpty || mapIDsText.immersalMapIDs.isEmpty { return "Enter the Immersal token and map ids below first." }
        return nil
    }

    private func runCalibration() {
        let service = glasses
        calibration.run(nextFrame: {
            guard let buffer = service.latestFrame()?.pixelBuffer,
                  let copy = ImmersalFrameEncoder.copyBGRA(from: buffer) else { return nil }
            let png = await Task.detached { ImmersalFrameEncoder.grayscalePNG(from: copy, factor: 1) }.value
            guard let png else { return nil }
            return (png, copy.width, copy.height)
        }, localize: { png, k in
            await ImmersalClient(token: ImmersalConfig.token, mapIDs: ImmersalConfig.mapIDs)
                .localize(pngData: png, fx: k.fx, fy: k.fy, ox: k.ox, oy: k.oy)
        })
        Task {
            // Adopt the result once the runner saves it.
            while case .running = calibration.state { try? await Task.sleep(for: .milliseconds(300)) }
            positioning.camera = GlassesCamera.load()
        }
    }

    // MARK: - Immersal

    private var immersalSection: some View {
        Section {
            SecureField("Immersal developer token", text: $token)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            TextField("Map ids, comma separated", text: $mapIDsText)
                .keyboardType(.numbersAndPunctuation)
                .autocorrectionDisabled()
            if let alignment = viewModel.mapAlignment {
                LabeledContent("Map alignment") {
                    Text(String(format: "%d fixes · %.2f m", alignment.pairCount, alignment.rmsError))
                }
            } else {
                Label("This map has no Immersal alignment yet. Run a probe walk with the phone and save one.",
                      systemImage: "exclamationmark.triangle")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            Text("Immersal")
        } footer: {
            Text("Shared with the measurement harness. Stored on this device only.")
        }
    }

    private var logSection: some View {
        Section("Glasses log") {
            ForEach(Array(glasses.log.suffix(12).enumerated()), id: \.offset) { _, line in
                Text(line).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
        }
    }
}
