import XCTest
@testable import Lamp

/// Before Lamp swaps an installed app for a new copy, it ends the process macOS runs that app's widget in,
/// and no other: an old widget process left alive fails every reload of the widget now installed.
final class WidgetProcessTests: XCTestCase {
    private var root: URL?
    private var started: [Process] = []

    override func tearDown() {
        for process in started where process.isRunning { process.terminate() }
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    /// A copy of a small system program at that place, signed again so macOS runs it from there.
    private func place(at file: URL) throws {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: file.path) else { return }
        try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.copyItem(at: URL(fileURLWithPath: "/bin/sleep"), to: file)
        XCTAssertTrue(Subprocess.runBlocking("/usr/bin/codesign", ["--force", "-s", "-", file.path], timeout: 30).ok)
    }

    /// A program standing in for a widget's, at the place a widget's has inside an app, and running.
    private func widget(in app: String) throws -> (file: URL, process: Process) {
        let fm = FileManager.default
        let root = self.root ?? fm.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("lamp-widget-process-\(UUID().uuidString)")
        self.root = root
        let file = root.appendingPathComponent("\(app).app/Contents/PlugIns/\(app)Widget.appex/Contents/MacOS/\(app)Widget")
        try place(at: file)
        let process = Process()
        process.executableURL = file
        process.arguments = ["60"]
        try process.run()
        started.append(process)
        return (file, process)
    }

    func testOnlyThatAppsWidgetProcessIsEnded() async throws {
        let tally = try widget(in: "Tally")
        let again = try widget(in: "Tally")       // macOS can run more than one for a widget
        let other = try widget(in: "Sips")        // another app's widget, running beside it
        XCTAssertEqual(Set(WidgetProcess.running(from: tally.file)), [tally.process.processIdentifier, again.process.processIdentifier])

        let ended = await WidgetProcess.end(from: tally.file)
        XCTAssertTrue(ended)
        XCTAssertTrue(WidgetProcess.running(from: tally.file).isEmpty)
        tally.process.waitUntilExit()
        again.process.waitUntilExit()
        XCTAssertFalse(tally.process.isRunning)
        XCTAssertFalse(again.process.isRunning)
        // The other app's widget was never touched.
        XCTAssertTrue(other.process.isRunning)
        XCTAssertEqual(WidgetProcess.running(from: other.file), [other.process.processIdentifier])
    }

    /// The copy of a widget that went to the Trash with its app. Its process must not answer for an app made
    /// later under the same name: it's found by the identifier of the widget it was started from.
    func testAnOldCopysProcessIsEndedWhereverItRunsFrom() async throws {
        func identify(_ file: URL, as identifier: String) throws {
            let info = file.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Info.plist")
            try XCTUnwrap(NSDictionary(dictionary: ["CFBundleIdentifier": identifier])).write(to: info)
        }
        // The app as installed now, and the deleted one's widget, still running from where it was moved to.
        let installed = try widget(in: "Countdown")
        try identify(installed.file, as: "dev.lamp.app.countdown.widget")
        let other = try widget(in: "Sips")
        try identify(other.file, as: "dev.lamp.app.sips.widget")
        let trash = try XCTUnwrap(root).appendingPathComponent("Trash")
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        let old = trash.appendingPathComponent("Countdown.app/Contents/PlugIns/CountdownWidget.appex/Contents/MacOS/CountdownWidget")
        try place(at: old)
        try identify(old, as: "dev.lamp.app.countdown.widget")
        let stale = Process()
        stale.executableURL = old
        stale.arguments = ["60"]
        try stale.run()
        started.append(stale)

        // By its place alone the old copy's process is missed, which is how a new app's widget stayed blank.
        XCTAssertEqual(WidgetProcess.running(from: installed.file), [installed.process.processIdentifier])
        XCTAssertEqual(Set(WidgetProcess.running(from: installed.file, identifier: "dev.lamp.app.countdown.widget")),
                       [installed.process.processIdentifier, stale.processIdentifier])
        let ended = await WidgetProcess.end(from: installed.file, identifier: "dev.lamp.app.countdown.widget")
        XCTAssertTrue(ended)
        stale.waitUntilExit()
        XCTAssertFalse(stale.isRunning)
        XCTAssertTrue(other.process.isRunning)   // another app's widget, another identifier
    }

    func testNothingRunningIsFine() async throws {
        let tally = try widget(in: "Tally")
        tally.process.terminate()
        tally.process.waitUntilExit()
        let ended = await WidgetProcess.end(from: tally.file)
        XCTAssertTrue(ended)
        // An app with no widget at all: the file isn't there, and that's fine too.
        let none = await WidgetProcess.end(from: try XCTUnwrap(root).appendingPathComponent("Plain.app/Contents/PlugIns/PlainWidget.appex/Contents/MacOS/PlainWidget"))
        XCTAssertTrue(none)
    }

    /// A process that won't go when asked is stopped, as an app that won't quit is.
    func testAProcessThatIgnoresTheRequestIsStopped() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("lamp-widget-process-\(UUID().uuidString)")
        self.root = root
        let file = root.appendingPathComponent("Stubborn.app/Contents/PlugIns/StubbornWidget.appex/Contents/MacOS/StubbornWidget")
        try place(at: file)
        // Started by a shell that ignores the request to end, which the program inherits.
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/sh")
        shell.arguments = ["-c", "trap '' TERM; exec \"$0\" 60", file.path]
        try shell.run()
        started.append(shell)
        for _ in 0..<50 where WidgetProcess.running(from: file).isEmpty { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertEqual(WidgetProcess.running(from: file).count, 1)
        let ended = await WidgetProcess.end(from: file)
        XCTAssertTrue(ended)
        XCTAssertTrue(WidgetProcess.running(from: file).isEmpty)
    }
}
