import SwiftUI

/// Navigate mode, per artboards 01–06 of the Claude Design canvas.
///
/// The screen is secondary to audio: the visitor is blind and the phone is chest
/// mounted. Everything here is sized so a sighted helper can read state in one
/// glance in direct greenhouse sun — one enormous talk control, one unambiguous
/// state, and every state carried by colour *and* icon *and* word.
struct ContentView: View {
    @Bindable var viewModel: NavigationViewModel
    @Environment(\.scenePhase) private var scenePhase

    @State private var showingGlasses = false

    var body: some View {
        VStack(spacing: 0) {
            ModeSwitcher(mode: $viewModel.mode)

            switch viewModel.mode {
            case .navigation:
                navigationScreen
            case .authoring:
                AuthoringView(arManager: viewModel.arManager, mapStore: viewModel.mapStore)
            case .settings:
                SettingsView(viewModel: viewModel)
            }
        }
        .background(viewModel.mode == .navigation ? DS.N.canvas : DS.A.canvas)
        .preferredColorScheme(viewModel.mode == .navigation ? .dark : .light)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            viewModel.startSession()
        }
        .onChange(of: scenePhase) { _, phase in
            // ARKit pauses itself in the background; restart tracking when we return.
            if phase == .active, viewModel.localizationStatus == .notStarted {
                viewModel.startSession()
            }
        }
        .sheet(isPresented: $showingGlasses) {
            GlassesView(viewModel: viewModel)
        }
    }

    // MARK: - Navigate

    private var navigationScreen: some View {
        VStack(spacing: 0) {
            cameraStage
            dock
        }
        .background(DS.N.canvas)
    }

    /// Live camera with the state stack over it. The scrim is what makes the
    /// overlay readable when the camera is pointed at a sunlit glasshouse wall.
    private var cameraStage: some View {
        ZStack(alignment: .top) {
            Group {
                if viewModel.positioningSource == .glasses {
                    GlassesStage(image: viewModel.glasses.previewImage)
                } else if ARNavigationManager.isSupported {
                    ARPreviewView(session: viewModel.arManager.session,
                                  showFeaturePoints: viewModel.showDebug)
                } else {
                    DS.N.canvas
                }
            }
            .overlay {
                LinearGradient(colors: [DS.N.canvas.opacity(0.85),
                                        DS.N.canvas.opacity(0.25),
                                        DS.N.canvas.opacity(0.85)],
                               startPoint: .top, endPoint: .bottom)
            }
            .clipped()

            VStack(alignment: .leading, spacing: 12) {
                LocalizationStatusBadge(status: viewModel.localizationStatus,
                                        usingSavedMap: viewModel.positioningSource == .phone
                                            && viewModel.arManager.isUsingSavedWorldMap)
                syncSection
                primaryPanel

                if viewModel.showDebug {
                    DebugOverlay(info: viewModel.debug,
                                 status: viewModel.localizationStatus,
                                 hasSavedMap: viewModel.arManager.hasSavedWorldMap,
                                 lastSpoken: viewModel.guidance.lastSpokenText)
                }

                Spacer(minLength: 12)
                footerPanel
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }

    // MARK: Sync line / download card

    @ViewBuilder
    private var syncSection: some View {
        switch viewModel.syncState {
        case .downloading(let version):
            DownloadCard(version: version,
                         progress: viewModel.syncProgress,
                         bytesText: viewModel.syncBytesText)
        case .idle:
            EmptyView()
        case .failed(let message):
            SyncRow(icon: "exclamationmark.triangle.fill",
                    text: "Sync failed: \(message)",
                    tint: DS.N.warnText)
        default:
            SyncRow(icon: "arrow.down.to.line",
                    text: viewModel.syncState.label(mapName: viewModel.mapName),
                    tint: DS.N.inkTertiary)
        }
    }

    // MARK: The one big panel: navigating, arrived, or nothing

    @ViewBuilder
    private var primaryPanel: some View {
        if viewModel.isNavigating, viewModel.isOffRoute {
            OffRoutePanel()
        } else if viewModel.isNavigating, let instruction = viewModel.currentInstruction {
            InstructionPanel(instruction: instruction,
                             remainingDistance: viewModel.remainingDistance,
                             leg: viewModel.routeLeg,
                             legCount: viewModel.routeLegCount)
        } else if viewModel.hasArrived, let place = viewModel.arrivedPlaceName {
            ArrivedPanel(placeName: place)
        }
    }

    // MARK: Bottom-of-stage panel: transcript, or the most useful sentence

    @ViewBuilder
    private var footerPanel: some View {
        if viewModel.isListening {
            TranscriptPanel(transcript: viewModel.recognizer.transcript)
        } else if viewModel.isOffRoute, let known = viewModel.lastKnownDescription {
            HintPanel(icon: "mappin.and.ellipse", text: "Last known: \(known).", style: .neutral)
        } else if isRelocalizing, let summary = viewModel.phoneImmersalSummary {
            HintPanel(icon: "arrow.trianglehead.2.clockwise.rotate.90",
                      text: "Finding your position in \(viewModel.mapName). Point the phone at the room and move slowly.\n\(summary)",
                      style: .warning)
        } else if isRelocalizing {
            HintPanel(icon: "arrow.trianglehead.2.clockwise.rotate.90",
                      text: viewModel.positioningSource == .glasses
                          ? "Look around slowly so the glasses can recognise \(viewModel.mapName)."
                          : "Pan the phone slowly across the room so it can recognise \(viewModel.mapName).",
                      style: .warning)
        } else if let message = viewModel.statusMessage {
            HintPanel(icon: "info.circle", text: message, style: .neutral)
        } else if !viewModel.isNavigating {
            HintPanel(icon: "info.circle",
                      text: "Say a place, or pick one below, then start guidance.",
                      style: .neutral)
        }
    }

    private var isRelocalizing: Bool {
        viewModel.localizationStatus == .relocalizing || viewModel.localizationStatus == .initializing
    }

    // MARK: - Dock

    private var dock: some View {
        @Bindable var guidance = viewModel.guidance
        return VStack(spacing: 12) {
            TalkButton(isListening: viewModel.isListening,
                       transcript: viewModel.recognizer.transcript,
                       hint: talkHint,
                       isCompact: viewModel.isNavigating) {
                viewModel.toggleListening()
            }

            if !viewModel.isNavigating {
                DestinationPicker(destinations: viewModel.destinations,
                                  selection: $viewModel.selectedDestination,
                                  hasArrived: viewModel.hasArrived)
            }

            HStack(spacing: 12) {
                if viewModel.isNavigating {
                    StopGuidanceButton { viewModel.stopNavigation() }
                } else {
                    StartGuidanceButton(blockedReason: startBlockedReason) {
                        viewModel.startNavigation()
                    }
                }

                Menu {
                    Button {
                        showingGlasses = true
                    } label: {
                        Label(viewModel.positioningSource == .glasses ? "Glasses (positioning)" : "Glasses…",
                              systemImage: "eyeglasses")
                    }
                    Divider()
                    Button("Check Server for Map Updates") { Task { await viewModel.checkForMapUpdate() } }
                    Button("Restart Tracking") { viewModel.resetSession(discardSavedMap: false) }
                    Button("Discard Local Map", role: .destructive) {
                        viewModel.resetSession(discardSavedMap: true)
                    }
                    .disabled(!viewModel.arManager.hasSavedWorldMap)
                    Divider()
                    Toggle("Mute Voice", isOn: $guidance.isMuted)
                    Toggle("Debug Overlay", isOn: $viewModel.showDebug)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(DS.N.accent)
                        .frame(width: viewModel.isNavigating ? 78 : 72,
                               height: viewModel.isNavigating ? 78 : 72)
                        .background(DS.N.raised, in: RoundedRectangle(cornerRadius: DS.R.control, style: .continuous))
                        .dsStroke(DS.N.hairline, radius: DS.R.control)
                }
                .accessibilityLabel("More options")
            }
        }
        .padding(16)
        .background(DS.N.dock, in: RoundedRectangle(cornerRadius: DS.R.dock, style: .continuous))
        .dsStroke(DS.N.hairlineSoft, radius: DS.R.dock)
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    /// The example phrases change with the state, so the hint is always the set
    /// of commands that are actually useful right now.
    private var talkHint: String {
        if viewModel.isOffRoute { return "“Where am I?” · “Repeat” · “Stop”" }
        if viewModel.isNavigating { return "“Repeat” · “Where am I?” · “Stop”" }
        if viewModel.hasArrived { return "“What's nearby?” · “Take me to the palms”" }
        if isRelocalizing { return "You can ask now — guidance starts as soon as the map is ready." }
        return "“Take me to the orchids” · “Where am I?” · “What's nearby?”"
    }

    /// Why Start Guidance is unavailable, or `nil` when it is ready. The disabled
    /// button wears this instead of its own name, so a glance explains the block.
    private var startBlockedReason: String? {
        switch viewModel.localizationStatus {
        case .unsupported:   return viewModel.positioningSource == .glasses ? "Map not aligned" : "AR unavailable"
        case .notStarted:    return viewModel.positioningSource == .glasses ? "Glasses not streaming" : "Tracking off"
        case .initializing:  return "Starting camera"
        case .relocalizing:  return "Waiting for map"
        case .limited(let reason):
            if viewModel.positioningSource == .glasses {
                return reason == "Map not aligned" ? "Map not aligned" : "Waiting for a fix"
            }
            return "Hold steady"
        case .trackingReady: return viewModel.selectedDestination == nil ? "Choose a destination" : nil
        }
    }
}

// MARK: - Status

/// Tracking quality. Colour, icon and word all change together.
struct LocalizationStatusBadge: View {
    let status: LocalizationStatus
    let usingSavedMap: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    private enum Kind { case ok, waiting, bad, off }

    private var kind: Kind {
        switch status {
        case .trackingReady:               return .ok
        case .relocalizing, .initializing: return .waiting
        case .limited, .unsupported:       return .bad
        case .notStarted:                  return .off
        }
    }

    private var ink: Color {
        switch kind {
        case .ok:      return DS.N.okText
        case .waiting: return DS.N.warnText
        case .bad:     return DS.N.hearing
        case .off:     return DS.N.inkTertiary
        }
    }

    private var fill: Color {
        switch kind {
        case .ok:      return DS.N.okBg
        case .waiting: return DS.N.warnBg
        case .bad:     return DS.N.stop.opacity(0.22)
        case .off:     return DS.N.raised
        }
    }

    private var stroke: Color {
        switch kind {
        case .ok:      return DS.N.okStroke
        case .waiting: return DS.N.warnStroke
        case .bad:     return DS.N.stopStroke
        case .off:     return DS.N.hairline
        }
    }

    /// "Tracking ready" reads better than the raw `Tracking Ready` label here.
    private var text: String {
        status == .trackingReady ? "Tracking ready" : status.label
    }

    var body: some View {
        HStack(spacing: 10) {
            switch kind {
            case .ok:
                Image(systemName: "checkmark").font(.headline.weight(.bold))
            case .waiting:
                pulsingDot
            case .bad:
                Image(systemName: "exclamationmark.triangle.fill").font(.subheadline.weight(.bold))
            case .off:
                Image(systemName: "pause.circle").font(.subheadline.weight(.bold))
            }

            Text(text).font(.dsHeadline)

            if usingSavedMap, status.isReliable {
                Image(systemName: "map.fill").font(.subheadline)
            }
        }
        .foregroundStyle(ink)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(fill, in: Capsule())
        .overlay(Capsule().strokeBorder(stroke, lineWidth: 1.5))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(usingSavedMap && status.isReliable
                            ? "\(text). Relocalized to saved map."
                            : text)
    }

    private var pulsingDot: some View {
        ZStack {
            if !reduceMotion {
                Circle()
                    .fill(DS.N.warnText)
                    .frame(width: 16, height: 16)
                    .scaleEffect(pulsing ? 1.6 : 1)
                    .opacity(pulsing ? 0 : 0.55)
                    .animation(.easeOut(duration: 1.8).repeatForever(autoreverses: false), value: pulsing)
            }
            Circle().fill(DS.N.warnText).frame(width: 16, height: 16)
        }
        .frame(width: 16, height: 16)
        .onAppear { pulsing = true }
    }
}

/// One-line server sync state.
struct SyncRow: View {
    let icon: String
    let text: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.dsSubhead.weight(.semibold)).foregroundStyle(tint)
            Text(text).font(.dsBody).foregroundStyle(DS.N.inkSecondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(DS.N.panel, in: RoundedRectangle(cornerRadius: DS.R.row, style: .continuous))
        .dsStroke(DS.N.hairline, radius: DS.R.row)
        .accessibilityElement(children: .combine)
    }
}

/// Map download, with the byte counts and the one instruction that helps.
struct DownloadCard: View {
    let version: Int
    let progress: Double
    let bytesText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.to.line")
                    .font(.dsHeadline).foregroundStyle(DS.N.accent)
                Text("Downloading map v\(version)")
                    .font(.dsHeadline).foregroundStyle(DS.N.ink)
                Spacer(minLength: 8)
                Text("\(Int((progress * 100).rounded()))%")
                    .font(.dsHeadline.monospacedDigit()).foregroundStyle(DS.N.accent)
            }

            ProgressView(value: min(max(progress, 0), 1))
                .progressViewStyle(.linear)
                .tint(DS.N.accent)

            Text([bytesText, "keep the phone still while it finishes"]
                .compactMap { $0 }.joined(separator: " · "))
                .font(.dsSubhead).foregroundStyle(DS.N.inkMuted)
        }
        .padding(18)
        .background(DS.N.panel, in: RoundedRectangle(cornerRadius: DS.R.panel, style: .continuous))
        .dsStroke(DS.N.accent.opacity(0.3), 1, radius: DS.R.panel)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - The three route panels

/// Active route. Inverted to off-white so it is the brightest thing on screen.
struct InstructionPanel: View {
    let instruction: NavigationInstruction
    let remainingDistance: Float
    let leg: Int
    let legCount: Int

    private var arrowSymbol: String {
        switch instruction.direction {
        case .straight:    return "arrow.up"
        case .slightLeft:  return "arrow.up.left"
        case .left:        return "arrow.turn.up.left"
        case .sharpLeft:   return "arrow.uturn.left"
        case .slightRight: return "arrow.up.right"
        case .right:       return "arrow.turn.up.right"
        case .sharpRight:  return "arrow.uturn.right"
        case .uTurn:       return "arrow.uturn.down"
        }
    }

    private var verb: String {
        instruction.direction.spokenPhrase.prefix(1).uppercased() + instruction.direction.spokenPhrase.dropFirst()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                Image(systemName: arrowSymbol)
                    .font(.system(size: 46, weight: .bold))
                    .foregroundStyle(DS.A.ink)
                Text(verb)
                    .font(.dsDisplay).foregroundStyle(DS.A.ink)
            }

            Text("\(instruction.isFinal ? "to the" : "toward the") \(instruction.nextNodeName)")
                .font(.dsTitle3.weight(.medium)).foregroundStyle(Color(dsHex: 0x3E3856))

            Divider().overlay(Color(dsHex: 0xE0DAF2))

            HStack(alignment: .top, spacing: 0) {
                metric(instruction.distanceText, "to the turn", tint: DS.A.lavender)
                Rectangle().fill(Color(dsHex: 0xE0DAF2)).frame(width: 2)
                metric("\(Int(remainingDistance.rounded())) m", "total left", tint: DS.A.ink)
                    .padding(.leading, 20)
            }

            if legCount > 1 {
                Divider().overlay(Color(dsHex: 0xE0DAF2))
                HStack(spacing: 12) {
                    HStack(spacing: 6) {
                        ForEach(0..<legCount, id: \.self) { index in
                            Circle()
                                .fill(index < leg ? DS.A.lavender : Color(dsHex: 0xD6CEEC))
                                .frame(width: 9, height: 9)
                        }
                    }
                    .accessibilityHidden(true)
                    Text("Leg \(leg) of \(legCount) · next cue in \(instruction.distanceText)")
                        .font(.dsSubhead).foregroundStyle(DS.A.inkTertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(DS.A.canvas, in: RoundedRectangle(cornerRadius: DS.R.card, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(verb) \(instruction.isFinal ? "to the" : "toward the") \(instruction.nextNodeName). \(instruction.distanceText) to the turn, \(Int(remainingDistance.rounded())) metres total left.")
    }

    private func metric(_ value: String, _ caption: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.dsDisplay).foregroundStyle(tint)
            Text(caption).dsEyebrow(DS.A.inkTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The one green screen in the app.
struct ArrivedPanel: View {
    let placeName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                Image(systemName: "checkmark")
                    .font(.system(size: 30, weight: .heavy))
                    .foregroundStyle(Color(dsHex: 0x062015))
                    .frame(width: 60, height: 60)
                    .background(DS.N.okSolid, in: Circle())
                Text("You have arrived")
                    .font(.dsDisplay).foregroundStyle(DS.N.ink)
            }

            Text("\(placeName) is directly in front of you.")
                .font(.dsTitle2.weight(.medium)).foregroundStyle(DS.N.okBody)

            Divider().overlay(DS.N.okSolid.opacity(0.4))

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.dsSubhead).foregroundStyle(DS.N.okText)
                Text("Speaking the exhibit description now — say “stop” to interrupt, “repeat” to hear it again.")
                    .font(.dsCallout).foregroundStyle(DS.N.okHint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 22)
        .background(DS.N.okBg, in: RoundedRectangle(cornerRadius: DS.R.card, style: .continuous))
        .dsStroke(DS.N.okSolid, 2, radius: DS.R.card)
        .accessibilityElement(children: .combine)
    }
}

/// Off route. The headline is an action, not a status.
struct OffRoutePanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 18) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 52, weight: .bold))
                    .foregroundStyle(DS.N.offRouteInk)
                Text("Off route — recalculating")
                    .font(.dsDisplay).foregroundStyle(DS.N.offRouteInk)
            }

            Text("Stop where you are. New directions in a moment.")
                .font(.dsTitle2.weight(.medium)).foregroundStyle(DS.N.offRouteBody)

            Divider().overlay(DS.N.offRouteInk.opacity(0.28))

            HStack(spacing: 12) {
                HStack(spacing: 5) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(DS.N.offRouteInk)
                            .frame(width: 9, height: 16)
                    }
                }
                .accessibilityHidden(true)
                Text("Three low rumbles = off route")
                    .font(.dsBody.weight(.semibold)).foregroundStyle(DS.N.offRouteInk)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background(DS.N.offRoute, in: RoundedRectangle(cornerRadius: DS.R.card, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Off route, recalculating. Stop where you are. New directions in a moment.")
    }
}

// MARK: - Footer panels

struct HintPanel: View {
    enum Style { case neutral, warning }

    let icon: String
    let text: String
    var style: Style = .neutral

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.dsBody.weight(.semibold))
                .foregroundStyle(style == .warning ? DS.N.warnText : DS.N.accent)
            Text(text)
                .font(.dsBody)
                .foregroundStyle(style == .warning ? DS.N.warnBody : DS.N.inkSecondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(style == .warning ? DS.N.warnBg.opacity(0.92) : DS.N.panel,
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .dsStroke(style == .warning ? DS.N.warnStroke : DS.N.hairline, radius: 20)
        .accessibilityElement(children: .combine)
    }
}

/// What the app is hearing, right above the thumb.
struct TranscriptPanel: View {
    let transcript: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Hearing you").dsEyebrow(DS.N.hearing)
            Text(transcript.isEmpty ? "…" : "“\(transcript)”")
                .font(.dsTitle.weight(.medium))
                .foregroundStyle(DS.N.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(DS.N.panel, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .dsStroke(DS.N.hairline, radius: 24)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Hearing you: \(transcript)")
    }
}

// MARK: - Dock controls

/// The largest control on the screen, by a wide margin.
struct TalkButton: View {
    let isListening: Bool
    let transcript: String
    let hint: String
    var isCompact: Bool = false
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Group {
                if isListening { listening } else { idle }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: isCompact ? 150 : 180)
            .padding(.vertical, isCompact ? 22 : 26)
            .padding(.horizontal, 24)
            .background(isListening ? DS.N.stop : DS.N.talk,
                        in: RoundedRectangle(cornerRadius: DS.R.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.R.card, style: .continuous)
                .strokeBorder(isListening ? DS.N.stopStroke : DS.N.talkStroke, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isListening ? "Listening. Tap to send." : "Talk. Tap and say a command.")
        .accessibilityValue(isListening ? transcript : "")
        .accessibilityHint(isListening ? "" : hint)
        .accessibilityAddTraits(.startsMediaSession)
    }

    private var idle: some View {
        HStack(spacing: 20) {
            Image(systemName: "mic.fill")
                .font(.system(size: isCompact ? 34 : 38, weight: .bold))
                .foregroundStyle(DS.A.lavender)
                .frame(width: isCompact ? 74 : 82, height: isCompact ? 74 : 82)
                .background(DS.N.ink, in: Circle())

            VStack(alignment: .leading, spacing: 8) {
                Text("Tap to talk")
                    .font(isCompact ? .dsTitle : .dsDisplay)
                    .foregroundStyle(.white)
                Text(hint)
                    .font(.dsCallout)
                    .foregroundStyle(Color(dsHex: 0xEDE7FF))
            }
            Spacer(minLength: 0)
        }
    }

    private var listening: some View {
        VStack(spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 30, weight: .bold))
                Text("Listening…").font(.dsDisplay)
            }
            .foregroundStyle(.white)

            Waveform(animated: !reduceMotion)

            // The recogniser stops on silence and the button toggles, so this is
            // "tap again", not the canvas's "release to send".
            Text(transcript.isEmpty
                 ? "Tap again to send · one firm tap confirmed"
                 : "Tap again to send")
                .font(.dsCallout)
                .foregroundStyle(DS.N.stopBody)
        }
    }
}

/// Seven bars, or seven static bars when Reduce Motion is on.
struct Waveform: View {
    let animated: Bool
    @State private var phase = false

    private let scales: [CGFloat] = [0.4, 0.8, 1.0, 0.6, 0.9, 0.35, 0.7]

    var body: some View {
        HStack(spacing: 7) {
            ForEach(Array(scales.enumerated()), id: \.offset) { index, scale in
                Capsule()
                    .fill(.white)
                    .frame(width: 8, height: 54)
                    .scaleEffect(y: animated ? (phase ? 1 : 0.28) : scale, anchor: .center)
                    .animation(animated
                               ? .easeInOut(duration: 0.45).repeatForever().delay(Double(index) * 0.12)
                               : nil,
                               value: phase)
            }
        }
        .frame(height: 54)
        .onAppear { if animated { phase = true } }
        .accessibilityHidden(true)
    }
}

/// Menu-based picker: works well with VoiceOver and with accessibility text sizes.
struct DestinationPicker: View {
    let destinations: [NavigationPOI]
    @Binding var selection: NavigationPOI?
    var hasArrived: Bool = false

    private var placeholder: String {
        hasArrived ? "Choose next destination" : "Choose destination"
    }

    var body: some View {
        Menu {
            ForEach(destinations) { poi in
                Button(poi.name) { selection = poi }
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "leaf.fill")
                    .font(.dsTitle3).foregroundStyle(DS.N.okText)
                Text(selection?.name ?? placeholder)
                    .font(.dsTitle3.weight(selection == nil ? .medium : .semibold))
                    .foregroundStyle(DS.N.ink)
                    .lineLimit(2)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.dsSubhead.weight(.semibold)).foregroundStyle(DS.N.inkTertiary)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: 72)
            .background(DS.N.raised, in: RoundedRectangle(cornerRadius: DS.R.control, style: .continuous))
            .dsStroke(DS.N.hairline, radius: DS.R.control)
        }
        .accessibilityLabel("Destination")
        .accessibilityValue(selection?.name ?? "none selected")
    }
}

/// Start is green-for-go and mirrors Stop exactly; when it cannot be used it
/// wears the reason instead of its own name.
struct StartGuidanceButton: View {
    let blockedReason: String?
    let action: () -> Void

    private var isEnabled: Bool { blockedReason == nil }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "figure.walk")
                    .font(.dsTitle3.weight(.bold))
                Text(blockedReason ?? "Start guidance")
                    .font(.dsTitle3.weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isEnabled ? .white : DS.N.inkDisabled)
            .frame(maxWidth: .infinity, minHeight: 72)
            .padding(.horizontal, 12)
            .background(isEnabled ? DS.N.okSolid : DS.N.sunk,
                        in: RoundedRectangle(cornerRadius: DS.R.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.R.control, style: .continuous)
                .strokeBorder(isEnabled ? DS.N.okText : DS.N.hairlineSoft, lineWidth: isEnabled ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel("Start guidance")
        .accessibilityHint(blockedReason.map { "Unavailable: \($0)" } ?? "")
    }
}

struct StopGuidanceButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "stop.fill").font(.dsTitle3.weight(.bold))
                Text("Stop guidance").font(.dsTitle2)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 78)
            .padding(.horizontal, 12)
            .background(DS.N.stop, in: RoundedRectangle(cornerRadius: DS.R.control, style: .continuous))
            .dsStroke(DS.N.stopStroke, 1.5, radius: DS.R.control)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Stop guidance")
    }
}

// MARK: - Debug

/// Instrument data, boxed and monospaced so it never reads as interface.
struct DebugOverlay: View {
    let info: DebugInfo
    let status: LocalizationStatus
    let hasSavedMap: Bool
    let lastSpoken: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("fps \(info.fps, specifier: "%.0f")  \(info.trackingState)  features \(info.featurePoints)  \(info.worldMapping)")
            Text("x \(info.position.x, specifier: "%.2f")  z \(info.position.y, specifier: "%.2f")  heading \(info.headingDegrees, specifier: "%.0f")°  saved \(hasSavedMap ? "yes" : "no")")
            Text("sub-goal \(info.subGoal)  anchored \(info.anchoredNodes)")
            if !info.routeNodes.isEmpty {
                Text("route " + info.routeNodes.joined(separator: " → "))
            }
            if !lastSpoken.isEmpty {
                Text("said: \(lastSpoken)")
            }
        }
        .font(.dsMonoTiny)
        .foregroundStyle(Color(dsHex: 0x9EE8C4))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(DS.N.canvas.opacity(0.82), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .dsStroke(DS.N.hairline, radius: 16)
        .accessibilityHidden(true)
    }
}

#Preview {
    ContentView(viewModel: NavigationViewModel())
}

// MARK: - Glasses stage

/// The glasses' live view in place of the phone camera, so a helper glancing at
/// the phone sees what the visitor's glasses see. Blank until the stream is up.
struct GlassesStage: View {
    let image: UIImage?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                DS.N.canvas
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "eyeglasses").font(.largeTitle)
                        Text("Waiting for the glasses camera").font(.dsHeadline)
                    }
                    .foregroundStyle(DS.N.inkTertiary)
                }
            }
        }
        .accessibilityHidden(true)
    }
}
