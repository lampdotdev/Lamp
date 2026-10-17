import XCTest
@testable import Lamp

/// The project Lamp has Xcode sign as itself (`TeamSigning`) is built from nothing the agent can write. The app's name
/// and program name are in its meta.json, which the agent can change to anything, so they must not reach that project.
@MainActor
final class SigningProjectNamesTests: XCTestCase {
    private var root: URL?
    private var project: LampProject?

    override func tearDown() {
        if let root { try? FileManager.default.removeItem(at: root) }
        let fm = FileManager.default
        if let project {
            try? fm.removeItem(at: Devices.buildFolder(for: project))
            try? fm.removeItem(at: Devices.signingFolder(for: project))
        }
        for folder in [Devices.buildsFolder.appendingPathComponent(".signing"), Devices.buildsFolder]
        where (try? fm.contentsOfDirectory(atPath: folder.path))?.isEmpty == true { try? fm.removeItem(at: folder) }
    }

    func testTheAppsOwnNamesStayOutOfLampsProject() async throws {
        let fm = FileManager.default
        let root = fm.homeDirectoryForCurrentUser.appendingPathComponent(".lamp-signing-names-test-\(UUID().uuidString)")
        self.root = root
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let marker = "Zqx\(UUID().uuidString.filter(\.isLetter).prefix(5))"
        let made = try Template.scaffold(name: "Probe \(marker)", platform: .iphone, in: root)
        // What the agent could have written into meta.json: any text at all, here only something to find again.
        let project = LampProject(id: made.id, name: "Probe \(marker)\" ; evil", exe: "Probe\(marker)", dir: made.dir)
        self.project = project.named(project.name, exe: project.exe)
        var copy = project
        copy.platform = .iphone
        // A team that isn't one: Xcode refuses to sign, after Lamp has written its project.
        _ = try? await TeamSigning.plan(for: copy, team: "ABCDE12345", place: .iphone, destination: "generic/platform=iOS")
        let folder = TeamSigning.folder(for: copy, place: .iphone).appendingPathComponent("Project")
        let files = (fm.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey])?.compactMap { $0 as? URL } ?? [])
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true }
        XCTAssertFalse(files.isEmpty, "Lamp wrote no project")
        for file in files {
            XCTAssertFalse(file.path.contains(marker), "the app's own name made a path in Lamp's project: \(file.lastPathComponent)")
            let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            XCTAssertFalse(text.contains(marker), "the app's own name is in Lamp's project: \(file.lastPathComponent)")
        }
    }
}
