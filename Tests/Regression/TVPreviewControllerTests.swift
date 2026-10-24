import CryptoKit
import LampRelayKit
import XCTest
@testable import Lamp

/// In the TV preview the app's page opens its own socket to the controllers' relay, as it does on a TV, rather than
/// going through Lamp: WebKit lets the preview's page (at its own address, `lamp-tv://app/`) reach the relay on this
/// Mac and be let in as its game's host.
@MainActor
final class TVPreviewControllerTests: XCTestCase {
    func testThePreviewsPageReachesTheRelayItself() async throws {
        let key = SymmetricKey(size: .bits256)
        let relay = Relay(key: key)
        defer { relay.stop() }
        let started: UInt16? = await withCheckedContinuation { done in relay.start { done.resume(returning: $0) } }
        let port = try XCTUnwrap(started)
        let app = "tv-preview-pads-\(UUID().uuidString)"
        relay.configure(app: app, Relay.Session(generation: 0, pagePort: nil, page: nil, hosts: []))
        let credential = ControllerToken.issue(kind: .host, app: app, generation: 0, preview: true, key: key)

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tv-preview-pads-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let dir = root.appendingPathComponent("app"), staged = root.appendingPathComponent("web")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: staged, withIntermediateDirectories: true)
        try """
            <html><body><script>
            var socket = new WebSocket('ws://127.0.0.1:\(port)/');
            socket.binaryType = 'arraybuffer';
            socket.onopen = function () { socket.send(JSON.stringify({ t: 'hello', app: '\(app)', credential: '\(credential)' })); };
            socket.onmessage = function (event) {
              var m = JSON.parse(event.data);
              console.log('from the relay ' + m.t + ' ' + (m.role || ''));
            };
            socket.onerror = function () { console.log('the socket failed'); };
            </script></body></html>
            """.write(to: staged.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        let project = LampProject(id: app, name: "Pads", exe: "Pads", dir: dir)
        defer { TVPreview.close(project) }
        let problem = await TVPreview.show(project, staged: staged, inFront: false)
        XCTAssertNil(problem)

        var log = ""
        for _ in 0..<50 {
            log = (try? String(contentsOf: Runtime.logURL(project), encoding: .utf8)) ?? ""
            if log.contains("from the relay") || log.contains("failed") { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertTrue(log.contains("from the relay welcome host"), "the page reached the relay and was let in as the host: \(log)")
    }
}
