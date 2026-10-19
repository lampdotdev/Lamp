import XCTest
@testable import Lamp

/// A change put into an open app (LiveReload) must leave the app's types the app's: a value made before the change
/// is still of its type after it (a cast, a dictionary key, a view's identity), a conformance the change adds is
/// found, a private static keeps its value, and a class's methods and deinit are the new ones. Run for real: a small
/// app built as a live build is, with `LampLive` out of the template, loads a change compiled, rewritten
/// (`LiveObject`) and linked as Lamp does it.
final class LiveReloadTests: XCTestCase {
    private var root: URL?
    override func tearDown() { if let root { try? FileManager.default.removeItem(at: root) } }

    private static let before = """
        import Foundation
        struct Point: Hashable { var x: Int }
        protocol Named { var name: String { get } }
        enum Ids { private static var next = 100; static func take() -> Int { next += 1; return next } }
        class Counter { var n = 0; func step() -> String { n += 1; return "step \\(n)" }; deinit { print("gone \\(n)") } }
        func describe(_ a: Any) -> String {
            if let p = a as? Point { return "point \\(p.x)" }
            if let n = a as? Named { return "named \\(n.name)" }
            return "other"
        }
        func keyed() -> [AnyHashable: String] { [AnyHashable(Point(x: 1)): "one"] }
        """
    private static let after = """
        import Foundation
        struct Point: Hashable { var x: Int }
        protocol Named { var name: String { get } }
        extension Point: Named { var name: String { "p\\(x)" } }
        enum Ids { private static var next = 100; static func take() -> Int { next += 1; return next } }
        class Counter { var n = 0; func step() -> String { n += 10; return "STEP \\(n)" }; deinit { print("GONE \\(n)") } }
        func describe(_ a: Any) -> String {
            if let n = a as? Named { return "NAMED \\(n.name)" }
            if let p = a as? Point { return "POINT \\(p.x)" }
            return "OTHER"
        }
        func keyed() -> [AnyHashable: String] { [AnyHashable(Point(x: 1)): "ONE"] }
        """
    /// The app: what it holds before the change, and what it sees after.
    private static let main = """
        import Foundation
        import CryptoKit
        @main struct Main {
            static func main() {
                let folder = CommandLine.arguments[1], path = folder + "/live/hot.dylib"
                let items: [Any] = [Point(x: 1)]
                let counter = Counter()
                let keys = keyed()
                print(describe(items[0]), Ids.take(), counter.step(), keys[AnyHashable(Point(x: 1))] ?? "nil")
                let key = SymmetricKey(data: Data("x".utf8))
                let signature = HMAC<SHA256>.authenticationCode(for: Data("reload\\n\\(path)".utf8), using: key).map { String(format: "%02x", $0) }.joined()
                MainActor.assumeIsolated { LampLive.shared.load(path, signature: signature) }
                print((try? String(contentsOf: URL(fileURLWithPath: folder + "/reloaded.txt"), encoding: .utf8)) ?? "no answer")
                print(describe(items[0]), Ids.take(), counter.step(), keys[AnyHashable(Point(x: 1))] ?? "nil", keyed()[AnyHashable(Point(x: 1))] ?? "nil")
                _ = Counter()
            }
        }
        """

    func testAChangeKeepsTheAppsTypesAndState() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("lamp-live-\(UUID().uuidString)")
        self.root = root
        let live = root.appendingPathComponent("live")
        try fm.createDirectory(at: live, withIntermediateDirectories: true)
        try Self.before.write(to: live.appendingPathComponent("Model.swift"), atomically: true, encoding: .utf8)
        try Self.main.write(to: live.appendingPathComponent("Main.swift"), atomically: true, encoding: .utf8)
        try Self.lampLive(folder: root).write(to: live.appendingPathComponent("LampLive.swift"), atomically: true, encoding: .utf8)
        let sdk = try run("/usr/bin/xcrun", ["--show-sdk-path"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let plugins = try run("/usr/bin/xcrun", ["-f", "swiftc"]).trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/bin/swiftc", with: "/lib/swift/host/plugins")
        let common = ["-module-name", "App", "-parse-as-library", "-Onone", "-enable-testing", "-D", "LAMP_LIVE", "-target", "arm64-apple-macosx14.0", "-sdk", sdk]
        let files = ["Model.swift", "Main.swift", "LampLive.swift"].map { live.appendingPathComponent($0).path }
        _ = try run("/usr/bin/xcrun", ["swiftc"] + common + files + ["-Xlinker", "-interposable", "-o", root.appendingPathComponent("app").path])
        // The change, compiled as Lamp compiles it: the changed file as the primary, the rest for context.
        try Self.after.write(to: live.appendingPathComponent("Model.swift"), atomically: true, encoding: .utf8)
        let object = live.appendingPathComponent("Model.o").path
        _ = try run("/usr/bin/xcrun", ["swiftc", "-frontend", "-c", "-primary-file", files[0], files[1], files[2]] + common
                    + ["-plugin-path", plugins, "-o", object])
        var matched = Set<String>()
        XCTAssertNil(LiveObject.rewrite(object, matched: &matched))
        let library = live.appendingPathComponent("hot.dylib").path
        _ = try run("/usr/bin/xcrun", ["swiftc", "-emit-library", object, "-o", library, "-target", "arm64-apple-macosx14.0", "-sdk", sdk,
                                       "-Xlinker", "-undefined", "-Xlinker", "dynamic_lookup", "-Xlinker", "-interposable",
                                       "-Xlinker", "-weak_reference_mismatches", "-Xlinker", "weak"])
        _ = try run("/usr/bin/codesign", ["--force", "-s", "-", library])
        let output = try run(root.appendingPathComponent("app").path, [root.path]).components(separatedBy: "\n")
        XCTAssertEqual(output[0], "point 1 101 step 1 one")
        XCTAssertTrue(output[1].hasPrefix("ok "), "the app didn't take the change: \(output[1])")
        // The value made before is a Point still, with the conformance the change gave it; the static went on
        // counting; the object's method and deinit are the new ones; the key made before finds the new dictionary's.
        XCTAssertEqual(output[2], "NAMED p1 102 STEP 11 one ONE")
        XCTAssertEqual(output[3], "GONE 0")
    }

    /// Lamp's own compile of a change: the library comes out with the types renamed as copies and asked for by
    /// their names, and a protocol's requirements are part of the layout a change is held to.
    @MainActor func testAChangeIsCompiledAgainstTheAppsTypes() async throws {
        let fm = FileManager.default
        let root = fm.homeDirectoryForCurrentUser.appendingPathComponent(".lamp-live-test-\(UUID().uuidString)")
        self.root = root
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let project = try Template.scaffold(name: "Lively", platform: .mac, in: root)
        let sources = LiveReload.sources(project)
        try fm.createDirectory(at: sources.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.copyItem(at: project.dir.appendingPathComponent("Sources"), to: sources)
        try """
            protocol Shape { func area() -> Int; var name: String { get set } }
            struct Square: Shape { var side: Int; var name = ""; func area() -> Int { side * side } }
            """.write(to: sources.appendingPathComponent("Shapes.swift"), atomically: true, encoding: .utf8)
        let layout = await LiveReload.layout(of: sources, in: project, files: ["Shapes.swift"], module: project.exe, macOS: "14.0")
        let shape = layout?.filter { $0.hasPrefix("protocol Shape") } ?? []
        XCTAssertEqual(shape.count, 6, "\(shape)")   // the protocol, area(), name, and name's get, set and _modify
        XCTAssertTrue(shape.contains { $0.hasPrefix("protocol Shape\tarea(): ") }, "\(shape)")
        XCTAssertTrue(shape.contains { $0.hasPrefix("protocol Shape\tname: String set: ") }, "\(shape)")
        let (library, problem) = await LiveReload.compile(project, changed: ["Shapes.swift"])
        XCTAssertNil(problem)
        let symbols = try run("/usr/bin/nm", ["-m", XCTUnwrap(library).path])
        XCTAssertTrue(symbols.contains("_$s6Lively6SquareVMf$lampcopy"), symbols)
        XCTAssertTrue(symbols.contains("(undefined) weak external _$s6Lively6SquareVMf"), symbols)
        XCTAssertTrue(symbols.contains("_$s6Lively5ShapeMp$lampcopy"), symbols)
    }

    /// `LampLive` as the template has it, standing on its own: its folder is the test's, its token "x".
    private static func lampLive(folder: URL) throws -> String {
        let template = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Lamp/Template.swift")
        let text = try String(contentsOf: template, encoding: .utf8)
        let start = try XCTUnwrap(text.range(of: "    @MainActor @Observable final class LampLive {"))
        let end = try XCTUnwrap(text.range(of: "\n    }\n", range: start.upperBound..<text.endIndex))
        // What an installed app reads from its Info.plist, given here.
        let install = "enum LampInstall { static let token = \"x\", note = \"t\" }\n"
        return "import Foundation\nimport CryptoKit\nimport MachO\nimport Observation\n" + install + text[start.lowerBound..<end.upperBound]
            .replacingOccurrences(of: "LampInstall.app + \"/.lamp/live/\"", with: "\"\(folder.path)/live/\"")
            .replacingOccurrences(of: "LampRuntime.folder.appendingPathComponent(\"reloaded.txt\")", with: "URL(fileURLWithPath: \"\(folder.path)/reloaded.txt\")")
            .replacingOccurrences(of: "private func load(", with: "func load(")
    }

    private func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else { throw NSError(domain: "LiveReloadTests", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: output]) }
        return output.split(separator: "\n").filter { !$0.hasPrefix("objc[") }.joined(separator: "\n")
    }
}
