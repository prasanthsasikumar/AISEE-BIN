//
// AiSeePhotoCapture.swift — AiSeeGlassKit
//
// One still: snapshot → getPictureData → stopCaptureTransfer. Adapted from the
// vendor demo's RtkGlassPhotoCapture with the side effects (tone player,
// photo library) removed. Only EMMC-busy (code 5) is retried; a transport
// timeout is not — re-shooting into a glass still recovering from a stalled
// transfer fails again (FINDINGS). Code 4 is the wedge and is surfaced as
// AiSeeError.deviceWedged.
//
// Called only by AiSeeDeviceCoordinator, which guarantees the mic is closed.
//

import Foundation

#if canImport(RTKAIDeviceConnection)
import RTKAIDeviceConnection

struct AiSeePhotoCapture {
    static let quality: UInt = 5
    static let pictureSize: (width: UInt, height: UInt) = (960, 640)
    static let emmcBusyCode = 5
    static let wedgedCode = 4
    static let maxAttempts = 3
    static let retryBackoffMs = 300
    /// Same settle the coordinator uses after closing the mic (400 + 300 ms, FINDINGS §1).
    static let voiceSettleMs = 700

    let connection: IntelligenceDeviceConnection
    let log: AiSeeLog

    func capture() async throws -> Data {
        var attempt = 0
        while true {
            attempt += 1
            // Belt-and-braces for FINDINGS §1: the coordinator closes the mic before
            // it gets here, but the glasses' own mic button can open voice input
            // behind its back. Shooting with it open is what wedges the device.
            if connection.mediaRoutine.isVoiceInputting {
                log("⚠️ device reports voice input active before shoot")
                try? await connection.mediaRoutine.stopInputAudioStream()
                try await Task.sleep(for: .milliseconds(Self.voiceSettleMs))
            }
            let t0 = Date()
            var phase = "shoot"
            do {
                let info = try await connection.mediaRoutine.snapshot(
                    quality: Self.quality, pictureSize: Self.pictureSize, playingTone: false)
                let shootMs = Self.ms(since: t0)
                phase = "transfer"
                let t1 = Date()
                let data: Data
                do {
                    data = try await connection.mediaRoutine.getPictureData(with: info)
                    try? await connection.mediaRoutine.stopCaptureTransfer()
                } catch {
                    try? await connection.mediaRoutine.stopCaptureTransfer()
                    throw error
                }
                log("✅ photo OK: shoot \(shootMs)ms + transfer \(Self.ms(since: t1))ms (\(data.count) bytes)")
                if data.count != Int(info.fileLen) {
                    log("⚠️ photo size mismatch: got \(data.count) bytes, device reported \(info.fileLen)")
                }
                return data
            } catch DeviceFailure.failure(let code) where code == Self.emmcBusyCode && attempt < Self.maxAttempts {
                log("⏳ photo \(phase) EMMC busy after \(Self.ms(since: t0))ms — retry \(attempt)/\(Self.maxAttempts)")
                try await Task.sleep(for: .milliseconds(Self.retryBackoffMs))
            } catch DeviceFailure.failure(let code) where code == Self.wedgedCode {
                log("❌ photo \(phase) FAILED after \(Self.ms(since: t0))ms: device status 4 — WEDGED, power-cycle the glasses")
                throw AiSeeError.deviceWedged
            } catch {
                log("❌ photo \(phase) FAILED after \(Self.ms(since: t0))ms: \(error)")
                throw AiSeeError.sdk(error)
            }
        }
    }

    private static func ms(since start: Date) -> Int { Int(Date().timeIntervalSince(start) * 1000) }
}
#endif
