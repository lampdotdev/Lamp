import AVFoundation
import Speech

/// Speech-to-text for the prompt box. Recognition runs on-device when the Mac supports it,
/// so audio never leaves the machine and there's no time limit.
@MainActor
final class Dictation: ObservableObject {
    @Published private(set) var isListening = false
    @Published var error: String?

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    /// Bumped on every start and cancel, so late callbacks from an old session are ignored.
    private var session = 0

    /// Starts listening; `onText` receives the full transcription so far, every time it changes.
    func start(onText: @escaping (String) -> Void) async {
        guard !isListening else { return }
        guard await Self.authorize() else {
            error = "Forge needs Microphone and Speech Recognition access to take dictation. You can turn them on in System Settings → Privacy & Security."
            return
        }
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            error = "Speech recognition isn't available right now."
            return
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }

        let input = engine.inputNode
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0), block: Self.feed(request))
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            self.error = "Couldn't start the microphone: \(error.localizedDescription)"
            return
        }
        self.request = request
        isListening = true
        session += 1
        task = recognizer.recognitionTask(with: request, resultHandler: Self.deliver(to: self, session: session, onText: onText))
    }

    /// Stops listening and lets the recognizer deliver its final take on the last words.
    func stop() {
        guard isListening else { return }
        stopAudio()
        request?.endAudio()
    }

    /// Stops listening and drops anything still in flight (e.g. the prompt was just sent).
    func cancel() {
        if isListening { stopAudio() }
        session += 1
        task?.cancel()
        task = nil
        request = nil
    }

    private func stopAudio() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        isListening = false
    }

    private func finished() {
        if isListening { stopAudio() }
        task = nil
        request = nil
    }

    // The audio tap and recognition callbacks run off the main thread, so they're built outside the actor.

    nonisolated private static func feed(_ request: SFSpeechAudioBufferRecognitionRequest) -> AVAudioNodeTapBlock {
        { buffer, _ in request.append(buffer) }
    }

    nonisolated private static func deliver(
        to dictation: Dictation, session: Int, onText: @escaping (String) -> Void
    ) -> (SFSpeechRecognitionResult?, Error?) -> Void {
        { [weak dictation] result, error in
            let text = result?.bestTranscription.formattedString
            let done = error != nil || result?.isFinal == true
            Task { @MainActor in
                guard let dictation, dictation.session == session else { return }
                if let text { onText(text) }
                if done { dictation.finished() }
            }
        }
    }

    nonisolated private static func authorize() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        guard speech else { return false }
        return await AVCaptureDevice.requestAccess(for: .audio)
    }
}
