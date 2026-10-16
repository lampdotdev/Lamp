import AVFoundation
import Foundation

/// One recording in progress: the microphone goes to an audio file in the app's data folder and to the
/// transcriber at the same time, and the level and words heard so far are published for the live view.
@MainActor
final class RecordingSession: ObservableObject {
    enum Phase { case idle, starting, recording, finishing }

    /// What stops a recording from starting, shown in place of the Record button's hint.
    enum Problem: Equatable {
        case permission(Permissions.Kind)
        case noMicrophone
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var startedAt: Date?
    /// The last few seconds of loudness, 0…1, oldest first: drawn as the level meter.
    @Published private(set) var levels: [Float] = Array(repeating: 0, count: RecordingSession.meterLength)
    @Published private(set) var lines: [TranscriptLine] = []
    @Published private(set) var volatileText = ""
    /// A one-time wait before recording, such as the speech model downloading.
    @Published private(set) var preparing: String?
    @Published var problem: Problem?
    /// Why this recording has no transcript (or stopped having one), when that happened.
    @Published private(set) var transcriptNote: String?

    static let meterLength = 48

    private var engine: AVAudioEngine?
    private var transcriber: Transcriber?
    private var collector: TranscriptCollector?
    private var fileName: String?

    var isRecording: Bool { phase == .recording }

    func start() async {
        guard phase == .idle else { return }
        phase = .starting
        problem = nil
        transcriptNote = nil
        lines = []
        volatileText = ""
        levels = Array(repeating: 0, count: RecordingSession.meterLength)

        guard await Permissions.microphone() else { return fail(.permission(.microphone)) }
        let engine = AVAudioEngine()
        let format = engine.inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { return fail(.noMicrophone) }

        let name = "\(UUID().uuidString).m4a"
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forWriting: Library.audioFolder.appendingPathComponent(name), settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: format.sampleRate,
                AVNumberOfChannelsKey: format.channelCount,
            ], commonFormat: .pcmFormatFloat32, interleaved: false)
        } catch {
            return fail(.failed("The recording couldn't be saved: \(error.localizedDescription)"))
        }

        let collector = TranscriptCollector { [weak self] lines, volatile in
            Task { @MainActor in
                self?.lines = lines
                self?.volatileText = volatile
            }
        }
        do {
            transcriber = try await Transcription.start(format: format, into: collector) { [weak self] message in
                Task { @MainActor in self?.preparing = message }
            }
        } catch {
            // Recording goes on without a transcript: the audio is still worth keeping.
            transcriptNote = error.localizedDescription
            preparing = nil
        }

        engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: format,
                                    block: Self.tap(file: file, transcriber: transcriber) { [weak self] level in
            Task { @MainActor in self?.addLevel(level) }
        })
        do {
            try engine.start()
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            await transcriber?.finish()
            transcriber = nil
            try? FileManager.default.removeItem(at: Library.audioFolder.appendingPathComponent(name))
            return fail(.failed("The microphone couldn't start: \(error.localizedDescription)"))
        }
        self.engine = engine
        self.collector = collector
        fileName = name
        startedAt = Date()
        phase = .recording
    }

    /// Stops, waits for the last words, and returns the finished recording for the library to keep.
    func stop() async -> Recording? {
        guard phase == .recording, let engine, let startedAt, let fileName else { return nil }
        phase = .finishing
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        await transcriber?.finish()
        let heard = collector?.finished() ?? lines
        let recording = Recording(
            title: "Recording, " + startedAt.formatted(date: .abbreviated, time: .shortened),
            date: startedAt,
            duration: Date().timeIntervalSince(startedAt),
            lines: heard,
            audioFileName: fileName,
            transcriptNote: heard.isEmpty ? (transcriptNote ?? "No speech was heard.") : transcriptNote)
        self.engine = nil
        transcriber = nil
        collector = nil
        self.fileName = nil
        self.startedAt = nil
        phase = .idle
        return recording
    }

    private func fail(_ problem: Problem) {
        self.problem = problem
        phase = .idle
    }

    private func addLevel(_ level: Float) {
        guard phase == .recording else { return }
        levels.removeFirst()
        levels.append(level)
    }

    /// The microphone's tap, made outside the main actor because it runs on the audio thread.
    private nonisolated static func tap(file: AVAudioFile, transcriber: Transcriber?,
                                        level: @escaping @Sendable (Float) -> Void) -> AVAudioNodeTapBlock {
        { buffer, _ in
            try? file.write(from: buffer)
            transcriber?.append(buffer)
            level(Self.loudness(of: buffer))
        }
    }

    /// How loud a buffer is, 0…1, on a decibel scale so quiet speech still moves the meter.
    private nonisolated static func loudness(of buffer: AVAudioPCMBuffer) -> Float {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var sum: Float = 0
        for index in 0..<Int(buffer.frameLength) { sum += samples[index] * samples[index] }
        let rms = (sum / Float(buffer.frameLength)).squareRoot()
        let decibels = 20 * log10(max(rms, 0.000_01))
        return min(1, max(0, (decibels + 55) / 50))
    }
}
