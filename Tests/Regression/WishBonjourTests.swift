import XCTest
@testable import Lamp

/// An iPhone app of a wish of several is found by the wish's other apps, and finds them, by the wish's Bonjour type,
/// which iOS lets it use only when its Info.plist names it: beside the types the app declared itself, never in place of
/// them, and nothing for an app on its own.
final class WishBonjourTests: XCTestCase {
    private func services(declaring own: [String]?, wishKey: Data?) throws -> [String]? {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("wish-bonjour-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let dir = root.appendingPathComponent("app"), phone = root.appendingPathComponent("phone")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let own {
            try JSONSerialization.data(withJSONObject: ["bonjourServices": own]).write(to: dir.appendingPathComponent("capabilities.json"))
        }
        let project = LampProject(id: "score.iphone", name: "Score", exe: "Score", dir: dir, platform: .iphone, partOf: "score")
        try Template.writeDeviceProject(for: project, team: "ABCDE12345", in: phone, wishKey: wishKey)
        let data = try Data(contentsOf: phone.appendingPathComponent("Info.plist"))
        let plist = try XCTUnwrap(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual(String(decoding: data, as: UTF8.self).components(separatedBy: "<key>NSBonjourServices</key>").count - 1,
                       plist["NSBonjourServices"] == nil ? 0 : 1, "named once")
        return plist["NSBonjourServices"] as? [String]
    }

    func testThePhonesInfoPlistNamesTheWishsTypeBesideTheAppsOwn() throws {
        XCTAssertEqual(try services(declaring: ["_http._tcp"], wishKey: Data(repeating: 7, count: 32)), ["_http._tcp", "_lampwish._tcp"])
        XCTAssertEqual(try services(declaring: nil, wishKey: Data(repeating: 7, count: 32)), ["_lampwish._tcp"])
        XCTAssertEqual(try services(declaring: ["_http._tcp"], wishKey: nil), ["_http._tcp"], "an app on its own keeps only its own")
        XCTAssertNil(try services(declaring: nil, wishKey: nil))
    }
}
