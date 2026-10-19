import XCTest
@testable import Lamp

/// A change put into an open app (LiveReload) must leave the app's types the app's: a value made before the change
/// is still of its type after it (a cast, a dictionary key, a view's identity), a conformance the change adds is
/// found, a private static keeps its value, and a class's methods and deinit are the new ones, a generic class's at
/// every type it's used at. Run for real: a small
/// app built as a live build is, with `LampLive` out of the template, loads a change compiled, rewritten
/// (`LiveObject`) and linked as Lamp does it.
final class LiveReloadTests: XCTestCase {
    private var root: URL?
    override func tearDown() { if let root { try? FileManager.default.removeItem(at: root) } }

    private static let before = """
        import Foundation
        import Observation
        @Observable final class Lab { var n = 0; func m() -> String { "m \\(n)" } }
        struct Point: Hashable { var x: Int }
        protocol Named { var name: String { get } }
        enum Ids { private static var next = 100; static func take() -> Int { next += 1; return next } }
        class Counter { var n = 0; func step() -> String { n += 1; return "step \\(n)" }; deinit { print("gone \\(n)") } }
        class Box<T> { var value: T; init(_ v: T) { value = v }; func show() -> String { "box \\(value)" } }
        func describe(_ a: Any) -> String {
            if let p = a as? Point { return "point \\(p.x)" }
            if let n = a as? Named { return "named \\(n.name)" }
            return "other"
        }
        func keyed() -> [AnyHashable: String] { [AnyHashable(Point(x: 1)): "one"] }
        """
    private static let after = """
        import Foundation
        import Observation
        @Observable final class Lab { var n = 0; func m() -> String { "M \\(n)" } }
        struct Point: Hashable { var x: Int }
        protocol Named { var name: String { get } }
        extension Point: Named { var name: String { "p\\(x)" } }
        enum Ids { private static var next = 100; static func take() -> Int { next += 1; return next } }
        class Counter { var n = 0; func step() -> String { n += 10; return "STEP \\(n)" }; deinit { print("GONE \\(n)") } }
        class Box<T> { var value: T; init(_ v: T) { value = v }; func show() -> String { "BOX \\(value)" } }
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
        @main enum Entry { @MainActor static func main() { LampLive.watch(); Main.main() } }
        struct Main {
            static func main() {
                let folder = CommandLine.arguments[1], path = folder + "/live/hot.dylib"
                let items: [Any] = [Point(x: 1)]
                let counter = Counter()
                let keys = keyed()
                let box = Box("s"), lab = Lab()
                print(describe(items[0]), Ids.take(), counter.step(), keys[AnyHashable(Point(x: 1))] ?? "nil", box.show(), lab.m())
                let key = SymmetricKey(data: Data("x".utf8))
                let signature = HMAC<SHA256>.authenticationCode(for: Data("reload\\n\\(path)".utf8), using: key).map { String(format: "%02x", $0) }.joined()
                MainActor.assumeIsolated { LampLive.shared.load(path, signature: signature) }
                print((try? String(contentsOf: URL(fileURLWithPath: folder + "/reloaded.txt"), encoding: .utf8)) ?? "no answer")
                print(describe(items[0]), Ids.take(), counter.step(), keys[AnyHashable(Point(x: 1))] ?? "nil", keyed()[AnyHashable(Point(x: 1))] ?? "nil",
                      box.show(), Box(2).show(), lab.m())
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
        XCTAssertEqual(output[0], "point 1 101 step 1 one box s m 0")
        XCTAssertTrue(output[1].hasPrefix("ok "), "the app didn't take the change: \(output[1])")
        // The value made before is a Point still, with the conformance the change gave it; the static went on
        // counting; the object's method and deinit are the new ones; the key made before finds the new dictionary's;
        // the generic class's method is the new one at the type it was used at before and at a new one; an
        // @Observable class, which the Objective-C runtime only meets when Swift first uses it, takes the change.
        XCTAssertEqual(output[2], "NAMED p1 102 STEP 11 one ONE BOX s BOX 2 M 0")
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
            typealias Side = Int
            private typealias Secret = Int
            protocol Shape { func area() -> Int; var name: String { get set } }
            struct Square: Shape { var side: Side; var name = ""; func area() -> Int { side * side } }
            extension Square: Hashable { typealias Key = String; var key: Key { name }; func grow(_ by: Int = 1) -> Square { self } }
            protocol Boxed {}
            extension Optional: Boxed {}
            protocol Lidded {}
            struct Jar<T>: Lidded { var value: T }
            protocol Flat {}
            struct Tile: Flat { var n: Int; var square: Square }
            enum Parcel<T>: Lidded { case value(T), none }
            enum Coin: Flat { case heads, tails(Int) }
            struct Outer { enum Mood: Shape { case a, b; func area() -> Int { 0 }; var name: String { get { "" } set {} } } }
            """.write(to: sources.appendingPathComponent("Shapes.swift"), atomically: true, encoding: .utf8)
        let layout = await LiveReload.layout(of: sources, in: project, files: ["Shapes.swift"], module: project.exe, macOS: "14.0")
        let shape = layout?.filter { $0.hasPrefix("protocol Shape") } ?? []
        XCTAssertEqual(shape.count, 6, "\(shape)")   // the protocol, area(), name, and name's get, set and _modify
        XCTAssertTrue(shape.contains { $0.hasPrefix("protocol Shape\tarea(): ") }, "\(shape)")
        XCTAssertTrue(shape.contains { $0.hasPrefix("protocol Shape\tname: String set: ") }, "\(shape)")
        // A typealias is printed as itself in what uses it, so it's listed with what it names; what's declared
        // (functions, computed properties, conformances) is listed apart from what the types hold.
        XCTAssertEqual(layout?.filter { $0.hasPrefix("Square\t") }, ["Square\t", "Square\tside: Side", "Square\tname: String"])
        XCTAssertEqual(layout?.filter { $0.hasPrefix(LiveReload.aliasGroup) },
                       [LiveReload.aliasGroup + "\tSide = Int", LiveReload.aliasGroup + "\tShapes.swift:Secret = Int", LiveReload.aliasGroup + "\tSquare.Key = String"])
        let declared = layout?.filter { $0.hasPrefix(LiveReload.declarationGroup) }.map { String($0.dropFirst(LiveReload.declarationGroup.count + 1)) } ?? []
        XCTAssertEqual(Array(declared.prefix(5)), ["Square inherits Shape", "Square.area(): (Square) -> () -> Int", "Square inherits Hashable",
                                                   "Square.key: Square.Key", "Square.grow(_:): (Square) -> (Int) -> Square"], "\(declared)")
        XCTAssertTrue(declared.contains("Optional inherits Boxed") && declared.contains("Outer.Mood inherits Shape"), "\(declared)")
        let retargeted = layout!.map { $0 == LiveReload.aliasGroup + "\tSide = Int" ? LiveReload.aliasGroup + "\tSide = Double" : $0 }
        XCTAssertEqual(LiveReload.layoutProblem(before: layout, after: retargeted).problem, "the typealias Side changed from Int to Double")
        let withoutAliases = LiveReload.layoutProblem(before: layout, after: layout!.filter { !$0.hasPrefix(LiveReload.aliasGroup) })
        XCTAssertNil(withoutAliases.problem)
        // An alias taken away is kept with the open app's layout, like a type, so one brought back is held to it.
        XCTAssertEqual(withoutAliases.layout?.filter { $0.hasPrefix(LiveReload.aliasGroup) }.count, 3)
        XCTAssertEqual(LiveReload.layoutProblem(before: withoutAliases.layout, after: retargeted).problem, "the typealias Side changed from Int to Double")
        // A global holding the enum still counts in the grown-enum check (its owner is empty, not a group).
        XCTAssertFalse(LiveReload.isGroup(String("\tselection: Mood?".prefix { $0 != "\t" })))
        XCTAssertTrue(LiveReload.declarationsChanged(before: layout!, after: layout!.filter { !$0.contains("grow(_:)") }))
        XCTAssertFalse(LiveReload.declarationsChanged(before: layout!, after: layout!))
        // An existential holds a grown enum when it's Any or AnyObject (a value is boxed for it), a protocol the
        // app doesn't declare (the standard wrappers conform to those on their own), or one of the app's that the
        // enum conforms to, through an extension and a protocol that inherits it too, or that an extension of a
        // system type gives, which could wrap the enum; never one of the app's the enum has nothing to do with.
        let conformances = LiveReload.conformances(inLayout: layout! + [LiveReload.declarationGroup + "\tMood inherits Loud", LiveReload.declarationGroup + "\tLoud inherits Named", "protocol Loud\t", "protocol Named\t"])
        XCTAssertEqual(conformances.of["Square"], ["Shape", "Hashable"])
        XCTAssertEqual(conformances.of["Outer.Mood"], ["Shape"])
        XCTAssertNil(LiveReload.existential(in: "any Shape", holding: "Mood", conformances: conformances))
        XCTAssertEqual(LiveReload.existential(in: "any Shape", holding: "Outer.Mood", conformances: conformances), "any Shape")
        XCTAssertEqual(LiveReload.existential(in: "[AnyObject]", holding: "Mood", conformances: conformances), "AnyObject")
        XCTAssertEqual(LiveReload.existential(in: "(any Named)?", holding: "Mood", conformances: conformances), "any Named")
        XCTAssertNil(LiveReload.existential(in: "[String: any Shape & Hashable]", holding: "Mood", conformances: conformances))
        XCTAssertEqual(LiveReload.existential(in: "any Boxed", holding: "Mood", conformances: conformances), "any Boxed")
        // A generic type of the app's conforming to the protocol may wrap the enum; one made of plain values and the
        // app's own types can't.
        XCTAssertEqual(LiveReload.existential(in: "any Lidded", holding: "Mood", conformances: conformances), "any Lidded")
        XCTAssertNil(LiveReload.existential(in: "any Flat", holding: "Mood", conformances: conformances))
        // An enum's cases' payloads count as what it holds: a generic payload may wrap the enum, a plain one can't.
        let noJar = LiveReload.conformances(inLayout: layout!.filter { !$0.hasPrefix("Jar") && !$0.contains("Jar inherits") })
        XCTAssertEqual(LiveReload.existential(in: "any Lidded", holding: "Mood", conformances: noJar), "any Lidded")
        XCTAssertEqual(noJar.fields["Coin"], ["(Coin.Type) -> Coin", "(Coin.Type) -> (Int) -> Coin"])
        XCTAssertEqual(LiveReload.existential(in: "any CustomDebugStringConvertible", holding: "Mood", conformances: conformances), "any CustomDebugStringConvertible")
        XCTAssertEqual(LiveReload.existential(in: "any Hashable", holding: "Mood", conformances: conformances), "any Hashable")
        XCTAssertEqual(LiveReload.existential(in: "[Any]", holding: "Mood", conformances: conformances), "Any")
        XCTAssertEqual(LiveReload.existential(in: "Set<AnyHashable>", holding: "Mood", conformances: conformances), "AnyHashable")
        // An enum that grew is met by code the open app is still running: a timer's closure or an async function
        // switching over it, or printing it; never what a view's body (as the live copy names it) makes again at the
        // next draw.
        try """
            import SwiftUI
            enum Mood { case a, b }
            @Observable final class Model {
                var mood = Mood.a
                func start() { Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [self] _ in switch mood { case .a: break; case .b: break } } }
                func tick() async { print("\\(mood)") }
                func now() -> String { switch mood { case .a: "a"; case .b: "b" } }
            }
            struct V: View {
                @State var model = Model()
                var body: AnyView { AnyView(__lampBody) }
                @ViewBuilder var __lampBody: some View { Button("x") { switch model.mood { case .a: break; case .b: break } } }
            }
            """.write(to: sources.appendingPathComponent("Moods.swift"), atomically: true, encoding: .utf8)
        let dumped = await LiveReload.dump(of: sources, in: project, module: project.exe, macOS: "14.0")
        let dump = try XCTUnwrap(dumped)
        XCTAssertEqual(LiveReload.oldCode(meeting: ["Mood"], inDump: dump),
                       "start() switches over Mood in code that may still be running (a timer, a task, an observer), which doesn't know the new cases")
        XCTAssertNil(LiveReload.oldCode(meeting: ["Other"], inDump: dump))
        let onlyTick = dump.components(separatedBy: "\n").filter { !$0.contains("Timer") }.joined(separator: "\n")
        XCTAssertEqual(LiveReload.oldCode(meeting: ["Mood"], inDump: onlyTick), "tick() prints Mood in code that may still be running (a timer, a task, an observer), which doesn't know the new cases")
        // The record outlives a change: the timer's switch, recorded from the installed sources, still counts once a
        // later change has taken it out of the sources that run.
        XCTAssertFalse(LiveReload.hasOldCodeRecord(project))
        LiveReload.recordOldCode(LiveReload.oldCodeUses(inDump: dump), for: project)
        XCTAssertTrue(LiveReload.hasOldCodeRecord(project))
        LiveReload.recordOldCode(LiveReload.oldCodeUses(inDump: onlyTick), for: project)
        XCTAssertEqual(LiveReload.oldCode(meeting: ["Mood"], uses: LiveReload.oldCodeRecorded(project) + LiveReload.oldCodeUses(inDump: onlyTick))?.hasPrefix("start() switches over Mood"), true)
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
