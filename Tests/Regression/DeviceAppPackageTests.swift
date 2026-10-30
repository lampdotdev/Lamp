import XCTest
@testable import Lamp
import LampRelayKit

/// What Lamp ships for devices, and the Windows packages it makes for one, held to what the device was seen to take.
final class DeviceAppPackageTests: XCTestCase {
    /// Every integration Lamp ships passes the same checks as one the builder writes (with its own marks allowed). The
    /// skills an integration names are checked against the source tree's, since the test runner's bundle has none.
    func testShippedIntegrationsPassTheChecker() throws {
        let resources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources")
        let folder = resources.appendingPathComponent("Devices"), skills = Skills.load(from: resources.appendingPathComponent("skills"))
        XCTAssertFalse(skills.isEmpty)
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }
        XCTAssertFalse(files.isEmpty)
        for file in files {
            let data = try Data(contentsOf: file)
            XCTAssertEqual(IntegrationCheck.unknownKeys(data) + IntegrationCheck.problems(data, submitted: false, skills: skills), [], file.lastPathComponent)
            // And the whole lifecycle a builder's integration is held to.
            XCTAssertEqual(IntegrationCheck.lifecycle(try JSONDecoder().decode(Integration.self, from: data)), [], file.lastPathComponent)
        }
    }

    /// A builder's integration that makes apps says how they're stopped, removed and typed into, or that the device can't.
    func testAnAppKindsLifecycleIsWholeOrSaidToBeMissing() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Devices/roku.json")
        var roku = try JSONDecoder().decode(Integration.self, from: Data(contentsOf: file))
        roku.bridge?.stop = nil
        XCTAssertTrue(IntegrationCheck.lifecycle(roku).contains { $0.hasPrefix("bridge.stop") })
        roku.bridge?.lacks = ["stop"]
        XCTAssertEqual(IntegrationCheck.lifecycle(roku), [])
        roku.app?.declared?.icons = nil
        XCTAssertTrue(IntegrationCheck.lifecycle(roku).contains { $0.contains("images/icon_focus_hd.png") })
        // A page's own relative picture is its folder's.
        roku.app?.declared?.files = ["Web/index.html": "<img src=\"images/icon.png\">"]
        roku.app?.declared?.icons = ["Web/images/icon.png": "200x200"]
        XCTAssertFalse(IntegrationCheck.lifecycle(roku).contains { $0.contains("icon.png") })
    }

    /// Windows names a package by a short id of its publisher; the bridge launches it by that name.
    func testWindowsNamesThePackageAsTheDeviceDoes() {
        XCTAssertEqual(MSIX.publisherID("CN=LampTest"), "t1a59ncyrzgcm")
        let identity = MSIX.Identity(name: "Lamp.demo", publisher: "CN=LampTest", version: "1.0.0.0")
        XCTAssertEqual(identity.fullName, "Lamp.demo_1.0.0.0_neutral__t1a59ncyrzgcm")
        XCTAssertEqual(identity.appUserModelID, "Lamp.demo_t1a59ncyrzgcm!App")
        // Two builds in one minute still get a newer version each, which Windows needs to replace the package.
        let now = Date()
        let first = MSIX.version(at: now), second = MSIX.version(at: now, after: first)
        XCTAssertNotEqual(first, second)
        XCTAssertTrue(first.split(separator: ".").map { Int($0)! }.lexicographicallyPrecedes(second.split(separator: ".").map { Int($0)! }))
    }

    /// A web app in Lamp's WebView2 host starts the host, and registers WebView2's classes from the library beside it:
    /// without them the host can't make a web view, and the console shows nothing.
    func testTheWebHostsPackageRegistersWebView2() {
        let identity = MSIX.Identity(name: "Lamp.demo", publisher: MSIX.publisher, version: "1.0.0.0", architecture: "x64")
        let manifest = MSIX.manifest(identity: identity, displayName: "Demo", entry: .webHost)
        XCTAssertTrue(manifest.contains("Executable=\"App.exe\""))
        XCTAssertFalse(manifest.contains("StartPage="))
        XCTAssertTrue(manifest.contains("<Path>Microsoft.Web.WebView2.Core.dll</Path>"))
        for name in WebHost.activatableClasses { XCTAssertTrue(manifest.contains("ActivatableClassId=\"\(name)\""), name) }
    }

    /// A shared app's Xbox package carries its sites beside the host, outside Web/, where the host reads them with Lamp
    /// closed (lamp_web_guard.h, which scripts/check-web-host-guard.sh runs): the policy Lamp kept at import, exact,
    /// with Lamp's own addresses for the page's calls to it. A file of the app's own by that name stays the app's, in Web/.
    func testASharedAppsXboxPackageCarriesItsSites() throws {
        let resources = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-web-host-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: resources) }
        try Data("MZ host reading network-policy.json".utf8).write(to: resources.appendingPathComponent(WebHost.program))
        try Data("library".utf8).write(to: resources.appendingPathComponent(WebHost.library))
        let kept = NetworkPolicy(origins: ["https://API.Open-Meteo.com/v1/forecast", "wss://relay.example:8443/"], mayConnect: true)
        let policy = WebHost.policy(from: kept, lamp: ["http://Test-Mac.local:7777", "http://192.168.1.5:7777"])
        let own = Data(#"{"format":1,"origins":["https://evil.example"]}"#.utf8)
        let files = try WebHost.payload([("index.html", Data("<p>".utf8)), (WebHost.policyFile, own)], policy: policy, from: resources)
        let written = try XCTUnwrap(files.first { $0.path == WebHost.policyFile }?.data)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: written) as? [String: Any])
        XCTAssertEqual(json["format"] as? Int, 1)
        XCTAssertEqual(json["origins"] as? [String], ["https://api.open-meteo.com", "wss://relay.example:8443"])
        XCTAssertEqual(json["lamp"] as? [String], ["http://192.168.1.5:7777", "http://test-mac.local:7777"])
        XCTAssertEqual(files.filter { $0.path == WebHost.policyFile }.count, 1)
        XCTAssertEqual(files.first { $0.path == "Web/" + WebHost.policyFile }?.data, own)
        // Nothing listed is nothing reached, not everything.
        XCTAssertEqual(WebHost.policy(from: NetworkPolicy(), lamp: [])?.origins, [])
        // The person's own app, and a shared one they let reach every site, carry none.
        XCTAssertNil(WebHost.policy(from: nil, lamp: []))
        XCTAssertNil(WebHost.policy(from: NetworkPolicy(origins: ["https://a.example"], unrestricted: true), lamp: []))
        XCTAssertFalse(try WebHost.payload([], from: resources).contains { $0.path == WebHost.policyFile })
        // A host built before the guard would run the page unheld: a shared app isn't put beside it, an own app still is.
        try Data("MZ host from before".utf8).write(to: resources.appendingPathComponent(WebHost.program))
        XCTAssertThrowsError(try WebHost.payload([("index.html", Data("<p>".utf8))], policy: policy, from: resources))
        XCTAssertNoThrow(try WebHost.payload([("index.html", Data("<p>".utf8))], from: resources))
    }

    /// The import map the rules give names the library where the page finds it, nested folders included.
    func testTheImportMapPathKeepsNestedFolders() {
        XCTAssertEqual(DeviceSupport.pagePath("Web/three", page: "Web"), "three")
        XCTAssertEqual(DeviceSupport.pagePath("Web/vendor/three", page: "Web"), "vendor/three")
        XCTAssertEqual(DeviceSupport.pagePath("Webby/three", page: "Web"), "Webby/three")
    }

    /// Every part of a package has a content type, a file with no extension (three.js's LICENSE) too: the Xbox refuses a
    /// package with an untyped part, as an invalid block map.
    func testAFileWithNoExtensionStillHasAType() {
        let types = String(decoding: MSIX.contentTypes(for: ["Web/three/LICENSE", "Web/index.html"]), as: UTF8.self)
        XCTAssertTrue(types.contains("<Override PartName=\"/Web/three/LICENSE\" ContentType=\"application/octet-stream\"/>"), types)
        XCTAssertTrue(types.contains("<Default Extension=\"html\""))
    }

    /// The package step's zip is read as plain files only: nothing above its top, no links.
    func testThePackageStepsZipIsReadAsPlainFilesOnly() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-zip-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("Web"), withIntermediateDirectories: true)
        try Data("<p>hi</p>".utf8).write(to: folder.appendingPathComponent("Web/index.html"))
        try FileManager.default.createSymbolicLink(atPath: folder.appendingPathComponent("Web/secret").path, withDestinationPath: "/etc/hosts")
        func zip(_ arguments: [String]) throws -> Data {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            process.arguments = ["-q", folder.appendingPathComponent("out.zip").path] + arguments
            process.currentDirectoryURL = folder.appendingPathComponent("Web")
            try? FileManager.default.removeItem(at: folder.appendingPathComponent("out.zip"))
            try process.run()
            process.waitUntilExit()
            return try Data(contentsOf: folder.appendingPathComponent("out.zip"))
        }
        XCTAssertEqual(try MSIX.files(inZip: try zip(["index.html"])).map(\.path), ["index.html"])
        // A game's models and sounds can be bigger than a device's answers are allowed to be: it's packaged whole.
        try Data(count: 20 << 20).write(to: folder.appendingPathComponent("Web/model.glb"))
        XCTAssertEqual(try MSIX.files(inZip: try zip(["-0", "model.glb"])).first?.data.count, 20 << 20)
        XCTAssertThrowsError(try MSIX.files(inZip: try zip(["-y", "secret"])), "a link isn't packaged")
        XCTAssertThrowsError(try MSIX.files(inZip: try zip(["../Web/index.html"])), "nothing above the zip's top")
        // A zip cut short is refused, never read past its end.
        let whole = try zip(["index.html"])
        for cut in [whole.count - 30, whole.count / 2, 40] {
            var broken = whole.prefix(cut) + whole.suffix(22)
            broken.replaceSubrange(broken.count - 6 ..< broken.count - 2, with: Data([0, 0, 0, 0]))
            XCTAssertThrowsError(try MSIX.files(inZip: Data(broken)))
        }
    }

    /// A cookie the device set goes back only as a header, and base64 is only of Lamp's own values.
    func testCookiesAndBase64StayWhereTheyBelong() throws {
        XCTAssertNil(Placeholders.problem("cookie:CSRF-Token", in: .header, fields: []))
        XCTAssertNotNil(Placeholders.problem("cookie:CSRF-Token", in: .path, fields: []))
        XCTAssertNil(Placeholders.problem("base64:packageFullName", in: .path, fields: []))
        XCTAssertNotNil(Placeholders.problem("base64:field:password", in: .path, fields: ["password"]))
        XCTAssertNotNil(Placeholders.problem("base64:signIn", in: .path, fields: []), "a sign-in isn't carried into a path by encoding it")
        let filled = try Placeholders.fill("/api/app?package={base64:packageFullName}", ["packageFullName": "Lamp.a_1.0.0.0_neutral__x"], in: .path)
        // The value's own "+", "/" and "=" can't change the query they're put in.
        XCTAssertEqual(filled, "/api/app?package=TGFtcC5hXzEuMC4wLjBfbmV1dHJhbF9feA%3D%3D")
        // Text being typed is any character, encoded in a path so it can't leave it, and never in a header.
        XCTAssertEqual(try Placeholders.fill("/keypress/Lit_{text}", ["text": "/"], in: .path), "/keypress/Lit_%2F")
        XCTAssertEqual(try Placeholders.fill("/keypress/Lit_{text}", ["text": "é"], in: .path), "/keypress/Lit_%C3%A9")
        XCTAssertNotNil(Placeholders.problem("text", in: .header, fields: []))
    }
}
