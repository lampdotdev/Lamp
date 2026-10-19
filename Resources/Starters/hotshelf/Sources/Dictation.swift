import Foundation
import Speech
import AVFoundation

/// Speak a verdict instead of typing it, recognized on this Mac.
@MainActor
final class Dictation: ObservableObject {
    @Published var text = ""
    @Published var isListening = false
    @Published var problem: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func toggle() {
        isListening ? stop() : start()
    }

    func start() {
        problem = nil
        Task {
            let speech = await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) } }
            guard speech == .authorized else { problem = "Speech recognition is off in System Settings."; return }
            guard await AVCaptureDevice.requestAccess(for: .audio) else { problem = "The microphone is off in System Settings."; return }
            guard let recognizer, recognizer.isAvailable else { problem = "Dictation isn't available right now."; return }
            begin(with: recognizer)
        }
    }

    private func begin(with recognizer: SFSpeechRecognizer) {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        self.request = request
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
            request.append(buffer)
        }
        do {
            engine.prepare()
            try engine.start()
        } catch {
            problem = "Couldn't start the microphone."
            return
        }
        isListening = true
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let words = result?.bestTranscription.formattedString
            let done = error != nil || (result?.isFinal ?? false)
            Task { @MainActor in
                guard let self else { return }
                if let words { self.text = words }
                if done { self.stop() }
            }
        }
    }

    func stop() {
        guard isListening else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.finish()
        request = nil
        task = nil
        isListening = false
    }
}
