import XCTest
@testable import Lamp

/// While the agent tries an app (`use_app`), the person can take it back: with Lamp's Stop or Esc, which reach a
/// Mac app as a stop signed with its token, or by clicking or typing in the app themselves. Then the rest of the
/// actions are dropped, keys the driver holds down are let go, and Lamp hears how far it got.
@MainActor
final class UseAppStopTests: XCTestCase {
    /// The app's half (`LampDriver.Handover` in LampSupport.swift) is cut out of the template, compiled into a small
    /// app and sent real events through its own event queue, the way the person's clicks and keys arrive.
    func testTheAppStopsForThePersonButNotForItsOwnKeysOrAForgedStop() throws {
        let support = Template.lampSupportSwift
        let start = try XCTUnwrap(support.range(of: "// begin LampDriver.Handover"))
        let end = try XCTUnwrap(support.range(of: "// end LampDriver.Handover", range: start.upperBound..<support.endIndex))
        let token = "made-up-token"
        // Signed by Lamp's own code, so the two halves are held to one scheme.
        let good = Store.signature(over: "stop\ntwo", token: token)
        let forged = Store.signature(over: "stop\ntwo", token: "another-token")
        let earlier = Store.signature(over: "stop\none", token: token)
        let program = """
        import AppKit
        import CryptoKit

        @MainActor enum LampDriver {
        \(support[start.upperBound..<end.lowerBound])
        }

        func say(_ line: String) { print(line); fflush(stdout) }
        func key(_ type: NSEvent.EventType, _ code: UInt16, _ characters: String) -> NSEvent {
            NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0,
                             context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
        }
        func click() -> NSEvent {
            NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        func later(_ seconds: Double, _ work: @escaping @MainActor () -> Void) {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { MainActor.assumeIsolated { work() } }
        }

        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        _ = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { event in
            say("let go of \\(event.characters ?? "")")
            return event
        }
        later(0.1) {
            // A batch of three, one begun, holding a key down for five seconds: the held key is its own, not the person's.
            let one = LampDriver.Handover.begin(id: "one", count: 3) { say("one: " + $0) }
            one.done = 1
            one.hold(key(.keyDown, 0, "a"), key(.keyUp, 0, "a"), for: 5)
            later(0.4) {
                say("one carries on after its own key: \\(one.carriesOn)")
                // The person types a letter of their own.
                NSApp.postEvent(key(.keyDown, 7, "x"), atStart: false)
                later(0.4) {
                    say("one carries on after the person's key: \\(one.carriesOn)")
                    // Lamp's Stop: only one signed with the app's token, for the batch running now, stops it.
                    let two = LampDriver.Handover.begin(id: "two", count: 2) { say("two: " + $0) }
                    LampDriver.Handover.stop(id: "two", signature: "\(forged)", token: "\(token)")
                    LampDriver.Handover.stop(id: "one", signature: "\(earlier)", token: "\(token)")
                    LampDriver.Handover.stop(id: "two", signature: nil, token: "\(token)")
                    say("two carries on after forged stops: \\(two.carriesOn)")
                    LampDriver.Handover.stop(id: "two", signature: "\(good)", token: "\(token)")
                    say("two carries on after Lamp's stop: \\(two.carriesOn)")
                    // The person clicks.
                    let three = LampDriver.Handover.begin(id: "three", count: 4) { say("three: " + $0) }
                    three.done = 2
                    NSApp.postEvent(click(), atStart: false)
                    later(0.4) {
                        say("three carries on after the person's click: \\(three.carriesOn)")
                        // Every action done: the person's keys are theirs alone from then on.
                        let four = LampDriver.Handover.begin(id: "four", count: 1) { say("four: " + $0) }
                        four.done = 1
                        four.end()
                        NSApp.postEvent(key(.keyDown, 53, "\\u{1b}"), atStart: false)
                        later(0.4) { say("done"); exit(0) }
                    }
                }
            }
        }
        app.run()
        """
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-use-stop-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        try program.write(to: work.appendingPathComponent("main.swift"), atomically: true, encoding: .utf8)
        let built = try run(Shell.compatibleSDK + "xcrun swiftc -o app main.swift 2>&1", in: work)
        XCTAssertEqual(built.status, 0, built.output)

        let ran = try run("./app", in: work)
        XCTAssertEqual(ran.status, 0, ran.output)
        XCTAssertEqual(ran.output, """
        one carries on after its own key: true
        one: Stopped after 1 of 3 actions: the person took the app over. Nothing after that was done.
        let go of a
        one carries on after the person's key: false
        two carries on after forged stops: true
        two: Stopped after 0 of 2 actions: the person took the app over. Nothing after that was done.
        two carries on after Lamp's stop: false
        three: Stopped after 2 of 4 actions: the person took the app over. Nothing after that was done.
        three carries on after the person's click: false
        done

        """)
    }

    /// On an iPhone the simulator is another app, so Lamp watches it: a press is the person's when Lamp didn't post
    /// it, and it's a click in the simulator's window or a key while the simulator is in front.
    func testOnlyThePersonsOwnPressInTheSimulatorTakesItBack() {
        let simulator: pid_t = 501
        let window = CGRect(x: 100, y: 100, width: 400, height: 800)
        let inside = CGPoint(x: 300, y: 500), outside = CGPoint(x: 900, y: 500)
        XCTAssertTrue(Handover.isPersons(key: false, mark: 0, at: inside, frontmost: 77, window: window, of: simulator))
        XCTAssertFalse(Handover.isPersons(key: false, mark: Handover.mark, at: inside, frontmost: 77, window: window, of: simulator))
        XCTAssertFalse(Handover.isPersons(key: false, mark: 0, at: outside, frontmost: simulator, window: window, of: simulator))
        XCTAssertFalse(Handover.isPersons(key: false, mark: 0, at: inside, frontmost: simulator, window: nil, of: simulator))
        XCTAssertTrue(Handover.isPersons(key: true, mark: 0, at: outside, frontmost: simulator, window: window, of: simulator))
        XCTAssertFalse(Handover.isPersons(key: true, mark: Handover.mark, at: outside, frontmost: simulator, window: window, of: simulator))
        XCTAssertFalse(Handover.isPersons(key: true, mark: 0, at: inside, frontmost: 77, window: window, of: simulator))
    }

    private func run(_ command: String, in directory: URL) throws -> (status: Int32, output: String) {
        TestShell.run(command, in: directory)
    }
}
