import XCTest
@testable import Lamp

/// three.js is Lamp's in a TV app's page only: a web app and a screen made before get lamp.js from the same writer, but
/// never three.js, so a copy of their own at Web/three stays as it is and none is added to a page that didn't ask.
final class TVThreeTests: XCTestCase {
    private var root: URL!
    private var source: ((LampProject) -> [(name: String, contents: String)])!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("lamp-tv-three-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        source = TVTemplate.threeSource
        // Lamp's own copy isn't in a test run: one file stands in for it.
        TVTemplate.threeSource = { _ in [(name: "three.module.js", contents: "export const REVISION = 'lamp';\n")] }
    }

    override func tearDownWithError() throws {
        TVTemplate.threeSource = source
        try? FileManager.default.removeItem(at: root)
    }

    private func app(_ platform: Platform) throws -> LampProject {
        let dir = root.appendingPathComponent(platform.rawValue)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Web"), withIntermediateDirectories: true)
        var project = LampProject(id: "tv-three-\(platform.rawValue)", name: "Page", exe: "Page", dir: dir)
        project.platform = platform
        return project
    }

    private func three(_ project: LampProject) -> String? {
        try? String(contentsOf: project.dir.appendingPathComponent("Web/three/three.module.js"), encoding: .utf8)
    }

    func testOnlyATVAppsPageGetsLampsThree() throws {
        let tv = try app(.tv)
        try TVTemplate.writeOwnedFiles(for: tv)
        XCTAssertEqual(three(tv), "export const REVISION = 'lamp';\n")

        for platform in [Platform.webApp, .screen] {
            let page = try app(platform)
            try TVTemplate.writeOwnedFiles(for: page)
            XCTAssertNotNil(try? String(contentsOf: page.dir.appendingPathComponent("Web/lamp.js"), encoding: .utf8), "\(platform.rawValue) still gets lamp.js")
            XCTAssertNil(three(page), "\(platform.rawValue) gets no three.js")
            try FileManager.default.createDirectory(at: page.dir.appendingPathComponent("Web/three"), withIntermediateDirectories: true)
            try "export const REVISION = 'its own';\n".write(to: page.dir.appendingPathComponent("Web/three/three.module.js"), atomically: true, encoding: .utf8)
            try TVTemplate.writeOwnedFiles(for: page)
            XCTAssertEqual(three(page), "export const REVISION = 'its own';\n", "\(platform.rawValue)'s own copy stays")
        }
    }
}
