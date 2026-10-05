import AVFoundation
import CoreHaptics
import Foundation
import Observation
import UIKit

/// Distinct tactile signatures so a user can tell cues apart without looking.
///
/// - `nodeReached`: one firm tap.
/// - `turnLeft`: two quick soft taps.
/// - `turnRight`: one long buzz.
/// - `offRoute`: three low rumbles (also used for "relocalizing").
/// - `arrived`: rising triple tap with a tail.
enum HapticPattern {
    case nodeReached, turnLeft, turnRight, offRoute, arrived
}

/// Turns `GuidanceCue`s into speech and haptics (`CoreHaptics`). Phrases with a
/// recorded clip (`VoiceClips`) play the clip; everything else goes to
/// `AVSpeechSynthesizer`. Contains no throttling logic; that lives in `GuidancePolicy`.
@MainActor
@Observable
final class GuidanceManager: NSObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {

    private(set) var isSpeaking = false
    private(set) var lastSpokenText = ""
    private(set) var hapticsAvailable = false
    var isMuted = false

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private let clips = VoiceClips.bundled
    /// One queue for clips and synthesized speech, so a clip waits behind a
    /// sentence the synthesizer is still reading and the other way round.
    @ObservationIgnored private var pending: [String] = []
    @ObservationIgnored private var currentUtterance: AVSpeechUtterance?
    @ObservationIgnored private var clipPlayer: AVAudioPlayer?
    @ObservationIgnored private var hapticEngine: CHHapticEngine?
    @ObservationIgnored private let fallbackImpact = UIImpactFeedbackGenerator(style: .heavy)
    @ObservationIgnored private let fallbackNotification = UINotificationFeedbackGenerator()

    /// Speech rate slightly below default reads more clearly over greenhouse noise.
    @ObservationIgnored private let voiceRate: Float = AVSpeechUtteranceDefaultSpeechRate * 0.92

    override init() {
        super.init()
        synthesizer.delegate = self
        configureAudioSession()
        prepareHaptics()
    }

    // MARK: - Cue dispatch

    func deliver(_ cue: GuidanceCue) {
        switch cue {
        case .approaching(let instruction):
            play(hapticFor: instruction.direction)
            speak(instruction.spokenText, interrupt: true)

        case .nodeReached(let instruction):
            play(.nodeReached)
            speak(instruction.spokenText, interrupt: true)

        case .arrived(let name):
            play(.arrived)
            speak("You have arrived at the \(name).", interrupt: true)

        case .progress(let instruction):
            speak(instruction.spokenText, interrupt: false)

        case .offRoute:
            play(.offRoute)
            speak("You are off route. Recalculating.", interrupt: true)

        case .relocalizing:
            play(.offRoute)
            speak("Tracking lost. Please pause and turn slowly until tracking resumes.", interrupt: true)
        }
    }

    // MARK: - Speech

    /// Speaks `text`. When `interrupt` is true any in-progress utterance is cut
    /// off so urgent prompts are never queued behind stale ones.
    func speak(_ text: String, interrupt: Bool) {
        guard !isMuted else { return }
        if interrupt { stopSpeaking() }
        pending.append(text)
        lastSpokenText = text
        if currentUtterance == nil && clipPlayer == nil { startNext() }
    }

    func stopSpeaking() {
        pending.removeAll()
        currentUtterance = nil
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        clipPlayer?.stop()
        clipPlayer = nil
        isSpeaking = false
    }

    private func startNext() {
        guard !pending.isEmpty else {
            isSpeaking = false
            return
        }
        let text = pending.removeFirst()
        isSpeaking = true
        if let url = clips.url(for: text), let player = try? AVAudioPlayer(contentsOf: url) {
            player.delegate = self
            clipPlayer = player
            if player.play() { return }
            clipPlayer = nil
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = voiceRate
        utterance.prefersAssistiveTechnologySettings = true
        utterance.preUtteranceDelay = 0.05
        currentUtterance = utterance
        synthesizer.speak(utterance)
    }

    /// Moves the queue on, unless the item that finished was already cut off.
    private func finished(utterance id: ObjectIdentifier) {
        guard let current = currentUtterance, ObjectIdentifier(current) == id else { return }
        currentUtterance = nil
        startNext()
    }

    private func finished(clip id: ObjectIdentifier) {
        guard let current = clipPlayer, ObjectIdentifier(current) == id else { return }
        clipPlayer = nil
        startNext()
    }

    private func configureAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            // Play-and-record so push-to-talk can open the microphone without
            // re-configuring the session; speech routes to the loudspeaker or
            // to Bluetooth over A2DP and ducks other audio while we talk.
            //
            // Deliberately *not* HFP (`.allowBluetooth` / `.allowBluetoothHFP`):
            // HFP is the phone-call profile, and with it allowed iOS opens a
            // call link for every utterance, which audio glasses announce as
            // "call ended" after each sentence. A2DP output plus the built-in
            // (or the glasses' own SDK) microphone is what this app wants.
            let options: AVAudioSession.CategoryOptions = [.duckOthers, .defaultToSpeaker, .allowBluetoothA2DP]
            try audioSession.setCategory(.playAndRecord, mode: .default, options: options)
            try audioSession.setActive(true)
        } catch {
            // Non-fatal: speech still works through the default session.
            print("GuidanceManager: audio session configuration failed: \(error)")
        }
    }

    // MARK: AVSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.finished(utterance: id) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.finished(utterance: id) }
    }

    // MARK: AVAudioPlayerDelegate

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let id = ObjectIdentifier(player)
        Task { @MainActor in self.finished(clip: id) }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        let id = ObjectIdentifier(player)
        Task { @MainActor in self.finished(clip: id) }
    }

    // MARK: - Haptics

    private func play(hapticFor direction: TurnDirection) {
        if direction.isLeft || direction == .uTurn {
            play(.turnLeft)
        } else if direction.isRight {
            play(.turnRight)
        }
        // Straight ahead: no haptic, the spoken prompt is enough.
    }

    func play(_ pattern: HapticPattern) {
        guard hapticsAvailable, let engine = hapticEngine else {
            playFallback(pattern)
            return
        }
        do {
            try engine.start()
            let player = try engine.makePlayer(with: makePattern(pattern))
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            print("GuidanceManager: haptic playback failed: \(error)")
            playFallback(pattern)
        }
    }

    private func prepareHaptics() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            let engine = try CHHapticEngine()
            engine.playsHapticsOnly = true
            engine.isAutoShutdownEnabled = true
            engine.resetHandler = { [weak engine] in
                // The system reset the engine (e.g. after an audio interruption); restart it.
                try? engine?.start()
            }
            engine.stoppedHandler = { reason in
                print("GuidanceManager: haptic engine stopped: \(reason.rawValue)")
            }
            try engine.start()
            hapticEngine = engine
            hapticsAvailable = true
        } catch {
            print("GuidanceManager: haptic engine unavailable: \(error)")
        }
    }

    /// Builds the `CHHapticPattern` for each cue. Times are seconds.
    private func makePattern(_ pattern: HapticPattern) throws -> CHHapticPattern {
        func transient(_ time: TimeInterval, intensity: Float, sharpness: Float) -> CHHapticEvent {
            CHHapticEvent(eventType: .hapticTransient,
                          parameters: [.init(parameterID: .hapticIntensity, value: intensity),
                                       .init(parameterID: .hapticSharpness, value: sharpness)],
                          relativeTime: time)
        }
        func continuous(_ time: TimeInterval, duration: TimeInterval, intensity: Float, sharpness: Float) -> CHHapticEvent {
            CHHapticEvent(eventType: .hapticContinuous,
                          parameters: [.init(parameterID: .hapticIntensity, value: intensity),
                                       .init(parameterID: .hapticSharpness, value: sharpness)],
                          relativeTime: time,
                          duration: duration)
        }

        let events: [CHHapticEvent]
        switch pattern {
        case .nodeReached:
            events = [transient(0, intensity: 1.0, sharpness: 0.6)]
        case .turnLeft:
            events = [transient(0, intensity: 0.8, sharpness: 0.3),
                      transient(0.15, intensity: 0.8, sharpness: 0.3)]
        case .turnRight:
            events = [continuous(0, duration: 0.45, intensity: 0.8, sharpness: 0.8)]
        case .offRoute:
            events = [continuous(0, duration: 0.25, intensity: 0.6, sharpness: 0.15),
                      continuous(0.4, duration: 0.25, intensity: 0.6, sharpness: 0.15),
                      continuous(0.8, duration: 0.25, intensity: 0.6, sharpness: 0.15)]
        case .arrived:
            events = [transient(0, intensity: 0.5, sharpness: 0.5),
                      transient(0.12, intensity: 0.75, sharpness: 0.6),
                      transient(0.24, intensity: 1.0, sharpness: 0.7),
                      continuous(0.36, duration: 0.3, intensity: 0.5, sharpness: 0.3)]
        }
        return try CHHapticPattern(events: events, parameters: [])
    }

    /// Coarse UIKit haptics for devices without a Core Haptics engine.
    private func playFallback(_ pattern: HapticPattern) {
        switch pattern {
        case .nodeReached, .turnLeft, .turnRight:
            fallbackImpact.impactOccurred()
        case .arrived:
            fallbackNotification.notificationOccurred(.success)
        case .offRoute:
            fallbackNotification.notificationOccurred(.warning)
        }
    }
}
