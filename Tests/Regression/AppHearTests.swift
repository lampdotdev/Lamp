import XCTest
@testable import Lamp

/// `/ai/hear`'s side of `LampAI.hear` (`AppHear`): what it takes before anything is paid for, what it asks OpenRouter,
/// and how it reads the answer. The answers in Tests/Fixtures/openrouter-hear are OpenRouter's own, recorded on
/// 2026-10-28: Scribe with `no_verbatim` on a 16 kHz WAV of "add milk, um, oat milk", and the same request with a key
/// OpenRouter doesn't know.
final class AppHearTests: XCTestCase {
    private let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/openrouter-hear")

    /// A WAV as the hosts write it: `seconds` of silence at `rate`, `channels`, `bits`.
    private func wav(seconds: Double, rate: Int = 16_000, channels: Int = 1, bits: Int = 16, claim: Int? = nil) -> Data {
        let frames = Int(seconds * Double(rate))
        let pcm = Data(count: frames * channels * bits / 8)
        var d = Data()
        func u32(_ v: Int) { var x = UInt32(v).littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: Int) { var x = UInt16(v).littleEndian; d.append(Data(bytes: &x, count: 2)) }
        d.append(Data("RIFF".utf8)); u32(36 + pcm.count); d.append(Data("WAVEfmt ".utf8)); u32(16); u16(1); u16(channels)
        u32(rate); u32(rate * channels * bits / 8); u16(channels * bits / 8); u16(bits); d.append(Data("data".utf8)); u32(claim ?? pcm.count)
        d.append(pcm)
        return d
    }

    func testAWavAsTheHostsMakeItIsTaken() throws {
        guard case .success(let ok) = AppHear.check(wav: wav(seconds: 2)) else { return XCTFail("refused") }
        XCTAssertEqual(ok.seconds, 2, accuracy: 0.001)
        XCTAssertEqual(ok.bytes, 64_000)
    }

    func testAnythingElseIsRefusedBeforeItCostsAnything() {
        let refused: [(Data, String)] = [
            (Data("not audio at all, just some words".utf8), "not a WAV"),
            (wav(seconds: 2, rate: 44_100), "another rate"),
            (wav(seconds: 2, channels: 2), "stereo"),
            (wav(seconds: 2, bits: 8), "8-bit"),
            (wav(seconds: 1, claim: 1_000_000), "a header claiming more audio than there is"),
            (wav(seconds: 0.1), "too short to hear"),
        ]
        for (data, what) in refused {
            guard case .failure(let f) = AppHear.check(wav: data) else { XCTFail("took \(what)"); continue }
            XCTAssertEqual(f.status, 400, what)
        }
        guard case .failure(let long) = AppHear.check(wav: wav(seconds: 16)) else { return XCTFail("took 16 seconds") }
        XCTAssertEqual(long.status, 413)
    }

    @MainActor
    func testAnOversizedOrMalformedBodyIsRefusedFirst() async {
        let big = Data(repeating: 0x41, count: AppHear.maxBody + 1)
        let (status, _, cost) = await AppHear.handle(big, app: "t")
        XCTAssertEqual(status, 413)
        XCTAssertEqual(cost, 0)
        let (bad, _, _) = await AppHear.handle(Data("[1,2".utf8), app: "t")
        XCTAssertEqual(bad, 400)
    }

    func testOpenRouterIsAskedForScribeWithoutTheUms() {
        let body = AppHear.openRouterBody(audio: "QUJD")
        XCTAssertEqual(body["model"] as? String, "elevenlabs/scribe-v2")
        XCTAssertEqual((body["input_audio"] as? [String: Any])?["format"] as? String, "wav")
        let options = ((body["provider"] as? [String: Any])?["options"] as? [String: Any])?["elevenlabs"] as? [String: Any]
        XCTAssertEqual(options?["no_verbatim"] as? Bool, true)
    }

    func testTheRecordedAnswerGivesTheTextAndWhatItCost() throws {
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fixtures.appendingPathComponent("oat-milk.json"))) as? [String: Any])
        let response = try JSONSerialization.data(withJSONObject: try XCTUnwrap(fixture["response"]))
        guard case .success(let heard) = AppHear.read(status: 200, body: response) else { return XCTFail("not read") }
        XCTAssertEqual(heard.text, "Add milk. Oat milk")
        XCTAssertEqual(heard.cost, 0.00012741284722219906, accuracy: 1e-12)
        XCTAssertGreaterThan(heard.seconds, 2)
    }

    func testAnUnknownKeyIsSaidSoThePersonCanFixIt() throws {
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fixtures.appendingPathComponent("unknown-key.json"))) as? [String: Any])
        let response = try JSONSerialization.data(withJSONObject: try XCTUnwrap(fixture["response"]))
        guard case .failure(let f) = AppHear.read(status: 401, body: response) else { return XCTFail("taken") }
        XCTAssertTrue(f.message.contains("key"), f.message)
        guard case .failure(let broke) = AppHear.read(status: 402, body: Data("{}".utf8)) else { return XCTFail("taken") }
        XCTAssertTrue(broke.message.contains("credit"), broke.message)
    }

    /// The hosts write one exact header; any other field, length or chunk is refused before the paid call.
    func testAHeaderThatIsNotExactlyTheHostsIsRefused() {
        func with(_ change: (inout [UInt8]) -> Void) -> Data { var b = [UInt8](wav(seconds: 1)); change(&b); return Data(b) }
        func u32(_ b: inout [UInt8], _ at: Int, _ v: Int) { for k in 0..<4 { b[at + k] = UInt8((v >> (8 * k)) & 0xff) } }
        let refused: [(Data, String)] = [
            (with { u32(&$0, 4, 999_999) }, "a RIFF length that isn't the file's"),
            (with { $0[32] = 0; $0[33] = 0 }, "a block align of zero"),
            (with { u32(&$0, 28, 44_100) }, "a byte rate that isn't 16 kHz × 2"),
            (wav(seconds: 1) + Data(count: 400), "data after the audio"),
            (with { u32(&$0, 40, 16_000) }, "a data chunk shorter than what follows it"),
        ]
        for (data, what) in refused {
            guard case .failure(let f) = AppHear.check(wav: data) else { XCTFail("took \(what)"); continue }
            XCTAssertEqual(f.status, 400, what)
        }
        // Another chunk before the audio (as some recorders add): not what the hosts write, so refused too.
        var listed = [UInt8](wav(seconds: 1))
        let list: [UInt8] = Array("LIST".utf8) + [4, 0, 0, 0] + Array("INFO".utf8)
        listed.insert(contentsOf: list, at: 36)
        let riff = listed.count - 8
        for k in 0..<4 { listed[4 + k] = UInt8((riff >> (8 * k)) & 0xff) }
        guard case .failure = AppHear.check(wav: Data(listed)) else { return XCTFail("took a LIST chunk") }
    }

    /// The page tries each way to the Mac in turn, so the same recording can arrive twice (the first answer lost on the
    /// way back). Both carry the page's id for it, and Lamp transcribes, and charges, once.
    @MainActor
    func testTheSameRecordingArrivingTwiceIsTranscribedAndChargedOnce() async throws {
        let audio = wav(seconds: 1).base64EncodedString()
        let body = try JSONSerialization.data(withJSONObject: ["audio": audio, "op": "h-\(UUID().uuidString)"])
        var calls = 0
        let transcribe: @MainActor (String) async -> Result<AppHear.Heard, AppHear.Failure> = { _ in
            calls += 1
            try? await Task.sleep(nanoseconds: 50_000_000)
            return .success(AppHear.Heard(text: "Add milk", seconds: 1, cost: 0.0001))
        }
        async let first = AppHear.handle(body, app: "homehq", hasKey: true, transcribe: transcribe)
        async let second = AppHear.handle(body, app: "homehq", hasKey: true, transcribe: transcribe)
        let (a, b) = await (first, second)
        // And once more after both have answered.
        let c = await AppHear.handle(body, app: "homehq", hasKey: true, transcribe: transcribe)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual([a.1["text"], b.1["text"], c.1["text"]] as? [String], ["Add milk", "Add milk", "Add milk"])
        XCTAssertEqual(a.2 + b.2 + c.2, 0.0001, accuracy: 1e-12, "charged once")
        // Another app's recording with the same id is its own.
        _ = await AppHear.handle(body, app: "other", hasKey: true, transcribe: transcribe)
        XCTAssertEqual(calls, 2)
    }
}
