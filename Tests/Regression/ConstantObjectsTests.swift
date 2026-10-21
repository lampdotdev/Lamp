import XCTest
@testable import Lamp

/// Which changed constants go into an open app as a new value, and which reopen it because a second object would
/// split the app's state. The layout lines are the shape `LiveReload.layout` gives them ("Type<tab>name: type").
final class ConstantObjectsTests: XCTestCase {
    private func holds(_ type: String, classes: Set<String> = [], layout: [String] = []) -> Bool {
        var seen = Set<String>()
        let byType = Dictionary(grouping: layout, by: { String($0.prefix { $0 != "\t" }) })
        return LiveSlots.holdsObject(type, classes: classes, layout: byType, seen: &seen)
    }

    func testPlainValuesGoInLive() {
        XCTAssertFalse(holds("Float"))
        XCTAssertFalse(holds("[String : Int]"))
        XCTAssertFalse(holds("SIMD3<Float>"))
    }

    func testATupleWithLabelsHoldsOnlyItsElements() {
        XCTAssertFalse(holds("(width: Int, height: Int)"))
        XCTAssertTrue(holds("(name: String, api: LampAPI)"))
    }

    func testAStructsSparePlaceIsntOneOfItsFields() {
        let layout = ["Tuning\t", "Tuning\tcount: Int", "Tuning\t__lampSpare_Tuning: LampSpare"]
        XCTAssertFalse(holds("Tuning", layout: layout))
        XCTAssertTrue(holds("Tuning", layout: layout + ["Tuning\tclient: LampAPI"]))
    }

    func testObjectsReopen() {
        XCTAssertTrue(holds("LampAPI"))
        XCTAssertTrue(holds("[Model]", classes: ["Model"]))
        XCTAssertTrue(holds("any Named"))
    }

    /// A theme held in one constant: its typeface's font types are system types Lamp can't judge from the code, so
    /// they're the ones asked about, and once the system says they hold no object the theme holds none. The layout is
    /// the one a theme change was refused with.
    func testAThemesFontTypesAreAskedAboutAndThenGoInLive() {
        let layout = ["Look.Typeface\t", "Look.Typeface\t__lampSpare_Typeface: LampSpare", "Look.Typeface\tdesign: Font.Design",
                      "Look.Typeface\twidth: Font.Width", "Look.Typeface\tweight: Font.Weight?", "Look.Typeface\ttracking: CGFloat",
                      "Look.Typeface\tuppercase: Bool", "Look\t", "Look\twall: Color", "Look\tdisplay: Look.Typeface",
                      "Look\tscheme: ColorScheme"]
        let byType = Dictionary(grouping: layout, by: { String($0.prefix { $0 != "\t" }) })
        var seen = Set<String>(), asked = Set<String>()
        XCTAssertNil(LiveSlots.objectHeld(in: "Look", classes: [], layout: byType, seen: &seen, unsure: { asked.insert($0) }))
        XCTAssertEqual(asked, ["Font.Design", "Font.Width", "Font.Weight"])
        XCTAssertTrue(holds("Look", layout: layout), "unanswered, a type Lamp can't judge may hold an object")
        seen = []
        XCTAssertFalse(LiveSlots.holdsObject("Look", classes: [], layout: byType, seen: &seen, plain: asked))
    }

    /// Two files' private types of one name are one type to the layout as the code names it (`bared`), so an answer
    /// can't be about a type and field: it's about the system type a field holds. The private twin's field of the
    /// same name, holding something else, still holds an object.
    func testAnAnswerIsAboutATypeNotAFieldOfATwin() {
        let layout = LiveReload.bared(["Look\t", "Look\tfield: Font.Design", "Look@Other.swift\t", "Look@Other.swift\tfield: NSCache<NSString, NSString>"])
        let byType = Dictionary(grouping: layout, by: { String($0.prefix { $0 != "\t" }) })
        var seen = Set<String>(), asked = Set<String>()
        _ = LiveSlots.objectHeld(in: "Look", classes: [], layout: byType, seen: &seen, unsure: { asked.insert($0) })
        XCTAssertEqual(asked, ["Font.Design", "NSCache", "NSString"])
        seen = []
        XCTAssertEqual(LiveSlots.objectHeld(in: "Look", classes: [], layout: byType, seen: &seen, plain: ["Font.Design"]), "Look.field (a NSCache)")
    }

    /// One of the app's classes is never asked about: it holds an object whatever else is answered.
    func testAClassIsntAskedAbout() {
        let layout = ["Look\t", "Look\tdesign: Font.Design", "Look\tstore: Store"]
        let byType = Dictionary(grouping: layout, by: { String($0.prefix { $0 != "\t" }) })
        var seen = Set<String>(), asked = Set<String>()
        XCTAssertEqual(LiveSlots.objectHeld(in: "Look", classes: ["Store"], layout: byType, seen: &seen, unsure: { asked.insert($0) }), "Look.store (a Store)")
    }

    /// A refusal names the field that may hold the object, the deepest one, not the generic line.
    func testWhatHoldsAnObjectIsNamedByItsField() {
        let layout = ["Look\t", "Look\twall: Color", "Look\tdisplay: Look.Typeface", "Look.Typeface\t", "Look.Typeface\tclient: LampAPI"]
        var seen = Set<String>()
        let byType = Dictionary(grouping: layout, by: { String($0.prefix { $0 != "\t" }) })
        XCTAssertEqual(LiveSlots.objectHeld(in: "Look", classes: [], layout: byType, seen: &seen), "Look.Typeface.client (a LampAPI)")
    }

    /// The system's own answer, from the program Lamp compiles and runs in the app's sandbox: the font styles hold no
    /// object, a class does, and a name the program can't find isn't said to be plain while the rest are still answered.
    @MainActor func testTheSystemSaysWhichTypesHoldNoObject() async throws {
        let fm = FileManager.default
        // Under the home folder, where the app's sandbox (which the program runs in) opens an app's folder.
        let root = fm.homeDirectoryForCurrentUser.appendingPathComponent(".lamp-plain-types-test-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let project = try Template.scaffold(name: "Plain", in: root)
        let plain = await LiveReload.plainTypes(["Font.Design": "SwiftUICore.Font.Design", "Font.Width": "SwiftUICore.Font.Width",
                                                 "Font.Weight": "SwiftUICore.Font.Weight", "URLSession": "Foundation.URLSession",
                                                 "NoSuchTypeHere": "Foundation.NoSuchTypeHere", "Bad": "Foundation.Bad(name)"], in: project)
        XCTAssertEqual(plain, ["Font.Design", "Font.Width", "Font.Weight"])
    }

    /// What's asked about is the system type the compiler resolved a field's type to, by its module and name. A name
    /// the app gives a type of its own isn't asked about as the system's type of that name, even when it's declared
    /// in the widget's shared code, which the app's analysis reads only as context: here `ComparisonResult` is the
    /// app's name for `URLSession`, and Foundation's `ComparisonResult` holding no object says nothing of it.
    @MainActor func testOnlyWhatTheCompilerResolvedToASystemTypeIsAskedAbout() async throws {
        let fm = FileManager.default
        let root = fm.homeDirectoryForCurrentUser.appendingPathComponent(".lamp-plain-types-test-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let project = try Template.scaffold(name: "Resolved", in: root)
        func copy(_ name: String, design: String) throws -> URL {
            // In the app's folder, which is what the sandbox the compiler runs in opens.
            let sources = project.dir.appendingPathComponent(name).appendingPathComponent("Sources")
            let shared = project.dir.appendingPathComponent(name).appendingPathComponent("Widget/Shared")
            try fm.createDirectory(at: sources, withIntermediateDirectories: true)
            try fm.createDirectory(at: shared, withIntermediateDirectories: true)
            try "import Foundation\ntypealias ComparisonResult = URLSession\n".write(to: shared.appendingPathComponent("Alias.swift"), atomically: true, encoding: .utf8)
            try """
                import SwiftUI
                struct Holder { var design: Font.Design; var weight: Font.Weight?; var order: ComparisonResult }
                enum Keep { static let current = Holder(design: .\(design), weight: .bold, order: URLSession(configuration: .ephemeral)) }
                """.write(to: sources.appendingPathComponent("Model.swift"), atomically: true, encoding: .utf8)
            return sources
        }
        let before = await LiveReload.analysis(of: try copy("before", design: "rounded"), in: project, module: project.exe, macOS: "14.0")
        let after = await LiveReload.analysis(of: try copy("after", design: "serif"), in: project, module: project.exe, macOS: "14.0")
        let open = try XCTUnwrap(before), changed = try XCTUnwrap(after)
        let asked = LiveSlots.unsureTypes(project, before: open.layout, after: changed.layout, declarations: changed.declarations)
        XCTAssertEqual(asked, ["Font.Design": "SwiftUICore.Font.Design", "Font.Weight": "SwiftUICore.Font.Weight"])
        // With the font styles answered plain, the app's ComparisonResult still holds an object.
        var seen = Set<String>()
        XCTAssertTrue(LiveSlots.holdsObject("Holder", classes: changed.declarations.classes, layout: LiveReload.byType(LiveReload.bared(changed.layout)),
                                            seen: &seen, plain: Set(asked.keys)))
    }
}
