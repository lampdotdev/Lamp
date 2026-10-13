import XCTest
@testable import Lamp

/// A build asks the app to quit before replacing it, and never ends one that may be asking the person about
/// work they haven't saved.
final class AppQuitTests: XCTestCase {
    /// The error numbers are what an app's reply to a quit request carried, each seen from a real app: -128
    /// when its unsaved-work question was answered Cancel, 0 when it was answered Discard or there was nothing
    /// to ask, and none at all when the app was ended from outside while the request waited.
    func testTheReplySaysWhetherTheAppStays() {
        XCTAssertEqual(AppQuit.reply(errorNumber: -128), .refused)
        XCTAssertEqual(AppQuit.reply(errorNumber: 0), .agreed)
        XCTAssertEqual(AppQuit.reply(errorNumber: nil), .agreed)
        // Any other error isn't the app saying it will go.
        XCTAssertNil(AppQuit.reply(errorNumber: -1708))
    }

    /// Only the app's own answer ends the wait: it may be asking the person, or saving with its main thread
    /// busy, for as long as that takes. There is no input for how long it has been, or how quiet.
    func testAnAppThatHasNotAnsweredIsWaitedFor() {
        XCTAssertEqual(AppQuit.step(terminated: false, reply: nil, sinceReply: 0), .wait)
    }

    func testAnAppThePersonKeptOpenIsKept() {
        XCTAssertEqual(AppQuit.step(terminated: false, reply: .refused, sinceReply: 3600), .kept)
    }

    func testAnAppThatQuitIsClosed() {
        XCTAssertEqual(AppQuit.step(terminated: true, reply: nil, sinceReply: 0), .closed)
        XCTAssertEqual(AppQuit.step(terminated: true, reply: .refused, sinceReply: 0), .closed)
    }

    /// It agreed to quit and is still there: the person has had their say.
    func testOnlyAnAppThatAgreedToQuitIsEnded() {
        XCTAssertEqual(AppQuit.step(terminated: false, reply: .agreed, sinceReply: 1), .wait)
        XCTAssertEqual(AppQuit.step(terminated: false, reply: .agreed, sinceReply: AppQuit.closing + 1), .force)
    }

    func testOnlyTheCopyThatSaidItListensIsTakenAtItsWord() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        XCTAssertFalse(AppQuit.listens(41, runtime: folder))
        try "41\n".write(to: folder.appendingPathComponent(AppQuit.listeningFile), atomically: true, encoding: .utf8)
        XCTAssertTrue(AppQuit.listens(41, runtime: folder))
        // The file is from an earlier run of the app: this copy hasn't said anything.
        XCTAssertFalse(AppQuit.listens(42, runtime: folder))
    }
}
