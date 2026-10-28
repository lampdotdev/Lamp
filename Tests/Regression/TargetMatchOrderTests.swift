import XCTest
@testable import Lamp

/// A kind made from another kind's files, with a mark of its own (an Android TV app is an Android app with a TV's
/// manifest), is read back as itself wherever it's listed: its folder also passes the other kind's check.
final class TargetMatchOrderTests: XCTestCase {
    func testAKindMadeFromAnothersFilesIsReadAsItself() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("match-order-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let phone = LampProject(id: "probe", name: "Probe", exe: "Probe", dir: dir, platform: .android)
        try Template.fillAndroid(phone)
        XCTAssertEqual(Targets.matchOrder([.mac, .android, .androidTV]).first { $0.recipe.isMade(dir) }?.platform, .android)

        let tv = LampProject(id: "probe", name: "Probe", exe: "Probe", dir: dir, platform: .androidTV)
        try Template.fillAndroidTV(tv)
        // Listed after Android, as a new kind is: still read as itself.
        XCTAssertEqual(Targets.matchOrder([.mac, .android, .androidTV]).first { $0.recipe.isMade(dir) }?.platform, .androidTV)
    }
}
