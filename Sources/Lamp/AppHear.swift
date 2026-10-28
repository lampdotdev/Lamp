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

    /// A WAV as the hosts make it, read back: its PCM samples' byte count and length in seconds. Anything else
    /// (another format, a header that lies about its size, too short or too long) is a sentence why not.
    static func check(wav data: Data) -> Result<(bytes: Int, seconds: Double), Failure> {
        func bad(_ why: String) -> Result<(bytes: Int, seconds: Double), Failure> { .failure(Failure(status: 400, message: why)) }
        let b = [UInt8](data)
        func u32(_ i: Int) -> Int { Int(b[i]) | Int(b[i + 1]) << 8 | Int(b[i + 2]) << 16 | Int(b[i + 3]) << 24 }
        func u16(_ i: Int) -> Int { Int(b[i]) | Int(b[i + 1]) << 8 }
        func tag(_ i: Int) -> String { String(decoding: b[i..<i + 4], as: UTF8.self) }
        guard b.count >= 44, tag(0) == "RIFF", tag(8) == "WAVE" else { return bad("The audio isn't a WAV.") }
        // The chunks after the header, in order: `fmt ` first, then `data` (others, such as LIST, are skipped).
        var i = 12
        var format: (pcm: Int, channels: Int, rate: Int, bits: Int)?
        while i + 8 <= b.count {
            let name = tag(i), size = u32(i + 4), body = i + 8
            if name == "fmt " {
                guard size >= 16, body + 16 <= b.count else { return bad("The WAV's format is cut short.") }
                format = (u16(body), u16(body + 2), u32(body + 4), u16(body + 14))
            } else if name == "data" {
                guard let f = format else { return bad("The WAV has no format before its audio.") }
                guard f.pcm == 1, f.channels == 1, f.rate == sampleRate, f.bits == 16 else {
                    return bad("The audio must be 16 kHz mono 16-bit PCM; this is \(f.rate) Hz, \(f.channels) channel(s), \(f.bits)-bit, format \(f.pcm).")
                }
                // The samples actually there, never what the header claims beyond them.
                guard size <= b.count - body else { return bad("The WAV says it holds more audio than it does.") }
                guard size % 2 == 0 else { return bad("The WAV's audio isn't whole 16-bit samples.") }
                let seconds = Double(size / 2) / Double(sampleRate)
                guard seconds >= minSeconds else { return bad("That was too short to hear anything.") }
                guard size <= maxAudioBytes else { return .failure(Failure(status: 413, message: "At most \(Int(maxSeconds)) seconds can be heard at once.")) }
                return .success((size, seconds))
            }
            i = body + size + (size % 2)
        }
        return bad("The WAV has no audio.")
    }

    /// The OpenRouter request: Scribe, without the ums and false starts (`no_verbatim`, as Switchboard asks).
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

    /// One request, end to end: the probe, or the audio checked and transcribed. The status, the JSON and the cost.
    /// It is one attempt: a step that times out on the page's side may still be billed here, and isn't sent twice.
    @MainActor static func handle(_ data: Data) async -> (Int, [String: Any], Double) {
        guard data.count <= maxBody else { return (413, ["error": "At most \(Int(maxSeconds)) seconds can be heard at once."], 0) }
        guard let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return (400, ["error": "Send the audio as JSON."], 0) }
        if body["probe"] as? Bool == true {
            return (200, ["hear": Provider.hasKey, "why": Provider.hasKey ? "" : unsupported, "max": maxSeconds], 0)
        }
        guard Provider.hasKey else { return (501, ["error": unsupported, "needs": "text", "setup": "openrouter"], 0) }
        guard let base64 = body["audio"] as? String, let wav = Data(base64Encoded: base64) else {
            return (400, ["error": "Send the audio as a base64 WAV in `audio`."], 0)
        }
        switch check(wav: wav) {
        case .failure(let f): return (f.status, ["error": f.message], 0)
        case .success: break
        }
        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(KeyStore.openRouterKey ?? "")", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Lamp", forHTTPHeaderField: "X-Title")
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: openRouterBody(audio: base64))
            let (reply, response) = try await URLSession.shared.data(for: request)
            switch read(status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: reply) {
            case .success(let heard):
                return (200, ["text": heard.text, "seconds": heard.seconds, "nothing": heard.text.isEmpty], heard.cost)
            case .failure(let f):
                return (f.status, ["error": f.message], 0)
            }
        } catch {
            return (502, ["error": "Couldn't reach OpenRouter to hear that: \(error.localizedDescription)"], 0)
        }
    }
}
