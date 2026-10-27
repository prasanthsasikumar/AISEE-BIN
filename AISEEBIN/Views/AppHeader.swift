import SwiftUI

/// The one header every screen shares, per artboards A–H of the Claude Design
/// canvas ("v2 — one structure"): the AiSee logo top-left, then the current map
/// or the screen's title, then settings. It replaces the old mode tab bar.
///
/// It sits on both surfaces: dark over Navigate, light everywhere else.
enum HeaderSurface {
    case dark, light

    var ink: Color { self == .dark ? DS.N.ink : DS.A.ink }
    var inkSecondary: Color { self == .dark ? DS.N.inkTertiary : DS.A.inkTertiary }
    var fill: Color { self == .dark ? DS.N.raised : DS.A.card }
    var stroke: Color { self == .dark ? DS.N.hairline : DS.A.hairline }
    var canvas: Color { self == .dark ? DS.N.canvas : DS.A.canvas }
    var accent: Color { self == .dark ? DS.N.accent : DS.A.lavender }
}

struct AppHeader<Center: View, Trailing: View>: View {
    let surface: HeaderSurface
    let logo: AppLogo
    @ViewBuilder var center: Center
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            logo
            center.frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 12)
        .background(surface.canvas)
    }
}

/// Title and an optional second line, for headers that are not the map chip.
struct HeaderTitle: View {
    let surface: HeaderSurface
    let title: String
    var subtitle: String?
    var subtitleIcon: String?
    var subtitleTint: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.dsTitle3.weight(.bold)).foregroundStyle(surface.ink).lineLimit(1)
            if let subtitle {
                HStack(spacing: 4) {
                    if let subtitleIcon { Image(systemName: subtitleIcon).font(.dsCaption) }
                    Text(subtitle).font(.dsFootnote).lineLimit(1)
                }
                .foregroundStyle(subtitleTint ?? surface.inkSecondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// The logo tile. Five taps within three seconds toggle staff mode, with a
/// light tick on taps three to five; nothing hints at it. In staff mode a house
/// badge shows, and the first tap also goes Home.
struct AppLogo: View {
    let isStaff: Bool
    var onHome: () -> Void = {}
    var onUnlock: () -> Void = {}
    /// Five taps in staff mode: back to what visitors see.
    var onExitStaff: () -> Void = {}

    /// Shared by every logo: the first staff tap swaps the screen (and with it
    /// this view), and the count has to carry on to Home's logo.
    @MainActor private static var taps: [Date] = []

    static let size: CGFloat = 52

    var body: some View {
        Button(action: tapped) {
            Image("AiSeeLogo")
                .renderingMode(.template)
                .resizable().scaledToFit()
                .foregroundStyle(.white)
                .frame(width: 30)
                .frame(width: Self.size, height: Self.size)
                .background(DS.Brand.tile, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    if isStaff {
                        Image(systemName: "house")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(DS.A.ink, in: Circle())
                            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                            .offset(x: 6, y: 6)
                    }
                }
        }
        .buttonStyle(.plain)
        // A visitor's VoiceOver never lands on the hidden unlock.
        .accessibilityHidden(!isStaff)
        .accessibilityLabel("AiSee, staff mode. Home")
        .accessibilityAction(named: "Exit staff mode", onExitStaff)
    }

    private func tapped() {
        let now = Date()
        Self.taps = Self.taps.filter { now.timeIntervalSince($0) < 3 } + [now]
        let count = Self.taps.count
        if isStaff, count == 1 { onHome() }
        if count >= 3, count < 5 {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        guard count >= 5 else { return }
        Self.taps = []
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        if isStaff { onExitStaff() } else { onUnlock() }
    }
}

/// Square icon button at the right of the header (settings, more).
struct HeaderIconButton: View {
    let surface: HeaderSurface
    let systemImage: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.dsHeadline.weight(.semibold))
                .foregroundStyle(surface.ink)
                .frame(width: AppLogo.size, height: AppLogo.size)
                .background(surface.fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .dsStroke(surface.stroke, 1.5, radius: 14)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// The current map, always on screen: its name, the mode, its version and a
/// status dot (with the status in words for VoiceOver). Tap to switch maps.
struct MapChip: View {
    let surface: HeaderSurface
    let viewModel: NavigationViewModel
    let action: () -> Void

    private enum Health { case ok, busy, failed, none }

    private var health: Health {
        switch viewModel.syncState {
        case .checking, .downloading:   return .busy
        case .failed:                   return .failed
        case .offlineSample:            return .none
        case .idle, .upToDate, .updated: return viewModel.isLocalDraft ? .none : .ok
        }
    }

    private var dot: Color {
        switch health {
        case .ok:     return surface == .dark ? DS.N.okText : DS.A.okDot
        case .busy:   return surface == .dark ? DS.N.warnText : DS.A.warnStroke
        case .failed: return surface == .dark ? DS.N.stop : DS.A.destructive
        case .none:   return surface.inkSecondary
        }
    }

    private var versionText: String {
        if viewModel.isLocalDraft { return "draft" }
        if case .offlineSample = viewModel.syncState { return "sample map" }
        if case .downloading(let v) = viewModel.syncState { return "downloading v\(v)" }
        guard let version = viewModel.localVersion?.version else { return "sample map" }
        return "map v\(version)"
    }

    private var healthWords: String {
        switch health {
        case .ok:     return "ready"
        case .busy:   return "updating"
        case .failed: return "sync failed"
        case .none:   return "not published"
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Circle().fill(dot).frame(width: 9, height: 9)
                VStack(alignment: .leading, spacing: 1) {
                    Text(viewModel.mapName)
                        .font(.dsHeadline).foregroundStyle(surface.ink).lineLimit(1)
                    Text("\(viewModel.mode.rawValue) · \(versionText)")
                        .font(.dsFootnote.monospaced()).foregroundStyle(surface.inkSecondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.down").font(.dsSubhead.weight(.semibold)).foregroundStyle(surface.inkSecondary)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: AppLogo.size)
            .background(surface.fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .dsStroke(surface.stroke, 1.5, radius: 16)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(viewModel.mapName) map, \(versionText), \(healthWords)")
        .accessibilityHint(viewModel.canReturnToWelcome ? "Choose another map, or go back to the start" : "Choose another map")
        .accessibilityAddTraits(.isButton)
    }
}

/// Artboard D: the published maps, current one ticked. Choosing another
/// downloads it in place of the one on this phone.
struct MapPickerSheet: View {
    let surface: HeaderSurface
    let viewModel: NavigationViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var pendingDraftReplace: RemoteMapSummary?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Choose map").font(.dsTitle2).foregroundStyle(surface.ink)
                Spacer()
                Button("Close") { dismiss() }
                    .font(.dsHeadline).foregroundStyle(surface.accent)
            }
            .padding(.top, 20)

            ScrollView {
                VStack(spacing: 10) {
                    if viewModel.canReturnToWelcome {
                        Button {
                            viewModel.mode = .welcome
                            dismiss()
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "arrow.uturn.backward").font(.dsTitle3).foregroundStyle(surface.accent)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Back to start").font(.dsHeadline).foregroundStyle(surface.ink)
                                    Text("Plan a visit or choose a place").font(.dsSubhead).foregroundStyle(surface.inkSecondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 16)
                            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
                            .background(surface.fill, in: RoundedRectangle(cornerRadius: DS.R.row, style: .continuous))
                            .dsStroke(surface.stroke, 1.5, radius: DS.R.row)
                        }
                        .buttonStyle(.plain)
                    }
                    if viewModel.serverMaps.isEmpty {
                        if viewModel.isListingMaps {
                            ProgressView().tint(surface.accent).padding(30)
                        } else {
                            note(viewModel.mapListError.map { "Could not reach the server: \($0)" }
                                 ?? "No maps have been published yet.")
                        }
                    }
                    ForEach(viewModel.serverMaps) { map in row(map) }
                    note("Only published maps are listed. Drafts stay with staff until they are uploaded.")
                }
            }
        }
        .padding(.horizontal, 20)
        .background(surface.canvas.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task { await viewModel.loadServerMaps() }
        .alert("Replace the draft on this phone?", isPresented: .constant(pendingDraftReplace != nil),
               presenting: pendingDraftReplace) { map in
            Button("Replace", role: .destructive) { pendingDraftReplace = nil; choose(map) }
            Button("Cancel", role: .cancel) { pendingDraftReplace = nil }
        } message: { _ in
            Text("The unpublished map on this phone will be deleted. Publish it first to keep it.")
        }
    }

    private func row(_ map: RemoteMapSummary) -> some View {
        let isCurrent = !viewModel.isLocalDraft && map.slug == viewModel.mapSlug
        let isSwitching = viewModel.switchingToSlug == map.slug
        return Button {
            guard !isCurrent else { dismiss(); return }
            if viewModel.isLocalDraft { pendingDraftReplace = map } else { choose(map) }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: isCurrent ? "checkmark.circle.fill" : "circle")
                    .font(.dsTitle3)
                    .foregroundStyle(isCurrent ? surface.accent : surface.inkSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(map.name).font(.dsHeadline).foregroundStyle(surface.ink)
                    Text(isCurrent ? "v\(map.version) · \(viewModel.displayMap.pois.count) places · on this phone"
                                   : isSwitching ? "Downloading…" : "v\(map.version) · downloads when chosen")
                        .font(.dsSubhead).foregroundStyle(surface.inkSecondary)
                }
                Spacer(minLength: 0)
                if isSwitching { ProgressView().tint(surface.accent) }
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .background(surface.fill, in: RoundedRectangle(cornerRadius: DS.R.row, style: .continuous))
            .dsStroke(isCurrent ? surface.accent : surface.stroke, isCurrent ? 2 : 1.5, radius: DS.R.row)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.switchingToSlug != nil)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
    }

    private func choose(_ map: RemoteMapSummary) {
        Task {
            await viewModel.switchMap(to: map.slug)
            dismiss()
        }
    }

    private func note(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle").foregroundStyle(surface.accent)
            Text(text).font(.dsSubhead).foregroundStyle(surface.inkSecondary)
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(surface.fill, in: RoundedRectangle(cornerRadius: DS.R.row, style: .continuous))
    }
}
