import SwiftUI

/// New map / edit map, artboards E–G (and 08–11) of the Claude Design canvas:
/// 1 Name, 2 Walk & mark, 3 Publish, each with one question and one primary
/// action, under the shared header (logo top-left goes back to Home).
///
/// Light, dense and calm — a pro tool. It is used standing up in daylight with a
/// sighted eye on it the whole time, which is why it is the opposite surface to
/// Navigate. Telemetry sits behind ··· so it never competes with the steps.
struct AuthoringView: View {
    @State private var viewModel: MapAuthoringViewModel
    @State private var showMarkSheet = false
    @State private var editingNode: NavigationPOI?
    @State private var connectingFrom: NavigationPOI?
    @State private var showGuide = false
    @State private var showProbe = false
    @State private var showScanDetails = false
    @State private var confirmLeave = false
    @State private var enteredFlow = false
    /// Set when starting a new scan would discard the scan on this phone.
    @State private var pendingNewScanName: String?
    @State private var newMapName = ""
    @State private var publishNote = ""
    /// Remembered so the error card can offer the right retry.
    @State private var lastAction: LastAction?
    let entry: AuthoringEntry
    /// Back to the staff Home screen.
    let onHome: () -> Void
    /// Switches the app to Navigate on the map just published.
    let onTestNow: () -> Void

    private enum LastAction: Equatable {
        case save
        case upload(note: String?)
        case publishSaved(note: String?)
        var retryLabel: String {
            switch self {
            case .save:         return "Try save again"
            case .upload:       return "Try publish again"
            case .publishSaved: return "Try publish again"
            }
        }
    }

    init(arManager: ARNavigationManager, mapStore: MapStore, entry: AuthoringEntry = .newMap,
         onHome: @escaping () -> Void = {}, onTestNow: @escaping () -> Void = {}) {
        _viewModel = State(initialValue: MapAuthoringViewModel(arManager: arManager, mapStore: mapStore))
        self.entry = entry
        self.onHome = onHome
        self.onTestNow = onTestNow
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Stepper(stage: viewModel.stage)
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            switch viewModel.stage {
            case .start:   startStage
            case .walk:    walkStage
            case .publish: publishStage
            case .done:    doneStage
            }
        }
        .background(DS.A.canvas)
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .overlay { errorCard }
        .onAppear {
            guard !enteredFlow else { return }
            enteredFlow = true
            if entry == .continueScan, viewModel.mapStore.hasSavedMap {
                viewModel.resumeExistingScan()
            } else if !viewModel.guideSeen {
                showGuide = true
            }
        }
        .sheet(isPresented: $showGuide, onDismiss: { viewModel.guideSeen = true }) {
            AuthorGuideSheet()
        }
        .fullScreenCover(isPresented: $showProbe) {
            ProbeView(arManager: viewModel.arManager,
                      mapStore: viewModel.mapStore,
                      places: viewModel.nodes)
        }
        .alert("Replace the scan on this phone?", isPresented: .constant(pendingNewScanName != nil),
               presenting: pendingNewScanName) { name in
            Button("Start new scan", role: .destructive) {
                pendingNewScanName = nil
                viewModel.startNewScan(named: name)
            }
            Button("Cancel", role: .cancel) { pendingNewScanName = nil }
        } message: { _ in
            Text("This deletes the local world map and marked places. Versions already on the server are kept.")
        }
        .alert("Leave without saving?", isPresented: $confirmLeave) {
            Button("Save draft and leave") {
                Task { await keepAsDraft() }
            }
            Button("Leave without saving", role: .destructive, action: onHome)
            Button("Keep mapping", role: .cancel) {}
        } message: {
            Text("Places marked since the last save are only in memory. Saving captures the scan so you can continue later.")
        }
        .sheet(isPresented: $showMarkSheet) {
            NodeForm(title: "Mark this spot",
                     position: NavigationGeometry.planarPosition(of: viewModel.arManager.cameraTransform)) { name, category, details in
                viewModel.markHere(name: name, category: category, details: details)
            }
        }
        .sheet(item: $editingNode) { node in
            NodeForm(title: "Edit place", node: node, position: SIMD2(node.x, node.z)) { name, category, details in
                viewModel.update(node.id, name: name, category: category, details: details)
            }
        }
        .confirmationDialog("Connect \(connectingFrom?.name ?? "") to…",
                            isPresented: Binding(get: { connectingFrom != nil },
                                                 set: { if !$0 { connectingFrom = nil } }),
                            titleVisibility: .visible) {
            if let from = connectingFrom {
                ForEach(viewModel.nodes.filter { $0.id != from.id }) { other in
                    Button(other.name) { viewModel.connect(from.id, to: other.id) }
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        AppHeader(surface: .light, logo: AppLogo(isStaff: true, onHome: leave)) {
            switch viewModel.stage {
            case .start:
                HeaderTitle(surface: .light, title: "New map")
            case .walk:
                HeaderTitle(surface: .light, title: viewModel.mapName,
                            subtitle: viewModel.hasUnsavedChanges ? "\(viewModel.nodes.count) places · not saved yet" : "Draft saved on this phone",
                            subtitleIcon: viewModel.hasUnsavedChanges ? "circle.dashed" : "checkmark",
                            subtitleTint: viewModel.hasUnsavedChanges ? DS.A.warnText : DS.A.okText)
            case .publish:
                HeaderTitle(surface: .light, title: viewModel.mapName,
                            subtitle: "Draft · \(viewModel.nodes.count) places")
            case .done:
                HeaderTitle(surface: .light, title: viewModel.mapName,
                            subtitle: "Published v\(viewModel.publishedVersion ?? viewModel.localVersion?.version ?? 0)",
                            subtitleIcon: "checkmark", subtitleTint: DS.A.okText)
            }
        } trailing: {
            switch viewModel.stage {
            case .start:
                textButton("Cancel", action: onHome)
            case .walk:
                walkMenu
            case .publish:
                Button { viewModel.backToWalking() } label: {
                    HStack(spacing: 4) { Image(systemName: "chevron.left"); Text("Back") }
                        .font(.dsHeadline).foregroundStyle(DS.A.lavender)
                        .frame(minHeight: 44)
                }
                .disabled(viewModel.isBusy)
            case .done:
                textButton("Home", action: onHome)
            }
        }
    }

    private func textButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.dsHeadline).foregroundStyle(DS.A.lavender)
            .frame(minHeight: 44)
            .disabled(viewModel.isBusy)
    }

    /// Everything the walk does not need on screen: telemetry, scan options, help.
    private var walkMenu: some View {
        Menu {
            Toggle("Show Scan Details", isOn: $showScanDetails)
            Toggle("Also Capture Immersal Map", isOn: Binding(get: { viewModel.immersalScanEnabled },
                                                             set: { viewModel.immersalScanEnabled = $0 }))
            Divider()
            Button("Continue Existing Scan (relocalize)") { viewModel.resumeExistingScan() }
                .disabled(!viewModel.mapStore.hasSavedWorldMap)
            if viewModel.mapStore.hasSavedWorldMap, !viewModel.nodes.isEmpty, !viewModel.hasUnsavedChanges {
                Button("Publish Saved Scan As Is") {
                    lastAction = .publishSaved(note: nil)
                    Task { await viewModel.publishSaved(note: nil) }
                }
            }
            Button("Save Draft Now") { Task { await keepAsDraft(thenLeave: false) } }
                .disabled(viewModel.nodes.isEmpty)
            Button("How Authoring Works") { showGuide = true }
            Divider()
            Button("Start Fresh Scan", role: .destructive) { pendingNewScanName = viewModel.mapName }
        } label: {
            Image(systemName: "ellipsis")
                .font(.dsHeadline.weight(.bold))
                .foregroundStyle(DS.A.ink)
                .frame(width: AppLogo.size, height: AppLogo.size)
                .background(DS.A.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .dsStroke(DS.A.hairline, 1.5, radius: 14)
        }
        .disabled(viewModel.isBusy)
        .accessibilityLabel("Scan options")
    }

    /// Logo tap: Home, but never silently dropping marks that exist only in memory.
    private func leave() {
        if viewModel.hasUnsavedChanges, !viewModel.isBusy { confirmLeave = true } else { onHome() }
    }

    private func keepAsDraft(thenLeave: Bool = true) async {
        lastAction = .save
        let saved = await viewModel.saveLocally()
        if saved != nil, thenLeave { onHome() }
    }

    // MARK: - Stage 1: name

    private var startStage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("What area are you mapping?").font(.dsTitle).foregroundStyle(DS.A.ink)
                    Text("Visitors will see this name in the map chip.")
                        .font(.dsCallout).foregroundStyle(DS.A.inkTertiary)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Map name").dsEyebrow(DS.A.inkTertiary)
                    TextField("e.g. Cloud Forest", text: $newMapName)
                        .font(.dsTitle3.weight(.regular))
                        .padding(.horizontal, 16)
                        .frame(minHeight: 60)
                        .background(DS.A.card, in: RoundedRectangle(cornerRadius: DS.R.field, style: .continuous))
                        .dsStroke(DS.A.lavender, 2, radius: DS.R.field)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .onSubmit(startScanning)
                        .accessibilityLabel("Map name")
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("Before you start").font(.dsHeadline).foregroundStyle(DS.A.ink)
                    ForEach(Array(Self.beforeYouStart.enumerated()), id: \.offset) { i, rule in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("\(i + 1)").font(.dsSubhead.weight(.bold)).foregroundStyle(DS.A.lavender)
                            Text(rule).font(.dsSubhead).foregroundStyle(DS.A.inkSecondary)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DS.A.card, in: RoundedRectangle(cornerRadius: DS.R.row, style: .continuous))
                .dsStroke(DS.A.hairline, 1.5, radius: DS.R.row)

                if viewModel.showsProgress {
                    PublishProgressCard(stage: viewModel.progressStage, step: viewModel.progressStep,
                                        fraction: viewModel.progressFraction, bytesText: viewModel.progressBytesText,
                                        version: viewModel.progressVersion, showsChecklist: viewModel.isUploading)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    private static let beforeYouStart: [AttributedString] = [
        "Stand at the entrance visitors use.",
        "Walk the visitor route slowly, phone upright.",
        (try? AttributedString(markdown: "Tap **Mark here** at every place visitors should be able to reach."))
            ?? "Tap Mark here at every place visitors should be able to reach.",
    ]

    private var trimmedNewName: String { newMapName.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func startScanning() {
        let name = trimmedNewName
        guard !name.isEmpty else { return }
        if viewModel.mapStore.hasSavedWorldMap || !viewModel.nodes.isEmpty {
            pendingNewScanName = name
        } else {
            viewModel.startNewScan(named: name)
        }
    }

    // MARK: - Stage 2: walk and mark

    private var walkStage: some View {
        VStack(spacing: 0) {
            ScanPreview(viewModel: viewModel,
                        isCompact: !viewModel.nodes.isEmpty,
                        showDetails: showScanDetails)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            placesList
        }
    }

    private var placesList: some View {
        List {
            if viewModel.showsProgress {
                PublishProgressCard(stage: viewModel.progressStage, step: viewModel.progressStep,
                                    fraction: viewModel.progressFraction, bytesText: viewModel.progressBytesText,
                                    version: viewModel.progressVersion, showsChecklist: viewModel.isUploading)
                    .plainRow()
            }
            if let warning = viewModel.mappingWarning, viewModel.nodes.isEmpty {
                NoticeBanner(icon: "exclamationmark.triangle.fill", text: warning, style: .warning).plainRow()
            }
            if viewModel.nodes.isEmpty {
                NoticeBanner(icon: "figure.walk", text: "Walk slowly, sweep the camera across walls and fixtures, and tap Mark here at each place a visitor would stop.", style: .success)
                    .plainRow()
            } else {
                Section {
                    ForEach(viewModel.nodes) { node in
                        NodeRow(node: node,
                                neighbours: viewModel.neighbours(of: node.id),
                                isChainOrigin: node.id == viewModel.chainFromID)
                            .contentShape(Rectangle())
                            .onTapGesture { editingNode = node }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { viewModel.remove(node.id) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button { connectingFrom = node } label: {
                                    Label("Connect", systemImage: "link")
                                }
                                .tint(DS.A.lavender)
                                Button { viewModel.continueChain(from: node.id) } label: {
                                    Label("Chain from", systemImage: "arrow.turn.down.right")
                                }
                                .tint(DS.A.warnStroke)
                            }
                            .plainRow()
                    }
                } header: {
                    HStack {
                        Text("Marked (\(viewModel.nodes.count))").dsEyebrow(DS.A.inkTertiary)
                        Spacer()
                        Text("swipe row for actions").font(.dsMonoTiny).foregroundStyle(DS.A.inkMuted)
                    }
                    .padding(.horizontal, 2)
                    .padding(.bottom, 6)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            if let message = viewModel.statusMessage {
                Text(message).font(.dsFootnote).foregroundStyle(DS.A.inkTertiary).plainRow()
            }
        }
        .listStyle(.plain)
        .listRowSpacing(8)
        .scrollContentBackground(.hidden)
        .background(DS.A.canvas)
        .environment(\.defaultMinListHeaderHeight, 0)
    }

    // MARK: - Bottom bar: one primary action per step

    @ViewBuilder
    private var bottomBar: some View {
        switch viewModel.stage {
        case .start:
            barContainer {
                PrimaryButton(title: "Start scanning", icon: "chevron.right", iconTrailing: true,
                              enabled: !trimmedNewName.isEmpty, action: startScanning)
            }
        case .walk:
            barContainer { walkActions }
        case .publish:
            barContainer {
                VStack(spacing: 6) {
                    PrimaryButton(title: viewModel.isBusy ? "Publishing…" : "Publish map", icon: "square.and.arrow.up",
                                  enabled: viewModel.canUpload && !viewModel.isBusy) {
                        let trimmed = publishNote.trimmingCharacters(in: .whitespacesAndNewlines)
                        let note = trimmed.isEmpty ? nil : trimmed
                        lastAction = .upload(note: note)
                        Task { await viewModel.publish(note: note) }
                    }
                    Button("Keep as draft") { Task { await keepAsDraft() } }
                        .font(.dsHeadline).foregroundStyle(DS.A.lavender)
                        .frame(minHeight: 44)
                        .disabled(viewModel.isBusy)
                }
            }
        case .done:
            EmptyView()
        }
    }

    private func barContainer<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 12)
            .background(DS.A.card)
            .overlay(alignment: .top) { Rectangle().fill(DS.A.hairline).frame(height: 1) }
    }

    private var walkActions: some View {
        HStack(spacing: 10) {
            Button {
                showMarkSheet = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "mappin.and.ellipse").font(.dsTitle3.weight(.semibold))
                    Text("Mark here").font(.dsTitle3.weight(.semibold))
                }
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .foregroundStyle(canMark ? .white : DS.A.inkDisabled)
                .frame(maxWidth: .infinity)
                .frame(height: Self.actionBarHeight)
                .background(canMark ? DS.A.lavender : DS.A.lavenderBg,
                            in: RoundedRectangle(cornerRadius: DS.R.row, style: .continuous))
                .dsStroke(canMark ? .clear : DS.A.hairlineLav, 1.5, radius: DS.R.row)
            }
            .buttonStyle(.plain)
            .disabled(!canMark)

            // Finished walking: on to the publish checklist.
            Button {
                viewModel.finishWalking()
            } label: {
                HStack(spacing: 6) {
                    Text("Done").font(.dsHeadline)
                    Image(systemName: "chevron.right").font(.dsHeadline)
                }
                .foregroundStyle(doneEnabled ? .white : DS.A.inkDisabled)
                .padding(.horizontal, 22)
                .frame(height: Self.actionBarHeight)
                .background(doneEnabled ? DS.A.ink : DS.A.inset, in: RoundedRectangle(cornerRadius: DS.R.row, style: .continuous))
            }
            .buttonStyle(.plain)
            .fixedSize()
            .disabled(!doneEnabled)
            .accessibilityLabel("Finished walking")
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var doneEnabled: Bool { !viewModel.nodes.isEmpty && !viewModel.isBusy }

    // MARK: - Stage 3: publish

    private var publishStage: some View {
        let exhibits = viewModel.nodes.filter { $0.category == .exhibit }
        let hazards = viewModel.nodes.filter { $0.category == .hazard }
        let undescribed = exhibits.filter { ($0.details ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
        let nextVersion = (viewModel.localVersion?.version ?? 0) + 1
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Ready to publish?").font(.dsTitle).foregroundStyle(DS.A.ink)

                HStack(spacing: 10) {
                    statTile(viewModel.nodes.count, viewModel.nodes.count == 1 ? "place" : "places")
                    statTile(exhibits.count, exhibits.count == 1 ? "exhibit" : "exhibits")
                    statTile(hazards.count, hazards.count == 1 ? "hazard" : "hazards")
                }

                VStack(spacing: 0) {
                    checkRow(ok: viewModel.coverageFraction >= 0.6,
                             text: viewModel.coverageFraction >= 0.6 ? "Scan quality is good"
                                   : "Scan coverage \(Int(viewModel.coverageFraction * 100))% · walk a little more for a reliable map",
                             fix: viewModel.coverageFraction >= 0.6 ? nil : ("Walk", { viewModel.backToWalking() }))
                    Divider().overlay(DS.A.hairline)
                    checkRow(ok: undescribed.isEmpty,
                             text: exhibits.isEmpty ? "No exhibits to describe"
                                   : undescribed.isEmpty ? "Every exhibit has a description"
                                   : "No description: \(undescribed.map(\.name).joined(separator: ", "))",
                             fix: undescribed.first.map { first in ("Fix", { editingNode = first }) })
                    ForEach(viewModel.unconnectedPlaces) { place in
                        Divider().overlay(DS.A.hairline)
                        checkRow(ok: false, text: "“\(place.name)” isn’t connected to the route",
                                 fix: ("Fix", { viewModel.connectUnconnected() }))
                    }
                    if viewModel.scanner.captured > 0 {
                        Divider().overlay(DS.A.hairline)
                        let photosOK = viewModel.scanner.queued == 0 && viewModel.scanner.failed == 0
                        checkRow(ok: photosOK,
                                 text: "Immersal photos: \(viewModel.scanner.uploaded) of \(viewModel.scanner.captured) uploaded\(viewModel.scanner.queued > 0 ? " · \(viewModel.scanner.queued) still sending" : "")\(viewModel.scanner.failed > 0 ? " · \(viewModel.scanner.failed) failed" : "")",
                                 fix: nil)
                    }
                }
                .background(DS.A.card, in: RoundedRectangle(cornerRadius: DS.R.row, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: DS.R.row, style: .continuous))
                .dsStroke(DS.A.hairline, 1.5, radius: DS.R.row)

                TextField("What changed? (optional)", text: $publishNote)
                    .font(.dsBody)
                    .padding(14)
                    .background(DS.A.card, in: RoundedRectangle(cornerRadius: DS.R.field, style: .continuous))
                    .dsStroke(DS.A.hairline, 1.5, radius: DS.R.field)

                Text("Publishing uploads the world map and makes it v\(nextVersion) on the server. Visitors can choose it from the map chip straight away. Stay on this screen until it says published.")
                    .font(.dsSubhead).foregroundStyle(DS.A.inkTertiary)

                if viewModel.showsProgress {
                    PublishProgressCard(stage: viewModel.progressStage, step: viewModel.progressStep,
                                        fraction: viewModel.progressFraction, bytesText: viewModel.progressBytesText,
                                        version: viewModel.progressVersion, showsChecklist: viewModel.isUploading)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    private func statTile(_ value: Int, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)").font(.dsTitle).foregroundStyle(DS.A.ink)
            Text(caption).font(.dsFootnote).foregroundStyle(DS.A.inkTertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.A.card, in: RoundedRectangle(cornerRadius: DS.R.field, style: .continuous))
        .dsStroke(DS.A.hairline, 1.5, radius: DS.R.field)
        .accessibilityElement(children: .combine)
    }

    private func checkRow(ok: Bool, text: String, fix: (String, () -> Void)?) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: ok ? "checkmark" : "exclamationmark.triangle")
                .font(.dsHeadline)
                .foregroundStyle(ok ? DS.A.okText : DS.A.warnIcon)
                .frame(width: 22)
            Text(text).font(.dsCallout).foregroundStyle(ok ? DS.A.ink : DS.A.warnText)
            Spacer(minLength: 4)
            if let fix {
                Button(fix.0, action: fix.1)
                    .font(.dsHeadline).foregroundStyle(DS.A.lavender)
                    .frame(minHeight: 44)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ok ? Color.clear : DS.A.warnBg)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Stage 4: done

    private var doneStage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Published", systemImage: "checkmark.seal.fill").font(.dsTitle2).foregroundStyle(DS.A.okText)
                    Text("\(viewModel.mapName), version \(viewModel.publishedVersion ?? viewModel.localVersion?.version ?? 0), with \(viewModel.nodes.count) places.")
                        .font(.dsBody).foregroundStyle(DS.A.ink)
                    if let id = viewModel.immersalMapID {
                        ChecklistRow(ok: viewModel.immersalMapStatus == "ready",
                                     pending: viewModel.immersalMapStatus != "ready" && viewModel.immersalMapStatus != "failed",
                                     text: "Immersal map \(id): \(viewModel.immersalMapStatus ?? "building…")")
                        if viewModel.immersalMapStatus != "ready" && viewModel.immersalMapStatus != "failed" {
                            Text("Usually a few minutes. The phone can leave this screen; the glasses and the accuracy walk need this map to be ready.")
                                .font(.dsMonoTiny).foregroundStyle(DS.A.inkMuted)
                        }
                    }
                    PrimaryButton(title: "Test it now", icon: "location.fill", enabled: true, action: onTestNow)
                    SecondaryRow(icon: "ruler", title: "Measure accuracy", detail: "Immersal vs ARKit walk on this map") { showProbe = true }
                    SecondaryRow(icon: "house", title: "Back to Home", detail: "every map, and new ones", action: onHome)
                }
                .padding(20)
                .background(DS.A.card, in: RoundedRectangle(cornerRadius: DS.R.card, style: .continuous))
                .dsStroke(DS.A.hairline, 1.5, radius: DS.R.card)
                if let message = viewModel.statusMessage {
                    NoticeBanner(icon: "checkmark", text: message, style: .success)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    private static let actionBarHeight: CGFloat = 60
    private var canMark: Bool { viewModel.canMark && !viewModel.isBusy }

    // MARK: - Error

    @ViewBuilder
    private var errorCard: some View {
        if let message = viewModel.errorMessage {
            ErrorCard(message: message,
                      retryLabel: lastAction?.retryLabel,
                      onRetry: retryLastAction,
                      onDismiss: { viewModel.errorMessage = nil })
        }
    }

    private func retryLastAction() {
        let action = lastAction
        viewModel.errorMessage = nil
        switch action {
        case .save:               Task { await viewModel.saveLocally() }
        case .upload(let note):   Task { await viewModel.publish(note: note) }
        case .publishSaved(let note): Task { await viewModel.publishSaved(note: note) }
        case nil:                 break
        }
    }
}

// MARK: - Guided-flow pieces

/// Three equal columns with full labels, so "Walk & mark" is never cut off:
/// a bar over each, filled up to the current step.
private struct Stepper: View {
    let stage: MapAuthoringViewModel.Stage

    private var index: Int {
        switch stage { case .start: return 0; case .walk: return 1; case .publish, .done: return 2 }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(Array(["Name", "Walk & mark", "Publish"].enumerated()), id: \.offset) { i, title in
                VStack(alignment: .leading, spacing: 8) {
                    Capsule()
                        .fill(i <= index ? DS.A.lavender : DS.A.lavenderTrack)
                        .frame(height: 5)
                    Text("\(i + 1) \(title)")
                        .font(.dsSubhead.weight(i == index ? .semibold : .regular))
                        .foregroundStyle(i == index ? DS.A.ink : DS.A.inkTertiary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(index + 1) of 3, \(["Name", "Walk and mark", "Publish"][index])")
    }
}

private struct PrimaryButton: View {
    let title: String
    let icon: String
    var iconTrailing = false
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if !iconTrailing { Image(systemName: icon).font(.dsTitle3.weight(.semibold)) }
                Text(title).font(.dsTitle3.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.75)
                if iconTrailing { Image(systemName: icon).font(.dsHeadline.weight(.semibold)) }
            }
            .foregroundStyle(enabled ? .white : DS.A.inkDisabled)
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(enabled ? DS.A.lavender : DS.A.lavenderBg, in: RoundedRectangle(cornerRadius: DS.R.row, style: .continuous))
            .dsStroke(enabled ? .clear : DS.A.hairlineLav, 1.5, radius: DS.R.row)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

private struct SecondaryRow: View {
    let icon: String
    let title: String
    let detail: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.dsHeadline).foregroundStyle(DS.A.lavender).frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.dsHeadline).foregroundStyle(DS.A.ink)
                    Text(detail).font(.dsSubhead).foregroundStyle(DS.A.inkTertiary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.dsSubhead).foregroundStyle(DS.A.inkTertiary)
            }
            .padding(14)
            .background(DS.A.card, in: RoundedRectangle(cornerRadius: DS.R.field, style: .continuous))
            .dsStroke(DS.A.hairline, 1.5, radius: DS.R.field)
        }
        .buttonStyle(.plain)
    }
}

private struct ChecklistRow: View {
    let ok: Bool
    var pending = false
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if pending {
                ProgressView().tint(DS.A.lavender).frame(width: 22)
            } else {
                Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.dsHeadline).foregroundStyle(ok ? DS.A.okText : DS.A.warnIcon).frame(width: 22)
            }
            Text(text).font(.dsSubhead).foregroundStyle(DS.A.ink)
            Spacer(minLength: 0)
        }
    }
}

/// The four rules, once, for a first-time mapper.
struct AuthorGuideSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let rules: [(String, String, String)] = [
        ("figure.walk", "Walk slowly", "About one step a second. Fast moves blur the camera and the map gets holes."),
        ("camera.viewfinder", "Point at walls and furniture", "The camera needs texture: displays, shelves, signs. Floors and blank walls give it nothing."),
        ("mappin.and.ellipse", "Mark where a visitor would stand", "Tap Mark here at each stop, facing the thing. Name it the way a visitor would ask for it."),
        ("icloud.and.arrow.up", "Publish before you leave", "Tap Done, then Publish, and stay until it says published. Needs mobile data, about 150 MB."),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("One walk makes the whole map: the space, the places, and the paths between them.")
                        .font(.dsBody).foregroundStyle(DS.A.inkSecondary)
                    ForEach(Array(rules.enumerated()), id: \.offset) { i, rule in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: rule.0).font(.dsTitle3).foregroundStyle(DS.A.lavender).frame(width: 32)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(i + 1). \(rule.1)").font(.dsHeadline).foregroundStyle(DS.A.ink)
                                Text(rule.2).font(.dsSubhead).foregroundStyle(DS.A.inkSecondary)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(DS.A.canvas)
            .navigationTitle("How authoring works")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .primaryAction) { Button("Got it") { dismiss() } } }
        }
        .preferredColorScheme(.light)
    }
}

private extension View {
    /// Strips List chrome so rows can carry the canvas's own card styling.
    func plainRow() -> some View {
        listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
    }
}

// MARK: - Scan preview

/// Camera with a plain-language scan-quality pill and the coverage bar over it.
/// The raw telemetry shows only when asked for from the ··· menu.
struct ScanPreview: View {
    let viewModel: MapAuthoringViewModel
    let isCompact: Bool
    let showDetails: Bool

    private var telemetryTint: Color {
        viewModel.mappingStatus.isSaveable ? DS.N.okText : DS.N.accent
    }

    private enum Quality { case good, fair, poor, starting }

    private var quality: Quality {
        switch viewModel.mappingStatus {
        case .mapped:    return .good
        case .extending: return .fair
        case .limited:   return .poor
        default:         return .starting
        }
    }

    var body: some View {
        ARPreviewView(session: viewModel.arManager.session, showFeaturePoints: true)
            .frame(height: isCompact ? 180 : 260)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 8) {
                    qualityPill
                    if showDetails { telemetry }
                }
                .padding(14)
            }
            .overlay(alignment: .bottom) { coverage.padding(14) }
    }

    private var qualityPill: some View {
        let (text, icon, ink, fill, stroke): (String, String, Color, Color, Color) = {
            switch quality {
            case .good:     return ("Scan quality good", "checkmark", DS.N.okText, DS.N.okBg, DS.N.okStroke)
            case .fair:     return ("Scan quality fair · keep going", "arrow.triangle.2.circlepath", DS.N.warnText, DS.N.warnBg, DS.N.warnStroke)
            case .poor:     return ("Keep scanning slowly", "exclamationmark.triangle.fill", DS.N.warnText, DS.N.warnBg, DS.N.warnStroke)
            case .starting: return ("Starting the scan…", "hourglass", DS.N.inkTertiary, DS.N.raised, DS.N.hairline)
            }
        }()
        return Label(text, systemImage: icon)
            .font(.dsSubhead.weight(.semibold))
            .foregroundStyle(ink)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(fill.opacity(0.92), in: Capsule())
            .overlay(Capsule().strokeBorder(stroke, lineWidth: 1.5))
            .accessibilityLabel(text)
    }

    /// How much of the walk has been done, with the Immersal photo count beside it.
    private var coverage: some View {
        let fraction = viewModel.coverageFraction
        return HStack(spacing: 10) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.N.ink.opacity(0.22))
                    Capsule().fill(fraction >= 0.6 ? DS.N.okText : DS.N.accent).frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 8)
            Text("\(Int(fraction * 100))%")
                .font(.dsMonoTiny.weight(.semibold))
                .foregroundStyle(fraction >= 0.6 ? DS.N.okText : DS.N.accent)
            if viewModel.scanner.running || viewModel.scanner.captured > 0 {
                Text(viewModel.scanner.tooFast ? "slow down" : "\(viewModel.scanner.uploaded)/\(viewModel.scanner.captured) photos")
                    .font(.dsMonoTiny.weight(.semibold))
                    .foregroundStyle(viewModel.scanner.tooFast ? DS.N.warnText : DS.N.inkTertiary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Coverage \(Int(fraction * 100)) percent")
    }

    private var telemetry: some View {
        let p = NavigationGeometry.planarPosition(of: viewModel.arManager.cameraTransform)
        return VStack(alignment: .leading, spacing: 3) {
            Text(viewModel.arManager.localizationStatus.label)
            Text("mapping: \(viewModel.mappingStatus.label)   features \(viewModel.arManager.featurePointCount)")
            Text("x \(p.x, specifier: "%.1f")  z \(p.y, specifier: "%.1f")   trail: \(viewModel.trail.count) pts")
            if let scan = viewModel.scanSummary { Text(scan) }
        }
        .font(.dsMonoTiny)
        .foregroundStyle(telemetryTint)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(DS.N.canvas.opacity(0.78), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .dsStroke(DS.N.ink.opacity(0.2), radius: 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Scan status: \(viewModel.arManager.localizationStatus.label), mapping \(viewModel.mappingStatus.label), \(viewModel.arManager.featurePointCount) feature points")
    }
}

// MARK: - Banners and cards

struct NoticeBanner: View {
    enum Style { case warning, success }

    let icon: String
    let text: String
    let style: Style

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.dsSubhead.weight(.bold))
                .foregroundStyle(style == .warning ? DS.A.warnIcon : DS.A.okText)
            Text(text)
                .font(.dsSubhead)
                .foregroundStyle(style == .warning ? DS.A.warnText : DS.A.okText)
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(style == .warning ? DS.A.warnBg : DS.A.okBg,
                    in: RoundedRectangle(cornerRadius: DS.R.field, style: .continuous))
        .dsStroke(style == .warning ? DS.A.warnStroke : DS.A.okStroke, 1.5, radius: DS.R.field)
        .accessibilityElement(children: .combine)
    }
}

/// One card carries every stage of the publish, so a mapper who looks away can
/// see exactly where it stopped.
struct PublishProgressCard: View {
    let stage: String?
    let step: AuthoringStep?
    let fraction: Double?
    let bytesText: String?
    let version: Int?
    let showsChecklist: Bool

    private var title: String {
        if let version, step == .upload { return "Uploading world map v\(version)" }
        return stage?.replacingOccurrences(of: "…", with: "") ?? step?.activeLabel ?? "Working"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: showsChecklist ? "icloud.and.arrow.up" : "icloud.and.arrow.down")
                    .font(.dsTitle3.weight(.semibold)).foregroundStyle(DS.A.lavenderDeep)
                Text(title)
                    .font(.dsTitle3).foregroundStyle(DS.A.lavenderInk)
                Spacer(minLength: 8)
                if let fraction {
                    Text("\(Int((fraction * 100).rounded()))%")
                        .font(.dsTitle3.monospacedDigit()).foregroundStyle(DS.A.lavenderDeep)
                }
            }

            if let fraction {
                ProgressView(value: min(max(fraction, 0), 1))
                    .progressViewStyle(.linear)
                    .tint(DS.A.lavender)
            } else {
                ProgressView().progressViewStyle(.linear).tint(DS.A.lavender)
            }

            if let bytesText {
                Text("\(bytesText) · stay on this screen until it \(showsChecklist ? "publishes" : "finishes")")
                    .font(.dsSubhead).foregroundStyle(DS.A.lavenderBody)
            }

            if showsChecklist, let step {
                Divider().overlay(DS.A.lavenderStroke)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(AuthoringStep.allCases) { candidate in
                        checklistRow(candidate, current: step)
                    }
                }
            }
        }
        .padding(20)
        .background(DS.A.lavenderBg, in: RoundedRectangle(cornerRadius: DS.R.panel, style: .continuous))
        .dsStroke(DS.A.lavenderStroke, 1.5, radius: DS.R.panel)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func checklistRow(_ candidate: AuthoringStep, current: AuthoringStep) -> some View {
        let isDone = candidate.rawValue < current.rawValue
        let isCurrent = candidate == current

        HStack(spacing: 10) {
            Group {
                if isDone {
                    Image(systemName: "checkmark")
                        .font(.dsFootnote.weight(.heavy)).foregroundStyle(DS.A.okDot)
                } else if isCurrent {
                    ProgressView().controlSize(.mini).tint(DS.A.lavenderDeep)
                } else {
                    Circle().strokeBorder(DS.A.lavenderStroke, lineWidth: 2)
                }
            }
            .frame(width: 18, height: 18)

            Text(isDone ? candidate.doneLabel : candidate.activeLabel)
                .font(isCurrent ? .dsSubhead.weight(.semibold) : .dsSubhead)
                .foregroundStyle(isDone || isCurrent ? DS.A.lavenderInk : Color(dsHex: 0x7A70A0))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(isDone ? candidate.doneLabel : candidate.activeLabel). \(isDone ? "Done" : isCurrent ? "In progress" : "Not started")")
    }
}

struct EmptyPlacesCard: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(DS.A.lavender)
                .frame(width: 64, height: 64)
                .background(DS.A.lavenderBg, in: Circle())

            Text("No places marked yet")
                .font(.dsTitle3).foregroundStyle(DS.A.ink)
                .multilineTextAlignment(.center)

            Text("Walk the visitor route, then tap **Mark here** at each destination, junction, exhibit or hazard.")
                .font(.dsCallout).foregroundStyle(DS.A.inkTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(DS.A.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .dsStroke(DS.A.hairline, 1.5, radius: 24)
    }
}

/// Node type is a dot *and* a word, never colour alone.
struct NodeRow: View {
    let node: NavigationPOI
    let neighbours: [String]
    let isChainOrigin: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(DS.Cat.dot(node.category))
                .frame(width: 12, height: 12)
                .padding(.top, 5)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(node.name)
                        .font(.dsHeadline).foregroundStyle(DS.A.ink)
                    CategoryChip(category: node.category)
                    if isChainOrigin {
                        Image(systemName: "link")
                            .font(.dsFootnote.weight(.bold))
                            .foregroundStyle(DS.A.lavender)
                            .accessibilityLabel("Next mark links from here")
                    }
                }

                Text(coordinateLine)
                    .font(.dsMonoTiny).foregroundStyle(DS.A.inkTertiary)

                if let details = node.details, !details.isEmpty {
                    Text(details).font(.dsFootnote).foregroundStyle(DS.A.inkSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(DS.A.card, in: RoundedRectangle(cornerRadius: DS.R.row, style: .continuous))
        .dsStroke(isChainOrigin ? DS.A.hairlineLav : DS.A.hairline, 1.5, radius: DS.R.row)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var coordinateLine: String {
        let position = String(format: "x %.1f z %.1f", node.x, node.z)
        guard !neighbours.isEmpty else { return position }
        return position + " → " + neighbours.joined(separator: ", ")
    }

    private var accessibilityText: String {
        let connections = neighbours.isEmpty
            ? "not connected"
            : "connected to " + neighbours.joined(separator: ", ")
        return "\(node.name), \(node.category.label), \(connections)"
    }
}

struct CategoryChip: View {
    let category: POICategory

    var body: some View {
        Text(category.label)
            .font(.caption2.weight(.semibold))
            .textCase(.uppercase)
            .kerning(0.5)
            .foregroundStyle(DS.Cat.chipInk(category))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(DS.Cat.chipBg(category), in: RoundedRectangle(cornerRadius: DS.R.chip, style: .continuous))
    }
}

// MARK: - Error card

/// Says what broke, what is safe, and what to do next.
struct ErrorCard: View {
    let message: String
    let retryLabel: String?
    let onRetry: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            DS.N.canvas.opacity(0.55).ignoresSafeArea()

            VStack(spacing: 0) {
                VStack(spacing: 14) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(DS.A.dangerText)
                        .frame(width: 60, height: 60)
                        .background(DS.A.dangerBg, in: Circle())

                    Text("Something went wrong")
                        .font(.dsTitle2).foregroundStyle(DS.A.ink)
                        .multilineTextAlignment(.center)

                    Text(message)
                        .font(.dsCallout).foregroundStyle(DS.A.inkSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 24)
                .padding(.top, 28)
                .padding(.bottom, 24)

                Divider().overlay(Color(dsHex: 0xDDD7EE))

                if let retryLabel {
                    Button(action: onRetry) {
                        Text(retryLabel)
                            .font(.dsTitle3.weight(.semibold)).foregroundStyle(DS.A.lavender)
                            .frame(maxWidth: .infinity, minHeight: 60)
                    }
                    .buttonStyle(.plain)
                    Divider().overlay(Color(dsHex: 0xDDD7EE))
                }

                Button(action: onDismiss) {
                    Text("OK")
                        .font(.dsTitle3.weight(.medium)).foregroundStyle(DS.A.inkSecondary)
                        .frame(maxWidth: .infinity, minHeight: 60)
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: 330)
            .background(DS.A.canvas, in: RoundedRectangle(cornerRadius: DS.R.card, style: .continuous))
            .shadow(color: .black.opacity(0.45), radius: 30, y: 18)
            .padding(24)
        }
        .accessibilityAddTraits(.isModal)
    }
}

// MARK: - Node form

/// Name / type / spoken description. Type is a 2×2 grid of large targets rather
/// than a wheel, so it is thumb-reachable while standing.
struct NodeForm: View {
    let title: String
    var node: NavigationPOI?
    var position: SIMD2<Float>
    let onSave: (String, POICategory, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var category: POICategory = .destination
    @State private var details = ""
    @FocusState private var nameFocused: Bool

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    field("Name") {
                        TextField("Orchid Display", text: $name)
                            .font(.dsTitle3.weight(.medium))
                            .textInputAutocapitalization(.words)
                            .focused($nameFocused)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 60, alignment: .leading)
                            .background(DS.A.card, in: RoundedRectangle(cornerRadius: DS.R.field, style: .continuous))
                            .dsStroke(nameFocused ? DS.A.lavender : DS.A.hairline,
                                      nameFocused ? 2 : 1.5, radius: DS.R.field)
                    }

                    field("Type") {
                        VStack(alignment: .leading, spacing: 10) {
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8),
                                                GridItem(.flexible(), spacing: 8)], spacing: 8) {
                                ForEach(POICategory.allCases) { candidate in
                                    typeOption(candidate)
                                }
                            }
                            categoryHintBox
                        }
                    }

                    field("Spoken description") {
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("A raised bench of tropical orchids at waist height.",
                                      text: $details, axis: .vertical)
                                .font(.dsBody)
                                .lineLimit(3...8)
                                .padding(16)
                                .frame(minHeight: 104, alignment: .topLeading)
                                .background(DS.A.card, in: RoundedRectangle(cornerRadius: DS.R.field, style: .continuous))
                                .dsStroke(DS.A.hairline, 1.5, radius: DS.R.field)
                            Text("Read aloud verbatim — write it the way you would say it.")
                                .font(.dsFootnote).foregroundStyle(DS.A.inkTertiary)
                        }
                    }

                    HStack(spacing: 10) {
                        coordinate("x", position.x)
                        coordinate("z", position.y)
                    }
                }
                .padding(20)
            }
        }
        .background(DS.A.canvas)
        .onAppear {
            if let node {
                name = node.name
                category = node.category
                details = node.details ?? ""
            }
        }
    }

    private var header: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .font(.dsTitle3.weight(.medium))
                .foregroundStyle(DS.A.lavender)

            Spacer()
            Text(title).font(.dsTitle2).foregroundStyle(DS.A.ink)
            Spacer()

            Button {
                onSave(trimmedName, category, details.isEmpty ? nil : details)
                dismiss()
            } label: {
                Text("Save")
                    .font(.dsTitle3.weight(.semibold))
                    .foregroundStyle(trimmedName.isEmpty ? DS.A.inkDisabled : .white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(trimmedName.isEmpty ? DS.A.inset : DS.A.lavender,
                                in: RoundedRectangle(cornerRadius: DS.R.segment, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(trimmedName.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).dsEyebrow(DS.A.inkTertiary)
            content()
        }
    }

    private func typeOption(_ candidate: POICategory) -> some View {
        let isOn = candidate == category
        return Button { category = candidate } label: {
            HStack(spacing: 10) {
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.dsFootnote.weight(.heavy))
                        .foregroundStyle(DS.Cat.chipInk(candidate))
                } else {
                    Circle().fill(DS.Cat.dot(candidate)).frame(width: 12, height: 12)
                }
                Text(candidate.label)
                    .font(isOn ? .dsBody.weight(.bold) : .dsBody)
                    .foregroundStyle(isOn ? DS.Cat.chipInk(candidate) : DS.A.inkSecondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .background(isOn ? DS.Cat.chipBg(candidate) : DS.A.card,
                        in: RoundedRectangle(cornerRadius: DS.R.field, style: .continuous))
            .dsStroke(isOn ? DS.Cat.dot(candidate) : DS.A.hairline,
                      isOn ? 2.5 : 1.5, radius: DS.R.field)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isSelected, .isButton] : .isButton)
    }

    /// Rewrites itself to the selected type's routing rule.
    private var categoryHintBox: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .font(.dsSubhead.weight(.semibold))
                .foregroundStyle(DS.Cat.chipInk(category))
            Text(categoryHint)
                .font(.dsSubhead)
                .foregroundStyle(DS.Cat.chipInk(category))
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(DS.Cat.chipBg(category), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func coordinate(_ label: String, _ value: Float) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).dsEyebrow(DS.A.inkTertiary)
            Text(String(format: "%.2f", value))
                .font(.dsBody.monospaced())
                .foregroundStyle(DS.A.inkSecondary)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                .background(DS.A.inset, in: RoundedRectangle(cornerRadius: DS.R.field, style: .continuous))
                .dsStroke(DS.A.hairline, 1.5, radius: DS.R.field)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(String(format: "%.2f", value)) metres")
    }

    private var categoryHint: String {
        switch category {
        case .destination:
            return "Destination — navigable. Not announced when passed."
        case .junction:
            return "Junction — routing only, never spoken to the visitor."
        case .exhibit:
            return "Exhibit — navigable, and the description is spoken automatically when the visitor comes within 2.5 m."
        case .hazard:
            return "Hazard — never a destination. Announced with a warning haptic within 2.5 m."
        }
    }
}
