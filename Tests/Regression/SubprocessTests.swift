import XCTest
@testable import Lamp

/// How the one runner treats a tool's input: closed at once unless a caller asks for it to stay open.
final class SubprocessTests: XCTestCase {
    /// Answers a moment after it starts, again much later, and quits as soon as its input closes, as webOS's
    /// `luna-send-pub -i` does.
    private let quitsWhenInputCloses = ["-c", "( sleep 0.5; echo installed; sleep 20; echo late ) & cat > /dev/null; kill $! 2>/dev/null"]

    func testAToolThatQuitsWhenItsInputClosesAnswersWhileTheInputIsKeptOpen() async {
        let start = Date()
        let result = await Subprocess.run("/bin/sh", quitsWhenInputCloses, timeout: 30,
                                          keepInputOpenUntil: { $0.contains("installed") })
        XCTAssertTrue(result.ok)
        XCTAssertEqual(result.output.trimmed, "installed")
        XCTAssertLessThan(Date().timeIntervalSince(start), 10, "the input closes at the answer, not at the deadline")
    }

    func testWithoutBeingAskedTheInputClosesAtOnceAsBefore() async {
        let result = await Subprocess.run("/bin/sh", quitsWhenInputCloses, timeout: 30)
        XCTAssertTrue(result.ok)
        XCTAssertEqual(result.output.trimmed, "")
        let written = await Subprocess.run("/bin/cat", input: Data("secret".utf8))
        XCTAssertEqual(written.output, "secret")
    }

    func testInputKeptOpenStillGoesWhenTheToolEndsOrTheDeadlinePasses() async {
        let start = Date()
        let byItself = await Subprocess.run("/bin/echo", ["done"], timeout: 30, keepInputOpenUntil: { _ in false })
        XCTAssertEqual(byItself.output.trimmed, "done")
        XCTAssertLessThan(Date().timeIntervalSince(start), 10)
        let neverAnswered = await Subprocess.run("/bin/cat", timeout: 1, input: Data("given".utf8), keepInputOpenUntil: { _ in false })
        XCTAssertTrue(neverAnswered.timedOut)
        XCTAssertEqual(neverAnswered.output, "given", "what was given is written before the input is held")
    }
}
