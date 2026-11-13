import XCTest
@testable import Lamp

/// Lamp's reading of a `.lampignore` is a port of lamp's command line's (`cli/ignore.mjs`): the same folder shared from
/// either must leave out the same files, so both are asked about the same paths and must agree.
final class LampIgnoreTests: XCTestCase {
    func testAgreesWithTheCommandLine() throws {
        let fm = FileManager.default
        let folder = fm.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("lamp-ignore-\(UUID().uuidString)")
        try fm.createDirectory(at: folder.appendingPathComponent("Web"), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: folder) }
        try "# a note\nldraw/\n*.csv\n/APP.md\nWeb/big/**/*.bin\nsave?.dat\n!keep.csv\n".write(to: folder.appendingPathComponent(".lampignore"), atomically: true, encoding: .utf8)
        try "/local.json\n".write(to: folder.appendingPathComponent("Web/.lampignore"), atomically: true, encoding: .utf8)
        let paths = ["Web/ldraw/parts/3001.dat", "Web/ldraw", "Web/data/scores.csv", "keep.csv", "APP.md", "Web/APP.md",
                     "Web/big/a/b/c.bin", "Web/big/c.bin", "Web/big/c.txt", "Web/save1.dat", "Web/save10.dat",
                     "Web/local.json", "Web/sub/local.json", "local.json", "Web/index.html", "Assets/ldraw.png"]
        let ignored = LampIgnore.rules(for: folder)
        let swift = paths.filter(ignored)
        XCTAssertEqual(swift, ["Web/ldraw/parts/3001.dat", "Web/data/scores.csv", "keep.csv", "APP.md", "Web/big/a/b/c.bin",
                               "Web/big/c.bin", "Web/save1.dat", "Web/local.json"])

        // The command line's own answer, when there's a Node to ask.
        guard let node = ToolLocator.path(named: "node") else { return }
        let ignore = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("cli/ignore.mjs")
        let script = """
        const { ignoredFor } = await import(process.argv[1]);
        const app = ignoredFor(process.argv[2] + "/Web", process.argv[2]), top = ignoredFor(process.argv[2]);
        const paths = JSON.parse(process.argv[3]);
        console.log(JSON.stringify(paths.filter((p) => p.startsWith("Web/") ? app(p.slice(4)) : top(p))));
        """
        let json = String(data: try JSONSerialization.data(withJSONObject: paths), encoding: .utf8)!
        let run = TestShell.run(node, ["--input-type=module", "-e", script, ignore.path, folder.path, json], mergeErrors: false)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: Data(run.output.utf8)) as? [String], swift)
    }
}
