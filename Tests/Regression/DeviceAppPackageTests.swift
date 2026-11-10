import XCTest
@testable import Lamp

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

    /// A Roku older than Roku's SDK needs stays at its first step, so nothing is put on it until it's updated (the
    /// comparison is lamp's command line's, tested there).
    func testARokuOlderThanTheSDKWaitsAtTheUpdateStep() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Devices/roku.json")
        let roku = try JSONDecoder().decode(Integration.self, from: Data(contentsOf: file))
        XCTAssertEqual(roku.steps.first?.check.first?.atLeast, "15.1")
        XCTAssertEqual(roku.steps.first?.check.first?.xml, "software-version")
    }

    /// Windows names a package by a short id of its publisher; the bridge launches it by that name.
    func testWindowsNamesThePackageAsTheDeviceDoes() {
        XCTAssertEqual(MSIX.publisherID("CN=LampTest"), "t1a59ncyrzgcm")
        let identity = MSIX.Identity(name: "Lamp.demo", publisher: "CN=LampTest", version: "1.0.0.0")
        XCTAssertEqual(identity.fullName, "Lamp.demo_1.0.0.0_neutral__t1a59ncyrzgcm")
        XCTAssertEqual(identity.appUserModelID, "Lamp.demo_t1a59ncyrzgcm!App")
    }

    /// The import map the rules give names the library where the page finds it, nested folders included.
    func testTheImportMapPathKeepsNestedFolders() {
        XCTAssertEqual(DeviceSupport.pagePath("Web/three", page: "Web"), "three")
        XCTAssertEqual(DeviceSupport.pagePath("Web/vendor/three", page: "Web"), "vendor/three")
        XCTAssertEqual(DeviceSupport.pagePath("Webby/three", page: "Web"), "Webby/three")
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
