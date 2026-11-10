import SwiftUI

/// The camera view with SoCat leading, a header with the stop, and a card with
/// what to do next.
struct NUSGuideView: View {
    let viewModel: NavigationViewModel
    let guide: TourGuide
    let onStaff: () -> Void
    @State private var hint: SoCatHint = .hidden

    var body: some View {
        ZStack {
            SoCatARView(viewModel: viewModel, guide: guide) { hint = $0 }
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Spacer()
                if guide.phase == .leading, viewModel.localizationStatus.isReliable, hint == .left || hint == .right {
                    lookHint
                }
                card
            }
        }
        .preferredColorScheme(.light)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            NUSLogoMark(size: 34, onStaff: onStaff)
            VStack(alignment: .leading, spacing: 1) {
                Text(headerTitle).font(.headline).foregroundStyle(NUS.ink).lineLimit(1)
                if let sub = headerSubtitle {
                    Text(sub).font(.caption.weight(.semibold)).foregroundStyle(NUS.orange)
                }
            }
            Spacer()
            Button { guide.exit() } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundStyle(NUS.ink)
                    .frame(width: 40, height: 40)
                    .background(.white.opacity(0.9), in: Circle())
            }
            .accessibilityLabel("End")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private var headerTitle: String {
        guard let stop = guide.current else { return guide.phase == .finished ? "Tour complete" : "NUS Open House" }
        return stop.name
    }

    private var headerSubtitle: String? {
        guard let stop = guide.current else { return nil }
        let level = guide.levelName(of: stop.id)
        if guide.isTour {
            return ["Stop \(guide.index + 1) of \(guide.stops.count)", level].compactMap { $0 }.joined(separator: " · ")
        }
        return level
    }

    // MARK: Cards

    @ViewBuilder private var card: some View {
        switch guide.phase {
        case .leading: leadingCard
        case .arrived: arrivedCard
        case .finished: finishedCard
        case .home: EmptyView()
        }
    }

    private var leadingCard: some View {
        let reliable = viewModel.localizationStatus.isReliable
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: reliable ? instructionIcon : "camera.viewfinder")
                    .font(.title2)
                    .foregroundStyle(reliable ? NUS.orange : NUS.warn)
                Text(reliable ? instructionText : "Look around slowly so I can find where you are")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(NUS.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if reliable, viewModel.isNavigating {
                Text("\(max(1, Int(viewModel.remainingDistance.rounded()))) m to go · follow SoCat")
                    .font(.subheadline)
                    .foregroundStyle(NUS.inkSecondary)
            } else if !reliable {
                Text("Point your phone at walls, doors and signs.")
                    .font(.subheadline)
                    .foregroundStyle(NUS.inkSecondary)
            }
            if guide.isTour {
                Button("Skip this stop") { guide.skipStop() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(NUS.blue)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(NUS.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        .padding(16)
    }

    private var arrivedCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image("SoCatWave").resizable().scaledToFit().frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text("You've arrived!").font(.subheadline.weight(.semibold)).foregroundStyle(NUS.ok)
                    Text(guide.current?.name ?? "").font(.title2.weight(.bold)).foregroundStyle(NUS.ink)
                }
            }
            if let text = guide.current?.details ?? guide.current?.about, !text.isEmpty {
                Text(text).font(.body).foregroundStyle(NUS.inkSecondary).fixedSize(horizontal: false, vertical: true)
            }
            if guide.isTour && !guide.isLastStop {
                Button { guide.nextStop() } label: {
                    Label("Next: \(guide.stops[guide.index + 1].name)", systemImage: "arrow.right")
                }
                .buttonStyle(NUSButtonStyle(fill: NUS.orange))
            } else {
                Button { guide.isTour ? guide.nextStop() : guide.exit() } label: {
                    Text(guide.isTour ? "Finish the tour" : "Done")
                }
                .buttonStyle(NUSButtonStyle(fill: NUS.blue))
            }
        }
        .padding(18)
        .background(NUS.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        .padding(16)
    }

    private var finishedCard: some View {
        VStack(spacing: 12) {
            Image("SoCatWave").resizable().scaledToFit().frame(height: 80)
            Text("Tour complete!").font(.title.weight(.bold)).foregroundStyle(NUS.ink)
            Text("You've visited all \(guide.stops.count) stops. Thanks for exploring the NUS Open House with SoCat.")
                .multilineTextAlignment(.center)
                .foregroundStyle(NUS.inkSecondary)
            Button { guide.exit() } label: { Text("Back to start") }
                .buttonStyle(NUSButtonStyle(fill: NUS.blue))
        }
        .padding(20)
        .background(NUS.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        .padding(16)
    }

    private var lookHint: some View {
        HStack(spacing: 8) {
            if hint == .left { Image(systemName: "arrow.left") }
            Text("SoCat is to your \(hint == .left ? "left" : "right")")
            if hint == .right { Image(systemName: "arrow.right") }
        }
        .font(.headline)
        .foregroundStyle(.white)
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(NUS.blue.opacity(0.9), in: Capsule())
        .frame(maxWidth: .infinity, alignment: hint == .left ? .leading : .trailing)
        .padding(.horizontal, 16)
    }

    // MARK: Instruction

    /// The level change on the current leg, or on the next one when it is close.
    private var levelChangeText: String? {
        let path = viewModel.routePath
        let target = viewModel.routeLeg - 1
        guard target >= 0, target < path.count else { return nil }
        let levels = viewModel.engine.levels
        if target > 0, let text = levels.levelChangeText(from: path[target - 1], to: path[target]) { return text }
        if target + 1 < path.count, let text = levels.levelChangeText(from: path[target], to: path[target + 1]),
           let instruction = viewModel.currentInstruction, instruction.distance < 6 {
            return text
        }
        return nil
    }

    private var instructionText: String {
        if let text = levelChangeText { return text }
        guard let instruction = viewModel.currentInstruction else { return "Follow SoCat" }
        if viewModel.isOffRoute { return "Let's go back to SoCat" }
        return instruction.bannerText
    }

    private var instructionIcon: String {
        if levelChangeText != nil { return levelChangeText!.contains("lift") ? "arrow.up.arrow.down.square" : "figure.stairs" }
        switch viewModel.currentInstruction?.direction {
        case .left?, .slightLeft?, .sharpLeft?: return "arrow.turn.up.left"
        case .right?, .slightRight?, .sharpRight?: return "arrow.turn.up.right"
        case .uTurn?: return "arrow.uturn.down"
        default: return "arrow.up"
        }
    }
}
