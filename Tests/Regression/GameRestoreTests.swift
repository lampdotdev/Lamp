import JavaScriptCore
import XCTest
@testable import Lamp

/// A game's page opened again for a change of its code starts where the player was (lamp-game.js, "Changes while it's
/// played"): the state is the game's to read before it starts, so it never shows its title first and is then patched.
@MainActor
final class GameRestoreTests: XCTestCase {
    /// Opens the page as it opens after a change, with `state` kept for it, and runs `game` (the game() call) and one
    /// frame; gives what the page recorded.
    private func reopen(_ game: String) throws -> [String: Any] {
        var failed: String?
        let context = try GameRuntimePage.load(page: """
            var testStore = { 'lamp.live': JSON.stringify({ state: { level: 3, overlay: 'map' }, gen: 2 }) };
            var sessionStorage = { getItem: function (k) { return k in testStore ? testStore[k] : null; },
                                   setItem: function (k, v) { testStore[k] = v; }, removeItem: function (k) { delete testStore[k]; } };
            var location = { reload: function () { seen.reloads++; } };
            var seen = { reloads: 0, restored: null, inInit: null, framesBeforeRestore: null, frames: 0 };
            """) { failed = failed ?? $0 }
        context.evaluateScript(game)
        context.evaluateScript("if (testFrames.length) testFrames.shift()(1000);")
        context.evaluateScript("seen.afterStart = pendingRestore(); seen.kept = testStore['lamp.live'] || null; seen.logs = testLogs.join('\\n');")
        XCTAssertNil(failed)
        return context.evaluateScript("seen")?.toDictionary() as? [String: Any] ?? [:]
    }

    func testAGameStartsWhereItWasBeforeItsFirstFrame() throws {
        // Read at start: the game builds that place in init, restore() isn't called, and the state is gone once it's
        // started (restored once).
        let read = try reopen("""
            game({ renderer: testRenderer, init: function () { seen.inInit = pendingRestore(); },
                   restore: function (s) { seen.restored = s; }, frame: function () { seen.frames++; } });
            """)
        XCTAssertEqual((read["inInit"] as? [String: Any])?["overlay"] as? String, "map")
        XCTAssertTrue(read["restored"] is NSNull, "\(read)")
        XCTAssertEqual(read["frames"] as? Int, 1)
        XCTAssertTrue(read["afterStart"] is NSNull && read["kept"] is NSNull, "\(read)")
        XCTAssertEqual(read["reloads"] as? Int, 0)

        // A game with only restore(): given the state before its first frame.
        let patched = try reopen("""
            game({ renderer: testRenderer, restore: function (s) { seen.restored = s; seen.framesBeforeRestore = seen.frames; },
                   frame: function () { seen.frames++; } });
            """)
        XCTAssertEqual((patched["restored"] as? [String: Any])?["level"] as? Int, 3)
        XCTAssertEqual(patched["framesBeforeRestore"] as? Int, 0)

        // Starting from the state fails: the page opens once more, fresh, and the log says so.
        let failed = try reopen("""
            game({ renderer: testRenderer, init: function () { pendingRestore(); throw new Error('no level 3'); }, frame: function () {} });
            """)
        XCTAssertEqual(failed["reloads"] as? Int, 1)
        XCTAssertTrue((failed["kept"] as? String)?.contains("\"fresh\":true") == true, "\(failed)")
        XCTAssertTrue((failed["logs"] as? String)?.contains("so it starts fresh") == true, "\(failed)")
    }
}
