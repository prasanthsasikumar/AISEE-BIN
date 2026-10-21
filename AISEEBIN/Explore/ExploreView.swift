import SwiftUI

/// Explore mode's root: one screen per visit phase, light theme, no staff chrome.
/// Staff leave with five quick taps on the AiSee logo at the top of any screen.
struct ExploreView: View {
    @State private var model: ExploreViewModel

    init(nav: NavigationViewModel) {
        _model = State(initialValue: ExploreViewModel(nav: nav))
    }

    var body: some View {
        Group {
            switch model.phase {
            case .welcome: ExploreWelcomeView(model: model)
            case .preview: ExplorePreviewView(model: model)
            case .walking: ExploreWalkingView(model: model)
            case .arrived(let index): ExploreArrivedView(model: model, stopIndex: index)
            case .complete: ExploreCompleteView(model: model)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(EX.canvas.ignoresSafeArea())
        .environment(\.colorScheme, .light)
        .onAppear {
            model.enter()
            #if DEBUG
            // Screenshots: `-exploreDemo preview|complete` plans 20 minutes on whatever map is loaded.
            if let demo = UserDefaults.standard.string(forKey: "exploreDemo") { model.demo(demo) }
            #endif
        }
        .fullScreenCover(isPresented: $model.isAskOpen) {
            ExploreAskView(model: model)
        }
        .animation(.easeInOut(duration: 0.25), value: model.phase)
    }
}

// MARK: - Welcome

struct ExploreWelcomeView: View {
    @Bindable var model: ExploreViewModel
    @State private var minutes: Double = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            EXHeader(model: model)
                .padding(.bottom, 28)

            Text("Flower Dome").dsEyebrow(EX.accent)
            Text("How much time do you have?")
                .font(.dsDisplay)
                .foregroundStyle(EX.ink)
                .padding(.top, 6).padding(.bottom, 24)

            if model.hasTour {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(ExploreViewModel.timeChoices, id: \.self) { choice in
                        timeButton(choice)
                    }
                }
                speakRow.padding(.top, 20)
                if let message = model.message {
                    Text(message).font(.dsSubhead).foregroundStyle(DS.A.warnText).padding(.top, 10)
                }
                Spacer(minLength: 20)
                EXPrimaryButton(title: "Plan my visit") { model.choose(minutes: minutes) }
            } else {
                EXCard {
                    Text("This map has no tour yet.").font(.dsHeadline).foregroundStyle(EX.ink)
                    Text("Ask a member of staff to load the Flower Dome map.").font(.dsSubhead).foregroundStyle(EX.inkSecondary)
                }
                Spacer()
            }
            Text("Your questions are answered by AI. We keep the words, not the photos, to improve the guide.")
                .font(.dsFootnote).foregroundStyle(EX.inkMuted)
                .padding(.top, 14)
        }
        .padding(.horizontal, 24).padding(.vertical, 20)
    }

    private func timeButton(_ choice: Double) -> some View {
        let selected = minutes == choice
        return Button { minutes = choice } label: {
            VStack(spacing: 2) {
                Text(choice >= 45 ? "45+" : "\(Int(choice))").font(.system(size: 30, weight: .bold, design: .rounded))
                Text("min").font(.dsFootnote).foregroundStyle(selected ? EX.accent : EX.inkMuted)
            }
            .foregroundStyle(selected ? DS.A.lavenderDeep : EX.ink)
            .frame(maxWidth: .infinity, minHeight: 88)
            .background(selected ? EX.accentSoft : EX.card, in: RoundedRectangle(cornerRadius: DS.R.panel, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.R.panel, style: .continuous)
                .strokeBorder(selected ? EX.accent : EX.hairline, lineWidth: selected ? 2 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var speakRow: some View {
        Button { model.listenForTime() } label: {
            HStack(spacing: 12) {
                Image(systemName: model.isListening ? "waveform" : "mic.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .symbolEffect(.variableColor.iterative, isActive: model.isListening)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(EX.accent, in: Circle())
                Group {
                    if model.isPlanningFromSpeech {
                        HStack { ProgressView(); Text("Planning…") }
                    } else if model.isListening {
                        Text(model.liveTranscript.isEmpty ? "Listening…" : "“\(model.liveTranscript)”")
                    } else {
                        Text("Or just say it: ") + Text("“About 20 minutes”").bold()
                    }
                }
                .font(.dsSubhead).foregroundStyle(EX.inkSecondary)
                .lineLimit(2)
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(EX.card, in: RoundedRectangle(cornerRadius: DS.R.field, style: .continuous))
            .dsStroke(EX.hairline, radius: DS.R.field)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

struct ExplorePreviewView: View {
    @Bindable var model: ExploreViewModel
    @State private var showingAdd = false

    var body: some View {
        let plan = model.plan
        VStack(alignment: .leading, spacing: 14) {
            EXHeader(model: model) {
                Button { model.backToWelcome() } label: {
                    Label("Change time", systemImage: "clock.arrow.circlepath").font(.dsSubhead.weight(.semibold))
                }
                .tint(EX.accent)
            }
            Text("Your \(Int(model.budgetMinutes))-minute visit").dsEyebrow(EX.accent)

            TourMapView(map: model.map, stopIDs: plan?.stopIDs ?? [], routePath: model.tourPath,
                        startID: plan?.startID, endID: plan?.endID)
                .frame(height: 190)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(Array((plan?.stopIDs ?? []).enumerated()), id: \.element) { index, id in
                        stopRow(index: index, id: id)
                    }
                    if !model.addableStops.isEmpty {
                        Button { showingAdd = true } label: {
                            Label("Add a stop", systemImage: "plus")
                                .font(.dsSubhead.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .foregroundStyle(EX.accent)
                                .background(EX.accentSoft, in: RoundedRectangle(cornerRadius: DS.R.row, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if let plan {
                if plan.totalMinutes > model.budgetMinutes {
                    Label("A bit over your time", systemImage: "clock.badge.exclamationmark")
                        .font(.dsSubhead.weight(.semibold)).foregroundStyle(DS.A.warnText)
                }
                let total = Int(plan.totalMinutes.rounded())
                EXPrimaryButton(title: plan.stopIDs.isEmpty ? "Straight to the end · about \(total) min"
                                                             : "Start · about \(total) min") { model.start() }
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
        .sheet(isPresented: $showingAdd) { addSheet }
    }

    private func stopRow(index: Int, id: String) -> some View {
        let poi = model.poi(id)
        return HStack(spacing: 12) {
            Text("\(index + 1)")
                .font(.dsSubhead.weight(.bold)).foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(EX.accent, in: Circle())
            Text(poi?.name ?? id).font(.dsHeadline).foregroundStyle(EX.ink)
            Spacer()
            Text("\(Int((poi?.visitMinutes ?? 3).rounded())) min").font(.dsSubhead).foregroundStyle(EX.inkMuted)
            Button { model.drop(id) } label: {
                Image(systemName: "xmark").font(.dsSubhead.weight(.semibold)).foregroundStyle(EX.inkMuted)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(poi?.name ?? id)")
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(EX.card, in: RoundedRectangle(cornerRadius: DS.R.row, style: .continuous))
        .dsStroke(EX.hairline, radius: DS.R.row)
    }

    private var addSheet: some View {
        NavigationStack {
            List(model.addableStops) { poi in
                Button {
                    model.add(poi.id)
                    showingAdd = false
                } label: {
                    HStack {
                        Text(poi.name).foregroundStyle(EX.ink)
                        Spacer()
                        Text("\(Int(poi.visitMinutes.rounded())) min").foregroundStyle(EX.inkMuted)
                    }
                }
            }
            .navigationTitle("Add a stop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { showingAdd = false } } }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Walking

struct ExploreWalkingView: View {
    @Bindable var model: ExploreViewModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 10)) { timeline in
            let now = timeline.date
            VStack(alignment: .leading, spacing: 14) {
                EXHeader(model: model) {
                    EXPill(systemImage: "timer", text: "\(max(0, Int(model.minutesLeft(now: now).rounded()))) min left")
                }

                TourMapView(map: model.map, stopIDs: model.plan?.stopIDs ?? [],
                            routePath: model.nav.routePath.isEmpty ? model.tourPath : model.nav.routePath,
                            pose: model.nav.mapPose, highlightID: model.currentTargetID,
                            startID: model.plan?.startID, endID: model.plan?.endID)
                    .frame(maxHeight: .infinity)

                if let offer = model.lateOffer(now: now) {
                    lateCard(offer)
                }
                nextCard

                // Equal side columns keep Ask centred whatever the captions say.
                HStack(alignment: .center, spacing: 0) {
                    EXSideButton(systemImage: model.voiceDirections ? "speaker.wave.2.fill" : "speaker.slash.fill",
                                 title: model.voiceDirections ? "Voice on" : "Voice off",
                                 on: model.voiceDirections) { model.voiceDirections.toggle() }
                        .accessibilityLabel("Voice directions")
                        .accessibilityValue(model.voiceDirections ? "On" : "Off")
                        .frame(maxWidth: .infinity)
                    EXAskButton(listening: false) { model.openAsk() }
                    EXSideButton(systemImage: "flag.checkered", title: "End visit") { model.endVisit() }
                        .frame(maxWidth: .infinity)
                }
                .padding(.top, 4)
                Text("Tap and ask about anything you see")
                    .font(.dsFootnote).foregroundStyle(EX.inkMuted)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
        }
    }

    private var stopLabel: String {
        let count = model.plan?.stopIDs.count ?? 0
        return model.isHeadingToEnd ? "Last leg" : "Stop \(model.stopIndex + 1) of \(count)"
    }

    private var nextCard: some View {
        let target = model.currentTargetID.flatMap(model.poi)
        let reliable = model.nav.localizationStatus.isReliable
        return EXCard {
            VStack(alignment: .leading, spacing: 4) {
                if reliable, model.nav.remainingDistance > 0 {
                    Text("\(stopLabel) · \(Int(model.nav.remainingDistance.rounded())) m ahead").dsEyebrow(EX.accent)
                } else {
                    Text(stopLabel).dsEyebrow(EX.accent)
                }
                Text(target?.name ?? "").font(.dsTitle2).foregroundStyle(EX.ink)
                Text(reliable ? (model.nav.currentInstruction?.bannerText ?? "Follow the purple line.")
                              : "Finding where you are. Hold the phone up and look around slowly.")
                    .font(.dsSubhead).foregroundStyle(EX.inkSecondary)
            }
        }
    }

    private func lateCard(_ poi: NavigationPOI) -> some View {
        EXCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("Running late: skip \(poi.name)?", systemImage: "clock")
                    .font(.dsHeadline).foregroundStyle(DS.A.warnText)
                HStack {
                    Button("Skip it") { model.skip(poi.id) }.buttonStyle(.borderedProminent).tint(EX.accent)
                    Button("Keep it") { model.keep(poi.id) }.buttonStyle(.bordered).tint(EX.inkSecondary)
                }
            }
        }
    }
}

// MARK: - Arrived

struct ExploreArrivedView: View {
    @Bindable var model: ExploreViewModel
    let stopIndex: Int

    var body: some View {
        let id = model.plan?.stopIDs[safe: stopIndex]
        let poi = id.flatMap(model.poi)
        let isLast = stopIndex + 1 >= (model.plan?.stopIDs.count ?? 0)
        VStack(alignment: .leading, spacing: 16) {
            EXHeader(model: model) {
                EXPill(systemImage: "checkmark.circle.fill", text: "Stop \(stopIndex + 1) of \(model.plan?.stopIDs.count ?? 0)")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let photo = poi?.photo, let url = URL(string: photo) {
                        AsyncImage(url: url) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            EX.mapGround
                        }
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: DS.R.panel, style: .continuous))
                    }
                    Text("You've reached").dsEyebrow(EX.accent)
                    Text(poi?.name ?? "").font(.dsDisplay).foregroundStyle(EX.ink)
                    if let details = poi?.details, !details.isEmpty {
                        Text(details).font(.dsBody).foregroundStyle(EX.inkSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 18) {
                EXAskButton(size: 72) { model.openAsk() }
                    .padding(.leading, 8)
                EXPrimaryButton(title: isLast ? "Finish the visit" : "Next stop") { model.nextStop() }
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
    }
}

// MARK: - Complete

struct ExploreCompleteView: View {
    @Bindable var model: ExploreViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            EXHeader(model: model)
                .padding(.bottom, 12)
            Text("Flower Dome").dsEyebrow(EX.accent)
            Text("That's your visit").font(.dsDisplay).foregroundStyle(EX.ink)
            if let stops = model.plan?.stopIDs, !stops.isEmpty {
                EXCard {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(stops.enumerated()), id: \.element) { i, id in
                            Label(model.poi(id)?.name ?? id, systemImage: "\(i + 1).circle.fill")
                                .font(.dsBody).foregroundStyle(EX.ink)
                        }
                    }
                }
            }
            Spacer()
            VStack(spacing: 16) {
                EXAskButton { model.openAsk() }
                Text("Still curious? Ask about anything you see.").font(.dsFootnote).foregroundStyle(EX.inkMuted)
            }
            .frame(maxWidth: .infinity)
            Spacer()
            EXPrimaryButton(title: "Start a new visit") { model.newVisit() }
        }
        .padding(.horizontal, 24).padding(.vertical, 20)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
