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
        TestShell.wait(for: tally.process, timeout: 10)
        TestShell.wait(for: again.process, timeout: 10)
        XCTAssertFalse(tally.process.isRunning)
        XCTAssertFalse(again.process.isRunning)
        // The other app's widget was never touched.
        XCTAssertTrue(other.process.isRunning)
        XCTAssertEqual(WidgetProcess.running(from: other.file), [other.process.processIdentifier])
    }
}
