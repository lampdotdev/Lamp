import SwiftUI
import AVFoundation
import Speech

@MainActor final class WeddingSpeech: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published var transcript = ""
    @Published var listening = false
    @Published var error = ""
    @Published var speaking = false
    private let synth = AVSpeechSynthesizer()
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var sessionID = UUID()
    private var starting = false
    private var finishing = false
    private var currentUtterance: AVSpeechUtterance?
    override init() {
        super.init()
        synth.delegate = self
    }
    func say(_ text: String, slow: Bool = false) {
        cancelSession()
        stopPlayback()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "it-IT")
        utterance.rate = slow ? 0.36 : 0.46
        currentUtterance = utterance
        speaking = true
        synth.speak(utterance)
    }
    func stopPlayback() {
        currentUtterance = nil
        synth.stopSpeaking(at: .immediate)
        speaking = false
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self, self.currentUtterance === utterance else { return }
            self.currentUtterance = nil; self.speaking = false
        }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self, self.currentUtterance === utterance else { return }
            self.currentUtterance = nil; self.speaking = false
        }
    }
    func stop() {
        guard listening else { return }
        finishing = true
        engine.stop(); engine.inputNode.removeTap(onBus: 0)
        request?.endAudio(); listening = false
    }
    private func cancelSession() {
        sessionID = UUID()
        if engine.isRunning { engine.stop(); engine.inputNode.removeTap(onBus: 0) }
        request?.endAudio(); task?.cancel()
        task = nil; request = nil; listening = false; finishing = false
    }
    func start() async {
        guard !starting, !speaking else { return }
        starting = true
        defer { starting = false }
        error = ""
        let authorized = await withCheckedContinuation { continuation in SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) } }
        guard authorized, await AVCaptureDevice.requestAccess(for: .audio) else { error = "Allow microphone and speech access to rehearse aloud. You can always type instead."; return }
        stopPlayback(); cancelSession(); transcript = ""
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "it-IT")), recognizer.isAvailable else { error = "Italian speech recognition isn’t available right now. Type your reply instead."; return }
        begin(recognizer, onDevice: recognizer.supportsOnDeviceRecognition)
    }
    private func begin(_ recognizer: SFSpeechRecognizer, onDevice: Bool) {
        let currentSession = UUID()
        sessionID = currentSession
        finishing = false
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = onDevice
        self.request = request
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            error = "No microphone is available. Connect one, or type your reply instead."
            return
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
        do {
            engine.prepare(); try engine.start(); listening = true
            task = recognizer.recognitionTask(with: request) { [weak self] result, failure in
                Task { @MainActor in
                    guard let self, self.sessionID == currentSession else { return }
                    if let result { self.transcript = result.bestTranscription.formattedString }
                    if failure != nil {
                        let retryOnline = onDevice && self.transcript.isEmpty && !self.finishing
                        let wasFinishing = self.finishing
                        self.cancelSession()
                        if retryOnline {
                            // Some Macs report offline support before Italian assets are installed.
                            self.begin(recognizer, onDevice: false)
                        } else if !wasFinishing {
                            self.error = "Italian listening couldn’t start. Check your connection and try again, or type your reply."
                        }
                    } else if result?.isFinal == true { self.cancelSession() }
                }
            }
        } catch { engine.inputNode.removeTap(onBus: 0); cancelSession(); self.error = error.localizedDescription }
    }
}

struct SpeakingInput: View {
    @ObservedObject var speech: WeddingSpeech
    @Binding var text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Say it in Italian, or type it here…", text: $text, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(2...5)
            HStack {
                Button(speech.listening ? "Finish speaking" : "Speak Italian", systemImage: speech.listening ? "stop.circle.fill" : "mic") {
                    if speech.listening { speech.stop() } else { Task { await speech.start() } }
                }
                if speech.listening { Text("Listening…").foregroundStyle(.secondary) }
            }
            if !speech.error.isEmpty { Text(speech.error).font(.caption).foregroundStyle(.red) }
        }.onChange(of: speech.transcript) { _, value in text = value }
        .onDisappear { speech.stop() }
    }
}
