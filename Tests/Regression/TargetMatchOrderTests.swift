import XCTest
@testable import Lamp

/// A kind made from another kind's files, with a mark of its own (an Android TV app is an Android app with a TV's
/// manifest), is read back as itself wherever it's listed: its folder also passes the other kind's check.
final class TargetMatchOrderTests: XCTestCase {
    func testAKindMadeFromAnothersFilesIsReadAsItself() throws {
        let android = Target.android
        let mark = "app/src/main/res/values/lamp-tv.xml"
        let r = android.recipe
        let tv = Target(platform: Platform(kind: "androidtv"), places: android.places, identity: android.identity, guidance: android.guidance,
                        recipe: Target.Recipe(language: r.language, fill: r.fill, ownedFiles: r.ownedFiles, support: r.support,
                                              isMade: { r.isMade($0) && FileManager.default.fileExists(atPath: $0.appendingPathComponent(mark).path) },
                                              scaffolded: r.scaffolded, sources: r.sources, built: r.built, builtURL: r.builtURL,
                                              marker: mark, refines: .android, shareRefusal: r.shareRefusal),
                        part: nil, setup: .none)

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("match-order-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let project = LampProject(id: "probe", name: "Probe", exe: "Probe", dir: dir, platform: .android)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Template.fillAndroid(project)
        XCTAssertEqual(Targets.matchOrder([.mac, android, tv]).first { $0.recipe.isMade(dir) }?.platform, .android)

        try FileManager.default.createDirectory(at: dir.appendingPathComponent(mark).deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("<resources/>\n".utf8).write(to: dir.appendingPathComponent(mark))
        // Listed after Android, as a new kind is: still read as itself.
        XCTAssertEqual(Targets.matchOrder([.mac, android, tv]).first { $0.recipe.isMade(dir) }?.platform.rawValue, "androidtv")
    }
}
