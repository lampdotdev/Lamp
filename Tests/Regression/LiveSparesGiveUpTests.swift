import XCTest
@testable import Lamp

/// A live build that fails is built again without the copy step's spares only to find out whether they were the
/// cause. When the agent's own code is (a call too new for the app's macOS), the build fails that way too, and the
/// spares must stay: without them every later change waits for Reload, since the open app has them.
/// Each test runs real builds, a minute or so apiece.
@MainActor
final class LiveSparesGiveUpTests: XCTestCase {
    private var root: URL?

    override func tearDown() async throws {
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    private func app(with code: String) throws -> LampProject {
        let fm = FileManager.default
        // Under the home folder, where the app's sandbox (which the build runs in) opens an app's folder.
        let root = fm.homeDirectoryForCurrentUser.appendingPathComponent(".lamp-spares-test-\(UUID().uuidString)")
        self.root = root
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let project = try Template.scaffold(name: "Spares", in: root)
        try code.write(to: project.dir.appendingPathComponent("Sources/Extra.swift"), atomically: true, encoding: .utf8)
        return project
    }

    private func liveBuild(_ project: LampProject) async -> (status: Int32, output: String) {
        var output: [String] = []
        let status = await Store.buildSparing("./build.sh", for: project, env: ["LAMP_LIVE": "1"]) { output = $0 }
        return (status, output.joined(separator: "\n"))
    }

    private func gaveUp(_ project: LampProject) -> Bool {
        FileManager.default.fileExists(atPath: LiveReload.folder(project).appendingPathComponent("no-spares").path)
    }

    func testTheAgentsOwnErrorKeepsTheSpares() async throws {
        let project = try app(with: """
            import SwiftUI
            final class Model: ObservableObject { @Published var count = 0 }
            struct Extra: View {
                @State private var text = ""
                var body: some View {
                    NavigationSplitView { Text(text) } detail: { Text("Detail") }
                        .toolbar(removing: .title)
                }
            }
            """)
        let (status, output) = await liveBuild(project)
        XCTAssertNotEqual(status, 0)
        XCTAssertTrue(output.contains("only available in macOS 15.0 or newer"), output)
        XCTAssertFalse(gaveUp(project), "the agent's own error was taken for the spares'")
    }

    /// The spares' own failure still goes: a memberwise initializer passed as a value, whose signature the spare
    /// changed.
    func testTheSparesOwnErrorStillBuilds() async throws {
        let project = try app(with: """
            struct Item { var name: String }
            let items = ["a"].map(Item.init(name:))
            """)
        let (status, output) = await liveBuild(project)
        XCTAssertEqual(status, 0, output)
        XCTAssertFalse(gaveUp(project), "the initializers written for the spares didn't build")
    }
}
