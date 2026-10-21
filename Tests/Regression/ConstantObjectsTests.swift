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

    /// A theme held in one constant: its typeface's font fields are system types Lamp can't judge from the code, so
    /// they're the fields the open app is asked about, and once it says they're plain the theme holds no object. The
    /// layout is the one a theme change was refused with.
    func testAThemesFontFieldsAreAskedAboutAndThenGoInLive() {
        let layout = ["Look.Typeface\t", "Look.Typeface\t__lampSpare_Typeface: LampSpare", "Look.Typeface\tdesign: Font.Design",
                      "Look.Typeface\twidth: Font.Width", "Look.Typeface\tweight: Font.Weight", "Look.Typeface\ttracking: CGFloat",
                      "Look.Typeface\tuppercase: Bool", "Look\t", "Look\twall: Color", "Look\tdisplay: Look.Typeface",
                      "Look\tscheme: ColorScheme"]
        let byType = Dictionary(grouping: layout, by: { String($0.prefix { $0 != "\t" }) })
        var seen = Set<String>(), asked = Set<String>()
        XCTAssertNil(LiveSlots.objectHeld(in: "Look", classes: [], layout: byType, seen: &seen, unsure: { asked.insert($0) }))
        XCTAssertEqual(asked, ["Look.Typeface\tdesign", "Look.Typeface\twidth", "Look.Typeface\tweight"])
        XCTAssertTrue(holds("Look", layout: layout), "unanswered, a field Lamp can't judge may hold an object")
        seen = []
        XCTAssertFalse(LiveSlots.holdsObject("Look", classes: [], layout: byType, seen: &seen, plain: asked))
    }

    /// One of the app's classes is never asked about: it holds an object whatever the app says of other fields.
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

    /// An app built before it could answer (no request key in its binary, here no binary at all) is asked nothing and
    /// not waited for: its constant waits for Reload, saying why, as it did.
    @MainActor func testAnAppThatCantAnswerIsAskedNothing() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("plain-fields-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let project = try Template.scaffold(name: "Older", in: root)
        let start = ContinuousClock.now
        let plain = await LiveReload.plainFields(["Look.Typeface\tdesign"], of: project, token: "x")
        XCTAssertEqual(plain, [])
        XCTAssertLessThan(ContinuousClock.now - start, .milliseconds(100))
    }
}
