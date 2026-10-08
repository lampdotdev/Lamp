import XCTest
@testable import Lamp

/// A shared app that launched Lamp is decided on only after Lamp's first real look at setup.
@MainActor
final class FirstLookTests: XCTestCase {
    func testWhatArrivesBeforeTheLookWaitsForIt() async {
        let look = FirstLook()
        var decided: [String] = []
        let first = Task { await look.wait(); decided.append("Tally") }
        let second = Task { await look.wait(); decided.append("Recipes") }
        // Both files are in, the look hasn't been made: nothing is decided, however long it takes.
        for _ in 0..<20 { await Task.yield() }
        XCTAssertTrue(decided.isEmpty)
        XCTAssertFalse(look.isDone)

        look.done()
        await first.value
        await second.value
        XCTAssertEqual(decided, ["Tally", "Recipes"])
    }

    func testAfterTheLookNothingWaits() async {
        let look = FirstLook()
        look.done()
        look.done()   // every later look at setup says so again
        await look.wait()
        XCTAssertTrue(look.isDone)
    }
}
