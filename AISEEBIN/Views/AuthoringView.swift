import SwiftUI

/// Author mode, per artboards 07–11 of the Claude Design canvas.
///
/// Light, dense and calm — a pro tool. It is used standing up in daylight with a
/// sighted eye on it the whole time, which is why it is the opposite surface to
/// Navigate. Telemetry stays monospaced and boxed so it reads as instrument data.
struct AuthoringView: View {
    @State private var viewModel: MapAuthoringViewModel
    @State private var showMarkSheet = false
    @State private var editingNode: NavigationPOI?
    @State private var connectingFrom: NavigationPOI?
    @State private var confirmFreshScan = false
    @State private var showUploadSheet = false
    @State private var showMapPicker = false
    /// Set when switching maps would discard unsaved marks; the alert confirms it.
    @State private var mapPendingSwitch: RemoteMapSummary?
    @State private var uploadNote = ""
    /// Seeded from the map's current name each time the publish alert opens.
    @State private var uploadName = ""
    /// Remembered so the error card can offer the right retry.
    @State private var lastAction: LastAction?

    private enum LastAction: Equatable {
        case save
        case upload(name: String, note: String?)
        case importLatest(slug: String)

        var retryLabel: String {
            switch self {
            case .save:         return "Try save again"
            case .upload:       return "Try upload again"
            case .importLatest: return "Try import again"
            }
        }
    }

    init(arManager: ARNavigationManager, mapStore: MapStore) {
        _viewModel = State(initialValue: MapAuthoringViewModel(arManager: arManager, mapStore: mapStore))
    }

    var body: some View {
        VStack(spacing: 0) {
            ScanPreview(viewModel: viewModel,
                        isCompact: !viewModel.nodes.isEmpty,
                        onImport: { showMapPicker = true },
                        onContinue: { viewModel.continueExistingScan() },
                        onFreshScan: { confirmFreshScan = true })
                .padding(.horizontal, 20)
                .padding(.bottom, 16)

            content
        }
        .background(DS.A.canvas)
        .safeAreaInset(edge: .bottom, spacing: 0) { actionBar }
        .overlay { errorCard }
        .sheet(isPresented: $showMapPicker) {
            ServerMapPicker(viewModel: viewModel) { map in
                showMapPicker = false
                // Re-fetching the map you are already on cannot lose anything;
                // switching to a different one replaces the whole local bundle.
                if viewModel.hasUnsavedChanges && map.slug != viewModel.targetSlug {
                    mapPendingSwitch = map
                } else {
                    startImport(of: map)
                }
            }
        }
        .alert("Discard unsaved marks?", isPresented: .constant(mapPendingSwitch != nil),
               presenting: mapPendingSwitch) { map in
            Button("Discard and import", role: .destructive) {
                mapPendingSwitch = nil
                startImport(of: map)
            }
            Button("Cancel", role: .cancel) { mapPendingSwitch = nil }
        } message: { map in
            Text("Importing “\(map.name)” replaces this bundle's world map and marked nodes. Marks you have not published will be lost.")
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
        .alert("Publish to server", isPresented: $showUploadSheet) {
            TextField("Map name", text: $uploadName)
            TextField("What changed? (optional)", text: $uploadNote)
            Button("Upload") {
                let name = uploadName.trimmingCharacters(in: .whitespacesAndNewlines)
                let trimmedNote = uploadNote.trimmingCharacters(in: .whitespacesAndNewlines)
                let note = trimmedNote.isEmpty ? nil : trimmedNote
                lastAction = .upload(name: name, note: note)
                uploadNote = ""
                Task { await viewModel.upload(name: name, note: note) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The name is what this map is called in the web editor. Uploads the world map, feature points and graph as a new version. Fine-tune it at \(ServerConfig.editorURL.host ?? "").")
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
        .alert("Start a fresh scan?", isPresented: $confirmFreshScan) {
            Button("Discard local map and rescan", role: .destructive) { viewModel.startFreshScan() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes the local world map and marked nodes. Versions already on the server are kept.")
        }
    }

    // MARK: - Scrolling body

    private var content: some View {
        List {
            if viewModel.showsProgress {
                PublishProgressCard(stage: viewModel.progressStage,
                                    step: viewModel.progressStep,
                                    fraction: viewModel.progressFraction,
                                    bytesText: viewModel.progressBytesText,
                                    version: viewModel.progressVersion,
                                    showsChecklist: viewModel.isUploading)
                    .plainRow()
            }

            if let warning = viewModel.mappingWarning {
                NoticeBanner(icon: "exclamationmark.triangle.fill", text: warning, style: .warning)
                    .plainRow()
            }

            if let message = viewModel.statusMessage {
                NoticeBanner(icon: "checkmark", text: message, style: .success)
                    .plainRow()
            }

            if viewModel.nodes.isEmpty {
                EmptyPlacesCard().plainRow()
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
                        Text("\(viewModel.mapName) · \(viewModel.nodes.count) places").dsEyebrow(DS.A.inkTertiary)
                        Spacer()
                        Text(viewModel.localVersion.map { "server v\($0.version)" } ?? "swipe row for actions")
                            .font(.dsMonoTiny).foregroundStyle(DS.A.inkMuted)
                    }
                    .padding(.horizontal, 2)
                    .padding(.bottom, 6)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
            }
        }
        .listStyle(.plain)
        .listRowSpacing(8)
        .scrollContentBackground(.hidden)
        .background(DS.A.canvas)
        .environment(\.defaultMinListHeaderHeight, 0)
    }

    // MARK: - Action bar

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button {
                showMarkSheet = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "mappin.and.ellipse").font(.dsTitle3.weight(.semibold))
                    Text("Mark here").font(.dsTitle3.weight(.semibold))
                }
                // This one is the flexible child, so it absorbs any shortfall in the
                // row. Held to a single line, shrinking slightly on a narrow phone,
                // rather than wrapping and dragging the whole bar taller.
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

            // Save and Upload are fixed squares: the row is narrower than three
            // labelled buttons on every phone, and a squeezed flexible button
            // grows tall instead of narrow (seen on iOS 26). With hard sizes the
            // only flexible child is Mark here, which shrinks its label instead.
            Button {
                lastAction = .save
                Task { await viewModel.saveLocally() }
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.dsTitle3.weight(.semibold))
                        .frame(width: Self.actionBarHeight, height: Self.actionBarHeight)
                    if viewModel.hasUnsavedChanges {
                        Circle().fill(DS.A.destructive).frame(width: 8, height: 8).padding(10)
                    }
                }
                .foregroundStyle(viewModel.canSave ? DS.A.lavender : DS.A.inkDisabled)
                .background(viewModel.canSave ? DS.A.lavenderBg : DS.A.inset,
                            in: RoundedRectangle(cornerRadius: DS.R.row, style: .continuous))
                .dsStroke(viewModel.canSave ? DS.A.hairlineLav : DS.A.hairline, 1.5, radius: DS.R.row)
            }
            .buttonStyle(.plain)
            .fixedSize()
            .disabled(!viewModel.canSave)
            .accessibilityLabel(viewModel.hasUnsavedChanges ? "Save, unsaved changes" : "Save")

            Button {
                uploadName = viewModel.mapName
                showUploadSheet = true
            } label: {
                Group {
                    if viewModel.isBusy, let fraction = viewModel.progressFraction {
                        Text("\(Int((fraction * 100).rounded()))%")
                            .font(.dsHeadline.monospacedDigit())
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    } else if viewModel.isBusy {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "icloud.and.arrow.up").font(.dsTitle3.weight(.semibold))
                    }
                }
                .frame(width: Self.actionBarHeight, height: Self.actionBarHeight)
                .foregroundStyle(viewModel.canUpload || viewModel.isBusy ? .white : DS.A.inkDisabled)
                .background(uploadFill, in: RoundedRectangle(cornerRadius: DS.R.row, style: .continuous))
                .dsStroke(viewModel.canUpload || viewModel.isBusy ? .clear : DS.A.hairline, 1.5, radius: DS.R.row)
            }
            .buttonStyle(.plain)
            .fixedSize()
            .disabled(!viewModel.canUpload)
            .accessibilityLabel("Upload")
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(DS.A.card)
        .overlay(alignment: .top) { Rectangle().fill(DS.A.hairline).frame(height: 1) }
    }

    /// One height for all three action-bar buttons, so they line up whether they
    /// are showing a label, an icon alone, or a progress spinner.
    private static let actionBarHeight: CGFloat = 60

    private var canMark: Bool { viewModel.canMark && !viewModel.isBusy }

    private var uploadFill: Color {
        if viewModel.isBusy { return DS.A.lavenderDeep }
        return viewModel.canUpload ? DS.A.ink : DS.A.inset
    }

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

    private func startImport(of map: RemoteMapSummary) {
        lastAction = .importLatest(slug: map.slug)
        Task { await viewModel.importLatestFromServer(slug: map.slug) }
    }

    private func retryLastAction() {
        let action = lastAction
        viewModel.errorMessage = nil
        switch action {
        case .save:               Task { await viewModel.saveLocally() }
        case .upload(let name, let note):
            Task { await viewModel.upload(name: name, note: note) }
        case .importLatest(let slug):
            Task { await viewModel.importLatestFromServer(slug: slug) }
        case nil:                 break
        }
    }
}

/// Lists every map on the server so the mapper can pull down one that is not the
/// bundle they happen to be carrying. Shows the newest version of each map; the
/// download itself is the slow part, so this stays a metadata-only listing.
struct ServerMapPicker: View {
    let viewModel: MapAuthoringViewModel
    let onPick: (RemoteMapSummary) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isListingMaps && viewModel.availableMaps.isEmpty {
                    loading
                } else if let error = viewModel.mapListError, viewModel.availableMaps.isEmpty {
                    message(icon: "exclamationmark.triangle.fill",
                            title: "Could not reach the server",
                            detail: error)
                } else if viewModel.availableMaps.isEmpty {
                    message(icon: "tray",
                            title: "No maps on the server yet",
                            detail: "Publish this one from the Upload button and it will appear here.")
                } else {
                    list
                }
            }
            .background(DS.A.canvas)
            .navigationTitle("Import from server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .task { await viewModel.loadAvailableMaps() }
    }

    private var list: some View {
        List {
            ForEach(viewModel.availableMaps) { map in
                Button { onPick(map) } label: { row(map) }
                    .buttonStyle(.plain)
                    .plainRow()
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func row(_ map: RemoteMapSummary) -> some View {
        let isCurrent = map.slug == viewModel.targetSlug
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(map.name).font(.dsHeadline).foregroundStyle(DS.A.ink)
                    if isCurrent {
                        Text("CURRENT")
                            .font(.dsCaption).kerning(1.1)
                            .foregroundStyle(DS.A.lavenderDeep)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(DS.A.lavenderBg, in: Capsule())
                    }
                }
                Text("v\(map.version) · \(map.source.rawValue) · \(map.pointCount) pts")
                    .font(.dsFootnote.monospaced()).foregroundStyle(DS.A.inkTertiary)
                Text(map.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.dsFootnote).foregroundStyle(DS.A.inkMuted)
            }
            Spacer(minLength: 8)
            Image(systemName: "icloud.and.arrow.down")
                .font(.dsHeadline).foregroundStyle(DS.A.lavender)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.A.card, in: RoundedRectangle(cornerRadius: DS.R.row, style: .continuous))
        .dsStroke(isCurrent ? DS.A.hairlineLav : DS.A.hairline, 1.5, radius: DS.R.row)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(map.name), version \(map.version), \(map.pointCount) points\(isCurrent ? ", current map" : "")")
        .accessibilityHint("Downloads this map and replaces the one on this device")
    }

    private var loading: some View {
        VStack(spacing: 12) {
            ProgressView().tint(DS.A.lavender)
            Text("Listing maps…").font(.dsSubhead).foregroundStyle(DS.A.inkTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func message(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.dsTitle3).foregroundStyle(DS.A.inkMuted)
            Text(title).font(.dsHeadline).foregroundStyle(DS.A.ink)
            Text(detail)
                .font(.dsSubhead).foregroundStyle(DS.A.inkTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

/// Camera with the scan telemetry over it, plus the scan menu.
struct ScanPreview: View {
    let viewModel: MapAuthoringViewModel
    let isCompact: Bool
    let onImport: () -> Void
    let onContinue: () -> Void
    let onFreshScan: () -> Void

    private var telemetryTint: Color {
        viewModel.mappingStatus.isSaveable ? DS.N.okText : DS.N.accent
    }

    var body: some View {
        ARPreviewView(session: viewModel.arManager.session, showFeaturePoints: true)
            .frame(height: isCompact ? 160 : 240)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(alignment: .topLeading) { telemetry.padding(14) }
            .overlay(alignment: .topTrailing) { menu.padding(14) }
            .overlay(alignment: .bottom) {
                if !isCompact { scanQuality.padding(14) }
            }
    }

    private var telemetry: some View {
        let p = NavigationGeometry.planarPosition(of: viewModel.arManager.cameraTransform)
        return VStack(alignment: .leading, spacing: 3) {
            Text(viewModel.arManager.localizationStatus.label)
            Text("mapping: \(viewModel.mappingStatus.label)   features \(viewModel.arManager.featurePointCount)")
            Text("x \(p.x, specifier: "%.1f")  z \(p.y, specifier: "%.1f")   trail: \(viewModel.trail.count) pts")
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

    private var menu: some View {
        Menu {
            Button("Import Map From Server…", action: onImport)
            Button("Continue Existing Scan (relocalize)", action: onContinue)
                .disabled(!viewModel.mapStore.hasSavedWorldMap)
            Divider()
            Button("Start Fresh Scan", role: .destructive, action: onFreshScan)
        } label: {
            Image(systemName: "ellipsis")
                .font(.dsHeadline.weight(.bold))
                .foregroundStyle(DS.N.ink)
                .frame(width: 44, height: 44)
                .background(DS.N.ink.opacity(0.16), in: Circle())
                .overlay(Circle().strokeBorder(DS.N.ink.opacity(0.3), lineWidth: 1))
        }
        .disabled(viewModel.isBusy)
        .accessibilityLabel("Scan options")
    }

    /// Rough scan quality: how far the feature count has come toward a map that
    /// relocalizes reliably.
    private var scanQuality: some View {
        let fraction = min(1, Double(viewModel.arManager.featurePointCount) / 3500)
        return HStack(spacing: 10) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.N.ink.opacity(0.22))
                    Capsule().fill(DS.N.warnText).frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 8)

            Text("SCAN \(Int(fraction * 100))%")
                .font(.dsMonoTiny.weight(.semibold))
                .foregroundStyle(DS.N.warnText)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Scan quality \(Int(fraction * 100)) percent")
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
