import XCTest
@testable import Lamp

/// What Lamp ships for devices, and the Windows packages it makes for one, held to what the device was seen to take.
final class DeviceAppPackageTests: XCTestCase {
    /// Every integration Lamp ships passes the same checks as one the builder writes (with its own marks allowed).
    func testShippedIntegrationsPassTheChecker() throws {
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Devices")
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }
        XCTAssertFalse(files.isEmpty)
        for file in files {
            let data = try Data(contentsOf: file)
            XCTAssertEqual(IntegrationCheck.unknownKeys(data) + IntegrationCheck.problems(data, submitted: false), [], file.lastPathComponent)
        }
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
    }
}
