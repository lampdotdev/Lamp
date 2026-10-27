import XCTest
@testable import Lamp

/// A screen or a game is built for each of its places on its own, so what each place's build was made from is kept
/// apart: a build for one place must never make another look up to date, or opening it there runs old code.
final class PlacesBuiltApartTests: XCTestCase {
    func testABuildForOnePlaceLeavesTheOthersBehind() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("places-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Web"), withIntermediateDirectories: true)
        try "<p>one</p>".write(to: dir.appendingPathComponent("Web/index.html"), atomically: true, encoding: .utf8)
        var screen = LampProject(id: "places", name: "Board", exe: "Board", dir: dir)
        screen.platform = .screen
        screen.places = [.mac, .ios, .android]
        for app in ["build/Board.app", "build/iOS/Board.app"] {
            try FileManager.default.createDirectory(at: dir.appendingPathComponent(app), withIntermediateDirectories: true)
        }
        let mac = screen.at(.mac), ios = screen.at(.ios), android = screen.at(.android)
        Runtime.markBuilt(mac, from: Runtime.fingerprint(mac))
        Runtime.markBuilt(android, from: Runtime.fingerprint(android))
        XCTAssertFalse(Runtime.behind(screen, at: .mac))

        // Changed, then built for the iPad only: the Mac's and Android's copies are older than the code.
        try "<p>two</p>".write(to: dir.appendingPathComponent("Web/index.html"), atomically: true, encoding: .utf8)
        Runtime.markBuilt(ios, from: Runtime.fingerprint(ios))
        XCTAssertFalse(Runtime.behind(screen, at: .ios))
        XCTAssertTrue(Runtime.behind(screen, at: .mac))
        XCTAssertNotEqual(Runtime.builtFingerprint(android), Runtime.fingerprint(android))

        // Built for Android: the Mac's record is its own, still behind.
        Runtime.markBuilt(android, from: Runtime.fingerprint(android))
        XCTAssertTrue(Runtime.behind(screen, at: .mac))
        XCTAssertEqual(Runtime.builtFingerprint(android), Runtime.fingerprint(android))
    }
}
