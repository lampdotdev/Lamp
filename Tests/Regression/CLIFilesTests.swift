import XCTest
@testable import Lamp

/// lamp's command line (cli/) gives an app the files Lamp's app writes into it, which are made by Lamp's own code. The
/// list of controllers is one, and a game's runtime can't load without it, so the command line keeps a copy
/// (cli/lamps/lamp-controllers.js) that must be the list as Lamp writes it. A new Mac app's starting files are another,
/// made on demand, and the package an Xbox takes a third, which the command line makes itself and a kept example
/// holds to Lamp's. Run with LAMP_WRITE_CLI_FILES=1 (scripts/cli-files.sh) to write them again.
final class CLIFilesTests: XCTestCase {
    private static let cli = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("cli/lamps")

    /// A new Mac app's folder as Lamp makes one (`Template.scaffold`), under a name the command line puts the app's own
    /// in the place of (`lamp new --mac`): Lamp's own files and the card the app shows until it's written. Made only
    /// when asked (LAMP_WRITE_CLI_FILES=1, which scripts/cli-files.sh sets) and never committed: the building blocks
    /// change often, and a copy kept in the repository would be one more thing to keep in step with them.
    func testWritesAMacAppsStartingFiles() throws {
        guard ProcessInfo.processInfo.environment["LAMP_WRITE_CLI_FILES"] == "1" else { throw XCTSkip("Only when asked: scripts/cli-files.sh") }
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("lamp-cli-starter-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let project = try Template.scaffold(name: "Zqx App Name", platform: .mac, in: root)
        let starter = Self.cli.appendingPathComponent("mac-starter")
        try? fm.removeItem(at: starter)
        try fm.createDirectory(at: Self.cli, withIntermediateDirectories: true)
        try fm.copyItem(at: project.dir, to: starter)
        // What the command line needs to know of it: the names it stands in for.
        let names = ["name": project.name, "exe": project.exe, "slug": project.id, "bundle": Edition.appBundlePrefix + project.id]
        try JSONSerialization.data(withJSONObject: names, options: [.sortedKeys, .prettyPrinted]).write(to: starter.appendingPathComponent("lamp-starter.json"))
        XCTAssertTrue(fm.fileExists(atPath: starter.appendingPathComponent("Sources/LampSupport.swift").path))
        XCTAssertTrue(fm.fileExists(atPath: starter.appendingPathComponent("build.sh").path))
    }

    /// A new web app's page as Lamp makes one (`Template.scaffold` for `Platform.webApp`), for `lamp new --web`: what's in
    /// its Web/ folder and its notes, without the app around the page, which is Lamp's app's to build. And lamp.js as
    /// that page is given it, Lamp's building blocks for a page, and as a game's page is given it.
    /// Made only when asked, and never committed, as a Mac app's starting files are.
    func testWritesAWebAppsStartingFiles() throws {
        guard ProcessInfo.processInfo.environment["LAMP_WRITE_CLI_FILES"] == "1" else { throw XCTSkip("Only when asked: scripts/cli-files.sh") }
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("lamp-cli-web-starter-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let project = try Template.draft(name: "Zqx App Name", platform: .webApp, in: root)
        // The page's own files are written first, then the app around the page, whose kit a test run doesn't have (it's
        // in Lamp's bundle): that failure is the end of what's wanted here.
        _ = try? ScreenKit.fill(project)
        let web = project.dir.appendingPathComponent(TVTemplate.webFolder)
        // lamp.js as Lamp writes it for the page, with the QR encoder it carries read from the repository, where a
        // test run finds it (Lamp reads it from its bundle).
        let qr = Self.cli.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/WebLibraries/qrcode")
        let encoder = try String(contentsOf: qr.appendingPathComponent("qrcode.js"), encoding: .utf8)
        let license = try? String(contentsOf: qr.appendingPathComponent("LICENSE"), encoding: .utf8)
        let lampJSText = TVTemplate.lampJS(for: project)
            .replacingOccurrences(of: DeviceSupport.qrJS(encoder: nil, license: nil), with: DeviceSupport.qrJS(encoder: encoder, license: license))
        try lampJSText.write(to: web.appendingPathComponent(TVTemplate.supportFile.components(separatedBy: "/").last ?? "lamp.js"), atomically: true, encoding: .utf8)
        let starter = Self.cli.appendingPathComponent("web-starter")
        try? fm.removeItem(at: starter)
        try fm.createDirectory(at: Self.cli, withIntermediateDirectories: true)
        try fm.copyItem(at: web, to: starter)
        let notes = project.dir.appendingPathComponent("APP.md")
        if fm.fileExists(atPath: notes.path) { try fm.copyItem(at: notes, to: starter.appendingPathComponent("APP.md")) }
        let names = ["name": project.name, "exe": project.exe, "slug": project.id]
        try JSONSerialization.data(withJSONObject: names, options: [.sortedKeys, .prettyPrinted]).write(to: starter.appendingPathComponent("lamp-starter.json"))
        XCTAssertTrue(fm.fileExists(atPath: starter.appendingPathComponent("index.html").path))
        let lampJS = starter.appendingPathComponent("lamp.js")
        XCTAssertTrue(fm.fileExists(atPath: lampJS.path))
        try? fm.removeItem(at: Self.cli.appendingPathComponent("lamp.js"))
        try fm.copyItem(at: lampJS, to: Self.cli.appendingPathComponent("lamp.js"))
        // And lamp.js as a game is given it (`GameKit.lampJS`), which leaves out a TV's remote: a game reads its own
        // controller, and the remote's code would take the keys the Xbox's controller sends.
        let gameJS = GameKit.lampJS(for: project)
            .replacingOccurrences(of: DeviceSupport.qrJS(encoder: nil, license: nil), with: DeviceSupport.qrJS(encoder: encoder, license: license))
        try gameJS.write(to: Self.cli.appendingPathComponent("lamp-for-games.js"), atomically: true, encoding: .utf8)
    }

    /// The command line makes an Xbox's package itself (cli/msix.mjs), and it must be the package Lamp makes: the same
    /// manifest, and the same files in the same layout, which the signature says (it signs the hashes of the records,
    /// the directory, the block map and the content types). So what's kept is the manifest and the signature of one
    /// small package under a key made for this alone, which the command line's own test makes again and compares.
    func testTheCommandLinesPackageIsLamps() throws {
        let folder = Self.cli.deletingLastPathComponent().appendingPathComponent("tests/fixtures/msix")
        let fm = FileManager.default
        let writing = ProcessInfo.processInfo.environment["LAMP_WRITE_CLI_FILES"] == "1"
        let keyURL = folder.appendingPathComponent("key.der"), certificateURL = folder.appendingPathComponent("certificate.der")
        if writing, !fm.fileExists(atPath: keyURL.path) {
            let made = try MSIX.Signer.throwaway()
            var error: Unmanaged<CFError>?
            let key = try XCTUnwrap(SecKeyCopyExternalRepresentation(made.key, &error) as Data?)
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            try key.write(to: keyURL)
            try made.certificate.write(to: certificateURL)
        }
        let attributes = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: kSecAttrKeyClassPrivate] as CFDictionary
        let key = try XCTUnwrap(SecKeyCreateWithData(try Data(contentsOf: keyURL) as CFData, attributes, nil))
        let signer = try MSIX.Signer.from(certificate: try Data(contentsOf: certificateURL), key: key)

        // The same made-up app on both sides: a name that needs escaping, a file in a folder, one with no extension,
        // one whose name has a space and an ampersand, an empty one, and one of more than a block.
        let identity = MSIX.Identity(name: MSIX.identityName(for: "harbor-racer-1a2b3c4d"), publisher: MSIX.publisher, version: "1.7.4660.2", architecture: "x64")
        let manifest = MSIX.manifest(identity: identity, displayName: "Harbor <Racer> & \"Friends\"", entry: .webHost)
        let files: [(path: String, data: Data)] = [
            ("App.exe", Data("host".utf8)),
            ("Web/index.html", Data("<!doctype html><title>Harbor Racer</title>".utf8)),
            ("Web/LICENSE", Data("MIT".utf8)),
            ("Web/sea & sky.txt", Data("blue".utf8)),
            ("Web/empty.js", Data()),
            ("Web/big.bin", Data((0..<70_000).map { UInt8($0 % 251) })),
            ("AppxManifest.xml", Data(manifest.utf8)),
        ]
        let package = try MSIX.assemble(files, signer: signer)

        // The signature's own record is the one deflated one: read back out, it's what the two sides compare, since
        // each deflates in its own way.
        let name = Data("AppxSignature.p7x".utf8)
        // Its record, not the content types' mention of it nor the directory's entry: the name 30 bytes after a
        // local record's mark.
        var found: Int?, from = package.startIndex
        while let range = package.range(of: name, in: from..<package.endIndex) {
            if range.lowerBound >= 30, package.subdata(in: (range.lowerBound - 30)..<(range.lowerBound - 26)) == Data([0x50, 0x4B, 0x03, 0x04]) { found = range.lowerBound - 30 }
            from = range.upperBound
        }
        let at = try XCTUnwrap(found)
        let packed = Int(package[at + 18]) | Int(package[at + 19]) << 8 | Int(package[at + 20]) << 16 | Int(package[at + 21]) << 24
        let deflated = package.subdata(in: (at + 30 + name.count)..<(at + 30 + name.count + packed))
        let signature = try (deflated as NSData).decompressed(using: .zlib) as Data
        let names = try JSONSerialization.data(withJSONObject: ["fullName": identity.fullName, "appUserModelID": identity.appUserModelID,
                                                                "nextVersion": MSIX.version(at: Date(timeIntervalSince1970: 1_800_000_000), after: "1.0.0.0"),
                                                                "sameMinute": MSIX.version(at: Date(timeIntervalSince1970: 1_800_000_000), after: "1.8.27776.0")],
                                                   options: [.sortedKeys, .prettyPrinted])
        let kept: [(String, Data)] = [("manifest.xml", Data(manifest.utf8)), ("signature.p7x", signature), ("names.json", names)]
        for (file, data) in kept {
            let url = folder.appendingPathComponent(file)
            if writing { try data.write(to: url) }
            XCTAssertEqual(try Data(contentsOf: url), data, "cli/tests/fixtures/msix/\(file) isn't what Lamp makes now: run scripts/cli-files.sh, then make cli/msix.mjs agree")
        }
    }

    func testTheCommandLinesControllersAreLamps() throws {
        let copy = Self.cli.appendingPathComponent("lamp-controllers.js")
        if ProcessInfo.processInfo.environment["LAMP_WRITE_CLI_FILES"] == "1" {
            try FileManager.default.createDirectory(at: copy.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Controllers.pageJS.write(to: copy, atomically: true, encoding: .utf8)
        }
        XCTAssertEqual(try String(contentsOf: copy, encoding: .utf8), Controllers.pageJS,
                       "cli/lamps/lamp-controllers.js isn't the controllers as Lamp writes them: run this test with LAMP_WRITE_CLI_FILES=1")
    }
}
