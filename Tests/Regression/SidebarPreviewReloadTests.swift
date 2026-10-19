import CryptoKit
import Network
import XCTest
@testable import Lamp

/// The builder loads an app's sidebar page again each time it looks. The page drops the `#tab=` from its address
/// as soon as it reads it, which once left every second load waiting on a fragment jump that never finished.
@MainActor
final class SidebarPreviewReloadTests: XCTestCase {
    private var root: URL?
    private var listener: NWListener?
    override func tearDown() async throws {
        listener?.cancel()
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    func testEveryLoadReachesTheAppsPage() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sidebar-reload-\(UUID().uuidString)")
        root = dir
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Assets/Sidebar"), withIntermediateDirectories: true)
        let project = LampProject(id: "reload\(UUID().uuidString.prefix(8))", name: "Reload", exe: "Reload", dir: dir)
        let port = Template.sidebarPort(for: project)
        let pages = PageServer(key: Template.sidebarKey(for: project), port: port)
        listener = try pages.start()

        let preview = PagePreview.of(project)
        for attempt in 1...4 {
            let problem = await preview.load(project)
            XCTAssertNil(problem, "load \(attempt)")
        }
        XCTAssertEqual(pages.pageRequests, 4, "each load asks the app for its page")
    }
}

/// What an app's sidebar server does for the preview: proves it's the app, and serves a page that, like lamp.js,
/// reads the tab from its address, drops it, and says hello.
private final class PageServer: @unchecked Sendable {
    let key: String, port: Int
    private let lock = NSLock()
    private var requests = 0
    var pageRequests: Int { lock.withLock { requests } }
    init(key: String, port: Int) { self.key = key; self.port = port }

    func start() throws -> NWListener {
        let listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: UInt16(port))!)
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { if case .ready = $0 { ready.signal() } }
        listener.newConnectionHandler = { [self] connection in
            connection.start(queue: .global())
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, _, _ in
                let line = String(decoding: data ?? Data(), as: UTF8.self).split(separator: "\r\n").first.map(String.init) ?? ""
                let path = line.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
                let (type, body) = self.answer(path)
                let head = "HTTP/1.1 200 OK\r\nContent-Type: \(type)\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n"
                connection.send(content: Data((head + body).utf8), completion: .contentProcessed { _ in connection.cancel() })
            }
        }
        listener.start(queue: .global())
        guard ready.wait(timeout: .now() + 5) == .success else { throw URLError(.cannotConnectToHost) }
        return listener
    }

    private func answer(_ path: String) -> (String, String) {
        if path.hasPrefix("/lamp/proof") {
            let nonce = URLComponents(string: path)?.queryItems?.first { $0.name == "nonce" }?.value ?? ""
            let proof = HMAC<SHA256>.authenticationCode(for: Data("\(nonce):\(port)".utf8), using: SymmetricKey(data: Data(key.utf8)))
                .map { String(format: "%02x", $0) }.joined()
            return ("application/json", #"{"proof":"\#(proof)"}"#)
        }
        lock.withLock { requests += 1 }
        return ("text/html", """
            <!doctype html><html><body><p>Sidebar</p><script>
            if (location.hash) history.replaceState(null, '', location.pathname + location.search);
            window.webkit.messageHandlers.lampPreview.postMessage({lamp: 'hello'});
            </script></body></html>
            """)
    }
}
