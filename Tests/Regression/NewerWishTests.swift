import XCTest
@testable import Lamp

/// A wish laid out by a newer Lamp (`NewerWish`) is left alone by this one, not read as its own.
final class NewerWishTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("newer-wish-\(UUID().uuidString)").resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    /// A newer Lamp keeps a wish's Mac app in Mac/ and nothing to build at the wish's root. Read as this Lamp's, the
    /// root is a draft with no scaffold, and the first message would write a new app over the wish.
    func testAWishLaidOutByANewerLampIsLeftAlone() throws {
        let wish = root.appendingPathComponent("habits")
        let mac = wish.appendingPathComponent("Mac")
        try FileManager.default.createDirectory(at: wish.appendingPathComponent(".lamp"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: mac.appendingPathComponent(".lamp"), withIntermediateDirectories: true)
        try #"{"name":"Habits","exe":"Habits","instance":"a1","layout":3,"apps":[{"folder":"Mac","kind":"mac"}]}"#
            .write(to: wish.appendingPathComponent(".lamp/meta.json"), atomically: true, encoding: .utf8)
        try #"{"name":"Habits","exe":"Habits","platform":"mac"}"#.write(to: mac.appendingPathComponent(".lamp/meta.json"), atomically: true, encoding: .utf8)
        try #"let package = Package(name: "Habits", platforms: [.macOS(.v14)])"#
            .write(to: mac.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)

        XCTAssertNil(Store.readWish(at: wish))
        XCTAssertEqual(NewerWish.read(at: wish)?.name, "Habits")
    }

    /// This Lamp's own wishes, which say no layout, are read as they always were.
    func testAWishOfThisLampsLayoutIsRead() throws {
        let wish = root.appendingPathComponent("notes")
        try FileManager.default.createDirectory(at: wish.appendingPathComponent(".lamp"), withIntermediateDirectories: true)
        try #"{"name":"Notes","exe":"Notes"}"#.write(to: wish.appendingPathComponent(".lamp/meta.json"), atomically: true, encoding: .utf8)
        XCTAssertNil(NewerWish.read(at: wish))
        XCTAssertEqual(Store.readWish(at: wish)?.name, "Notes")
    }
}
