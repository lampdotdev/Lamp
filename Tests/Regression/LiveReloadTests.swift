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
        struct Q: Comparable { var v: Int; static func < (a: Q, b: Q) -> Bool { a.v < b.v } }
        func boxed(_ a: Any) -> Bool { if let c = a as? any Comparable { return above(c) }; return false }
        func above<T: Comparable>(_ x: T) -> Bool { x > x }
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
        final class Coord: NSObject { @objc func a() -> String { "a" } }
        extension Coord { @objc func same() -> String { "same" } }
        """
    /// A file the change doesn't compile: what its extension adds from Objective-C stays with the class.
    private static let ext = """
        import Foundation
        extension Coord { @objc func other() -> String { "other" } }
        """
    private static let after = """
        import Foundation
        import Observation
        @Observable final class Lab { var n = 0; func m() -> String { "M \\(n)" } }
        struct Q: Comparable { var v: Int; static func < (a: Q, b: Q) -> Bool { a.v < b.v }; static func > (a: Q, b: Q) -> Bool { true } }
        func boxed(_ a: Any) -> Bool { if let c = a as? any Comparable { return above(c) }; return false }
        func above<T: Comparable>(_ x: T) -> Bool { x > x }
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
        final class Coord: NSObject { @objc func a() -> String { "A" } }
        extension Coord: NSCacheDelegate { @objc func same() -> String { "SAME" } }
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
                let box = Box("s"), lab = Lab(), coord = Coord()
                // What the class answers to from Objective-C: its own method, its file's extension's, another file's;
                // and whether it has taken on a protocol an extension adopts (the system's, which the change
                // names by its own copy).
                func answers() -> String { ["a", "same", "other"].map { (coord.perform(NSSelectorFromString($0))?.takeUnretainedValue() as? String) ?? "nil" }.joined(separator: " ") + " \\(coord is NSCacheDelegate)" }
                print(describe(items[0]), Ids.take(), counter.step(), keys[AnyHashable(Point(x: 1))] ?? "nil", box.show(), lab.m(), boxed(Q(v: 1)), answers())
                let key = SymmetricKey(data: Data("x".utf8))
                let signature = HMAC<SHA256>.authenticationCode(for: Data("reload\\n\\(path)".utf8), using: key).map { String(format: "%02x", $0) }.joined()
                MainActor.assumeIsolated { LampLive.shared.load(path, signature: signature) }
                print((try? String(contentsOf: URL(fileURLWithPath: folder + "/reloaded.txt"), encoding: .utf8)) ?? "no answer")
                print(describe(items[0]), Ids.take(), counter.step(), keys[AnyHashable(Point(x: 1))] ?? "nil", keyed()[AnyHashable(Point(x: 1))] ?? "nil",
                      box.show(), Box(2).show(), lab.m(), boxed(Q(v: 1)), answers())
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
        try Self.ext.write(to: live.appendingPathComponent("Ext.swift"), atomically: true, encoding: .utf8)
        try Self.main.write(to: live.appendingPathComponent("Main.swift"), atomically: true, encoding: .utf8)
        try Self.lampLive(folder: root).write(to: live.appendingPathComponent("LampLive.swift"), atomically: true, encoding: .utf8)
        let sdk = try run("/usr/bin/xcrun", ["--show-sdk-path"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let plugins = try run("/usr/bin/xcrun", ["-f", "swiftc"]).trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/bin/swiftc", with: "/lib/swift/host/plugins")
        let common = ["-module-name", "App", "-parse-as-library", "-Onone", "-enable-testing", "-D", "LAMP_LIVE", "-target", "arm64-apple-macosx14.0", "-sdk", sdk]
        let files = ["Model.swift", "Ext.swift", "Main.swift", "LampLive.swift"].map { live.appendingPathComponent($0).path }
        _ = try run("/usr/bin/xcrun", ["swiftc"] + common + files + ["-Xlinker", "-interposable", "-o", root.appendingPathComponent("app").path])
        // The change, compiled as Lamp compiles it: the changed file as the primary, the rest for context.
        try Self.after.write(to: live.appendingPathComponent("Model.swift"), atomically: true, encoding: .utf8)
        let object = live.appendingPathComponent("Model.o").path
        _ = try run("/usr/bin/xcrun", ["swiftc", "-frontend", "-c", "-primary-file", files[0]] + Array(files[1...]) + common
                    + ["-plugin-path", plugins, "-o", object])
        var matched = Set<String>()
        XCTAssertNil(LiveObject.rewrite(object, matched: &matched))
        let library = live.appendingPathComponent("hot.dylib").path
        _ = try run("/usr/bin/xcrun", ["swiftc", "-emit-library", object, "-o", library, "-target", "arm64-apple-macosx14.0", "-sdk", sdk,
                                       "-Xlinker", "-undefined", "-Xlinker", "dynamic_lookup", "-Xlinker", "-interposable",
                                       "-Xlinker", "-weak_reference_mismatches", "-Xlinker", "weak"])
        _ = try run("/usr/bin/codesign", ["--force", "-s", "-", library])
        let output = try run(root.appendingPathComponent("app").path, [root.path]).components(separatedBy: "\n")
        XCTAssertEqual(output[0], "point 1 101 step 1 one box s m 0 false a same other false")
        XCTAssertTrue(output[1].hasPrefix("ok "), "the app didn't take the change: \(output[1])")
        // The value made before is a Point still, with the conformance the change gave it; the static went on
        // counting; the object's method and deinit are the new ones; the key made before finds the new dictionary's;
        // the generic class's method is the new one at the type it was used at before and at a new one; an
        // @Observable class, which the Objective-C runtime only meets when Swift first uses it, takes the change; a
        // Comparable reached only through a cast, whose witness table the runtime made before the change, answers
        // with the `>` the change gave it in place of the protocol's default.
        XCTAssertEqual(output[2], "NAMED p1 102 STEP 11 one ONE BOX s BOX 2 M 0 true A SAME other true")
        XCTAssertEqual(output[3], "GONE 0")
    }

    /// Lamp's own compile of a change: the library comes out with the types renamed as copies and asked for by
    /// their names, and a protocol's requirements are part of the layout a change is held to.
    @MainActor func testAChangeIsCompiledAgainstTheAppsTypes() async throws {
        let fm = FileManager.default
        // Under a folder with a space in its name, as the apps folder has: a declaration's place carries its path.
        let root = fm.homeDirectoryForCurrentUser.appendingPathComponent(".lamp live test-\(UUID().uuidString)")
        self.root = root
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let project = try Template.scaffold(name: "Lively", platform: .mac, in: root)
        let sources = LiveReload.sources(project)
        try fm.createDirectory(at: sources.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.copyItem(at: project.dir.appendingPathComponent("Sources"), to: sources)
        try """
            import Foundation
            import Observation
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
            protocol Counted { func count() -> Int }
            final class Item: Identifiable, Counted { var name = ""; func count() -> Int { 1 } }
            protocol Drawn { associatedtype Mark; func mark() -> Mark }
            struct Round: Shape { var r: Int; var name = ""; func area() -> Int { r } }
            struct Styled: Drawn { func mark() -> some Shape { Square(side: 1, name: "s") }; func n() -> some Numeric { 1 }; func t() -> some Equatable { "a" }; func p() -> some Equatable { n() }; func l() -> some Equatable { func local() -> some Equatable { 0 }; return String() } }
            struct Outer { enum Mood: Shape { case a, b; func area() -> Int { 0 }; var name: String { get { "" } set {} } } }
            struct Pick { var mood: Outer.Mood; var n: Int }
            enum Other { typealias Pick = Int; final class Picky {} }
            typealias Feeling = Outer.Mood
            struct Picky { var mood: Feeling; var n: Int }
            typealias Choice = Picky
            struct Picked { var mood: Outer.Mood; var __lampSpare_Picked = 0 }
            struct Stack<Feeling> { var top: Feeling?; enum Inner { case x } }
            enum Space { struct Wrapper { var mood: Outer.Mood } }
            @Observable final class Lab { var dirty = false { didSet {} } }
            final class Holder { var byName: [String: Outer.Mood] = [:]; var byMood: [Outer.Mood: Int] = [:]; var list: [Outer.Mood] = []; var picked: Picked? = nil; var stack = Stack<Int>(top: nil) }
            private struct Hidden { var v = 1 }
            final class Tagged: NSObject { @objc(oldName) func a() {}; @objc func b() {}; override var description: String { "t" }; @objc(oldStatic) static var value = 1 }
            indirect enum Tree { case leaf, node(Tree) }
            @objc enum Level: Int { case low }
            class Thing {}
            final class Owner { weak var item: Item? = nil; unowned let thing: Thing; init(thing: Thing) { self.thing = thing } }
            struct Dated { var at: Int; var note = ""; init() { at = 1; self.note = "n" }; let fixed = 2 }
            final class Doc { var title = ""; init() {}; convenience init(named: String) { self.init(); title = named } }
            private enum Tone: CaseIterable { case a, b; typealias Pair = (Tone, Tone) }
            enum Tones { static let count = Tone.allCases.count }
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
                       [LiveReload.aliasGroup + "\tSide = Int", LiveReload.aliasGroup + "\tShapes.swift:Secret = Int", LiveReload.aliasGroup + "\tSquare.Key = String",
                        LiveReload.aliasGroup + "\tItem.ID = ObjectIdentifier", LiveReload.aliasGroup + "\tOther.Pick = Int",
                        LiveReload.aliasGroup + "\tFeeling = Outer.Mood", LiveReload.aliasGroup + "\tChoice = Picky", LiveReload.aliasGroup + "\tLevel.RawValue = Int",
                        LiveReload.aliasGroup + "\tTone@Shapes.swift.Pair = (Tone, Tone)", LiveReload.aliasGroup + "\tTone@Shapes.swift.AllCases = [Tone]"])
        let declared = layout?.filter { $0.hasPrefix(LiveReload.declarationGroup) }.map { String($0.dropFirst(LiveReload.declarationGroup.count + 1)) } ?? []
        XCTAssertEqual(Array(declared.prefix(5)), ["Square inherits Shape", "Square.area(): (Square) -> () -> Int", "Square inherits Hashable",
                                                   "Square.key: Square.Key", "Square.grow(_:): (Square) -> (Int) -> Square"], "\(declared)")
        XCTAssertTrue(declared.contains("Optional inherits Boxed") && declared.contains("Outer.Mood inherits Shape"), "\(declared)")
        // A type's shape: its kind, an enum's @objc and indirect, a class's superclass (the first name it inherits
        // when that's a class, the app's own or a system one), a protocol's requirement signature; and a stored
        // reference's weak or unowned, in its field.
        let shapes = layout!.filter { $0.hasPrefix(LiveReload.shapeGroup) }.map { String($0.dropFirst(LiveReload.shapeGroup.count + 1)) }
        for entry in ["Square\tstruct", "Item\tclass", "Tagged\tclass : NSObject", "Tree\tenum indirect", "Level\tenum @objc", "Thing\tclass", "Outer.Mood\tenum", "Other.Picky\tclass", "Jar\tstruct generic<T>", "Parcel\tenum generic<T>", "Stack.Inner\tenum generic"] {
            XCTAssertTrue(shapes.contains(entry), "\(entry) in \(shapes)")
        }
        XCTAssertTrue(shapes.contains { $0.hasPrefix("protocol Shape\t<Self where ") }, "\(shapes)")
        XCTAssertEqual(layout!.filter { $0.hasPrefix("Owner\t") }, ["Owner\t", "Owner\tweak item: Item?", "Owner\tunowned thing: Thing"])
        XCTAssertNil(LiveReload.layoutProblem(before: layout!.filter { !$0.hasPrefix(LiveReload.shapeGroup) }, after: layout).problem)
        XCTAssertEqual(LiveReload.readable("Row changed what it holds (no longer Row.____lampState_Row: LazyState<LampStateBox>), Shop.Item.__lampSpare_Item_0, __lampBinding_name, __lampBody"),
                       "Row changed what it holds (no longer Lamp's state box for Row), Lamp's spare place in Item, $name, its body")
        let retargeted = layout!.map { $0 == LiveReload.aliasGroup + "\tSide = Int" ? LiveReload.aliasGroup + "\tSide = Double" : $0 }
        XCTAssertEqual(LiveReload.layoutProblem(before: layout, after: retargeted).problem, "the typealias Side changed from Int to Double")
        let withoutAliases = LiveReload.layoutProblem(before: layout, after: layout!.filter { !$0.hasPrefix(LiveReload.aliasGroup) })
        XCTAssertNil(withoutAliases.problem)
        // An alias taken away is kept with the open app's layout, like a type, so one brought back is held to it.
        XCTAssertEqual(withoutAliases.layout?.filter { $0.hasPrefix(LiveReload.aliasGroup) }.count, 10)
        XCTAssertEqual(LiveReload.layoutProblem(before: withoutAliases.layout, after: retargeted).problem, "the typealias Side changed from Int to Double")
        // A global holding the enum still counts in the grown-enum check (its owner is empty, not a group).
        XCTAssertFalse(LiveReload.isGroup(String("\tselection: Mood?".prefix { $0 != "\t" })))
        // A dictionary of the enum is a plain holder, however the compiler spaces its key.
        let heldMood = await LiveReload.enumsHeld(project, grown: ["Outer.Mood"])
        XCTAssertNil(heldMood, heldMood ?? "")
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
        // An associated type the compiler inferred is a typealias of the type's, held like one written out; a
        // member returning `some …` is held to the type it builds, by its name when the compiler prints it and by
        // what its body names when that is opaque too.
        XCTAssertTrue(layout!.contains(LiveReload.aliasGroup + "\tItem.ID = ObjectIdentifier"), "\(layout!.filter { $0.contains("Item") })")
        XCTAssertTrue(layout!.contains(LiveReload.opaqueGroup + "\tStyled.mark(): (Styled) -> () -> some Shape\tSquare"), "\(layout!.filter { $0.hasPrefix(LiveReload.opaqueGroup) })")
        XCTAssertTrue(layout!.contains(LiveReload.opaqueGroup + "\tStyled.n(): (Styled) -> () -> some Numeric\tInt"))
        // A local function's own conversion isn't the member's.
        XCTAssertTrue(layout!.contains(LiveReload.opaqueGroup + "\tStyled.l(): (Styled) -> () -> some Equatable\tString"), "\(layout!.filter { $0.contains("Styled.l") })")
        XCTAssertEqual(layout!.filter { $0.hasPrefix(LiveReload.opaqueGroup + "\tStyled.p(): (Styled) -> () -> some Equatable\t~") }.count, 1)
        XCTAssertTrue(declared.contains("Styled.mark(): (Styled) -> () -> some Shape"), "\(declared)")
        // What a member answers to from Objective-C is declared: a selector renamed or taken away compiles every file.
        for entry in ["Tagged.a(): (Tagged) -> () -> () @objc(oldName)", "Tagged.b(): (Tagged) -> () -> () @objc", "Tagged.description: String @objc(description)", "Tagged.value: Int @objc(oldStatic)"] {
            XCTAssertTrue(declared.contains(entry), "\(declared.filter { $0.hasPrefix("Tagged") })")
        }
        // The same sources read from another folder (the copy the app runs) give the same digest: a declaration
        // is named with where it is, which isn't part of what it builds.
        let elsewhere = sources.deletingLastPathComponent().appendingPathComponent("running")
        try? fm.removeItem(at: elsewhere)
        try fm.copyItem(at: sources, to: elsewhere)
        let same = await LiveReload.layout(of: elsewhere, in: project, files: ["Shapes.swift"], module: project.exe, macOS: "14.0")
        XCTAssertEqual(same?.filter { $0.hasPrefix(LiveReload.opaqueGroup) }, layout!.filter { $0.hasPrefix(LiveReload.opaqueGroup) })
        func layoutWith(_ edits: [(String, String)]) async throws -> [String] {
            var text = try String(contentsOf: sources.appendingPathComponent("Shapes.swift"), encoding: .utf8)
            for (from, to) in edits { text = text.replacingOccurrences(of: from, with: to) }
            try text.write(to: sources.appendingPathComponent("Shapes.swift"), atomically: true, encoding: .utf8)
            let changed = await LiveReload.layout(of: sources, in: project, files: ["Shapes.swift"], module: project.exe, macOS: "14.0")
            return try XCTUnwrap(changed)
        }
        // A literal, or a call that gives the same type back (`"a".uppercased()`), changes nothing; a literal that
        // makes another type (`1.5`) does, as does another call where the type is opaque too.
        let sameType = try await layoutWith([("Square(side: 1, name: \"s\")", "Square(side: 2, name: \"t\")"), ("{ \"a\" }", "{ \"a\".uppercased() }")])
        XCTAssertNil(LiveReload.layoutProblem(before: layout, after: sameType).problem)
        let otherLiteral = try await layoutWith([("some Numeric { 1 }", "some Numeric { 1.5 }")])
        XCTAssertEqual(LiveReload.layoutProblem(before: layout, after: otherLiteral).problem, "Styled.n(): (Styled) -> () -> some Numeric returns a Double now, where the open app's returned a Int")
        let otherCall = try await layoutWith([("some Numeric { 1.5 }", "some Numeric { 1 }"), ("some Equatable { n() }", "some Equatable { t() }")])
        XCTAssertEqual(LiveReload.layoutProblem(before: layout, after: otherCall).problem, "Styled.p(): (Styled) -> () -> some Equatable returns another kind of value now (some …), which what the open app made can't take")
        let otherType = try await layoutWith([("some Equatable { t() }", "some Equatable { n() }"), ("Square(side: 2, name: \"t\")", "Round(r: 1)")])
        XCTAssertEqual(LiveReload.layoutProblem(before: layout, after: otherType).problem, "Styled.mark(): (Styled) -> () -> some Shape returns a Round now, where the open app's returned a Square")
        // One taken away is kept with the layout on its own, so one brought back is held to what it built.
        let without = try await layoutWith([("struct Styled: Drawn { func mark() -> some Shape { Round(r: 1) }; ", "struct Unstyled { "), ("some Equatable { \"a\".uppercased() }", "some Equatable { \"a\" }")])
        let retained = LiveReload.layoutProblem(before: layout, after: without)
        XCTAssertNil(retained.problem)
        XCTAssertEqual(LiveReload.layoutProblem(before: retained.layout, after: otherType).problem?.hasPrefix("Styled.mark()"), true)
        let otherID = try await layoutWith([("Round(r: 1)", "Square(side: 1, name: \"s\")"),
                                            ("final class Item: Identifiable, Counted { var name = \"\"; func count() -> Int { 1 } }", "final class Item: Identifiable, Counted { var name = \"\"; func count() -> Int { 1 }; var id: String { name } }")])
        XCTAssertEqual(LiveReload.layoutProblem(before: layout, after: otherID).problem, "the typealias Item.ID changed from ObjectIdentifier to String")
        let renamedSelector = try await layoutWith([("var id: String { name } }", "}"), ("@objc(oldName)", "@objc(newName)")])
        XCTAssertNil(LiveReload.layoutProblem(before: layout, after: renamedSelector).problem)
        XCTAssertTrue(LiveReload.declarationsChanged(before: layout!, after: renamedSelector))
        let renamedStatic = try await layoutWith([("@objc(newName)", "@objc(oldName)"), ("@objc(oldStatic)", "@objc(newStatic)")])
        XCTAssertNil(LiveReload.layoutProblem(before: layout, after: renamedStatic).problem)
        XCTAssertTrue(LiveReload.declarationsChanged(before: layout!, after: renamedStatic))
        // A shape that changed reopens the app: a struct become a class, a class given a superclass, a protocol made
        // class-bound; a reference held weakly no longer is a change to the field.
        let classified = try await layoutWith([("@objc(newStatic)", "@objc(oldStatic)"), ("struct Tile: Flat { var n: Int; var square: Square }", "final class Tile: Flat { var n = 1; var square = Square(side: 1) }")])
        XCTAssertEqual(LiveReload.layoutProblem(before: layout, after: classified).problem, "Tile is a class now, where the open app's is a struct")
        let rooted = try await layoutWith([("final class Tile: Flat { var n = 1; var square = Square(side: 1) }", "struct Tile: Flat { var n: Int; var square: Square }"), ("class Thing {}", "class Thing: NSObject {}")])
        XCTAssertEqual(LiveReload.layoutProblem(before: layout, after: rooted).problem, "Thing is a class under NSObject now, where the open app's is a class")
        let bound = try await layoutWith([("class Thing: NSObject {}", "class Thing {}"), ("protocol Counted {", "protocol Counted: AnyObject {")])
        XCTAssertEqual(LiveReload.layoutProblem(before: layout, after: bound).problem?.hasPrefix("the protocol Counted's requirements changed in kind"), true)
        let strongly = try await layoutWith([("protocol Counted: AnyObject {", "protocol Counted {"), ("weak var item: Item?", "var item: Item?")])
        XCTAssertEqual(LiveReload.layoutProblem(before: layout, after: strongly).problem, "Owner changed what it holds (Owner.item: Item?)")
        // Observers added to a stored property change no layout, but turn every write into a call: declared.
        let observed = try await layoutWith([("var item: Item?", "weak var item: Item?"), ("struct Tile: Flat { var n: Int;", "struct Tile: Flat { var n: Int { didSet {} };")])
        XCTAssertNil(LiveReload.layoutProblem(before: layout, after: observed).problem)
        XCTAssertTrue(LiveReload.declarationsChanged(before: layout!, after: observed))
        XCTAssertTrue(observed.contains(LiveReload.declarationGroup + "\tTile.n: Int observed"), "\(observed.filter { $0.contains("Tile") })")
        // A SwiftData model's file is held whole: its accessors find its data by key paths the open app made.
        try """
            import SwiftData
            @Model final class Note { var title = ""; init() {} }
            func noteHelper() -> Int { 1 }
            """.write(to: sources.appendingPathComponent("Notes.swift"), atomically: true, encoding: .utf8)
        // What's read at launch is part of the whole analysis, not of a few files' layout.
        let analysed = await LiveReload.analysis(of: sources, in: project, module: project.exe, macOS: "14.0")
        let notes = try XCTUnwrap(analysed?.layout)
        // An @Observable property's didSet is moved by the macro to its storage: still an observed property.
        XCTAssertEqual(analysed?.declarations.variables["Lab\tdirty"]?.special, true)
        // A property set in an initializer the type writes, however it's spelt, and where each type is declared.
        XCTAssertEqual(analysed?.declarations.assigned.filter { $0.hasPrefix("Dated") }.sorted(), ["Dated\tat", "Dated\tnote"])
        // Not what a convenience initializer sets after `self.init`, when a computed property can be set; a let is known.
        XCTAssertEqual(analysed?.declarations.assigned.filter { $0.hasPrefix("Doc") }, [])
        XCTAssertEqual(analysed?.declarations.lets.contains("Dated\tfixed"), true)
        XCTAssertEqual(analysed?.declarations.privateTypes.contains("Hidden@Shapes.swift"), true)
        XCTAssertNotNil(analysed?.declarations.types["Hidden@Shapes.swift"])
        // A constant made from a private enum is found by the enum's bare name, and the bared layout names every
        // type bare, an alias's owner included.
        XCTAssertEqual(LiveSlots.constants(naming: ["Tone@Shapes.swift"], in: try XCTUnwrap(analysed?.declarations)), ["Tones\tcount"])
        XCTAssertTrue(LiveReload.bared(layout!).contains(LiveReload.aliasGroup + "\tTone.Pair = (Tone, Tone)"), "\(LiveReload.bared(layout!).filter { $0.contains("Tone") })")
        XCTAssertEqual(analysed?.declarations.types["Dated"]?.start.file.hasSuffix("Shapes.swift"), true)
        XCTAssertTrue(notes.contains { $0.hasPrefix("\u{1}launch\tmodel Note@Notes.swift: ") }, "\(notes.filter { $0.hasPrefix("\u{1}launch") })")
        XCTAssertEqual(LiveReload.modelFiles(inLayout: notes).map { "\($0.name) \($0.file)" }, ["Note Notes.swift"])
        try """
            import SwiftData
            @Model final class Note { var title = ""; init() {} }
            func noteHelper() -> Int { 2 }
            """.write(to: sources.appendingPathComponent("Notes.swift"), atomically: true, encoding: .utf8)
        let notesChangedLayout = await LiveReload.analysis(of: sources, in: project, module: project.exe, macOS: "14.0")?.layout
        let notesChanged = try XCTUnwrap(notesChangedLayout)
        XCTAssertEqual(LiveReload.layoutProblem(before: notes, after: notesChanged).problem, "the file of the SwiftData model Note changed, and its data is found by key paths the open app made")
        // The model keeps its data as any value, which would hide a grown enum from the checks below.
        try FileManager.default.removeItem(at: sources.appendingPathComponent("Notes.swift"))
        // A private type is keyed with its file, so two files' private types of one name are two types; it's named
        // bare where the code names it, and known by its file for a move.
        XCTAssertEqual(layout!.filter { $0.hasPrefix("Hidden") }, ["Hidden@Shapes.swift\t", "Hidden@Shapes.swift\tv: Int"])
        XCTAssertEqual(LiveReload.bare("Outer@A.swift.Hidden@A.swift"), "Outer.Hidden")
        // Two files' private types of one name are judged each by its own key: a class in one doesn't speak for a
        // struct in the other, which still carries the enum.
        let twins = ["Twin@A.swift\t", "Twin@A.swift\tmood: Outer.Mood", LiveReload.shapeGroup + "\tTwin@A.swift\tstruct",
                     "Twin@B.swift\t", LiveReload.shapeGroup + "\tTwin@B.swift\tclass", "Keep\t", "Keep\tkept: Twin?", LiveReload.shapeGroup + "\tKeep\tclass"]
        XCTAssertEqual(LiveReload.holders(of: ["Outer.Mood"], inLayout: twins), ["Twin"])
        XCTAssertEqual(LiveReload.enumsHeld(grown: ["Outer.Mood"], held: twins, spares: [:]), "Keep holds Twin, which carries Outer.Mood, as Twin?, which a new case would change")
        XCTAssertEqual(LiveReload.readable("Hidden@Shapes.swift changed what it holds"), "Hidden in Shapes.swift changed what it holds")
        XCTAssertTrue(LiveObject.isKept("_$s6Lively6Hidden33_0123456789ABCDEF0123456789ABCDEFLLVMn", as: LiveObject.mangledType("Hidden", module: "Lively", kind: "V")))
        XCTAssertTrue(LiveObject.isKept("_$s6Lively5Outer4MoodOMn", as: LiveObject.mangledType("Outer.Mood", module: "Lively", kind: "O", kinds: ["Outer": "V"])) == false)
        XCTAssertTrue(LiveObject.isKept("_$s6Lively5OuterV4MoodOMn", as: LiveObject.mangledType("Outer.Mood", module: "Lively", kind: "O", kinds: ["Outer": "V"])))
        XCTAssertFalse(LiveObject.isKept("_$s6Lively6HiddenVMn", as: LiveObject.mangledType("Hidde", module: "Lively", kind: "V")))
        // A private type moved to another file is another type to the runtime, whatever its layout.
        XCTAssertTrue(layout!.contains(LiveReload.placeGroup + "\tHidden\tShapes.swift"), "\(layout!.filter { $0.hasPrefix(LiveReload.placeGroup) })")
        _ = try await layoutWith([("private struct Hidden { var v = 1 }\n", "")])
        try "private struct Hidden { var v = 1 }\n".write(to: sources.appendingPathComponent("Hidden.swift"), atomically: true, encoding: .utf8)
        let moved = await LiveReload.layout(of: sources, in: project, files: ["Shapes.swift", "Hidden.swift"], module: project.exe, macOS: "14.0")
        XCTAssertEqual(LiveReload.layoutProblem(before: layout, after: try XCTUnwrap(moved)).problem, "Hidden is private and moved from Shapes.swift to Hidden.swift, which makes it another type for the values the open app holds")
        // Two files each with their own: taking one away moves nothing.
        _ = try await layoutWith([("typealias Side = Int\n", "typealias Side = Int\nprivate struct Hidden { var v = 1 }\n")])
        let both = await LiveReload.layout(of: sources, in: project, files: ["Shapes.swift", "Hidden.swift"], module: project.exe, macOS: "14.0")
        try FileManager.default.removeItem(at: sources.appendingPathComponent("Hidden.swift"))
        let oneLeft = await LiveReload.layout(of: sources, in: project, files: ["Shapes.swift"], module: project.exe, macOS: "14.0")
        XCTAssertEqual(try XCTUnwrap(both).filter { $0.hasPrefix(LiveReload.placeGroup + "\tHidden") }.count, 2)
        XCTAssertNil(LiveReload.layoutProblem(before: both, after: try XCTUnwrap(oneLeft)).problem)
        // A struct carrying the enum lends its optional the enum's numbers; one with a spare of Lamp's doesn't.
        _ = try await layoutWith([("var stack = Stack<Int>(top: nil) }", "var stack = Stack<Int>(top: nil); var pick: Pick? = nil }")])
        let carried = await LiveReload.enumsHeld(project, grown: ["Outer.Mood"])
        XCTAssertEqual(carried, "Holder holds Pick, which carries Outer.Mood, as Pick?, which a new case would change")
        // A carrier through typealiases, held by one: each is written out as what it names, wrappers included.
        _ = try await layoutWith([("var pick: Pick? = nil }", "var choice: Choice? = nil }")])
        let aliased = await LiveReload.enumsHeld(project, grown: ["Outer.Mood"])
        XCTAssertEqual(aliased, "Holder holds Picky, which carries Outer.Mood, as Picky?, which a new case would change")
        _ = try await layoutWith([("typealias Choice = Picky", "typealias Choice = Picky?"), ("var choice: Choice? = nil }", "var choice: Choice = nil }")])
        let wrappedAlias = await LiveReload.enumsHeld(project, grown: ["Outer.Mood"])
        XCTAssertEqual(wrappedAlias, "Holder holds Picky, which carries Outer.Mood, as Picky?, which a new case would change")
        // A class's initializers are in its method table, a final class's too; and finality itself is held.
        let initAdded = try await layoutWith([("typealias Choice = Picky?", "typealias Choice = Picky"), ("var choice: Choice = nil }", "var choice: Choice? = nil }"),
                                              ("final class Item: Identifiable, Counted { var name = \"\"", "final class Item: Identifiable, Counted { var name = \"\"; init(n: String) { name = n }")])
        XCTAssertEqual(LiveReload.layoutProblem(before: layout, after: initAdded).problem, "an initializer of Item was added, taken away or changed, and a class's initializers are in its method table")
        let unfinal = try await layoutWith([("; init(n: String) { name = n }", ""), ("; var choice: Choice? = nil }", " }"), ("final class Holder", "class Holder")])
        XCTAssertEqual(LiveReload.layoutProblem(before: layout, after: unfinal).problem, "Holder is no longer final (something subclasses it), and its methods would go through a table the open app's class doesn't have")
        // An initializer in an extension is a convenience one, in no method table: declared, not held.
        let extensionInit = try await layoutWith([("class Holder", "final class Holder"),
                                                  ("final class Tagged: NSObject {", "extension Item { convenience init(copy: Item) { self.init(); name = copy.name } }\nfinal class Tagged: NSObject {")])
        XCTAssertNil(LiveReload.layoutProblem(before: layout, after: extensionInit).problem)
        XCTAssertTrue(LiveReload.declarationsChanged(before: layout!, after: extensionInit))
        // A type holding the enum, printed, is no reason to reopen: the enum's description is the change's once it's in.
        _ = try await layoutWith([("var stack = Stack<Int>(top: nil) }", "var stack = Stack<Int>(top: nil); func show() -> String { \"\\(Space.Wrapper(mood: .a))\" } }")])
        let printed = await LiveReload.enumsHeld(project, grown: ["Outer.Mood"])
        XCTAssertNil(printed, printed ?? "")
        // What holds the enum by value is changed with it, for the old code that may have one in hand: never a class,
        // whose field keeps its layout.
        XCTAssertEqual(LiveReload.holders(of: ["Outer.Mood"], inLayout: layout!).filter { ["Pick", "Picky", "Picked", "Space.Wrapper", "Holder"].contains($0) }.sorted(), ["Pick", "Picked", "Picky", "Space.Wrapper"])
        // The copy step's scan tells the spares step what no struct may have a spare for: an OptionSet made in an
        // extension (its init(rawValue:) is the memberwise one), and every struct when any file lays memory out by hand.
        let perl = root.appendingPathComponent("live.pl")
        try Template.livePerl.write(to: perl, atomically: true, encoding: .utf8)
        let zones = root.appendingPathComponent("Zones.swift"), plain = root.appendingPathComponent("Plain.swift"), bytes = root.appendingPathComponent("Bytes.swift")
        try "struct Zone { let rawValue: Int }\nextension Zone: OptionSet {}\nstruct Flags: OptionSet { let rawValue: Int }\n".write(to: zones, atomically: true, encoding: .utf8)
        try "struct Plain { var a = 1 }\nfinal class Box { var n = 1 }\n".write(to: plain, atomically: true, encoding: .utf8)
        try "let size = MemoryLayout<Plain>.size\n".write(to: bytes, atomically: true, encoding: .utf8)
        let scanned = try run("/usr/bin/perl", [perl.path, "scan", zones.path, plain.path, bytes.path]).trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(scanned, "-raw -nospare:Zone")
        // Lamp's own files always read raw memory (as the scaffold's LampSupport.swift does): no reason to keep the
        // app's structs from their spares.
        let own = try run("/usr/bin/perl", [perl.path, "scan", "-own=Bytes.swift,LampSupport.swift", zones.path, plain.path, bytes.path, sources.appendingPathComponent("LampSupport.swift").path]).trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertFalse(own.contains("-raw"), own)
        XCTAssertTrue(own.hasSuffix(" -nospare:Zone"), own)
        _ = try run("/usr/bin/perl", [perl.path, "4", scanned, "s", zones.path, plain.path])
        XCTAssertFalse(try String(contentsOf: zones, encoding: .utf8).contains("LampSpare"))
        let rewritten = try String(contentsOf: plain, encoding: .utf8)
        XCTAssertFalse(rewritten.contains("__lampSpare_Plain"), rewritten)
        XCTAssertTrue(rewritten.contains("__lampSpare_Box_0"), rewritten)
        try "struct Plain { var a = 1; struct Sub { var b = 0 }; var sub = Sub() }\n".write(to: plain, atomically: true, encoding: .utf8)
        _ = try run("/usr/bin/perl", [perl.path, "4", "-nospare:Zone", "s", plain.path])
        let spared = try String(contentsOf: plain, encoding: .utf8)
        XCTAssertTrue(spared.contains("var __lampSpare_Plain = LampSpare(nil)"), spared)
        XCTAssertTrue(spared.contains("struct Sub { var __lampSpare_Sub = LampSpare(nil); var b = 0 }"), spared)
        // The memberwise initializers written again beside the spares, from the plain sources, for the structs the
        // live copy gave one: a reference to one as a value (`.map(Item.init)`) then still matches.
        try "struct Item { var name: String; var count = 1 }\nstruct Keyed { let rawValue: Int }\nprivate struct Own { var n: Int }\n".write(to: project.dir.appendingPathComponent("Sources/Items.swift"), atomically: true, encoding: .utf8)
        try "struct Item { var name: String; var count = 1\n    var __lampSpare_Item = LampSpare(nil); }\nstruct Keyed { let rawValue: Int }\nprivate struct Own { var n: Int\n    var __lampSpare_Own = LampSpare(nil); }\n".write(to: sources.appendingPathComponent("Items.swift"), atomically: true, encoding: .utf8)
        let addedMemberwise = await LiveSlots.addMemberwise(project)
        XCTAssertTrue(addedMemberwise)
        XCTAssertEqual(try String(contentsOf: sources.appendingPathComponent(LiveSlots.memberwiseFile), encoding: .utf8),
                       "extension Item { init(name: String, count: Int) { self.init(name: name, count: count, __lampSpare_Item: LampSpare(nil)) } }\n")
        let unchangedMemberwise = await LiveSlots.addMemberwise(project)
        XCTAssertFalse(unchangedMemberwise)
        try FileManager.default.removeItem(at: sources.appendingPathComponent(LiveSlots.memberwiseFile))
        try FileManager.default.removeItem(at: sources.appendingPathComponent("Items.swift"))
        try FileManager.default.removeItem(at: project.dir.appendingPathComponent("Sources/Items.swift"))
        // A class the app's own code writes `final` is the agent's error, not the copy step's; a mention in a comment
        // or a string isn't the app writing it.
        let written = project.dir.appendingPathComponent("Sources").appendingPathComponent("Roots.swift")
        try "/* \" */ let help = \"final class Root\"\n// Example: final class Root\nlet raw = #\"final class Root\"#\nlet nested = \"\\(String(\"final class Root\"))\"\nlet escaped = #\"\\#\"#final class Root\"#\nclass Root {}\n".write(to: written, atomically: true, encoding: .utf8)
        XCTAssertTrue(LiveSlots.brokeFinal("error: inheritance from a final class 'Root'", project: project))
        try "final class Root {}\n".write(to: written, atomically: true, encoding: .utf8)
        XCTAssertFalse(LiveSlots.brokeFinal("error: inheritance from a final class 'Root'", project: project))
        XCTAssertEqual(LiveReload.existential(in: "any CustomDebugStringConvertible", holding: "Mood", conformances: conformances), "any CustomDebugStringConvertible")
        XCTAssertEqual(LiveReload.existential(in: "any Hashable", holding: "Mood", conformances: conformances), "any Hashable")
        XCTAssertEqual(LiveReload.existential(in: "[Any]", holding: "Mood", conformances: conformances), "Any")
        XCTAssertEqual(LiveReload.existential(in: "State<NavigationPath>", holding: "Mood", conformances: conformances), "NavigationPath")
        XCTAssertEqual(LiveReload.existential(in: "NSMutableArray", holding: "Mood", conformances: conformances), "NSMutableArray")
        XCTAssertEqual(LiveReload.existential(in: "Set<AnyHashable>", holding: "Mood", conformances: conformances), "AnyHashable")
        // An enum that grew is met by code the open app is still running: a timer's closure or an async function
        // switching over it, or printing it; never what a view's body (as the live copy names it) makes again at the
        // next draw.
        try """
            import SwiftUI
            enum Mood { case a, b }
            @Observable final class Model {
                var mood = Mood.a
                var handler: () -> Void = {}
                var onTick: (Mood) -> Void = { m in switch m { case .a: break; case .b: break } }
                func start() { Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [self] _ in switch mood { case .a: break; case .b: break } } }
                func tick() async { print("\\(mood)") }
                func now() -> String { switch mood { case .a: "a"; case .b: "b" } }
            }
            struct V: View {
                @State var model = Model()
                var body: AnyView { AnyView(__lampBody) }
                @ViewBuilder var __lampBody: some View { Button("x") { switch model.mood { case .a: break; case .b: break } } }
            }
            struct W: View {
                @State var model = Model()
                var body: AnyView { AnyView(__lampBody) }
                @ViewBuilder var __lampBody: some View {
                    Text("w").onAppear { Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in switch model.mood { case .a: break; case .b: break } } }
                    Text("x").onAppear { model.handler = { switch model.mood { case .a: break; case .b: break } } }
                    row()
                }
                func row() -> some View { Button("r") { switch model.mood { case .a: break; case .b: break } } }
                func slow() async -> some View { await Task.yield(); switch model.mood { case .a: return Text("a"); case .b: return Text("b") } }
            }
            """.write(to: sources.appendingPathComponent("Moods.swift"), atomically: true, encoding: .utf8)
        let dumped = await LiveReload.dump(of: sources, in: project, module: project.exe, macOS: "14.0")
        let dump = try XCTUnwrap(dumped)
        XCTAssertEqual(LiveReload.oldCode(meeting: ["Mood"], inDump: dump),
                       "Model switches over Mood in code that may still be running (a timer, a task, an observer), which doesn't know the new cases")
        XCTAssertNil(LiveReload.oldCode(meeting: ["Other"], inDump: dump))
        // A closure a body hands to Foundation (a Timer's, in onAppear) is kept by it, unlike a Button's action.
        // A closure set into a property or given as a property's value is kept too, inside a body or not; what a
        // view helper returning `some View` hands SwiftUI (a Button's action) is made again at the next draw.
        let uses = LiveReload.oldCodeUses(inDump: dump)
        // A switch and an interpolation are named as such; any value of the enum's type in running code is a use.
        XCTAssertTrue(Set(uses).isSuperset(of: ["Mood\tModel\tswitches over", "Mood\tW\tswitches over", "Mood\tslow()\tswitches over", "Mood\tstart()\tswitches over", "Mood\ttick()\tprints", "Mood\tstart()\tuses"]), "\(uses.filter { $0.hasPrefix("Mood\t") })")
        let onlyTick = dump.components(separatedBy: "\n").filter { !$0.contains("Timer") }.joined(separator: "\n")
        XCTAssertTrue(LiveReload.oldCodeUses(inDump: onlyTick).contains("Mood\ttick()\tprints"))
        // The record outlives a change: the timer's switch, recorded from the installed sources, still counts once a
        // later change has taken it out of the sources that run.
        XCTAssertFalse(LiveReload.hasOldCodeRecord(project))
        LiveReload.recordOldCode(LiveReload.oldCodeUses(inDump: dump), for: project)
        XCTAssertTrue(LiveReload.hasOldCodeRecord(project))
        LiveReload.recordOldCode(LiveReload.oldCodeUses(inDump: onlyTick), for: project)
        XCTAssertTrue(LiveReload.oldCodeRecorded(project).contains("Mood\tstart()\tswitches over"))
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
        // The spare type comes with it: the loader sets aside the names of retired properties.
        let start = try XCTUnwrap(text.range(of: "    struct LampSpare: Codable, Hashable, @unchecked Sendable {"))
        let live = try XCTUnwrap(text.range(of: "    @MainActor @Observable final class LampLive {"))
        let end = try XCTUnwrap(text.range(of: "\n    }\n", range: live.upperBound..<text.endIndex))
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
