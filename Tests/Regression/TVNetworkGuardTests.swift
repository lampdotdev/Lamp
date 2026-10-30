import XCTest
import LampRelayKit
@testable import Lamp

/// A shared TV app goes on a TV held to its own files and the sites its sheet named: the policy is in every page of
/// both packages, Samsung's manifest names only those sites, and Lamp's gateway and relay stay reachable for phones.
final class TVNetworkGuardTests: XCTestCase {
    private var folder: URL!
    private let policy = TVNetworkGuard.Policy(origins: ["https://api.open-meteo.com"], lampHosts: ["studio.local", "192.168.1.20"], gatewayPort: 47100)

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("tv-guard-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func staged() throws -> URL {
        let web = folder.appendingPathComponent("web")
        try FileManager.default.createDirectory(at: web.appendingPathComponent("more"), withIntermediateDirectories: true)
        try Data(TVTemplate.indexHTML.utf8).write(to: web.appendingPathComponent("index.html"))
        try Data("<!-- <head> --><p>second page</p>".utf8).write(to: web.appendingPathComponent("more/other.htm"))
        try Data("fetch('https://evil.example/')".utf8).write(to: web.appendingPathComponent("app.js"))
        return web
    }

    func testAnOriginIsTakenOnlyWhole() {
        XCTAssertEqual(TVNetworkGuard.origin("https://API.Open-Meteo.com"), "https://api.open-meteo.com")
        XCTAssertEqual(TVNetworkGuard.origin("wss://live.example.com:8443/"), "wss://live.example.com:8443")
        for bad in ["https://a.com/path", "https://a.com?x=1", "ftp://a.com", "https://user@a.com", "https://a.com\"; script-src *",
                    "https://*.a.com", "javascript:alert(1)", "https://a .com", ""] {
            XCTAssertNil(TVNetworkGuard.origin(bad), bad)
        }
    }

    func testThePolicyIsTheFirstThingInEveryPage() throws {
        let csp = TVNetworkGuard.tvPage(policy)
        let first = String(decoding: TVNetworkGuard.guarded(Data(TVTemplate.indexHTML.utf8), policy: csp), as: UTF8.self)
        XCTAssertTrue(first.hasPrefix("<!DOCTYPE html><meta charset=\"utf-8\"><meta http-equiv=\"Content-Security-Policy\""), first)
        // A comment that looks like a head can't hide the tag: it goes before anything the page says.
        let tricky = String(decoding: TVNetworkGuard.guarded(Data("<!-- <head> --><p>x</p>".utf8), policy: csp), as: UTF8.self)
        XCTAssertTrue(tricky.hasPrefix("<meta http-equiv=\"Content-Security-Policy\""), tricky)
        XCTAssertTrue(csp.contains("connect-src 'self' file: https://api.open-meteo.com data: blob: http://studio.local:47100 ws://studio.local:*"))
        XCTAssertTrue(csp.contains("ws://192.168.1.20:*") && csp.contains("ws://127.0.0.1:*"), "the relay and an LG game's own service")
        XCTAssertTrue(csp.contains("frame-src https://api.open-meteo.com; child-src https://api.open-meteo.com; worker-src https://api.open-meteo.com;"),
                      "no frame or worker of the app's own files, which no meta tag reaches")
        XCTAssertTrue(TVNetworkGuard.tvPage(TVNetworkGuard.Policy(origins: [], lampHosts: [], gatewayPort: 1)).contains("frame-src 'none'"))
        // Any character but HTML's own spaces before the doctype opens the body, where a policy counts for nothing.
        let spaced = String(decoding: TVNetworkGuard.guarded(Data("\u{00A0}<!doctype html><p>x</p>".utf8), policy: csp), as: UTF8.self)
        XCTAssertTrue(spaced.hasPrefix("<meta http-equiv=\"Content-Security-Policy\""), spaced)
        // A doctype ends at its first `>`, quoted or not, as HTML's tokenizer ends it: the tag then opens the head.
        let quoted = String(decoding: TVNetworkGuard.guarded(Data("<!DOCTYPE html PUBLIC \"a>b\"><p>x</p>".utf8), policy: csp), as: UTF8.self)
        XCTAssertTrue(quoted.hasPrefix("<!DOCTYPE html PUBLIC \"a><meta http-equiv=\"Content-Security-Policy\""), quoted)
        XCTAssertTrue(TVNetworkGuard.isPage("a.shtml") && TVNetworkGuard.isPage("b.HTM"))
        XCTAssertFalse(TVNetworkGuard.isPage("c.xhtml"), "an XHTML page can't take an HTML meta tag")
    }

    func testTheSamsungPackageNamesOnlyTheAppsSites() throws {
        let project = LampProject(id: "weather", name: "Weather", exe: "Weather", dir: folder.appendingPathComponent("weather"))
        let files = try TVPackage.wgtFiles(for: project, staged: try staged(), guarded: policy)
        let config = try XCTUnwrap(files.first { $0.path == "config.xml" }).data
        let manifest = try XMLDocument(data: config)
        let access = try manifest.nodes(forXPath: "//*[local-name()='access']").compactMap { ($0 as? XMLElement)?.attribute(forName: "origin")?.stringValue }
        XCTAssertFalse(access.contains("*"))
        XCTAssertEqual(access, ["https://api.open-meteo.com", "http://studio.local:47100", "ws://studio.local", "http://192.168.1.20:47100", "ws://192.168.1.20", "ws://127.0.0.1"])
        XCTAssertEqual(try manifest.nodes(forXPath: "//*[local-name()='content-security-policy']").first?.stringValue, TVNetworkGuard.tvPage(policy))
        XCTAssertEqual(try manifest.nodes(forXPath: "//*[local-name()='allow-navigation']").first?.stringValue, "api.open-meteo.com")
        for page in ["index.html", "more/other.htm"] {
            let text = String(decoding: try XCTUnwrap(files.first { $0.path == page }).data, as: UTF8.self)
            XCTAssertTrue(text.contains("http-equiv=\"Content-Security-Policy\""), page)
        }

        let open = try XMLDocument(data: try XCTUnwrap(TVPackage.wgtFiles(for: project, staged: try staged(), guarded: nil).first { $0.path == "config.xml" }).data)
        XCTAssertEqual(try open.nodes(forXPath: "//*[local-name()='access']").compactMap { ($0 as? XMLElement)?.attribute(forName: "origin")?.stringValue }, ["*"],
                       "an app made here reaches what it did")
    }

    func testTheLGPackageCarriesThePolicyInEveryPage() async throws {
        let project = LampProject(id: "weather", name: "Weather", exe: "Weather", dir: folder.appendingPathComponent("weather"))
        let ipk = try await TVPackage.ipk(for: project, staged: try staged(), guarded: policy)
        defer { try? FileManager.default.removeItem(at: ipk.deletingLastPathComponent()) }
        let out = folder.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let unpacked = await Subprocess.run("/usr/bin/tar", ["-xf", ipk.path], cwd: out, timeout: 30).ok
        let untarred = await Subprocess.run("/usr/bin/tar", ["-xzf", "data.tar.gz"], cwd: out, timeout: 30).ok
        XCTAssertTrue(unpacked && untarred)
        let app = out.appendingPathComponent("usr/palm/applications/\(TVTemplate.webOSID(for: project))")
        for page in ["index.html", "more/other.htm"] {
            let text = try String(contentsOf: app.appendingPathComponent(page), encoding: .utf8)
            XCTAssertTrue(text.contains("<meta http-equiv=\"Content-Security-Policy\" content=\"\(TVNetworkGuard.tvPage(policy))\">"), page)
        }
        XCTAssertEqual(try String(contentsOf: app.appendingPathComponent("app.js"), encoding: .utf8), "fetch('https://evil.example/')", "scripts go as they are")
    }

    /// The app's policy is the one Lamp recorded when it arrived (`SharedNetwork`): a shared app's Samsung package is held
    /// to its sites, one the person let reach everything isn't, and an app made here has none.
    func testASharedAppIsHeldToTheSitesLampRecorded() throws {
        let project = LampProject(id: "tv-guard-" + UUID().uuidString, name: "Weather", exe: "Weather", dir: folder.appendingPathComponent("weather"))
        defer { SharedNetwork.forget(project) }
        func config() throws -> String {
            let files = try TVPackage.wgtFiles(for: project, staged: try staged(), guarded: TVNetworkGuard.policy(for: project))
            return String(decoding: try XCTUnwrap(files.first { $0.path == "config.xml" }).data, as: UTF8.self)
        }
        XCTAssertNil(TVNetworkGuard.policy(for: project), "an app made here")
        XCTAssertTrue(try config().contains("<access origin=\"*\""))

        try SharedNetwork.save(NetworkPolicy(origins: ["https://api.open-meteo.com"], mayConnect: true), for: project)
        XCTAssertEqual(TVNetworkGuard.policy(for: project)?.origins, ["https://api.open-meteo.com"])
        let held = try config()
        XCTAssertFalse(held.contains("<access origin=\"*\""))
        XCTAssertTrue(held.contains("<access origin=\"https://api.open-meteo.com\" subdomains=\"false\"/>"))
        let page = try TVPackage.wgtFiles(for: project, staged: try staged(), guarded: TVNetworkGuard.policy(for: project)).first { $0.path == "index.html" }
        XCTAssertTrue(String(decoding: try XCTUnwrap(page).data, as: UTF8.self).contains("connect-src 'self' file: https://api.open-meteo.com data: blob:"))

        try SharedNetwork.save(NetworkPolicy(origins: ["https://api.open-meteo.com"], unrestricted: true), for: project)
        XCTAssertNil(TVNetworkGuard.policy(for: project), "the person let it reach every site")
    }

    func testOnlyATVWhoseBrowserHoldsThePolicyCountsAsGuarding() {
        func tv(_ maker: String, _ version: String) -> TVs.Record {
            TVs.Record(id: "x", maker: maker, name: "TV", model: "", modelID: "", address: "192.168.1.30", os: "", osVersion: version, resolution: "")
        }
        XCTAssertFalse(TVNetworkGuard.holds(on: tv("Samsung", "4.0")))
        XCTAssertTrue(TVNetworkGuard.holds(on: tv("Samsung", "5.0")))
        XCTAssertFalse(TVNetworkGuard.holds(on: tv("LG", "4.10.0")))
        XCTAssertTrue(TVNetworkGuard.holds(on: tv("LG", "6.3.1")))
        XCTAssertFalse(TVNetworkGuard.holds(on: tv("LG", "")), "a version Lamp hasn't read")
    }
}
