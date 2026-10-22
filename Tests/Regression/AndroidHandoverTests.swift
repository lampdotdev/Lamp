import XCTest
@testable import Lamp

/// Once the person takes the emulator back (Stop, Esc or their own click), no more of Lamp's input reaches it, even
/// when they do it while Lamp's fingertip is still on its way to a spot or while the screen is being read between
/// the steps of one action. `Adb.perform` is given a stand-in for adb that records what it's sent.
@MainActor
final class AndroidHandoverTests: XCTestCase {
    /// adb as the device would answer it, with a hook for when the screen is read.
    private final class FakeAdb: @unchecked Sendable {
        var sent: [[String]] = []
        var onRead: () -> Void = {}
        private let lock = NSLock()
        static let screen = "<?xml version='1.0' encoding='UTF-8'?><hierarchy rotation=\"0\">" +
            "<node class=\"android.widget.EditText\" text=\"Old\" hint=\"Counter name\" bounds=\"[0,0][400,100]\" " +
            "clickable=\"true\" focused=\"true\" enabled=\"true\"/>" +
            "<node class=\"android.widget.Button\" text=\"Reset\" bounds=\"[0,200][400,300]\" clickable=\"true\" enabled=\"true\"/>" +
            "</hierarchy>"

        func run(_ arguments: [String], _ timeout: TimeInterval) async -> Subprocess.Result {
            lock.withLock { sent.append(arguments) }
            if arguments.contains("uiautomator") {
                let read = lock.withLock { onRead }
                await MainActor.run { read() }
                return Subprocess.Result(status: 0, output: Self.screen, errors: "", timedOut: false)
            }
            return Subprocess.Result(status: 0, output: "", errors: "", timedOut: false)
        }

        /// The input commands that reached the device: taps, swipes, keys and text, not the screen reads.
        var inputs: [[String]] { lock.withLock { sent.filter { $0.starts(with: ["shell", "input"]) && !$0.contains("KEYCODE_WAKEUP") } } }
    }

    private func perform(_ json: String, adb: FakeAdb, aim: @escaping @MainActor (CGPoint, String?, Bool) async -> Void = { _, _, _ in },
                         taken: @escaping @MainActor () -> Bool) async -> String {
        let actions = try! JSONDecoder().decode([Simulator.Driver.Action].self, from: Data(json.utf8))
        let screen = Adb.Screen.parse(FakeAdb.screen, scale: 1)
        return await Adb.perform(actions, on: "emulator-0", density: 160, screen: screen, aim: aim, tookOver: taken,
                                 adb: adb.run, stillMine: { !taken() })
    }

    func testATakeOverDuringTheGlideSendsNothing() async {
        let adb = FakeAdb()
        var taken = false
        let report = await perform(#"[{"action":"tap","x":50,"y":50},{"action":"tap","x":50,"y":250}]"#, adb: adb,
                                   aim: { _, _, _ in taken = true }, taken: { taken })
        XCTAssertEqual(adb.inputs, [], "a tap went out after the person took the app over")
        XCTAssertTrue(report.contains("took the app over"), report)
    }

    func testATakeOverWhileTypingStopsBeforeTheText() async {
        let adb = FakeAdb()
        var taken = false
        adb.onRead = { taken = true }   // the person takes over while the field is read, after the tap that focused it
        let report = await perform(#"[{"action":"type","target":"Counter name","text":"Water"}]"#, adb: adb, taken: { taken })
        XCTAssertEqual(adb.inputs.count, 1, "after the focusing tap, more input went out: \(adb.inputs)")
        XCTAssertFalse(adb.inputs.contains { $0.contains("text") }, "the text was typed after the person took over")
        XCTAssertTrue(report.contains("took the app over"), report)
    }

    func testATakeOverAfterASwipeSkipsItsTap() async {
        let adb = FakeAdb()
        var taken = false
        adb.onRead = { taken = true }   // the person takes over while the screen the swipe uncovered is read
        let report = await perform(#"[{"action":"swipe","x":200,"y":250,"direction":"left","item":"Reset"}]"#, adb: adb, taken: { taken })
        XCTAssertEqual(adb.inputs.map { $0[2] }, ["swipe"], "the swipe's tap went out after the person took over")
        XCTAssertTrue(report.contains("took the app over"), report)
    }
}
