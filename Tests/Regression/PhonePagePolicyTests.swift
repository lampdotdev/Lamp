import Foundation
@testable import Lamp
import LampRelayKit
import XCTest

/// A phone page's rules (`PhonePagePolicy`) as its servers send them: only the page's own files, its game's relay where
/// it listens now, by the name the phone used, and the sites the reach file names, with anything that isn't a site
/// dropped rather than written into the header.
final class PhonePagePolicyTests: XCTestCase {
    private var folder: URL!

    override func setUp() {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("phone-policy-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
    }

    private static let hostile = ["api.example.com", "https://cdn.example.org:8443/", "x.test; script-src *", "'unsafe-eval'",
                                  "javascript:alert(1)", "http://[::1]:80", "*.example.net", "evil.test\r\nSet-Cookie: a=b"]

    func testAGamesOwnPageServerSendsAPolicyNamingOnlyItsRelayAndItsSites() async throws {
        let page = ControllerSnapshot(files: [.init(path: "index.html", data: Data("<title>Pad</title>".utf8)),
                                              .init(path: PhonePagePolicy.reachFile, data: PhonePagePolicy.file(for: .only(Self.hostile))!)])
        try page.write(to: folder)
        let runtime = ControllerRuntime(app: "padgame", page: folder)
        runtime.hosts = { ["127.0.0.1", "localhost"] }
        runtime.linkHost = { "127.0.0.1" }
        defer { runtime.stop() }
        let (status, answer) = runtime.startNow()
        XCTAssertEqual(status, 200)
        let socket = try XCTUnwrap((answer["links"] as? [[String: Any]])?.first?["socket"] as? String)
        let relayPort = try XCTUnwrap(URL(string: socket)?.port)
        let pagePort = try XCTUnwrap(runtime.pagePort)

        let (_, response) = try await URLSession.shared.data(from: URL(string: "http://localhost:\(pagePort)/")!)
        let policy = try XCTUnwrap((response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Security-Policy"))
        let sites = "api.example.com https://cdn.example.org:8443"
        XCTAssertEqual(policy, "default-src 'none'; script-src 'self' 'unsafe-inline' \(sites); style-src 'self' 'unsafe-inline' \(sites); "
            + "img-src 'self' data: blob: \(sites); media-src 'self' data: blob: \(sites); font-src 'self' data: \(sites); "
            + "connect-src 'self' ws://localhost:\(relayPort) \(sites); worker-src 'self' blob:; manifest-src 'self'; base-uri 'none'; form-action 'none'")
    }

    /// A shared app's phone page, as Lamp bundles it, is held to its shared policy's sites (`SharedNetwork`): here Home
    /// HQ's as `SharedNetworkTests` reads them, which may connect where Lamp couldn't tell, so nothing beyond its one site.
    /// An app the person made, or let reach every site, reaches any https site.
    func testASharedAppsPhonePageReachesOnlyItsPolicysSites() async throws {
        let shared = NetworkPolicy(origins: ["https://geocoding-api.open-meteo.com"], mayConnect: true, ownSwift: true)
        XCTAssertEqual(PhonePageReach.reach(shared), .only(["https://geocoding-api.open-meteo.com"]))
        XCTAssertEqual(PhonePageReach.reach(nil), .unrestricted)
        XCTAssertEqual(PhonePageReach.reach(NetworkPolicy(origins: [], unrestricted: true)), .unrestricted)

        let page = ControllerSnapshot(files: [.init(path: "index.html", data: Data("<title>Pad</title>".utf8)),
                                              .init(path: PhonePagePolicy.reachFile, data: PhonePagePolicy.file(for: PhonePageReach.reach(shared))!)])
        try page.write(to: folder)
        let runtime = ControllerRuntime(app: "homehq", page: folder)
        runtime.hosts = { ["127.0.0.1"] }
        runtime.linkHost = { "127.0.0.1" }
        defer { runtime.stop() }
        let (_, answer) = runtime.startNow()
        let socket = try XCTUnwrap((answer["links"] as? [[String: Any]])?.first?["socket"] as? String)
        let relayPort = try XCTUnwrap(URL(string: socket)?.port)
        let (_, response) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(try XCTUnwrap(runtime.pagePort))/")!)
        let policy = try XCTUnwrap((response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Security-Policy"))
        XCTAssertTrue(policy.contains("connect-src 'self' ws://127.0.0.1:\(relayPort) https://geocoding-api.open-meteo.com;"), policy)
        XCTAssertFalse(policy.contains("https:;") || policy.contains("https: ") || policy.contains("wss:"), "no site beyond the policy's: \(policy)")
    }

    /// An app the person made (or a starter) has no shared policy, so its page carries no reach file, as a page from before
    /// phone pages had rules doesn't either, and it's served as it always was: no policy header at all.
    func testAnOwnAppsPhonePageGetsNoPolicy() async throws {
        let page = ControllerSnapshot(files: [.init(path: "index.html", data: Data("<title>Pad</title>".utf8))])
        try page.write(to: folder)
        let runtime = ControllerRuntime(app: "mygame", page: folder)
        runtime.hosts = { ["127.0.0.1"] }
        runtime.linkHost = { "127.0.0.1" }
        defer { runtime.stop() }
        XCTAssertEqual(runtime.startNow().status, 200)
        let (_, response) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(try XCTUnwrap(runtime.pagePort))/")!)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 200)
        XCTAssertNil(http.value(forHTTPHeaderField: "Content-Security-Policy"), "an own app's phone page is served with no policy")
    }

    /// The page Lamp puts in a bundle or package carries a reach file only when it's held: an own app's is the app's files
    /// and lamp-controller.js, as before these rules, with any reach file of the app's own taken out.
    func testOnlyAHeldPagesSnapshotCarriesAReachFile() {
        let published = ControllerSnapshot(files: [.init(path: "index.html", data: Data("<p>pad</p>".utf8)),
                                                   .init(path: PhonePagePolicy.reachFile, data: Data(#"{"only":["https://anything.example"]}"#.utf8))])
        let own = PhonePageReach.snapshot(published, reach: .unrestricted, controller: Data("// Lamp's".utf8))
        XCTAssertEqual(own.files.map(\.path), ["index.html", "lamp-controller.js"])
        let shared = PhonePageReach.snapshot(published, reach: .only(["https://api.example.org"]), controller: Data("// Lamp's".utf8))
        XCTAssertEqual(shared.files.first { $0.path == PhonePagePolicy.reachFile }?.data, PhonePagePolicy.file(for: .only(["https://api.example.org"])))
    }

    /// A reach file that's there but can't be read as one holds the page to no sites: a shared page fails closed.
    func testAnUnreadableReachFileReachesNoSites() {
        let policy = PhonePagePolicy.header(host: "192.168.1.20:52000", relayPort: 52001, reach: PhonePagePolicy.reach(json: Data("not json".utf8))) ?? ""
        XCTAssertTrue(policy.contains("connect-src 'self' ws://192.168.1.20:52001;"), policy)
        XCTAssertFalse(policy.contains("https:"), policy)
    }

    /// relay.js (an LG TV's service) writes the same policy as Swift for the same page, hostile sites included, and the
    /// Xbox host is held to relay.js's by Tests/WebHost/controllers.mjs.
    func testLGServiceWritesTheSamePolicy() throws {
        let node = ["/opt/homebrew/bin/node", "/usr/local/bin/node", "/usr/bin/node"].first { FileManager.default.isExecutableFile(atPath: $0) }
        guard let node else { throw XCTSkip("Node isn't installed") }
        let relay = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/LGPhones/relay.js")
        // Each page's reach file as Lamp writes it (nil: none, an own app's), and one that can't be read.
        let cases: [(String?, UInt16?, Data?)] = [
            ("192.168.1.20:52000", 52001, PhonePagePolicy.file(for: .only(Self.hostile))), ("Mac.local", 60000, nil),
            ("[fe80::1]:5000", 5001, PhonePagePolicy.file(for: .only([]))), (nil, 5001, PhonePagePolicy.file(for: .only(["a.test"]))),
            ("localhost:9", nil, nil), ("10.0.0.2:80", 81, Data("not json".utf8)),
        ]
        for (host, port, file) in cases {
            let reach = PhonePagePolicy.reach(json: file)
            let script = "var r = require(process.argv[1]); var f = process.argv[4]; process.stdout.write(r.policy(JSON.parse(process.argv[2]), JSON.parse(process.argv[3]), f === '-' ? { unrestricted: true } : r.readReachJSON(f)) || '')"
            let process = Process()
            process.executableURL = URL(fileURLWithPath: node)
            let hostJSON = host.map { "\"\($0)\"" } ?? "null"
            process.arguments = ["-e", script, relay.path, hostJSON, port.map(String.init) ?? "null", file.map { String(decoding: $0, as: UTF8.self) } ?? "-"]
            let out = Pipe()
            process.standardOutput = out
            try process.run()
            process.waitUntilExit()
            let js = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            XCTAssertEqual(js, PhonePagePolicy.header(host: host, relayPort: port, reach: reach) ?? "", "\(host ?? "nil")")
        }
    }
}
