import AVFoundation
import Foundation
import Observation
import Speech

/// Push-to-talk speech capture. One utterance per `startListening()`: the
/// session ends after `silenceTimeout` seconds without new words, or at
/// `maximumDuration`, and the final transcript is passed to `onFinalTranscript`.
///
/// Uses on-device recognition when the locale supports it (no network, no
/// 1-minute server limit), falling back to Apple's servers otherwise.
@MainActor
@Observable
final class VoiceCommandRecognizer {

    private(set) var isListening = false
    private(set) var isAuthorized = false
    private(set) var transcript = ""
    private(set) var errorMessage: String?

    @ObservationIgnored var onFinalTranscript: ((String) -> Void)?

    @ObservationIgnored private let recognizer: SFSpeechRecognizer?
    @ObservationIgnored private let audioEngine = AVAudioEngine()
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var silenceTimer: Task<Void, Never>?
    @ObservationIgnored private var capTimer: Task<Void, Never>?

    let silenceTimeout: TimeInterval = 4
    let maximumDuration: TimeInterval = 10

    init(locale: Locale = Locale(identifier: "en-US")) {
        recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer()
    }

    var isAvailable: Bool { recognizer?.isAvailable ?? false }

    // MARK: - Permissions

    /// Requests microphone and speech-recognition permission. Safe to call repeatedly.
    func requestAuthorization() async -> Bool {
        let micGranted = await AVAudioApplication.requestRecordPermission()
        let speechStatus: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        isAuthorized = micGranted && speechStatus == .authorized
        if !isAuthorized {
            errorMessage = micGranted ? "Speech recognition not authorized." : "Microphone access denied."
        }
        return isAuthorized
    }

    // MARK: - Listening

    func startListening() {
        guard !isListening else { return }
        guard isAuthorized, let recognizer, recognizer.isAvailable else {
            errorMessage = "Speech recognition unavailable."
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .search
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            errorMessage = "Microphone failed to start: \(error.localizedDescription)"
            inputNode.removeTap(onBus: 0)
            return
        }

        transcript = ""
        errorMessage = nil
        isListening = true

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failure = error?.localizedDescription
            Task { @MainActor [weak self] in
                self?.handleRecognition(text: text, isFinal: isFinal, failure: failure)
            }
        }

        restartSilenceTimer()
        capTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(self?.maximumDuration ?? 10))
            guard !Task.isCancelled else { return }
            self?.finish(deliver: true)
        }
    }

    /// Ends the session early. `deliver` controls whether the partial transcript is reported.
    func stopListening(deliver: Bool = true) {
        finish(deliver: deliver)
    }

    // MARK: - Private

    private func handleRecognition(text: String?, isFinal: Bool, failure: String?) {
        guard isListening else { return }
        if let text, !text.isEmpty, text != transcript {
            transcript = text
            restartSilenceTimer()
        }
        if isFinal {
            finish(deliver: true)
        } else if let failure, transcript.isEmpty {
            // Errors after we already have words are usually the cancellation we triggered ourselves.
            errorMessage = failure
            finish(deliver: false)
        }
    }

    private func restartSilenceTimer() {
        silenceTimer?.cancel()
        silenceTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(self?.silenceTimeout ?? 4))
            guard !Task.isCancelled else { return }
            self?.finish(deliver: true)
        }
    }

    private func finish(deliver: Bool) {
        guard isListening else { return }
        isListening = false
        silenceTimer?.cancel()
        capTimer?.cancel()

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil

        let final = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if deliver {
            onFinalTranscript?(final)
        }
    }
}
