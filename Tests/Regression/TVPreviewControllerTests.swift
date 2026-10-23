import XCTest
@testable import Lamp

/// In the TV preview the app's page is its game's host in Lamp itself: what it sends over the controller bridge reaches
/// Lamp, and what Lamp sends back reaches the page, at the address the preview opens it at.
@MainActor
final class TVPreviewControllerTests: XCTestCase {
    func testThePreviewsPageHostsItsGame() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tv-preview-pads-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let dir = root.appendingPathComponent("app"), staged = root.appendingPathComponent("web")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: staged, withIntermediateDirectories: true)
        try """
            <html><body><script>
            window.__lampControllers = function (m) { console.log('from Lamp ' + m.t + ' ' + (m.role || '')); };
            window.webkit.messageHandlers.lampController.postMessage({ op: 'start' });
            </script></body></html>
            """.write(to: staged.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        let project = LampProject(id: "tv-preview-pads-\(UUID().uuidString)", name: "Pads", exe: "Pads", dir: dir)
        defer {
            PhoneControllers.shared.end(project.id)
            TVPreview.window(project)?.orderOut(nil)
        }
        let problem = await TVPreview.show(project, staged: staged, inFront: false)
        XCTAssertNil(problem)

        var log = ""
        for _ in 0..<50 {
            log = (try? String(contentsOf: Runtime.logURL(project), encoding: .utf8)) ?? ""
            if log.contains("from Lamp") { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertTrue(log.contains("from Lamp welcome host"), "the page's start reached Lamp and its welcome came back: \(log)")
    }
}
