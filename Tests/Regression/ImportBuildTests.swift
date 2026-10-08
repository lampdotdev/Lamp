import XCTest
@testable import Lamp

final class ImportBuildTests: XCTestCase {
    private let building = Store.ImportBuild(id: "tally", name: "Tally")

    func testAnAppThatOpenedGivesTheWelcomeBack() {
        XCTAssertFalse(building.failed)
        XCTAssertNil(Store.ImportBuild.after(building, finished: "tally", opened: true))
    }

    func testAnAppThatDidNotOpenStaysUpSayingSo() {
        let shown = Store.ImportBuild.after(building, finished: "tally", opened: false)
        XCTAssertEqual(shown, Store.ImportBuild(id: "tally", name: "Tally", failed: true))
    }

    func testAnEarlierImportFinishingLeavesTheNewerOneAlone() {
        XCTAssertEqual(Store.ImportBuild.after(building, finished: "ledger", opened: true), building)
        XCTAssertEqual(Store.ImportBuild.after(building, finished: "ledger", opened: false), building)
    }

    func testNothingShownStaysNothing() {
        // Outside the welcome the build is in the app's chat, and a failure dismissed with Continue stays dismissed.
        XCTAssertNil(Store.ImportBuild.after(nil, finished: "tally", opened: false))
    }
}
