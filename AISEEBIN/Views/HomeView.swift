import SwiftUI

/// Staff start screen, artboard A of the Claude Design canvas. Every map shows
/// where it lives (on this phone and synced, this phone only, or on the server)
/// and the one next action that status calls for. Replaces Author's competing
/// start buttons and the map ids in Settings.
struct HomeView: View {
    @Bindable var viewModel: NavigationViewModel
    let onSettings: () -> Void

    @State private var pendingDraftReplace: RemoteMapSummary?

    var body: some View {
        VStack(spacing: 0) {
            AppHeader(surface: .light, logo: AppLogo(isStaff: true, onExitStaff: { viewModel.exitStaffMode() })) {
                HeaderTitle(surface: .light, title: "Maps", subtitle: "Staff mode")
            } trailing: {
                HeaderIconButton(surface: .light, systemImage: "slider.horizontal.3", label: "Settings", action: onSettings)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    newMapCard
                    Text("Your maps").dsEyebrow(DS.A.inkTertiary).padding(.top, 10).padding(.horizontal, 4)
                    if viewModel.mapStore.hasSavedMap { localMapCard }
                    ForEach(otherServerMaps) { serverRow($0) }
                    if otherServerMaps.isEmpty { listingState }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .refreshable { await viewModel.loadServerMaps() }
        }
        .background(DS.A.canvas)
        .task { await viewModel.loadServerMaps() }
        .alert("Replace the draft on this phone?", isPresented: .constant(pendingDraftReplace != nil),
               presenting: pendingDraftReplace) { map in
            Button("Replace", role: .destructive) {
                pendingDraftReplace = nil
                Task { await viewModel.switchMap(to: map.slug) }
            }
            Button("Cancel", role: .cancel) { pendingDraftReplace = nil }
        } message: { map in
            Text("Getting “\(map.name)” deletes the unpublished “\(viewModel.mapName)” on this phone. Publish it first to keep it.")
        }
    }

    /// Server maps other than the one this phone carries.
    private var otherServerMaps: [RemoteMapSummary] {
        viewModel.serverMaps.filter { viewModel.isLocalDraft || $0.slug != viewModel.mapSlug }
    }

    // MARK: - New map

    private var newMapCard: some View {
        Button { viewModel.openAuthoring(.newMap) } label: {
            HStack(spacing: 16) {
                Image(systemName: "plus")
                    .font(.dsTitle3.weight(.bold))
                    .foregroundStyle(DS.A.lavender)
                    .frame(width: 52, height: 52)
                    .background(.white, in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text("New map").font(.dsTitle3.weight(.bold))
                    Text("Scan a new area in 3 steps").font(.dsSubhead).foregroundStyle(Color(dsHex: 0xEDE7FF))
                }
                .foregroundStyle(.white)
                Spacer(minLength: 0)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.A.lavender, in: RoundedRectangle(cornerRadius: DS.R.panel, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    // MARK: - The map on this phone

    private var localMapCard: some View {
        let places = viewModel.displayMap.pois.count
        let isDraft = viewModel.isLocalDraft
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.mapName).font(.dsTitle3.weight(.bold)).foregroundStyle(DS.A.ink)
                    Text(isDraft ? "draft · \(places) places · not published"
                                 : "v\(viewModel.localVersion?.version ?? 0) · \(places) places · \(syncWords)")
                        .font(.dsFootnote.monospaced()).foregroundStyle(DS.A.inkTertiary)
                }
                Spacer(minLength: 8)
                if isDraft {
                    badge("This phone only", icon: "iphone", ink: DS.A.warnText, fill: DS.A.warnBg)
                } else {
                    badge("In use", icon: "checkmark", ink: DS.A.okText, fill: DS.A.okBg)
                }
            }
            if isDraft {
                Button { viewModel.openAuthoring(.continueScan) } label: {
                    HStack(spacing: 8) {
                        Text("Continue mapping")
                        Image(systemName: "chevron.right")
                    }
                    .font(.dsHeadline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(DS.A.lavender, in: RoundedRectangle(cornerRadius: DS.R.field, style: .continuous))
                }
                .buttonStyle(.plain)
            } else {
                HStack(spacing: 8) {
                    actionButton("Navigate", ink: .white, fill: DS.A.ink, stroke: .clear) { viewModel.mode = .navigation }
                    actionButton("Explore", ink: DS.A.ink, fill: DS.A.inset, stroke: DS.A.hairline) { viewModel.mode = .explore }
                    actionButton("Edit", ink: DS.A.lavender, fill: DS.A.lavenderBg, stroke: DS.A.lavenderStroke) {
                        viewModel.openAuthoring(.continueScan)
                    }
                }
            }
        }
        .padding(16)
        .background(DS.A.card, in: RoundedRectangle(cornerRadius: DS.R.row, style: .continuous))
        .dsStroke(isDraft ? DS.A.hairline : DS.A.lavenderStroke, isDraft ? 1.5 : 2, radius: DS.R.row)
    }

    private var syncWords: String {
        switch viewModel.syncState {
        case .checking:            return "checking"
        case .downloading:         return "downloading"
        case .failed:              return "sync failed"
        case .offlineSample:       return "not on server"
        case .idle, .upToDate, .updated: return "synced"
        }
    }

    // MARK: - Maps on the server

    private func serverRow(_ map: RemoteMapSummary) -> some View {
        let isSwitching = viewModel.switchingToSlug == map.slug
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(map.name).font(.dsHeadline).foregroundStyle(DS.A.ink)
                Text(isSwitching ? downloadWords : "v\(map.version) · on server · \(map.createdAt.formatted(.dateTime.day().month(.abbreviated)))")
                    .font(.dsFootnote.monospaced()).foregroundStyle(DS.A.inkTertiary)
            }
            Spacer(minLength: 8)
            Button {
                if viewModel.isLocalDraft { pendingDraftReplace = map }
                else { Task { await viewModel.switchMap(to: map.slug) } }
            } label: {
                HStack(spacing: 6) {
                    if isSwitching { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.down.to.line") }
                    Text("Get")
                }
                .font(.dsHeadline)
                .foregroundStyle(DS.A.ink)
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
                .background(DS.A.inset, in: RoundedRectangle(cornerRadius: DS.R.field, style: .continuous))
                .dsStroke(DS.A.hairline, 1.5, radius: DS.R.field)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.switchingToSlug != nil)
            .accessibilityLabel("Get \(map.name)")
            .accessibilityHint("Downloads it and makes it the map in use on this phone")
        }
        .padding(16)
        .background(DS.A.card, in: RoundedRectangle(cornerRadius: DS.R.row, style: .continuous))
        .dsStroke(DS.A.hairline, 1.5, radius: DS.R.row)
    }

    private var downloadWords: String {
        guard case .downloading = viewModel.syncState else { return "fetching…" }
        return "downloading \(Int((viewModel.syncProgress * 100).rounded()))%"
    }

    @ViewBuilder
    private var listingState: some View {
        if viewModel.isListingMaps {
            HStack(spacing: 10) {
                ProgressView()
                Text("Listing maps on the server…").font(.dsSubhead).foregroundStyle(DS.A.inkTertiary)
            }
            .padding(.horizontal, 4)
        } else if let error = viewModel.mapListError {
            NoticeBanner(icon: "exclamationmark.triangle.fill", text: "Could not reach the server: \(error)", style: .warning)
        } else if !viewModel.mapStore.hasSavedMap {
            Text("No maps yet. Start with New map.").font(.dsSubhead).foregroundStyle(DS.A.inkTertiary).padding(.horizontal, 4)
        }
    }

    // MARK: - Pieces

    private func badge(_ text: String, icon: String, ink: Color, fill: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.dsCaption)
            .foregroundStyle(ink)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(fill, in: Capsule())
    }

    private func actionButton(_ title: String, ink: Color, fill: Color, stroke: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.dsHeadline)
                .foregroundStyle(ink)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(fill, in: RoundedRectangle(cornerRadius: DS.R.field, style: .continuous))
                .dsStroke(stroke, 1.5, radius: DS.R.field)
        }
        .buttonStyle(.plain)
    }
}
