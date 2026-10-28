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
        let (status, _, cost) = await AppHear.handle(big)
        XCTAssertEqual(status, 413)
        XCTAssertEqual(cost, 0)
        let (bad, _, _) = await AppHear.handle(Data("[1,2".utf8))
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
}
