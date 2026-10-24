import XCTest
@testable import Lamp

/// Undo Last Change in the chat is offered only for the latest change, and only when the app's code as it was
/// before can still read what the changed app saved: Undo puts the code back, never the data. Each case is a real
/// history and a real compile of both versions.
final class UndoOfferTests: XCTestCase {
    private let escape = HistoryEscapeTests()
    override func tearDown() { escape.tearDown() }

    private let before = """
        import Foundation
        struct Watering: Codable, Identifiable {
            var id: UUID
            var plant: String
            var when: Date
            var how: Method
        }
        enum Method: String, Codable { case can, hose }
        """

    /// An app at `before`, then a request that changed it to `after`, linked in the chat as Lamp links it.
    private func changed(from start: String? = nil, to after: String) async throws -> (app: HistoryEscapeTests.App, chat: [LogLine]) {
        let app = try escape.app()
        let file = app.project.dir.appendingPathComponent("Sources/App.swift")
        try (start ?? before).write(to: file, atomically: true, encoding: .utf8)
        let first = await Versions.save(app.project, message: "Log watering")
        XCTAssertTrue(first)
        try after.write(to: file, atomically: true, encoding: .utf8)
        let second = await Versions.save(app.project, message: "Add how much water")
        XCTAssertTrue(second)
        let head = await Versions.head(app.project)
        var request = LogLine(kind: .user, text: "Let me add how much water, too.")
        request.version = head
        return (app, [request, LogLine(kind: .status, text: "Coin Flip is ready")])
    }

    private func offer(_ app: HistoryEscapeTests.App, _ chat: [LogLine]) async -> String? {
        await UndoOffer.version(for: app.project, chat: chat)
    }

    func testAnOptionalFieldAddedIsOffered() async throws {
        let (app, chat) = try await changed(to: before.replacingOccurrences(of: "var how: Method", with: "var how: Method\n    var millilitres: Int?"))
        let offered = await offer(app, chat)
        XCTAssertEqual(offered, chat[0].version, "the older code reads entries with an amount: it ignores the amount")
    }

    func testAFieldRenamedIsNotOffered() async throws {
        let (app, chat) = try await changed(to: before.replacingOccurrences(of: "var plant: String", with: "var plantName: String"))
        let offered = await offer(app, chat)
        XCTAssertNil(offered, "entries saved without `plant` can't be read by the older code")
    }

    func testAFieldRetypedIsNotOffered() async throws {
        let (app, chat) = try await changed(to: before.replacingOccurrences(of: "var when: Date", with: "var when: String"))
        let offered = await offer(app, chat)
        XCTAssertNil(offered, "a date saved as words can't be read as a date")
    }

    func testACaseAddedToASavedEnumIsNotOffered() async throws {
        let (app, chat) = try await changed(to: before.replacingOccurrences(of: "case can, hose", with: "case can, hose, rain"))
        let offered = await offer(app, chat)
        XCTAssertNil(offered, "an entry watered by rain can't be read by code that knows only can and hose")
    }

    func testNotOfferedOnceTheAppHasMovedOn() async throws {
        let (app, chat) = try await changed(to: before + "\n// darker\n")
        let offered = await offer(app, chat)
        XCTAssertEqual(offered, chat[0].version)
        // Undone from the toolbar: the change in the chat is no longer the app's current version.
        let versions = await Versions.list(app.project)
        let (undoing, target) = try XCTUnwrap(Versions.undoTarget(in: versions))
        let undone = await Versions.restore(app.project, to: target, message: "Undid “\(undoing.label)”", trailer: "Lamp-Undid: \(undoing.id)")
        XCTAssertTrue(undone)
        let after = await offer(app, chat)
        XCTAssertNil(after)
    }

    func testNotOfferedWithUnsavedWork() async throws {
        let (app, chat) = try await changed(to: before + "\n// darker\n")
        try "// a stopped turn's edit\n".write(to: app.project.dir.appendingPathComponent("Sources/More.swift"), atomically: true, encoding: .utf8)
        let offered = await offer(app, chat)
        XCTAssertNil(offered, "the toolbar's Undo would discard the unsaved work, not this change")
    }

    func testAKeyRenamedInCodingKeysIsNotOffered() async throws {
        let keys = "\n    enum CodingKeys: String, CodingKey { case id, plant = \"plant_name\", when, how }\n}"
        let after = before.replacingOccurrences(of: "var how: Method\n}", with: "var how: Method" + keys)
        let (app, chat) = try await changed(to: after)
        let offered = await offer(app, chat)
        XCTAssertNil(offered, "entries saved under plant_name have no `plant` for the older code")
    }

    func testARawValueChangedIsNotOffered() async throws {
        let (app, chat) = try await changed(to: before.replacingOccurrences(of: "case can, hose", with: "case can = \"watering-can\", hose"))
        let offered = await offer(app, chat)
        XCTAssertNil(offered, "an entry saved as watering-can can't be read by code that knows only can and hose")
    }

    func testAnOptionalRetypedIsNotOffered() async throws {
        let start = before.replacingOccurrences(of: "var how: Method", with: "var how: Method\n    var amount: Int?")
        let (app, chat) = try await changed(from: start, to: start.replacingOccurrences(of: "var amount: Int?", with: "var amount: String?"))
        let offered = await offer(app, chat)
        XCTAssertNil(offered, "an amount saved as \"a cup\" can't be read as a number, and the whole entry is skipped")
    }

    func testAnOptionalTakenAwayIsOffered() async throws {
        let start = before.replacingOccurrences(of: "var how: Method", with: "var how: Method\n    var amount: Int?")
        let (app, chat) = try await changed(from: start, to: before)
        let offered = await offer(app, chat)
        XCTAssertEqual(offered, chat[0].version, "the older code reads an entry without an amount")
    }

    /// A TV wish with a Mac app beside it: the TV app at the root, the Mac app's Swift in Mac/, a change made to that.
    private func changedMacPart(to after: String) async throws -> (wish: LampProject, part: LampProject, chat: [LogLine]) {
        let app = try escape.app()
        let dir = app.project.dir, fm = FileManager.default
        try fm.createDirectory(at: dir.appendingPathComponent("Mac"), withIntermediateDirectories: true)
        try fm.moveItem(at: dir.appendingPathComponent("Sources"), to: dir.appendingPathComponent("Mac/Sources"))
        try fm.createDirectory(at: dir.appendingPathComponent("Web"), withIntermediateDirectories: true)
        try "".write(to: dir.appendingPathComponent("Web/lamp.js"), atomically: true, encoding: .utf8)
        let wish = LampProject(id: "coinflip", name: "Coin Flip", exe: "CoinFlip", dir: dir, platform: .tv)
        let part = LampProject(id: "coinflip.mac", name: "Coin Flip", exe: "CoinFlip", dir: dir.appendingPathComponent("Mac"),
                               platform: .mac, partOf: "coinflip")
        let file = dir.appendingPathComponent("Mac/Sources/App.swift")
        try before.write(to: file, atomically: true, encoding: .utf8)
        let first = await Versions.save(wish, message: "Log watering")
        XCTAssertTrue(first)
        try after.write(to: file, atomically: true, encoding: .utf8)
        let second = await Versions.save(wish, message: "Add how much water")
        XCTAssertTrue(second)
        var request = LogLine(kind: .user, text: "Let me add how much water, too.")
        request.version = await Versions.head(wish)
        return (wish, part, [request, LogLine(kind: .status, text: "Coin Flip is ready")])
    }

    /// The wish's code is its Mac app's, in Mac/: looked for at the root, where the TV app has none, it was never
    /// found, and Undo was never offered in a TV wish.
    func testAChangeToAWishsMacAppIsOfferedWhenItsDataStaysReadable() async throws {
        let (wish, part, chat) = try await changedMacPart(to: before.replacingOccurrences(of: "var how: Method", with: "var how: Method\n    var millilitres: Int?"))
        let offered = await UndoOffer.version(for: wish, chat: chat, parts: [part])
        XCTAssertEqual(offered, chat[0].version, "the Mac app's older code reads entries with an amount")
    }

    func testAChangeToAWishsMacAppIsNotOfferedWhenItsDataWouldBeLost() async throws {
        let (wish, part, chat) = try await changedMacPart(to: before.replacingOccurrences(of: "var plant: String", with: "var plantName: String"))
        let offered = await UndoOffer.version(for: wish, chat: chat, parts: [part])
        XCTAssertNil(offered, "entries the Mac app saved without `plant` can't be read by its older code")
    }

    /// A turn's end, the chat shown and the sidebar all ask at once: every one of them gets the answer.
    func testLooksAtTheSameTimeAgree() async throws {
        let (app, chat) = try await changed(to: before.replacingOccurrences(of: "var how: Method", with: "var how: Method\n    var millilitres: Int?"))
        let versions = await Versions.list(app.project)
        let older = try XCTUnwrap(versions.dropFirst().first?.id), newer = try XCTUnwrap(chat[0].version)
        async let a = UndoOffer.keepsSavedDataReadable(app.project, from: older, to: newer)
        async let b = UndoOffer.keepsSavedDataReadable(app.project, from: older, to: newer)
        async let c = UndoOffer.keepsSavedDataReadable(app.project, from: older, to: newer)
        let answers = await [a, b, c]
        XCTAssertEqual(answers, [true, true, true])
    }
}
