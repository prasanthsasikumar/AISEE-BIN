import ARKit
import SceneKit
import SwiftUI

/// Renders the live camera feed of the shared `ARSession`. The user rarely looks
/// at the screen (chest mount), so this exists mainly for setup and debugging.
struct ARPreviewView: UIViewRepresentable {
    let session: ARSession
    var showFeaturePoints: Bool

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.session = session
        view.automaticallyUpdatesLighting = false
        view.rendersContinuously = true
        view.isAccessibilityElement = false
        return view
    }

    func updateUIView(_ view: ARSCNView, context: Context) {
        view.debugOptions = showFeaturePoints ? [.showFeaturePoints] : []
    }
}
