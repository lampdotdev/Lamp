import XCTest
@testable import Lamp

/// Someone who turned notes off while they were an experiment that was off by default keeps them off, now
/// that they're on by default: Lamp doesn't start noting things about them unasked.
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

    func testSomeoneWhoTurnedItOffKeepsItOff() {
        defaults.set(false, forKey: "experimentMemory")
        XCTAssertFalse(Memory.isOn(in: defaults))
    }
}
