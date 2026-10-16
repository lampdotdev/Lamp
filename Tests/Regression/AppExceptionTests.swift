import XCTest
@testable import Lamp

/// Clicking an app in the Dock (or Lamp's Play) with every window closed makes Lamp's reopen handler open one, and
/// the new window's views are the app's own code, which may throw an Objective-C exception (WebKit refusing a script
/// message handler added a second time). Thrown inside the Apple Event, it was caught there and the app went on with
/// Swift's state half unwound, crashing minutes later in the background with a report that named neither. Here the
/// template's reopen handler is cut out, compiled into a small app whose window opener throws, and run.
@MainActor
final class AppExceptionTests: XCTestCase {
    func testAnExceptionOpeningAWindowOnReopenEndsTheApp() throws {
        let support = Template.lampSupportSwift
        let start = try XCTUnwrap(support.range(of: "// begin LampWindows.reopen"))
        let end = try XCTUnwrap(support.range(of: "// end LampWindows.reopen", range: start.upperBound..<support.endIndex))
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

        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        DispatchQueue.main.async {
            // AppKit puts in its own handler while launching, so the template installs it again once it's done.
            MainActor.assumeIsolated { LampWindows.installReopen() }
            let me = NSAppleEventDescriptor(processIdentifier: getpid())
            let event = NSAppleEventDescriptor(eventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEReopenApplication),
                                               targetDescriptor: me, returnID: AEReturnID(kAutoGenerateReturnID),
                                               transactionID: AETransactionID(kAnyTransactionID))
            _ = try? event.sendEvent(options: [.noReply], timeout: 2)
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

        let ran = try run("./app", in: work)
        XCTAssertTrue(ran.output.contains("opening a window"), ran.output)
        XCTAssertFalse(ran.output.contains("still running"), ran.output)
        XCTAssertNotEqual(ran.status, 0, ran.output)
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
