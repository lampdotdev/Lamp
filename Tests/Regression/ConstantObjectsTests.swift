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
        let plain = await LiveReload.plainTypes(["Font.Design", "Font.Width", "Font.Weight", "URLSession", "NoSuchTypeHere", "Bad(name)"], in: project)
        XCTAssertEqual(plain, ["Font.Design", "Font.Width", "Font.Weight"])
    }
}
