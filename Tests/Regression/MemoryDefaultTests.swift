import XCTest
@testable import Lamp

/// Lamp keeps notes unless the person says otherwise, and a choice made while this was an experiment that
/// was off by default still stands.
final class MemoryDefaultTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "MemoryDefaultTests"

    override func setUp() {
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    func testSomeoneWhoNeverChoseHasItOn() {
        XCTAssertTrue(Memory.isOn(in: defaults))
    }

    func testSomeoneWhoTurnedItOffKeepsItOff() {
        defaults.set(false, forKey: "experimentMemory")
        XCTAssertFalse(Memory.isOn(in: defaults))
    }

    func testSomeoneWhoTurnedItOnAsAnExperimentKeepsItOn() {
        defaults.set(true, forKey: "experimentMemory")
        XCTAssertTrue(Memory.isOn(in: defaults))
    }
}
