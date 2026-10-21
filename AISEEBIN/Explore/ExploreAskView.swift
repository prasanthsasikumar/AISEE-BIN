import ARKit
import SwiftUI

/// Point, tap, ask: the live camera with the answer as a caption, spoken as it
/// streams in. Tap the camera (or the button) to ask again; swipe down or ✕ to go back.
struct ExploreAskView: View {
    @Bindable var model: ExploreViewModel
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        ZStack {
            camera
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { model.ask() }

            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(.white.opacity(0.85), lineWidth: 2)
                .frame(width: 200, height: 200)
                .offset(y: -120)
                .allowsHitTesting(false)

            VStack {
                HStack {
                    Spacer()
                    Button { model.closeAsk() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(EX.ink)
                            .frame(width: 44, height: 44)
                            .background(.white.opacity(0.92), in: Circle())
                    }
                    .accessibilityLabel("Close")
                }
                .padding(.horizontal, 20)
                Spacer()
                caption
                    .padding(.horizontal, 14)
                EXAskButton(listening: model.isListening, size: 84) { model.ask() }
                    .padding(.top, 14).padding(.bottom, 8)
            }
        }
        .offset(y: dragOffset)
        .gesture(DragGesture()
            .onChanged { dragOffset = max(0, $0.translation.height) }
            .onEnded { value in
                if value.translation.height > 120 { model.closeAsk() }
                dragOffset = 0
            })
        .environment(\.colorScheme, .light)
    }

    @ViewBuilder private var camera: some View {
        if ARNavigationManager.isSupported {
            ARPreviewView(session: model.nav.arManager.session, showFeaturePoints: false)
        } else {
            LinearGradient(colors: [Color(dsHex: 0x2D4A2F), Color(dsHex: 0x5D7B3C), Color(dsHex: 0xA6874A)],
                           startPoint: .top, endPoint: .bottom)
        }
    }

    @ViewBuilder private var caption: some View {
        let content: (question: String?, body: String, busy: Bool)? = {
            if model.isListening {
                return (nil, model.liveTranscript.isEmpty ? "Listening… ask about what you see." : "“\(model.liveTranscript)”", false)
            }
            switch model.askState {
            case .idle: return (nil, "Point at something and tap to ask.", false)
            case .thinking(let q): return (q, "", true)
            case .answering(let q, let text): return (q, text, false)
            case .failed(let q): return (q, ExploreViewModel.failureText, false)
            }
        }()
        if let content {
            VStack(alignment: .leading, spacing: 6) {
                if let q = content.question {
                    Text("“\(q)”").font(.dsSubhead.weight(.semibold)).foregroundStyle(EX.accent)
                }
                if content.busy {
                    HStack(spacing: 8) { ProgressView(); Text("Thinking…").foregroundStyle(EX.inkSecondary) }
                        .font(.dsBody)
                } else {
                    Text(content.body).font(.dsBody).foregroundStyle(EX.ink)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.96), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .onTapGesture { model.closeAsk() }
            .animation(.easeOut(duration: 0.2), value: content.body)
        }
    }
}
