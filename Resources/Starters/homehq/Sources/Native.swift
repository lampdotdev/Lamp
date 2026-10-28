import AVFoundation
import EventKit
import Foundation
import Speech
#if os(iOS)
import UIKit
#endif

/// What the page asks of this Mac, iPhone or iPad with `LampNative.call(name, args)` in Web/: the person's own
/// calendars and photos, read with Lamp's building blocks in LampSupport.swift. Each is asked for only when the person
/// turns it on in the page's settings, so the system asks for access then and not as the screen opens.
enum Native {
    @MainActor static func register() {
        // The calendars, for the settings sheet: each with its own id and where it's from, since two can share a name
        // (a "Family" in iCloud and a "Family" subscribed to from Google).
        LampNative.on("calendars") { _ in try await Calendars.list() }

        // Events from a week ago to `days` ahead from the chosen calendars, in the page's shape (js/data.js).
        LampNative.on("events") { args in
            try await Calendars.events(in: args["calendars"] as? [String] ?? [], days: args["days"] as? Int ?? 42)
        }

        // Talking to Home HQ (js/agent.js): whether this device can hear and speak, then one thing said, and the reply
        // read out. Asked for only when the person taps Ask, so the system asks for the microphone then.
        LampNative.on("voice") { _ in Voice.shared.status() }
        LampNative.on("listen") { args in await Voice.shared.listen(words: args["words"] as? [String] ?? []) }
        LampNative.on("stop") { args in Voice.shared.stop(cancel: args["cancel"] as? Bool ?? false); return true }
        LampNative.on("speak") { args in await Voice.shared.speak(args["text"] as? String ?? "") }

        // The person's albums with something in them, for the settings sheet.
        LampNative.on("albums") { _ in
            guard try await LampPhotos.authorize() else { throw Refused() }
            return try await LampPhotos.albums().filter { $0.count > 0 }.map { ["id": $0.id, "title": $0.title, "count": String($0.count)] }
        }

        // Pictures from one album (Favorites unless named), newest first, each a JPEG small enough for a screen across
        // the room and to send on to the screen's other copies (js/sync.js), with the date and whether it's tall.
        LampNative.on("photos") { args in
            guard try await LampPhotos.authorize() else { throw Refused() }
            let limit = min(args["limit"] as? Int ?? 24, 40)
            let album = try await LampPhotos.albums().first { $0.id == args["album"] as? String }
            let found = if let album { try await LampPhotos.photos(in: album, limit: limit * 2) } else { try await LampPhotos.favorites(limit: limit * 2) }
            let photos = found.filter { !$0.isVideo }.prefix(limit)
            let day = DateFormatter()
            day.dateFormat = "yyyy-MM-dd"
            var out: [[String: String]] = []
            for photo in photos {
                guard let image = await LampPhotos.image(photo, size: 1280), let cg = image.lampCGImage,
                      let jpeg = LampImage.lampJPEG(cg, quality: 0.72) else { continue }
                out.append(["id": photo.id, "src": "data:image/jpeg;base64," + jpeg.base64EncodedString(),
                            "o": photo.height > photo.width ? "p" : "l", "date": photo.date.map(day.string(from:)) ?? "",
                            "fav": photo.isFavorite ? "1" : ""])
            }
            return out
        }
    }

    struct Refused: LocalizedError {
        var errorDescription: String? { "Photos isn't allowed." }
    }
}

/// The person's calendars, read with EventKit off the main thread: EventKit waits on the system's calendar service, which
/// holds it while it asks for access. Calendars are chosen by their identifier; a name saved by an earlier version still
/// finds its calendar.
enum Calendars {
    nonisolated(unsafe) private static let store = EKEventStore()

    private static func authorize() async throws {
        if EKEventStore.authorizationStatus(for: .event) == .fullAccess { return }
        guard try await store.requestFullAccessToEvents() else { throw Refused(what: "Calendars") }
    }

    static func list() async throws -> [[String: String]] {
        try await authorize()
        return await Task.detached {
            store.calendars(for: .event).map { ["id": $0.calendarIdentifier, "title": $0.title, "source": $0.source?.title ?? ""] }
        }.value
    }

    static func events(in chosen: [String], days: Int) async throws -> [[String: String]] {
        try await authorize()
        return await Task.detached {
            // [] (saved by an earlier version) is every calendar; otherwise the ones chosen, and none when nothing matches.
            let all = store.calendars(for: .event)
            let calendars = chosen.isEmpty ? all : all.filter { chosen.contains($0.calendarIdentifier) || chosen.contains($0.title) }
            guard !calendars.isEmpty else { return [] }
            let now = Date()
            let from = Calendar.current.date(byAdding: .day, value: -7, to: Calendar.current.startOfDay(for: now)) ?? now
            let to = Calendar.current.date(byAdding: .day, value: days, to: now) ?? now
            let iso = ISO8601DateFormatter()
            return store.events(matching: store.predicateForEvents(withStart: from, end: to, calendars: calendars))
                .sorted { $0.startDate < $1.startDate }
                .map { e in
                    ["id": e.eventIdentifier ?? UUID().uuidString, "title": e.title ?? "", "start": iso.string(from: e.startDate),
                     "end": iso.string(from: e.endDate), "allDay": e.isAllDay ? "1" : "", "loc": e.location ?? "", "notes": e.notes ?? "",
                     "calendar": e.calendar.title]
                }
        }.value
    }

    struct Refused: LocalizedError {
        let what: String
        var errorDescription: String? { "\(what) isn't allowed." }
    }
}


/// Hearing and speaking for Ask Home HQ, on the device: Speech's recognizer (on the device only, so what the family says
/// stays here; where it can't, `listen` is false and Ask is typed) and the system's voice. One thing is heard at a time,
/// ending after a moment of quiet, a stop, or the app going to the background; it never listens while it speaks.
@MainActor
final class Voice: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = Voice()

    private let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let synthesizer = AVSpeechSynthesizer()
    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silence: Task<Void, Never>?
    private var heard = ""
    private var waiting: CheckedContinuation<[String: String], Never>?
    private var speaking: CheckedContinuation<Bool, Never>?

    override init() {
        super.init()
        synthesizer.delegate = self
        #if os(iOS)
        // Locked, or another app in front: what's being heard is let go, and nothing more is said.
        NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { Voice.shared.stop(cancel: true, ended: "interrupted") }
        }
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { Voice.shared.stop(cancel: true, ended: "interrupted") }
        }
        #endif
    }

    func status() -> [String: String] {
        let speech = SFSpeechRecognizer.authorizationStatus()
        let permission = speech == .denied || speech == .restricted ? "denied" : speech == .authorized ? "granted" : "undetermined"
        let onDevice = recognizer?.supportsOnDeviceRecognition == true
        return ["listen": onDevice ? "1" : "", "speak": "1", "onDevice": onDevice ? "1" : "", "permission": permission]
    }

    func listen(words: [String]) async -> [String: String] {
        stop(cancel: true)
        guard await Self.authorize() else { return ["text": "", "ended": "denied"] }
        guard let recognizer, recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else { return ["text": "", "ended": "unavailable"] }
        #if os(iOS)
        let audio = AVAudioSession.sharedInstance()
        try? audio.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
        try? audio.setActive(true, options: .notifyOthersOnDeactivation)
        #endif
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.contextualStrings = Array(words.prefix(80))
        let engine = AVAudioEngine()
        Self.tap(engine.inputNode, into: request)
        engine.prepare()
        do { try engine.start() } catch {
            engine.inputNode.removeTap(onBus: 0)
            return ["text": "", "ended": "nothing"]
        }
        self.engine = engine
        self.request = request
        heard = ""
        task = recognizer.recognitionTask(with: request) { result, error in
            let text = result?.bestTranscription.formattedString
            let done = (result?.isFinal ?? false) || (error != nil && result == nil)
            Task { @MainActor in Voice.shared.got(text, done: done) }
        }
        armSilence(after: 6, ended: "nothing")
        return await withCheckedContinuation { waiting = $0 }
    }

    /// Ends listening: with `cancel` what was heard is let go, else it's the answer. Also stops speaking.
    func stop(cancel: Bool, ended: String? = nil) {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        finish(ended: ended ?? (cancel ? "cancelled" : "stopped"), keep: !cancel)
    }

    func speak(_ text: String) async -> Bool {
        guard !text.isEmpty else { return true }
        if engine != nil { finish(ended: "cancelled", keep: false) }
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        speaking?.resume(returning: false)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.identifier.replacingOccurrences(of: "_", with: "-"))
            ?? AVSpeechSynthesisVoice(language: "en-US")
        return await withCheckedContinuation { done in
            speaking = done
            synthesizer.speak(utterance)
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in Voice.shared.spoke(true) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in Voice.shared.spoke(false) }
    }

    private func spoke(_ finished: Bool) {
        speaking?.resume(returning: finished)
        speaking = nil
    }

    private func got(_ text: String?, done: Bool) {
        guard engine != nil else { return }
        if let text, !text.isEmpty {
            heard = text
            armSilence(after: 1.3, ended: "silence")
        }
        if done { finish(ended: "silence", keep: true) }
    }

    private func armSilence(after seconds: Double, ended: String) {
        silence?.cancel()
        silence = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.finish(ended: ended, keep: true)
        }
    }

    private func finish(ended: String, keep: Bool) {
        silence?.cancel()
        silence = nil
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.finish()
        engine = nil
        request = nil
        task = nil
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
        let text = keep ? heard.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        heard = ""
        waiting?.resume(returning: ["text": text, "ended": text.isEmpty && ended == "silence" ? "nothing" : ended])
        waiting = nil
    }

    nonisolated private static func tap(_ input: AVAudioInputNode, into request: SFSpeechAudioBufferRecognitionRequest) {
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
    }

    nonisolated private static func authorize() async -> Bool {
        let speech: Bool = await withCheckedContinuation { done in
            SFSpeechRecognizer.requestAuthorization { done.resume(returning: $0 == .authorized) }
        }
        guard speech else { return false }
        #if os(iOS)
        return await AVAudioApplication.requestRecordPermission()
        #else
        return await AVCaptureDevice.requestAccess(for: .audio)
        #endif
    }
}
