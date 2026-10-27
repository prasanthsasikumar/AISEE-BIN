import SwiftUI

/// The visitor start screen, for blind and sighted visitors alike: one big talk
/// control that understands both "I have 20 minutes" and "take me to the
/// orchids", and two large choices for anyone who would rather tap. Dark and
/// high-contrast like Navigate, so a helper can read it in greenhouse sun.
struct WelcomeView: View {
    @Bindable var viewModel: NavigationViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Welcome to \(viewModel.mapName)")
                    .font(.dsDisplay).foregroundStyle(DS.N.ink)
                    .accessibilityAddTraits(.isHeader)
                Text("Tell me what you'd like to do, or choose below.")
                    .font(.dsBody).foregroundStyle(DS.N.inkSecondary)
            }
            .padding(.top, 8)

            Spacer(minLength: 0)

            if viewModel.isListening {
                TranscriptPanel(transcript: viewModel.recognizer.transcript)
            }

            TalkButton(isListening: viewModel.isListening,
                       transcript: viewModel.recognizer.transcript,
                       hint: "“I have 20 minutes” · “Take me to the orchids”") {
                viewModel.listenOnWelcome()
            }

            HStack(spacing: 12) {
                choice(title: "Plan my visit", detail: "A tour that fits your time",
                       icon: "clock.fill", tint: DS.N.accent) { viewModel.mode = .explore }
                choice(title: "Take me somewhere", detail: "Spoken directions to one place",
                       icon: "figure.walk", tint: DS.N.okText) { viewModel.mode = .navigation }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DS.N.canvas)
    }

    private func choice(title: String, detail: String, icon: String, tint: Color,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon).font(.dsTitle2).foregroundStyle(tint)
                Text(title).font(.dsTitle3.weight(.bold)).foregroundStyle(DS.N.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail).font(.dsSubhead).foregroundStyle(DS.N.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .background(DS.N.raised, in: RoundedRectangle(cornerRadius: DS.R.card, style: .continuous))
            .dsStroke(DS.N.hairline, 1.5, radius: DS.R.card)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(detail)")
        .accessibilityAddTraits(.isButton)
    }
}
