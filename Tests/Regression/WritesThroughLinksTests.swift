import XCTest
@testable import Lamp

/// After a build, Lamp writes into the app's folder: what the build was made from, the stamp in the built app, the
/// live copy's records, its own files for the next build. A build (or any command of the agent's) can leave a link
/// where one of those goes. Lamp must replace the link, never write through it, and never read through one into
/// what it writes.
@MainActor
final class WritesThroughLinksTests: XCTestCase {
    private var root: URL?
    override func tearDown() { if let root { try? FileManager.default.removeItem(at: root) } }

    func testLinksLeftInTheAppFolderLeadNowhere() throws {
        let fm = FileManager.default
        // Under the home folder, like a real app.
        let root = fm.homeDirectoryForCurrentUser.appendingPathComponent(".lamp-links-test-\(UUID().uuidString)")
        self.root = root
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let project = try Template.scaffold(name: "Linked", platform: .mac, in: root)

        // What the links lead to: files and a bundle outside the app that only Lamp could change.
        let outside = root.appendingPathComponent("outside")
        try fm.createDirectory(at: outside.appendingPathComponent("Other.app/Contents"), withIntermediateDirectories: true)
        let otherPlist = outside.appendingPathComponent("Other.app/Contents/Info.plist")
        try #"<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>other.app</string></dict></plist>"#
            .write(to: otherPlist, atomically: true, encoding: .utf8)
        let precious = outside.appendingPathComponent("precious.txt")
        try "precious".write(to: precious, atomically: true, encoding: .utf8)
        let secret = outside.appendingPathComponent("secret.txt")
        try "a key of Lamp's".write(to: secret, atomically: true, encoding: .utf8)
        let elsewhere = outside.appendingPathComponent("elsewhere")
        try fm.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        let before = try snapshot(outside)

        // What a build could leave: a link where each of Lamp's files goes, and folders that are links.
        let runtime = project.dir.appendingPathComponent(".lamp/runtime")
        try fm.createDirectory(at: runtime, withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: runtime.appendingPathComponent("built"), withDestinationURL: precious)
        try fm.createSymbolicLink(at: runtime.appendingPathComponent("held-build"), withDestinationURL: precious)
        try fm.createDirectory(at: project.dir.appendingPathComponent("build"), withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: project.builtURL, withDestinationURL: outside.appendingPathComponent("Other.app"))
        try fm.createSymbolicLink(at: LiveReload.folder(project), withDestinationURL: elsewhere)
        try? fm.removeItem(at: project.dir.appendingPathComponent("build.sh"))
        try fm.createSymbolicLink(at: project.dir.appendingPathComponent("build.sh"), withDestinationURL: precious)
        try? fm.removeItem(at: project.dir.appendingPathComponent(".lamp/widget-token"))
        try fm.createSymbolicLink(at: project.dir.appendingPathComponent(".lamp/widget-token"), withDestinationURL: secret)
        try? fm.removeItem(at: project.dir.appendingPathComponent(".lamp/token"))
        try fm.createSymbolicLink(at: project.dir.appendingPathComponent(".lamp/token"), withDestinationURL: secret)

        // Lamp's writes after a build, and before the next one.
        Runtime.markBuilt(project, from: "fingerprint")
        Runtime.holdBuild(project)
        BuildStamp.write(for: project)
        LiveReload.awaitInstall(project)
        LiveReload.startedBuilding(project, from: "fingerprint")
        LiveReload.markRunning(project)
        LiveReload.keepLayout(["a layout"], for: project)
        try? Template.writeOwnedFiles(for: project)

        XCTAssertEqual(try snapshot(outside), before, "Lamp wrote through a link the build left")
        // The secret behind the token's link isn't what the app is built with.
        let support = try String(contentsOf: project.dir.appendingPathComponent("Sources/LampSupport.swift"), encoding: .utf8)
        XCTAssertFalse(support.contains("a key of Lamp's"), "Lamp read a file through a link into the app's code")
        // Its own files are there all the same, in place of the links.
        XCTAssertNil(try? fm.destinationOfSymbolicLink(atPath: runtime.appendingPathComponent("built").path))
        XCTAssertEqual(try String(contentsOf: runtime.appendingPathComponent("built"), encoding: .utf8), "fingerprint")
        XCTAssertNil(try? fm.destinationOfSymbolicLink(atPath: project.dir.appendingPathComponent("build.sh").path))
        XCTAssertTrue(fm.isExecutableFile(atPath: project.dir.appendingPathComponent("build.sh").path))
    }

    /// Every file under `folder` with what it holds, links as where they lead.
    private func snapshot(_ folder: URL) throws -> [String: String] {
        let fm = FileManager.default
        var files: [String: String] = [:]
        for case let url as URL in fm.enumerator(at: folder, includingPropertiesForKeys: nil) ?? FileManager.DirectoryEnumerator() {
            let name = String(url.path.dropFirst(folder.path.count))
            if let link = try? fm.destinationOfSymbolicLink(atPath: url.path) { files[name] = "-> " + link; continue }
            var folder: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &folder), folder.boolValue { files[name] = "folder"; continue }
            files[name] = (try? String(contentsOf: url, encoding: .utf8)) ?? "unreadable"
        }
        return files
    }
}
