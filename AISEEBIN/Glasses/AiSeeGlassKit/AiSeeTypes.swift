//
// AiSeeTypes.swift — AiSeeGlassKit
//
// Vendor-free value types shared by the kit and its consumers. Foundation +
// UIKit/CoreVideo only, so the Hermes simulator build compiles this file.
//

import CoreImage
import CoreVideo
import Foundation
import UIKit

enum AiSeeConnectionState: Equatable {
    case disconnected
    case scanning
    case connecting
    case connected(name: String)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

struct AiSeeDiscoveredDevice: Identifiable, Equatable {
    let id: UUID          // CBPeripheral.identifier
    let name: String
    let rssi: Int
}

/// One decoded frame from the glasses camera. Mirrors Hermes's `VisionFrame`.
///
/// The UIImage is rendered lazily on first access and cached, because most
/// consumers (Hermes) only ever want the pixel buffer — rendering a CGImage for
/// every decoded frame at 30 fps was pure waste. `image` stays the accessor
/// name, so callers are unchanged.
struct AiSeeFrame {
    let pixelBuffer: CVPixelBuffer?
    private let cache: ImageCache

    init(pixelBuffer: CVPixelBuffer?) {
        self.pixelBuffer = pixelBuffer
        self.cache = ImageCache()
    }

    var image: UIImage? { cache.image(pixelBuffer) }

    /// Shared because CIContext is expensive to build and safe to use from
    /// several threads; frames are decoded on the SDK's thread and read on the main one.
    private static let ciContext = CIContext()

    /// Renders once, under a lock, and hands out the same UIImage afterwards.
    private final class ImageCache: @unchecked Sendable {
        // @unchecked: every access to `rendered`/`didRender` goes through `lock`.
        private let lock = NSLock()
        private var rendered: UIImage?
        private var didRender = false

        func image(_ pixelBuffer: CVPixelBuffer?) -> UIImage? {
            lock.withLock {
                if didRender { return rendered }
                didRender = true
                if let pixelBuffer {
                    let ci = CIImage(cvPixelBuffer: pixelBuffer)
                    if let cg = AiSeeFrame.ciContext.createCGImage(ci, from: ci.extent) {
                        rendered = UIImage(cgImage: cg)
                    }
                }
                return rendered
            }
        }
    }
}

enum AiSeeError: LocalizedError {
    case notConnected
    case captureInProgress
    case streamUnavailable
    /// `DeviceFailure.failure(code: 4)`: the camera refuses every shot until the
    /// glasses are power-cycled (FINDINGS §1).
    case deviceWedged
    case sdk(Error)

    var errorDescription: String? {
        switch self {
        case .notConnected: return "AiSee glasses are not connected."
        case .captureInProgress: return "A photo capture is already in progress."
        case .streamUnavailable: return "Could not open the AiSee live stream."
        case .deviceWedged: return "AiSee camera stopped responding — restart your glasses."
        case .sdk(let error): return error.localizedDescription
        }
    }
}

/// Diagnostic line sink. Every kit component takes one so the sample app's log
/// pane and Hermes's bridge log see the same text.
typealias AiSeeLog = @Sendable (String) -> Void
