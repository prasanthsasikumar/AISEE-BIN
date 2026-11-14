import SwiftUI

/// The camera view with arrows on the floor, a small map, a header with the
/// stop, and a card with what to do next.
struct NUSGuideView: View {
    let viewModel: NavigationViewModel
    let guide: TourGuide
    let onStaff: () -> Void
    @State private var hint: RouteHint = .hidden

    var body: some View {
        ZStack {
            RouteARView(viewModel: viewModel, guide: guide) { hint = $0 }
                .ignoresSafeArea()

            let cue = RouteCue(viewModel: viewModel, pose: viewModel.mapPose)
            VStack(spacing: 0) {
                header
                if guide.phase == .leading, viewModel.localizationStatus.isReliable, let pose = viewModel.mapPose {
                    NUSMiniMap(map: viewModel.displayMap, levels: viewModel.engine.levels, pose: pose,
                               cue: cue, destinationID: guide.current?.id)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.horizontal, 12)
                        .padding(.top, 10)
                }
                Spacer()
                if let notice = guide.notice {
                    noticeBanner(notice)
                } else if guide.phase == .leading, cue != nil, hint == .left || hint == .right || hint == .down {
                    lookHint
                }
                card(cue)
            }
            .animation(.snappy, value: guide.notice)
        }
        .preferredColorScheme(.light)
        .onChange(of: viewModel.localizationStatus.isReliable) { _, reliable in
            if reliable { guide.positionIsReliable() }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            // No logo here: the lockup is too wide to sit beside the stop's name. It is on the home screen.
            VStack(alignment: .leading, spacing: 1) {
                Text(headerTitle).font(.headline).foregroundStyle(NUS.ink).lineLimit(1)
                if let sub = headerSubtitle {
                    Text(sub).font(.caption.weight(.semibold)).foregroundStyle(NUS.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .staffTaps(onStaff)
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
        .background(.white.opacity(0.9))
    }

    private var headerTitle: String {
        if guide.startPending { return "Finding where you are" }
        guard let stop = guide.current else { return guide.phase == .finished ? "Tour complete" : "NUS Computing Tour" }
        return stop.name
    }

    private var headerSubtitle: String? {
        if guide.startPending { return "The tour starts from the nearest stop" }
        guard let stop = guide.current else { return nil }
        let level = guide.levelName(of: stop.id)
        if guide.isTour {
            return ["Stop \(guide.index + 1) of \(guide.stops.count)", level].compactMap { $0 }.joined(separator: " · ")
        }
        return level
    }

    // MARK: Cards

    @ViewBuilder private func card(_ cue: RouteCue?) -> some View {
        switch guide.phase {
        case .leading:
            if let cue, let text = cue.stairsText, let run = cue.run { stairsCard(text, run: run, cue: cue) } else { leadingCard }
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
                Text("\(max(1, Int(viewModel.remainingDistance.rounded()))) m to \(guide.current?.name ?? "go") · follow the arrows")
                    .font(.subheadline)
                    .foregroundStyle(NUS.inkSecondary)
            } else if !reliable {
                Text("Point your phone at walls, doors and signs.")
                    .font(.subheadline)
                    .foregroundStyle(NUS.inkSecondary)
            }
            skipButton
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(NUS.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        .padding(16)
    }

    @ViewBuilder private var skipButton: some View {
        if guide.isTour && !guide.startPending {
            Button(guide.isLastStop ? "Skip and finish the tour" : "Skip to \(guide.stops[guide.index + 1].name)") { guide.skipStop() }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(NUS.blue)
                .frame(minHeight: 32)
        }
    }

    /// Stairs or a lift are next: a card of its own, big enough to read at a glance.
    private func stairsCard(_ text: String, run: StairRun, cue: RouteCue) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: run.kind == .lift ? "arrow.up.arrow.down.square.fill" : "figure.stairs")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 68, height: 68)
                        .background(NUS.blue, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    Image(systemName: run.up ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white, NUS.orange)
                        .offset(x: 8, y: -8)
                }
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(text)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(NUS.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(stairsDetail(cue))
                        .font(.subheadline)
                        .foregroundStyle(NUS.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            skipButton
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(NUS.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        .padding(16)
    }

    private func stairsDetail(_ cue: RouteCue) -> String {
        let place = guide.current?.name ?? "the next stop"
        let onLevel = "\(place) is on Level \(guide.current.map { viewModel.engine.levels.level(of: $0.id) } ?? cue.run?.toLevel ?? 1)"
        if case .stairsAhead(_, let metres) = cue.stage, metres > 2 {
            return "\(Int(metres.rounded())) m ahead · \(onLevel)"
        }
        return onLevel
    }

    private func noticeBanner(_ text: String) -> some View {
        Label(text, systemImage: "forward.end.fill")
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 18).padding(.vertical, 12)
            .background(NUS.blue, in: Capsule())
            .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
            .padding(.horizontal, 16)
            .transition(.move(edge: .bottom).combined(with: .opacity))
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
            Text("You've visited all \(guide.stops.count) stops. Thanks for exploring NUS Computing.")
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
            if hint == .down { Image(systemName: "arrow.down") }
            Text(hint == .down ? "Tilt your phone down to see the arrows" : "Turn \(hint == .left ? "left" : "right") to see the arrows")
            if hint == .right { Image(systemName: "arrow.right") }
        }
        .font(.headline)
        .foregroundStyle(.white)
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(NUS.blue.opacity(0.9), in: Capsule())
        .frame(maxWidth: .infinity, alignment: hint == .left ? .leading : hint == .right ? .trailing : .center)
        .padding(.horizontal, 16)
    }

    // MARK: Instruction

    private var instructionText: String {
        guard let instruction = viewModel.currentInstruction else { return "Follow the arrows" }
        if viewModel.isOffRoute { return "Head back to the arrows" }
        return instruction.bannerText
    }

    private var instructionIcon: String {
        switch viewModel.currentInstruction?.direction {
        case .left?, .slightLeft?, .sharpLeft?: return "arrow.turn.up.left"
        case .right?, .slightRight?, .sharpRight?: return "arrow.turn.up.right"
        case .uTurn?: return "arrow.uturn.down"
        default: return "arrow.up"
        }
    }
}
