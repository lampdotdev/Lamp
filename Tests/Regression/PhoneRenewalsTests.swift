import XCTest
@testable import Lamp

/// When an app on the person's phone is put back: a day after it was signed (six days before a seven-day profile runs
/// out), soon again after a phone
/// that was away, a day later after a problem the person fixes, and the person told once when it has stopped opening.
final class PhoneRenewalsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    private func record(expiresIn days: Double, failedHoursAgo hours: Double? = nil, failure: PhoneFailure.Cause? = nil) -> PhoneRenewals.Record {
        PhoneRenewals.Record(udid: "PHONE", bundleID: "dev.lamp.app.test.abcde12345", team: "ABCDE12345",
                             expires: now.addingTimeInterval(days * 86400), failedAt: hours.map { now.addingTimeInterval(-$0 * 3600) },
                             failure: failure?.rawValue)
    }

    func testWhenAnAppIsPutBack() {
        XCTAssertFalse(PhoneRenewals.isDue(record(expiresIn: 6.5), now: now), "a seven-day profile signed hours ago")
        XCTAssertTrue(PhoneRenewals.isDue(record(expiresIn: 5.9), now: now), "a day old: renewed every day")
        XCTAssertFalse(PhoneRenewals.isDue(record(expiresIn: 300), now: now), "a paid team's year-long profile")
        XCTAssertTrue(PhoneRenewals.isDue(record(expiresIn: -3), now: now), "one that has run out goes back as soon as it can")
        // A phone away or locked comes back by itself: tried again within the hour.
        XCTAssertFalse(PhoneRenewals.isDue(record(expiresIn: 1, failedHoursAgo: 0.5, failure: .unreachable), now: now))
        XCTAssertTrue(PhoneRenewals.isDue(record(expiresIn: 1, failedHoursAgo: 1.5, failure: .locked), now: now))
        // Xcode signed out of Apple is the person's to fix: a day before Lamp tries again.
        XCTAssertFalse(PhoneRenewals.isDue(record(expiresIn: 1, failedHoursAgo: 5, failure: .authentication), now: now))
        XCTAssertTrue(PhoneRenewals.isDue(record(expiresIn: 1, failedHoursAgo: 25, failure: .authentication), now: now))
    }

    /// Signed for another team, an app is a new app on the phone: the old team's copy is the one to take off.
    func testANewTeamsCopyReplacesTheOldOne() {
        let free = record(expiresIn: 3)
        XCTAssertEqual(PhoneRenewals.replaced(free, on: "PHONE", by: "dev.lamp.app.test.fghij67890"), free.bundleID)
        XCTAssertNil(PhoneRenewals.replaced(free, on: "PHONE", by: free.bundleID), "the same team: the same app, put back over itself")
        XCTAssertNil(PhoneRenewals.replaced(free, on: "OTHER", by: "dev.lamp.app.test.fghij67890"), "another phone keeps its own")
        XCTAssertNil(PhoneRenewals.replaced(nil, on: "PHONE", by: free.bundleID))
    }

    func testThePersonIsToldOncePerExpiry() {
        var expired = record(expiresIn: -1)
        XCTAssertFalse(PhoneRenewals.shouldTell(record(expiresIn: 1), now: now), "nothing while it still opens")
        XCTAssertTrue(PhoneRenewals.shouldTell(expired, now: now))
        expired.told = expired.expires
        XCTAssertFalse(PhoneRenewals.shouldTell(expired, now: now))
    }
}
