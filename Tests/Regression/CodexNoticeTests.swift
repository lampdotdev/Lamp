import XCTest
@testable import Lamp

/// What Codex prints that isn't its JSON reaches the chat, apart from the notices Lamp causes on purpose.
final class CodexNoticeTests: XCTestCase {
    func testTheSandboxedSkillsLookupIsntShown() {
        let line = "2026-10-12T10:13:11.868830Z ERROR codex_skills_extension::loader::host: failed to walk skills root file:///Users/someone/.agents/skills: Operation not permitted (os error 1)"
        XCTAssertTrue(Agent.parse(line, engine: .codex).isEmpty)
    }

    func testOtherErrorsStillAre() {
        let line = "2026-10-12T10:14:38.579513Z ERROR codex_api::endpoint::responses_websocket: failed to connect to websocket: HTTP error: 401 Unauthorized"
        XCTAssertFalse(Agent.parse(line, engine: .codex).isEmpty)
    }
}
