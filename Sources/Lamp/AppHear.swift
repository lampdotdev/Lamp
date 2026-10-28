import Foundation

/// `/ai/hear`, the gateway's side of `LampAI.hear` in lamp.js: what the person said, as text. The page's host records
/// it (`LampVoice` in lamp.js, answered by the app around the page) and the page sends it here as a WAV in base64:
/// 16 kHz, mono, signed 16-bit little-endian PCM, the format the hosts convert to. It's checked here before anything
/// is paid for, then transcribed by ElevenLabs' Scribe through OpenRouter, with the OpenRouter key Lamp keeps on this
/// Mac: it never reaches the device. The cost OpenRouter reports is recorded as the app's, as any AI call's is.
///
/// Only OpenRouter transcribes for now: with no key, the answer says so (501, `needs: text`), as act's does.
enum AppHear {
    static let model = "elevenlabs/scribe-v2"
    static let sampleRate = 16_000
    /// What one request may hold: 15 seconds of audio, and the least that's worth sending.
    static let maxSeconds = 15.0
    static let minSeconds = 0.3
    static var maxAudioBytes: Int { Int(maxSeconds) * sampleRate * 2 }
    /// The body: the audio's base64 (4/3 of it), its header and a little JSON.
    static var maxBody: Int { (maxAudioBytes + 44) * 4 / 3 + 4096 }
    static let unsupported = "Talking to apps needs OpenRouter set up in Lamp: other AI there can't hear yet."

    struct Failure: Error, Equatable { let status: Int; let message: String }

    /// A WAV exactly as the hosts write it, read back: its PCM samples' byte count and length in seconds. The hosts
    /// write one header, 44 bytes, and the samples straight after it, so that is all that's taken: every field of it,
    /// the RIFF and data lengths true to the file, and nothing before or after the samples. Anything else is a
    /// sentence why not, before anything is paid for.
    static func check(wav data: Data) -> Result<(bytes: Int, seconds: Double), Failure> {
        func bad(_ why: String) -> Result<(bytes: Int, seconds: Double), Failure> { .failure(Failure(status: 400, message: why)) }
        let b = [UInt8](data)
        func u32(_ i: Int) -> Int { Int(b[i]) | Int(b[i + 1]) << 8 | Int(b[i + 2]) << 16 | Int(b[i + 3]) << 24 }
        func u16(_ i: Int) -> Int { Int(b[i]) | Int(b[i + 1]) << 8 }
        func tag(_ i: Int) -> String { String(decoding: b[i..<i + 4], as: UTF8.self) }
        guard b.count >= 44, tag(0) == "RIFF", tag(8) == "WAVE", tag(12) == "fmt ", tag(36) == "data" else {
            return bad("The audio isn't a WAV as Lamp's apps record it.")
        }
        guard u32(16) == 16, u16(20) == 1, u16(22) == 1, u32(24) == sampleRate, u16(34) == 16 else {
            return bad("The audio must be 16 kHz mono 16-bit PCM; this is \(u32(24)) Hz, \(u16(22)) channel(s), \(u16(34))-bit, format \(u16(20)).")
        }
        guard u32(28) == sampleRate * 2, u16(32) == 2 else { return bad("The WAV's header doesn't add up.") }
        let size = u32(40)
        guard u32(4) == b.count - 8, size == b.count - 44 else { return bad("The WAV's lengths aren't the file's.") }
        guard size % 2 == 0 else { return bad("The WAV's audio isn't whole 16-bit samples.") }
        let seconds = Double(size / 2) / Double(sampleRate)
        guard seconds >= minSeconds else { return bad("That was too short to hear anything.") }
        guard size <= maxAudioBytes else { return .failure(Failure(status: 413, message: "At most \(Int(maxSeconds)) seconds can be heard at once.")) }
        return .success((size, seconds))
    }

    /// The OpenRouter request: Scribe, without the ums and false starts (`no_verbatim`).
    static func openRouterBody(audio base64: String) -> [String: Any] {
        ["model": model, "input_audio": ["data": base64, "format": "wav"],
         "provider": ["options": ["elevenlabs": ["no_verbatim": true]]]]
    }

    struct Heard: Equatable { let text: String; let seconds: Double; let cost: Double }

    /// Reads OpenRouter's answer: the text and what it says it cost, or the reason in words the person can act on.
    static func read(status: Int, body: Data) -> Result<Heard, Failure> {
        let obj = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
        guard status == 200 else {
            switch status {
            case 401, 403: return .failure(Failure(status: 502, message: "OpenRouter didn't accept Lamp's key. Check it in Lamp → Settings."))
            case 402: return .failure(Failure(status: 502, message: "The OpenRouter account is out of credit."))
            case 429: return .failure(Failure(status: 503, message: "OpenRouter is busy. Try again in a moment."))
            default: return .failure(Failure(status: 502, message: Provider.friendlyError(status: status, reply: obj, from: Provider.openRouter)))
            }
        }
        guard let text = obj["text"] as? String else { return .failure(Failure(status: 502, message: "The transcription came back empty-handed.")) }
        let usage = obj["usage"] as? [String: Any] ?? [:]
        return .success(Heard(text: text.trimmed, seconds: (usage["seconds"] as? NSNumber)?.doubleValue ?? 0,
                              cost: (usage["cost"] as? NSNumber)?.doubleValue ?? 0))
    }

    typealias Transcribe = @MainActor (String) async -> Result<Heard, Failure>

    /// Each recording the page sends carries its own id (`op`). The page tries each way to the Mac in turn, so the same
    /// recording can arrive again when an answer is lost on the way back; it's transcribed and charged once, and the
    /// copy waits for, or is given, that one answer. Kept per app for a few minutes.
    private static var heard: [String: (at: Date, answer: Task<(Int, [String: Any], Double), Never>)] = [:]
    static let keepFor: TimeInterval = 300

    /// One request, end to end: the probe, or the audio checked and transcribed. The status, the JSON and the cost.
    @MainActor static func handle(_ data: Data, app: String, hasKey: Bool = Provider.hasKey,
                                  transcribe: @escaping Transcribe = openRouter) async -> (Int, [String: Any], Double) {
        guard data.count <= maxBody else { return (413, ["error": "At most \(Int(maxSeconds)) seconds can be heard at once."], 0) }
        guard let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return (400, ["error": "Send the audio as JSON."], 0) }
        if body["probe"] as? Bool == true {
            return (200, ["hear": hasKey, "why": hasKey ? "" : unsupported, "max": maxSeconds], 0)
        }
        guard hasKey else { return (501, ["error": unsupported, "needs": "text", "setup": "openrouter"], 0) }
        guard let base64 = body["audio"] as? String, let wav = Data(base64Encoded: base64) else {
            return (400, ["error": "Send the audio as a base64 WAV in `audio`."], 0)
        }
        switch check(wav: wav) {
        case .failure(let f): return (f.status, ["error": f.message], 0)
        case .success: break
        }
        let now = Date()
        heard = heard.filter { now.timeIntervalSince($0.value.at) < keepFor }
        let op = (body["op"] as? String).flatMap { $0.isEmpty || $0.count > 80 ? nil : app + "\u{1}" + $0 }
        if let op, let earlier = heard[op] {
            let (status, json, _) = await earlier.answer.value
            return (status, json, 0)
        }
        let answer = Task { @MainActor () -> (Int, [String: Any], Double) in
            switch await transcribe(base64) {
            case .success(let heard): return (200, ["text": heard.text, "seconds": heard.seconds, "nothing": heard.text.isEmpty], heard.cost)
            case .failure(let f): return (f.status, ["error": f.message], 0)
            }
        }
        if let op { heard[op] = (now, answer) }
        return await answer.value
    }

    /// Scribe through OpenRouter, once.
    @MainActor static func openRouter(_ base64: String) async -> Result<Heard, Failure> {
        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(KeyStore.openRouterKey ?? "")", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Lamp", forHTTPHeaderField: "X-Title")
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: openRouterBody(audio: base64))
            let (reply, response) = try await URLSession.shared.data(for: request)
            return read(status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: reply)
        } catch {
            return .failure(Failure(status: 502, message: "Couldn't reach OpenRouter to hear that: \(error.localizedDescription)"))
        }
    }
}
