import XCTest
@testable import Lamp

/// An Objective-C exception thrown by a framework the app calls ends a generated app where it's thrown. Left to
/// AppKit (or to the Apple Event that asked for a window) it was logged and the app went on, with Swift's state
/// half unwound, and crashed minutes later in the background with a report that named neither. Here the template's
/// own code is cut out, compiled into a small app whose window opener throws as a web view's did, and run.
@MainActor
final class AppExceptionTests: XCTestCase {
    /// Clicking the app in the Dock (or Lamp's Play) with every window closed: Lamp's reopen handler opens one.
    func testAnExceptionOpeningAWindowOnReopenEndsTheApp() throws {
        let run = try runApp(trigger: "reopen")
        XCTAssertTrue(run.output.contains("opening a window"), run.output)
        XCTAssertFalse(run.output.contains("still running"), run.output)
        XCTAssertNotEqual(run.status, 0, run.output)
    }

    /// The app's own menu command (or button) throwing, under AppKit's handling of the event.
    func testAnExceptionInAMenuCommandEndsTheApp() throws {
        let run = try runApp(trigger: "command")
        XCTAssertTrue(run.output.contains("running the command"), run.output)
        XCTAssertFalse(run.output.contains("still running"), run.output)
        XCTAssertNotEqual(run.status, 0, run.output)
    }

    private func runApp(trigger: String) throws -> (status: Int32, output: String) {
        let support = Template.lampSupportSwift
        let start = try XCTUnwrap(support.range(of: "// begin LampWindows.calls"))
        let end = try XCTUnwrap(support.range(of: "// end LampWindows.calls", range: start.upperBound..<support.endIndex))
        let program = """
        import AppKit

        enum LampWindows {
        \(support[start.upperBound..<end.lowerBound])
            @MainActor static func installReopen() { ReopenHandler.shared.install() }
            // The new window's first view, as WebKit refused a script message handler added a second time.
            @MainActor static func show() {
                print("opening a window"); fflush(stdout)
                NSException(name: .invalidArgumentException, reason: "made-up refusal", userInfo: nil).raise()
            }
        }

        final class Command: NSObject {
            @objc func run(_ sender: Any?) {
                print("running the command"); fflush(stdout)
                NSException(name: .invalidArgumentException, reason: "made-up refusal", userInfo: nil).raise()
            }
        }

        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        LampWindows.endsAtAnException()
        MainActor.assumeIsolated { LampWindows.installReopen() }
        let command = Command()
        let menu = NSMenu(), top = NSMenuItem(), submenu = NSMenu()
        let item = NSMenuItem(title: "Run", action: #selector(Command.run(_:)), keyEquivalent: "r")
        item.target = command
        submenu.addItem(item)
        top.submenu = submenu
        menu.addItem(top)
        app.mainMenu = menu
        DispatchQueue.main.async {
            // AppKit puts in its own handler while launching, so the template installs it again once it's done.
            MainActor.assumeIsolated { LampWindows.installReopen() }
            if CommandLine.arguments[1] == "reopen" {
                let me = NSAppleEventDescriptor(processIdentifier: getpid())
                let event = NSAppleEventDescriptor(eventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEReopenApplication),
                                                   targetDescriptor: me, returnID: AEReturnID(kAutoGenerateReturnID),
                                                   transactionID: AETransactionID(kAnyTransactionID))
                _ = try? event.sendEvent(options: [.noReply], timeout: 2)
            } else {
                let key = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: 0,
                                           context: nil, characters: "r", charactersIgnoringModifiers: "r", isARepeat: false, keyCode: 15)!
                app.postEvent(key, atStart: false)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                print("still running"); fflush(stdout)
                exit(0)
            }
        }
        app.run()
        """
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-exception-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        try program.write(to: work.appendingPathComponent("main.swift"), atomically: true, encoding: .utf8)
        let built = try run(Shell.compatibleSDK + "xcrun swiftc -o app main.swift 2>&1", in: work)
        XCTAssertEqual(built.status, 0, built.output)
        return try run("./app \(trigger)", in: work)
    }

    private func run(_ command: String, in directory: URL) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.currentDirectoryURL = directory
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
