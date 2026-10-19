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
}
