import XCTest
@testable import Lamp

/// A free account's phone holds three of its apps. Lamp counts its own there by the team at the end of their bundle
/// ids, and before a fourth offers to take one off: one that stopped opening, then the one renewed least lately.
final class PhoneSlotsTests: XCTestCase {
    func testWhichAppIsOfferedToComeOff() {
        // `devicectl device info apps --json-output`, in the shape Xcode 27 writes it, with made-up ids.
        let listing = #"""
        {"result": {"apps": [
          {"bundleIdentifier": "dev.lamp.app.notes.abcde12345", "builtByDeveloper": true, "removable": true},
          {"bundleIdentifier": "dev.lamp.app.steps.abcde12345", "builtByDeveloper": true, "removable": true},
          {"bundleIdentifier": "dev.lamp.dev.app.timer.abcde12345", "builtByDeveloper": true, "removable": true},
          {"bundleIdentifier": "dev.lamp.app.paid.fghij67890", "builtByDeveloper": true, "removable": true},
          {"bundleIdentifier": "com.example.store", "builtByDeveloper": false, "removable": true}
        ]}}
        """#
        let team = PhoneSlots.teamApps(PhoneSlots.developerApps(in: Data(listing.utf8)), team: "ABCDE12345")
        XCTAssertEqual(team, ["dev.lamp.app.notes.abcde12345", "dev.lamp.app.steps.abcde12345", "dev.lamp.dev.app.timer.abcde12345"])
        let now = Date()
        let notes = PhoneSlots.Known(bundleID: "dev.lamp.app.notes.abcde12345", expires: now.addingTimeInterval(5 * 86400))
        let steps = PhoneSlots.Known(bundleID: "dev.lamp.app.steps.abcde12345", expires: now.addingTimeInterval(6 * 86400))
        let mine = "dev.lamp.app.new.abcde12345"
        // The one renewed least lately, of Lamp's own.
        XCTAssertEqual(PhoneSlots.toTakeOff(installed: team, mine: mine, known: [notes, steps], now: now), notes.bundleID)
        // One that stopped opening comes first.
        let stopped = PhoneSlots.Known(bundleID: steps.bundleID, expires: now.addingTimeInterval(-3600))
        XCTAssertEqual(PhoneSlots.toTakeOff(installed: team, mine: mine, known: [notes, stopped], now: now), steps.bundleID)
        // Nothing this Lamp knows: another Lamp's app of the team.
        XCTAssertEqual(PhoneSlots.toTakeOff(installed: team, mine: mine, known: [], now: now), team[0])
        // Room left, or the app already there (a reinstall takes no room): nothing to ask.
        XCTAssertNil(PhoneSlots.toTakeOff(installed: Array(team.prefix(2)), mine: mine, known: [notes], now: now))
        XCTAssertNil(PhoneSlots.toTakeOff(installed: team, mine: notes.bundleID, known: [notes, steps], now: now))
    }
}
