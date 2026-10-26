import JavaScriptCore
import XCTest

/// The game runtime's own measure of the frame rate wherever a three.js game is played (`lamp-game.js`): what the log
/// says of it, and the drawing made smaller when frames run slow, the same on every device. Frames are given at the
/// times a device would give them, from how long a frame takes at the size the game is drawn.
@MainActor
final class GameFrameRateTests: XCTestCase {
    /// Plays `seconds` of frames, each taking `ms(width)` for the width the game is drawn at; gives what was logged
    /// and every size the drawing was set to.
    private func play(seconds: Double, sharp: Bool = false, ms: @escaping (Int) -> Double) throws -> (logs: [String], sizes: [String]) {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Resources/GameKit/web/lamp-game.js"), encoding: .utf8)
        let context = try XCTUnwrap(JSContext())
        var failed: String?
        context.exceptionHandler = { _, value in failed = failed ?? value?.toString() ?? "?" }
        context.evaluateScript("""
            var window = this, testLogs = [], testSizes = [], testFrames = [];
            var console = { log: function (line) { testLogs.push(String(line)); } };
            function addEventListener() {}
            var navigator = { maxTouchPoints: 0 }, innerWidth = 1920, innerHeight = 1080;
            var document = { documentElement: { style: {} }, body: { style: {}, append: function () {} } };
            function requestAnimationFrame(fn) { testFrames.push(fn); }
            var testRenderer = { domElement: { style: {} }, width: 1920, setPixelRatio: function () {},
                             setSize: function (w, h) { this.width = w; testSizes.push(w + 'x' + h); } };
            """)
        // The module as a script in a scope of its own, as a module has, giving its game().
        context.evaluateScript("(function () {\n" + source.replacingOccurrences(of: "export ", with: "") + "\nwindow.game = game; })();")
        context.evaluateScript("game({ renderer: testRenderer, frame: function () {}, sharp: \(sharp) });")
        let tick = try XCTUnwrap(context.evaluateScript("(function (now) { var fn = testFrames.shift(); fn(now); return testRenderer.width; })"))
        var now = 1000.0, width = 1920
        while now < 1000 + seconds * 1000 {
            width = Int(tick.call(withArguments: [now]).toInt32())
            if let failed { XCTFail(failed); break }
            now += ms(width)
        }
        let logs = context.evaluateScript("testLogs")?.toArray() as? [String] ?? []
        let sizes = context.evaluateScript("testSizes")?.toArray() as? [String] ?? []
        // Without the times, and only what's said of frames.
        return (logs.map { $0.replacingOccurrences(of: #"^\[[0-9.]+ s\] "#, with: "", options: .regularExpression) }
                    .filter { !$0.contains("controller") }, sizes)
    }

    /// A device that keeps up: drawn at 1920x1080 throughout, and the log says it gets 60 frames a second.
    func testAFastDeviceKeepsTheFullSizeAndSaysItsRate() throws {
        let played = try play(seconds: 21) { _ in 1000 / 60 }
        XCTAssertEqual(played.sizes, ["1920x1080"])
        XCTAssertEqual(played.logs.filter { $0.contains("frames a second") }.count, 2)
        XCTAssertTrue(played.logs.allSatisfy { $0.hasPrefix("Lamp: 60 frames a second") && $0.hasSuffix("drawn at 1920x1080.") }, "\(played.logs)")
    }

    /// A device slow at drawing pixels (30 frames a second at full size, 60 with fewer pixels): drawn smaller once,
    /// and the log says so and then how fast it comes.
    func testSlowDrawingIsMadeSmaller() throws {
        let played = try play(seconds: 12) { width in width == 1920 ? 1000 / 30 : 1000 / 60 }
        XCTAssertEqual(played.sizes, ["1920x1080", "1440x810"])
        XCTAssertEqual(played.logs.first, "Lamp: frames were slow (30 a second), so the game is now drawn at 1440x810 and scaled up to the screen.")
        XCTAssertTrue(played.logs.contains { $0.hasSuffix("drawn at 1440x810.") }, "\(played.logs)")
    }

    /// One long frame among quick ones (a window shown, a file read: over half a second once, as a Mac in a virtual
    /// machine had as a game opened) is a hitch, not a device too slow to draw: the game stays at full size.
    func testOneHitchDoesntMakeItSmaller() throws {
        var frames = 0
        let played = try play(seconds: 12) { _ in frames += 1; return frames == 400 ? 600 : 1000 / 60 }
        XCTAssertEqual(played.sizes, ["1920x1080"])
    }

    /// Still too slow after the first step but faster for it: a second step, down to half the size.
    func testVerySlowDrawingTakesAnotherStep() throws {
        let played = try play(seconds: 12) { width in width == 1920 ? 100 : width == 1440 ? 50 : 1000 / 60 }
        XCTAssertEqual(played.sizes, ["1920x1080", "1440x810", "960x540"])
    }

    /// Slow whatever the size (a busy frame function, or a screen that refreshes 30 times a second): the smaller
    /// drawing is undone and no more are tried.
    func testSlowFramesThatArentTheDrawingKeepTheFullSize() throws {
        let played = try play(seconds: 30) { _ in 1000 / 30 }
        XCTAssertEqual(played.sizes, ["1920x1080", "1440x810", "1920x1080"])
        XCTAssertTrue(played.logs.contains("Lamp: drawing smaller didn't make frames faster (30 a second, then 30), so the game is drawn at 1920x1080 again."), "\(played.logs)")
    }

    /// A game that asks to stay sharp is never drawn smaller, and still hears its rate.
    func testASharpGameKeepsItsSize() throws {
        let played = try play(seconds: 11, sharp: true) { _ in 1000 / 30 }
        XCTAssertEqual(played.sizes, ["1920x1080"])
        XCTAssertTrue(played.logs.contains { $0.hasPrefix("Lamp: 30 frames a second") }, "\(played.logs)")
    }
}
