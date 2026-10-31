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

    /// A shared game is held to the sites its review named, and Lamp's relay is none of them: its preview lets the page
    /// connect to the relay at the port it listens on now, and to no other port on this Mac.
    func testASharedGamesPageReachesTheRelayAndNoOtherPort() async throws {
        ControllerRelay.executable = Bundle(for: Self.self).bundleURL.deletingLastPathComponent().appendingPathComponent("LampRelay")
        let kept = SharedNetwork.folder
        SharedNetwork.folder = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-network-\(UUID().uuidString)")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tv-preview-shared-\(UUID().uuidString)")
        let dir = root.appendingPathComponent("app"), staged = root.appendingPathComponent("web")
        var project = LampProject(id: "tv-preview-shared-\(UUID().uuidString.prefix(8))", name: "Pads", exe: "Pads", dir: dir)
        project.platform = .tv
        let other = try SharedNetworkTests.Listener()
        defer {
            other.stop()
            TVPreview.close(project)
            ControllerRelay.sync([])
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: TVs.stagingFolder(for: project))
            try? FileManager.default.removeItem(at: SharedNetwork.folder)
            SharedNetwork.folder = kept
        }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: staged, withIntermediateDirectories: true)
        // It takes players: its phone page as a build publishes it (`TVs.stagePhone`).
        try FileManager.default.createDirectory(at: TVs.phoneFolder(for: project), withIntermediateDirectories: true)
        try Data("<title>Pad</title>".utf8).write(to: TVs.phoneFolder(for: project).appendingPathComponent("index.html"))
        try SharedNetwork.save(NetworkPolicy(), for: project)

        ControllerRelay.open(project.id)
        let started = await ControllerRelay.ready()
        let relayPort = try XCTUnwrap(started, "the relay starts")
        let otherPort = try await other.port()
        try """
            <html><body><script>
            function reach(name, address) {
              try {
                var socket = new WebSocket(address);
                socket.onopen = function () { console.log(name + ' opened'); socket.close(); };
                socket.onerror = function () { console.log(name + ' failed'); };
              } catch (e) { console.log(name + ' refused ' + e.name); }
            }
            reach('relay', 'ws://127.0.0.1:\(relayPort)/');
            reach('other', 'ws://127.0.0.1:\(otherPort)/other');
            </script></body></html>
            """.write(to: staged.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        let problem = await TVPreview.show(project, staged: staged, inFront: false)
        XCTAssertNil(problem)

        var log = ""
        for _ in 0..<50 {
            log = (try? String(contentsOf: Runtime.logURL(project), encoding: .utf8)) ?? ""
            if log.contains("relay "), log.contains("other ") { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        print("The shared page's sockets: \(log.split(separator: "\n").filter { $0.contains("relay ") || $0.contains("other ") })")
        XCTAssertTrue(log.contains("relay opened"), "the page reached the relay: \(log)")
        XCTAssertFalse(log.contains("other opened"), "no other port on this Mac: \(log)")
        XCTAssertEqual(other.paths, [], "nothing reached the other port")
        XCTAssertEqual(SharedNetwork.policy(for: project), NetworkPolicy(), "the relay is never kept as one of its sites")
    }
}
