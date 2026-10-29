import Foundation
@testable import Lamp
import LampRelayKit
import XCTest

/// The controllers service that keeps a Mac game's phones playing with Lamp closed (`ControllerHost`): a game Lamp
/// handed it gets its session with its own key, its phone page is served from the copy Lamp handed over, a phone that
/// never opened the page before joins through it, and the session ends, taking its listeners and credentials with it,
/// when the game's connection goes or it stops asking.
final class ControllerServiceTests: XCTestCase {
    private var folder: URL!
    private var host: ControllerHost!
    private let game = "padgame"
    private let key = ControllerService.newKey()

    override func setUp() {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("controller-service-\(UUID().uuidString)")
        host = Self.makeHost(folder)
    }

    override func tearDown() {
        host.closed(connection: 1)
        host.closed(connection: 2)
        _ = host.openSessions
        try? FileManager.default.removeItem(at: folder)
    }

    private static func makeHost(_ folder: URL) -> ControllerHost {
        let host = ControllerHost(names: ControllerService.Names(bundleID: "dev.lamp.host.dev.controller-tests"), folder: folder)
        host.hosts = { ["127.0.0.1", "localhost", "::1"] }
        host.linkHost = { "127.0.0.1" }
        return host
    }

    private func page(_ title: String) -> ControllerSnapshot {
        ControllerSnapshot(files: [.init(path: "index.html", data: Data("<title>\(title)</title>".utf8)),
                                   .init(path: "lamp-controller.js", data: Data("// Lamp's".utf8)),
                                   .init(path: "art/pad.svg", data: Data("<svg/>".utf8))])
    }

    @discardableResult
    private func provision(_ snapshot: ControllerSnapshot, key: String? = nil) -> [String: Any] {
        host.manage(["op": "provision", "installation": game, "version": snapshot.version,
                     "keyVerifier": ControllerService.verifier(of: key ?? self.key),
                     "requirement": #"identifier "dev.lamp.dev.app.padgame""#, "files": snapshot.encoded])
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

    func testAPhoneThatNeverOpenedThePageJoinsThroughTheServicesOwnPageAndLink() async throws {
        let snapshot = page("Pad")
        XCTAssertEqual(provision(snapshot)["ok"] as? Bool, true)

        XCTAssertEqual(host.open(installation: game, version: snapshot.version, key: "someone else's", connection: 1)["status"] as? Int, 403,
                       "only the key Lamp gave the game's copy opens its session")
        let answer = host.open(installation: game, version: snapshot.version, key: key, connection: 1)
        XCTAssertEqual(answer["status"] as? Int, 200)
        let link = try XCTUnwrap((answer["links"] as? [[String: Any]])?.first)
        let relayPort = try XCTUnwrap(URL(string: link["socket"] as? String ?? "")?.port)
        let pagePort = try XCTUnwrap(host.pagePort(game))

        // The game's page, as the game in its window joins: the host.
        let tv = try await socket(relayPort, hello: ["t": "hello", "app": game, "credential": link["credential"] as Any])
        let hosting = try await Self.text(tv)
        XCTAssertEqual(hosting["role"] as? String, "host")
        try await tv.send(.string(#"{"t":"link"}"#))
        let said = try await Self.text(tv)
        let url = try XCTUnwrap(URLComponents(string: said["url"] as? String ?? ""))
        XCTAssertEqual(url.port, Int(pagePort), "the QR code's link is the service's own page")
        let join = try XCTUnwrap(url.fragment)

        // A new phone fetches the page Lamp handed over, and where to open its socket, from the service alone.
        let (status, body) = try await get(pagePort, "/")
        XCTAssertEqual(status, 200)
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

        // The game quits: its connection goes, and so does everything that listened for its phones.
        host.closed(connection: 1)
        XCTAssertEqual(host.openSessions, [])
        XCTAssertFalse(host.relayListening, "nothing listens for phones while no game is played")
        do {
            _ = try await get(pagePort, "/")
            XCTFail("the page is no longer served")
        } catch {}

        // Its next run is a new session: the link the phone had gets it nowhere.
        _ = host.open(installation: game, version: snapshot.version, key: key, connection: 2)
        let stale = try await socket(relayPort, hello: ["t": "hello", "app": game, "credential": join])
        do {
            _ = try await stale.receive()
            XCTFail("an earlier session's link is turned away")
        } catch {}
        XCTAssertEqual(stale.closeCode.rawValue, 4003)
    }

    func testAGameThatStopsAskingLetsItsSessionLapse() throws {
        let snapshot = page("Pad")
        provision(snapshot)
        _ = host.open(installation: game, version: snapshot.version, key: key, connection: 1)
        host.expire(now: Date().addingTimeInterval(ControllerService.lease - 5))
        XCTAssertEqual(host.openSessions, [game], "a game that renews within its lease keeps its session")
        host.expire(now: Date().addingTimeInterval(ControllerService.lease + 1))
        XCTAssertEqual(host.openSessions, [])
        XCTAssertNil(host.pagePort(game))
    }

    func testANewBuildNeverChangesThePageUnderTheGameStillBeingPlayed() async throws {
        let first = page("First"), second = page("Second")
        provision(first)
        _ = host.open(installation: game, version: first.version, key: key, connection: 1)
        let port = try XCTUnwrap(host.pagePort(game))
        provision(second, key: "the new build's")
        let still = try await get(port, "/").1
        XCTAssertEqual(String(decoding: still, as: UTF8.self), "<title>First</title>")
        XCTAssertEqual(host.open(installation: game, version: second.version, key: key, connection: 2)["status"] as? Int, 403,
                       "each build has its own key")

        // Lamp opened again, or the service started again: what it was given is still there.
        host.closed(connection: 1)
        host = Self.makeHost(folder)
        XCTAssertEqual(host.open(installation: game, version: second.version, key: "the new build's", connection: 3)["status"] as? Int, 200)
        let again = try XCTUnwrap(host.pagePort(game))
        let served = try await get(again, "/").1
        XCTAssertEqual(String(decoding: served, as: UTF8.self), "<title>Second</title>")
        host.closed(connection: 3)
    }

    func testAPageIsServedOnlyAsItsOwnFilesToThisMacsNames() throws {
        let snapshot = page("Pad")
        provision(snapshot)
        let root = folder.appendingPathComponent("pages/\(game)/\(snapshot.version)")
        let server = PhonePageServer(port: 1, root: root, app: game, hosts: { ["127.0.0.1"] }, relayPort: { 9 })
        XCTAssertEqual(server.answer(path: "/", host: "127.0.0.1:47981").status, 200)
        XCTAssertEqual(server.answer(path: "/", host: "evil.example").status, 403, "a page elsewhere that made its name lead here reads nothing")
        XCTAssertEqual(server.answer(path: "/", host: "127.0.0.1.evil.example").status, 403)
        for path in ["/../registry.json", "/%2e%2e/registry.json", "/.hidden", "/art/../../registry.json", "/art%2f..%2f..%2fregistry.json"] {
            XCTAssertEqual(server.answer(path: path, host: "127.0.0.1").status, 404, path)
        }

        // Lamp's request can't put a file outside the page, or a link in it.
        let outside = ControllerSnapshot(files: [.init(path: "index.html", data: Data()), .init(path: "../escape.html", data: Data())])
        XCTAssertNotNil(host.manage(["op": "provision", "installation": game, "version": outside.version,
                                     "keyVerifier": ControllerService.verifier(of: key), "requirement": #"identifier "x""#,
                                     "files": outside.encoded])["error"])
        XCTAssertNotNil(host.manage(["op": "provision", "installation": "../\(game)", "version": snapshot.version,
                                     "keyVerifier": ControllerService.verifier(of: key), "requirement": #"identifier "x""#,
                                     "files": snapshot.encoded])["error"])
        let linked = folder.appendingPathComponent("linked")
        try FileManager.default.createDirectory(at: linked, withIntermediateDirectories: true)
        try Data("<p>".utf8).write(to: linked.appendingPathComponent("index.html"))
        try FileManager.default.createSymbolicLink(at: linked.appendingPathComponent("secret.txt"), withDestinationURL: folder.appendingPathComponent("registry.json"))
        XCTAssertThrowsError(try ControllerSnapshot.read(linked))
    }

    func testEachLampsServiceHasPortsOfItsOwn() {
        let editions = ["dev.lamp.host", "dev.lamp.host.nightly", "dev.lamp.host.dev", "dev.lamp.host.dev.alpha", "dev.lamp.host.dev.beta"]
        let ranges = editions.map { ControllerService.Names(bundleID: $0).ports }
        for (index, range) in ranges.enumerated() {
            for other in ranges[(index + 1)...] { XCTAssertFalse(range.overlaps(other), "\(range) and \(other)") }
        }
        // Clear of each Lamp's own phone pages and of the ports it gives its emulators, so an open Lamp and its service
        // never take each other's.
        let lamps: [(isDev: Bool, instance: String, isNightly: Bool)] = [(false, "", false), (false, "", true), (true, "", false), (true, "alpha", false), (true, "beta", false)]
        for (range, lamp) in zip(ranges, lamps) {
            for other in lamps {
                XCTAssertFalse(range.overlaps(Edition.phonePagePorts(isDev: other.isDev, instance: other.instance, isNightly: other.isNightly)))
                let android = Edition.androidPorts(isDev: other.isDev, instance: other.instance, isNightly: other.isNightly).all
                XCTAssertFalse(android.contains { range.contains(UInt16($0)) })
            }
            XCTAssertFalse(range.contains(Edition.gatewayPort))
            _ = lamp
        }
        let names = ControllerService.Names(bundleID: "dev.lamp.host.dev.alpha")
        XCTAssertEqual(names.label, "dev.lamp.host.dev.alpha.controllers")
        XCTAssertEqual(names.lampName, "Lamp Dev alpha")
        XCTAssertNotEqual(names.manageService, names.gameService)
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
