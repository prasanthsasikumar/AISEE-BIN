import AVFoundation
import Foundation

/// Plays the beacon: a looped, synthesized pattern per `BeaconCue`, panned
/// left or right, on the audio session `GuidanceManager` already configured
/// (A2DP to the glasses, else the loudspeaker). Contains no decisions about
/// *when* to sound; `BeaconPolicy` makes those.
///
/// Each pattern is one period of audio (beeps then silence) scheduled with
/// `.loops`, so the cadence is sample-accurate and needs no timer, and a
/// change of cue is a stop and a new schedule.
@MainActor
final class BeaconSynth {

    /// False when the engine could not start; the beacon then stays silent.
    private(set) var isAvailable = true

    private let engine = AVAudioEngine()
    private let loop = AVAudioPlayerNode()
    private let oneShot = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private let onCourseBuffer: AVAudioPCMBuffer
    private let offLeftBuffer: AVAudioPCMBuffer
    private let offRightBuffer: AVAudioPCMBuffer
    private let boundaryBuffer: AVAudioPCMBuffer

    private var cue: BeaconCue = .silent
    private var paused = false
    private var observers: [NSObjectProtocol] = []

    init() {
        let r = Renderer(format: format)
        // On course: one short high tick every 0.6 s.
        onCourseBuffer = r.period(0.6, notes: [(0, 0.06, 880)])
        // Off course: a low pattern every 1.2 s. Left = two quick ticks, right = one long tone,
        // mirroring the turn haptics (two taps left, one long buzz right).
        offLeftBuffer = r.period(1.2, notes: [(0, 0.06, 440), (0.16, 0.06, 440)])
        offRightBuffer = r.period(1.2, notes: [(0, 0.30, 440)])
        // Boundary: three descending notes, once.
        boundaryBuffer = r.period(0.6, notes: [(0, 0.12, 330), (0.18, 0.12, 277), (0.36, 0.12, 220)])

        engine.attach(loop)
        engine.attach(oneShot)
        engine.connect(loop, to: engine.mainMixerNode, format: format)
        engine.connect(oneShot, to: engine.mainMixerNode, format: format)

        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return }
            MainActor.assumeIsolated { self?.restart() }
        })
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            // Output route changed (glasses connected or dropped): the engine stops itself.
            MainActor.assumeIsolated { self?.restart() }
        })
    }

    deinit {
        for o in observers { NotificationCenter.default.removeObserver(o) }
    }

    // MARK: - Control

    /// Idempotent: the same cue twice leaves the loop running untouched.
    func apply(_ cue: BeaconCue) {
        guard cue != self.cue else { return }
        self.cue = cue
        restartLoop()
    }

    /// Pauses while the app speaks or listens; the cue is kept and resumes.
    func setPaused(_ paused: Bool) {
        guard paused != self.paused else { return }
        self.paused = paused
        restartLoop()
    }

    /// The corridor earcon, once, centred. The loop stops for it and comes back
    /// on the next `apply`/`setPaused` change (speech follows, which pauses it).
    func playBoundary() {
        guard ensureRunning() else { return }
        loop.stop()
        oneShot.stop()
        oneShot.pan = 0
        oneShot.scheduleBuffer(boundaryBuffer, at: nil, options: [], completionHandler: nil)
        oneShot.play()
    }

    /// Silence and release the engine (route ended, beacon switched off).
    func stop() {
        cue = .silent
        paused = false
        loop.stop()
        oneShot.stop()
        if engine.isRunning { engine.stop() }
    }

    // MARK: - Internals

    private func restart() {
        guard cue != .silent else { return }
        restartLoop()
    }

    private func restartLoop() {
        loop.stop()
        guard !paused, cue != .silent, ensureRunning() else {
            if cue == .silent, engine.isRunning, !oneShot.isPlaying { engine.stop() }
            return
        }
        let buffer: AVAudioPCMBuffer
        let pan: Float
        switch cue {
        case .silent:
            return
        case .onCourse:
            buffer = onCourseBuffer; pan = 0
        case .offCourse(let side, let p):
            buffer = side == .left ? offLeftBuffer : offRightBuffer; pan = p
        }
        loop.pan = pan
        loop.scheduleBuffer(buffer, at: nil, options: [.loops], completionHandler: nil)
        loop.play()
    }

    private func ensureRunning() -> Bool {
        if engine.isRunning { return true }
        do {
            try engine.start()
            isAvailable = true
            return true
        } catch {
            print("BeaconSynth: engine failed to start: \(error)")
            isAvailable = false
            return false
        }
    }

    // MARK: - Synthesis

    /// Renders one period of mono PCM: sine notes with a 5 ms ramp at each end so
    /// nothing clicks, then silence to the end of the period.
    private struct Renderer {
        let format: AVAudioFormat
        let amplitude: Float = 0.3

        func period(_ seconds: Double, notes: [(start: Double, duration: Double, hz: Double)]) -> AVAudioPCMBuffer {
            let rate = format.sampleRate
            let frames = AVAudioFrameCount(seconds * rate)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
            buffer.frameLength = frames
            let out = buffer.floatChannelData![0]
            for i in 0..<Int(frames) { out[i] = 0 }
            let ramp = Int(0.005 * rate)
            for note in notes {
                let first = Int(note.start * rate)
                let count = Int(note.duration * rate)
                for n in 0..<count where first + n < Int(frames) {
                    let envelope = min(1, Float(n) / Float(ramp), Float(count - n) / Float(ramp))
                    let phase = 2 * Double.pi * note.hz * Double(n) / rate
                    out[first + n] = amplitude * envelope * Float(sin(phase))
                }
            }
            return buffer
        }
    }
}
