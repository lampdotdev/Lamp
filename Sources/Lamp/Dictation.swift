import AVFoundation
import Speech

/// Speech-to-text for the prompt box. Recognition runs on-device when the Mac supports it,
/// so audio never leaves the machine and there's no time limit.
@MainActor
final class Dictation: ObservableObject {
    /// Something the user needs to know (and usually fix) before dictation can work.
    struct Problem {
        var title: String
        var message: String
        /// A System Settings page that fixes it, if there is one, and the button that opens it.
        var settingsURL: URL?
        var settingsButton = "Open System Settings"
    }

    @Published private(set) var isListening = false
    @Published var problem: Problem?

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    /// Bumped on every start and cancel, so late callbacks from an old session are ignored.
    private var session = 0

    /// Starts listening; `onText` receives the full transcription so far, every time it changes.
    func start(onText: @escaping (String) -> Void) async {
        guard !isListening else { return }
        let startingSession = session
        if let denied = await Self.authorize() {
            if session == startingSession { problem = denied }
            return
        }
        // Send or leaving the chat can cancel dictation while macOS is still asking for permission.
        guard session == startingSession else { return }
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            problem = Problem(title: "Dictation Isn't Available", message: "Speech recognition isn't available right now. Try again in a moment.")
            return
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }

        let input = engine.inputNode
        // With no input device the format is 0 Hz, and installing a tap with it raises an exception that
        // can't be caught: say so instead.
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            problem = Problem(title: "No Microphone", message: "This Mac has no microphone connected, so there's nothing to listen to.")
            return
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.feed(request))
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            problem = Problem(title: "Couldn't Start the Microphone", message: error.localizedDescription)
            return
        }
        self.request = request
        isListening = true
        session += 1
        task = recognizer.recognitionTask(with: request, resultHandler: Self.deliver(to: self, session: session, onText: onText))
    }

    /// Whether this Mac has a microphone right now; the dictation button is only shown when it does.
    static var hasMicrophone: Bool {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified)
            .devices.isEmpty == false
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

    private func finished(_ failure: Error?) {
        if isListening { stopAudio() }
        task = nil
        request = nil
        if let failure = failure as NSError?, !Self.isBenign(failure) {
            NSLog("Dictation failed: %@", failure)
            problem = Self.problem(for: failure)
        }
    }

    /// Errors that just mean "stopped" or "heard nothing", not that something's wrong.
    private static func isBenign(_ error: NSError) -> Bool {
        switch (error.domain, error.code) {
        case ("kAFAssistantErrorDomain", 203), // no speech recognized
             ("kAFAssistantErrorDomain", 216), // canceled
             ("kAFAssistantErrorDomain", 1110), // no speech detected
             ("kLSRErrorDomain", 301): // canceled
            return true
        default:
            return false
        }
    }

    private static func problem(for error: NSError) -> Problem {
        switch (error.domain, error.code) {
        // macOS refuses all speech recognition while system Dictation is off.
        case ("kAFAssistantErrorDomain", 1101), ("kAFAssistantErrorDomain", 1700),
             ("kLSRErrorDomain", 201), ("kLSRErrorDomain", 102):
            return Problem(
                title: "Turn On Dictation to Use the Mic",
                message: """
                    macOS only turns speech into text while Dictation is on. To turn it on:

                    1. Click Open Keyboard Settings.
                    2. Scroll down to Dictation and turn it on.
                    3. Click Enable when macOS asks.

                    Then click the mic in Lamp again. Speech is processed on your Mac.
                    """,
                settingsURL: URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension"),
                settingsButton: "Open Keyboard Settings")
        default:
            return Problem(title: "Dictation Stopped",
                           message: "\(error.localizedDescription) (\(error.domain) \(error.code))")
        }
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
                if done { dictation.finished(error) }
            }
        }
    }

    /// Asks for speech and microphone access; returns what's missing, or nil when both are granted.
    nonisolated private static func authorize() async -> Problem? {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        if !speech { return accessProblem("Speech Recognition", anchor: "Privacy_SpeechRecognition") }
        if await !AVCaptureDevice.requestAccess(for: .audio) { return accessProblem("Microphone", anchor: "Privacy_Microphone") }
        return nil
    }

    nonisolated private static func accessProblem(_ name: String, anchor: String) -> Problem {
        Problem(
            title: "Allow \(name) Access",
            message: """
                Lamp needs \(name) access to take dictation. To allow it:

                1. Click Open Privacy Settings.
                2. Turn on Lamp in the list.

                Then click the mic in Lamp again.
                """,
            settingsURL: URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)"),
            settingsButton: "Open Privacy Settings")
    }
}
