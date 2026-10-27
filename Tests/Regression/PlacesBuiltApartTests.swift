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

    /// Android's phone and TV places build one APK: one built before each place had its own record gives both a record
    /// that matches no code, before a build writes the first, so neither is taken for never built.
    func testAnAPKFromBeforeRecordsMakesBothAndroidPlacesBehind() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("android-places-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Web"), withIntermediateDirectories: true)
        var screen = LampProject(id: "android-places", name: "Board", exe: "Board", dir: dir)
        screen.platform = .screen
        screen.places = [.mac, .android, .androidTV]
        let apk = GameAndroid.apk(screen)
        try FileManager.default.createDirectory(at: apk.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: apk)
        Runtime.recordAndroidBuiltBefore(screen)
        let phone = screen.at(.android)
        Runtime.markBuilt(phone, from: Runtime.fingerprint(phone))
        Runtime.recordAndroidBuiltBefore(screen)
        XCTAssertFalse(Runtime.behind(screen, at: .android))
        XCTAssertTrue(Runtime.behind(screen, at: .androidTV))
        XCTAssertNotNil(Runtime.builtFingerprint(screen.at(.androidTV)))
    }
}
