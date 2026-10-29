import Foundation
import LampRelayKit
import XCTest

/// A game on the Mac running its own phones (`ControllerRuntime`): its page served from the copy in its bundle and its
/// relay, in its own process, so a phone that never opened the page joins with nothing from Lamp; stopping closes
/// both and forgets the key, so nothing handed out before gets in again.
final class ControllerRuntimeTests: XCTestCase {
    private var folder: URL!
    private let game = "padgame"

    override func setUp() {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("controller-runtime-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
    }

    /// The page as Lamp puts it in the game's bundle.
    private func runtime() throws -> ControllerRuntime {
        let page = ControllerSnapshot(files: [.init(path: "index.html", data: Data("<title>Pad</title>".utf8)),
                                              .init(path: "lamp-controller.js", data: Data("// Lamp's".utf8)),
                                              .init(path: "art/pad.svg", data: Data("<svg/>".utf8))])
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try page.write(to: folder.appendingPathComponent("Phone"))
        let runtime = ControllerRuntime(app: game, page: folder.appendingPathComponent("Phone"))
        runtime.hosts = { ["127.0.0.1", "localhost", "::1"] }
        runtime.linkHost = { "127.0.0.1" }
        return runtime
    }

    private func get(_ port: UInt16, _ path: String) async throws -> (Int, Data) {
        let (data, response) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)\(path)")!)
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, data)
    }

    private func socket(_ port: Int, hello: [String: Any]) async throws -> URLSessionWebSocketTask {
        let task = URLSession.shared.webSocketTask(with: URL(string: "ws://127.0.0.1:\(port)/")!)
        task.resume()
        try await task.send(.string(Self.json(hello)))
        return task
    }

    func testAPhoneThatNeverOpenedThePageJoinsThroughTheGamesOwnPageAndLink() async throws {
        let runtime = try runtime()
        defer { runtime.stop() }
        XCTAssertFalse(runtime.isRunning, "nothing listens for phones before the game starts its controllers")
        let (status, answer) = runtime.startNow()
        XCTAssertEqual(status, 200)
        let link = try XCTUnwrap((answer["links"] as? [[String: Any]])?.first)
        let relayPort = try XCTUnwrap(URL(string: link["socket"] as? String ?? "")?.port)
        let pagePort = try XCTUnwrap(runtime.pagePort)
        XCTAssertNotEqual(Int(pagePort), relayPort)

        // The game's page joins as the host and asks for a link for phones: the game's own page.
        let tv = try await socket(relayPort, hello: ["t": "hello", "app": game, "credential": link["credential"] as Any])
        let hosting = try await Self.text(tv)
        XCTAssertEqual(hosting["role"] as? String, "host")
        try await tv.send(.string(#"{"t":"link"}"#))
        let said = try await Self.text(tv)
        let url = try XCTUnwrap(URLComponents(string: said["url"] as? String ?? ""))
        XCTAssertEqual(url.port, Int(pagePort))
        let join = try XCTUnwrap(url.fragment)
        XCTAssertFalse(String(data: try JSONSerialization.data(withJSONObject: answer), encoding: .utf8)!.contains(join),
                       "a phone's link is made at the relay, never handed to the page")

        // A new phone fetches the page and where to open its socket from the game alone, and joins.
        let (pageStatus, body) = try await get(pagePort, "/")
        XCTAssertEqual(pageStatus, 200)
        XCTAssertEqual(String(decoding: body, as: UTF8.self), "<title>Pad</title>")
        let art = try await get(pagePort, "/art/pad.svg")
        XCTAssertEqual(art.0, 200)
        let relay = try JSONSerialization.jsonObject(with: try await get(pagePort, "/lamp-relay.json").1) as? [String: Any]
        XCTAssertEqual(relay?["port"] as? Int, relayPort)
        XCTAssertEqual(relay?["app"] as? String, game)
        let phone = try await socket(relayPort, hello: ["t": "hello", "app": game, "credential": join])
        let welcome = try await Self.text(phone)
        XCTAssertEqual(welcome["role"] as? String, "controller")
        let joined = try await Self.text(tv)
        XCTAssertEqual(joined["t"] as? String, "joined")
        try await phone.send(.string(#"{"t":"button","name":"a","down":true}"#))
        let pressed = try await Self.text(tv)
        XCTAssertEqual(pressed["name"] as? String, "a")

        // Asking again keeps the same session: the page's next ask doesn't let its phones go.
        XCTAssertEqual(runtime.startNow().status, 200)
        XCTAssertEqual(runtime.pagePort, pagePort)

        // The page stops its controllers: nothing listens for phones any more.
        runtime.stop()
        XCTAssertFalse(runtime.isRunning)
        do {
            _ = try await get(pagePort, "/")
            XCTFail("the page is no longer served")
        } catch {}

        // Started again, it's a new session with a new key: the link the phone had gets it nowhere.
        let again = runtime.startNow()
        let port = try XCTUnwrap(URL(string: ((again.answer["links"] as? [[String: Any]])?.first?["socket"] as? String) ?? "")?.port)
        let stale = try await socket(port, hello: ["t": "hello", "app": game, "credential": join])
        do {
            _ = try await stale.receive()
            XCTFail("an earlier session's link is turned away")
        } catch {}
        XCTAssertEqual(stale.closeCode.rawValue, 4003)
    }

    /// A game that stops its controllers and starts them again for its next round, at once, as the page's calls arrive:
    /// they happen in that order, so the round gets a session that stays open and a credential that gets in.
    func testAStopThenAStartHappenInTheOrderTheyWereAsked() async throws {
        let runtime = try runtime()
        defer { runtime.stop() }
        XCTAssertEqual(runtime.startNow().status, 200)
        let answer: (Int, [String: Any]) = await withCheckedContinuation { done in
            runtime.stop {}
            runtime.start { status, answer in done.resume(returning: (status, answer)) }
        }
        XCTAssertEqual(answer.0, 200)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(runtime.isRunning, "the stop asked first never closes the session the start asked after it opened")
        let link = try XCTUnwrap((answer.1["links"] as? [[String: Any]])?.first)
        let port = try XCTUnwrap(URL(string: link["socket"] as? String ?? "")?.port)
        let host = try await socket(port, hello: ["t": "hello", "app": game, "credential": link["credential"] as Any])
        let welcome = try await Self.text(host)
        XCTAssertEqual(welcome["role"] as? String, "host")
    }

    /// A device on no network a phone could share (an iPhone with Wi‑Fi off, a Mac unplugged) says so, rather than hand
    /// out a loopback link that would point a phone at itself, and leaves nothing listening.
    func testOnNoNetworkThereIsNoLinkAndNothingListens() throws {
        let runtime = try runtime()
        defer { runtime.stop() }
        runtime.linkHost = { nil }
        let (status, answer) = runtime.startNow()
        XCTAssertEqual(status, 503)
        XCTAssertNil(answer["links"])
        XCTAssertFalse(runtime.isRunning)
        let page = DispatchSemaphore(value: 0)
        let said = Box()
        runtime.phonePage { status, answer in said.value = (status, answer["url"] as? String); page.signal() }
        XCTAssertEqual(page.wait(timeout: .now() + 5), .success)
        XCTAssertEqual(said.value?.0, 503)
        XCTAssertNil(said.value?.1, "no address for the phone page either")
    }

    /// The page's address as `Lamp.phonePage` asks for it: the network host given, at the page's own port.
    func testThePhonePageAddressIsTheDevicesOnTheNetwork() throws {
        let runtime = try runtime()
        defer { runtime.stop() }
        runtime.linkHost = { "192.168.1.20" }
        let page = DispatchSemaphore(value: 0)
        let said = Box()
        runtime.phonePage { status, answer in said.value = (status, answer["url"] as? String); page.signal() }
        XCTAssertEqual(page.wait(timeout: .now() + 5), .success)
        XCTAssertEqual(said.value?.0, 200)
        XCTAssertEqual(said.value?.1, "http://192.168.1.20:\(try XCTUnwrap(runtime.pagePort))/")
    }

    func testTheDevicesAddressesForPhonesAreNeverLoopback() {
        XCTAssertFalse(ControllerAddresses.lan().contains { $0.hasPrefix("127.") })
        XCTAssertNotEqual(ControllerAddresses.linkHost(), "127.0.0.1")
    }

    func testAGameWithoutAPhonePageOpensNothing() throws {
        let runtime = ControllerRuntime(app: game, page: folder.appendingPathComponent("Phone"))
        XCTAssertEqual(runtime.startNow().status, 409)
        XCTAssertFalse(runtime.isRunning)
    }

    func testAPageIsServedOnlyAsItsOwnFilesToThisMacsNames() throws {
        _ = try runtime()
        let server = PhonePageServer(root: folder.appendingPathComponent("Phone"), app: game, hosts: { ["127.0.0.1"] }, relayPort: { 9 })
        XCTAssertEqual(server.answer(path: "/", host: "127.0.0.1:47981").status, 200)
        XCTAssertEqual(server.answer(path: "/", host: "evil.example").status, 403, "a page elsewhere that made its name lead here reads nothing")
        XCTAssertEqual(server.answer(path: "/", host: "127.0.0.1.evil.example").status, 403)
        try Data("secret".utf8).write(to: folder.appendingPathComponent("outside.txt"))
        for path in ["/../outside.txt", "/%2e%2e/outside.txt", "/.hidden", "/art/../../outside.txt", "/art%2f..%2f..%2foutside.txt"] {
            XCTAssertEqual(server.answer(path: path, host: "127.0.0.1").status, 404, path)
        }

        // A page with a link in it isn't put in a game at all.
        let linked = folder.appendingPathComponent("linked")
        try FileManager.default.createDirectory(at: linked, withIntermediateDirectories: true)
        try Data("<p>".utf8).write(to: linked.appendingPathComponent("index.html"))
        try FileManager.default.createSymbolicLink(at: linked.appendingPathComponent("secret.txt"), withDestinationURL: folder.appendingPathComponent("outside.txt"))
        XCTAssertThrowsError(try ControllerSnapshot.read(linked))
        XCTAssertThrowsError(try ControllerSnapshot(files: [.init(path: "index.html", data: Data()), .init(path: "../escape.html", data: Data())]).check())
    }

    /// A host on the network that opens connections to a game's page and sends nothing can't hold them: past a few from
    /// one address it's turned away at once, and each is let go once it hasn't sent its request in time, so the game
    /// keeps what it needs for phones.
    func testIdleConnectionsToAPageAreLetGo() async throws {
        _ = try runtime()
        let page = PhonePageServer(root: folder.appendingPathComponent("Phone"), app: game, hosts: { ["127.0.0.1"] }, relayPort: { 9 })
        let listening = await withCheckedContinuation { done in page.start(ready: { done.resume(returning: $0) }) }
        XCTAssertTrue(listening)
        let port = try XCTUnwrap(page.port)
        defer { page.stop() }
        func connect() -> Int32 {
            let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = port.bigEndian
            address.sin_addr.s_addr = inet_addr("127.0.0.1")
            _ = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
            var wait = timeval(tv_sec: 2, tv_usec: 0)
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &wait, socklen_t(MemoryLayout<timeval>.size))
            return fd
        }
        /// Whether the server has closed the connection: a read that ends rather than times out.
        func closed(_ fd: Int32) -> Bool {
            var byte: UInt8 = 0
            return read(fd, &byte, 1) == 0
        }
        let idle = (0..<PhonePageServer.connectionLimit.each).map { _ in connect() }
        defer { idle.forEach { close($0) } }
        try await Task.sleep(for: .milliseconds(300))
        let extra = connect()
        defer { close(extra) }
        XCTAssertTrue(closed(extra), "one more from the same address is turned away")
        try await Task.sleep(for: .seconds(PhonePageServer.headDeadline + 1))
        XCTAssertTrue(idle.allSatisfy(closed), "connections that never sent a request are let go")
        let (status, _) = try await get(port, "/")
        XCTAssertEqual(status, 200)
    }

    private static func json(_ value: [String: Any]) -> String {
        String(decoding: (try? JSONSerialization.data(withJSONObject: value)) ?? Data(), as: UTF8.self)
    }

    private static func text(_ task: URLSessionWebSocketTask) async throws -> [String: Any] {
        while true {
            guard case .string(let text) = try await task.receive(),
                  let value = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else { continue }
            if value["t"] as? String == "beat" { continue }
            return value
        }
    }
}

private final class Box: @unchecked Sendable {
    var value: (Int, String?)?
}
