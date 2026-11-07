import XCTest
@testable import Lamp

/// Whether a request in a chat waits for setup: only for what the chosen engine really lacks.
final class SetupReadinessTests: XCTestCase {
    /// A sign-in check that ran out of time, or whose tool couldn't start, couldn't tell: it isn't "signed out", which
    /// holds back a request the person's own sign-in can answer.
    func testACheckThatDidNotAnswerIsNotSignedOut() async {
        let slow = await Subprocess.run("/bin/sleep", ["5"], timeout: 1)
        XCTAssertTrue(slow.timedOut)
        XCTAssertNil(EngineSignIn.verdict(.claude, slow))
        XCTAssertNil(EngineSignIn.verdict(.codex, slow))

        let missing = await Subprocess.run("/nonexistent/claude", ["auth", "status"], timeout: 5)
        XCTAssertNil(EngineSignIn.verdict(.claude, missing))
        XCTAssertNil(EngineSignIn.verdict(.codex, missing))

        let refused = await Subprocess.run("/usr/bin/false", [], timeout: 5)
        XCTAssertEqual(EngineSignIn.verdict(.claude, refused), false, "a status that answers no is still signed out")
        XCTAssertEqual(EngineSignIn.verdict(.codex, refused), false)
    }

    /// pi inside Lamp is needed only when pi builds.
    func testClaudeCodeAndCodexBuildWithoutLampsOwnPi() {
        XCTAssertTrue(SetupCheck.hasAgent(for: .claude, bundledPi: nil))
        XCTAssertTrue(SetupCheck.hasAgent(for: .codex, bundledPi: nil))
        XCTAssertFalse(SetupCheck.hasAgent(for: .pi, bundledPi: nil))
        XCTAssertTrue(SetupCheck.hasAgent(for: .pi, bundledPi: URL(fileURLWithPath: "/bin/sh")))
    }

    /// With Claude Code chosen, the line names what it lacks rather than asking again what builds.
    func testTheLineNamesWhatTheChosenEngineLacks() {
        let signIn = "Sign in to \(Engine.claude.title) to build."
        XCTAssertEqual(BuilderLine.missing(engine: .claude, problem: signIn), signIn)
        XCTAssertNil(BuilderLine.missing(engine: .pi, problem: "Add your OpenRouter key."), "pi without a key is still to be chosen")
        XCTAssertEqual(BuilderLine.missing(engine: .pi, problem: Builder.piMissing), Builder.piMissing)

        let saved = BuilderLine.text([.codex], missing: signIn)
        XCTAssertEqual(BuilderLine.engines(in: saved), [.codex])
        XCTAssertEqual(BuilderLine.missing(in: saved), signIn)
        // A line saved before it said what's missing reads as it did.
        XCTAssertEqual(BuilderLine.engines(in: "claude codex"), [.claude, .codex])
        XCTAssertNil(BuilderLine.missing(in: "claude codex"))
    }
}
