import XCTest
@testable import Lamp

/// What builds is offered in the chat with a click, never chosen for the person.
final class BuilderLineTests: XCTestCase {
    func testOnlyAnEngineInstalledAndSignedInIsOffered() {
        let both = BuilderLine.offers(installed: { _ in true }, signedIn: { _ in true })
        XCTAssertEqual(both, [.claude, .codex])
        XCTAssertEqual(BuilderLine.offers(installed: { $0 == .codex }, signedIn: { _ in true }), [.codex])
        XCTAssertEqual(BuilderLine.offers(installed: { _ in true }, signedIn: { $0 == .claude }), [.claude])
        XCTAssertEqual(BuilderLine.offers(installed: { _ in false }, signedIn: { _ in true }), [])
        XCTAssertEqual(BuilderLine.offers(installed: { _ in true }, signedIn: { _ in false }), [])
    }

    func testTheLineSaysWhoseAccountIsUsedOnlyWhenOneIsOffered() {
        XCTAssertEqual(BuilderLine.status([.claude]), "Uses your signed-in account.")
        XCTAssertEqual(BuilderLine.status([]), "Your request starts as soon as this is done.")
    }

    /// What's offered is read back from the saved chat, so a click can only ever take one of Claude Code and Codex.
    func testOnlyWhatWasOfferedComesBack() {
        XCTAssertEqual(BuilderLine.engines(in: BuilderLine.text([.claude, .codex])), [.claude, .codex])
        XCTAssertEqual(BuilderLine.engines(in: ""), [])
        XCTAssertEqual(BuilderLine.engines(in: "pi something claude"), [.claude])
    }

    func testARefusedPrebuiltStarterIsTriedAgainOnlyWhenOpenedOrWithTheTools() {
        XCTAssertFalse(Store.triesStarter(refused: true, opened: false, hasTools: false))
        XCTAssertTrue(Store.triesStarter(refused: true, opened: true, hasTools: false))
        XCTAssertTrue(Store.triesStarter(refused: true, opened: false, hasTools: true))
        XCTAssertTrue(Store.triesStarter(refused: false, opened: false, hasTools: false))
    }
}
