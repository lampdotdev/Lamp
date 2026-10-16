import XCTest
@testable import Lamp

/// The wishes Lamp comes with carry their icons ready-made (each starter's icon/ folder), so they're on the desk
/// the moment the starters are, instead of being drawn one by one on a new person's Mac. This draws them again from
/// each icon.json with Lamp's own drawing, the way an app's icon is made: run it after changing a starter's
/// icon.json or how icons are drawn, with Xcode installed so the Liquid Glass icon is compiled too.
/// `LAMP_RENDER_STARTER_ICONS=1 swift test --filter StarterIconsTests` (or `=today` for one).
final class StarterIconsTests: XCTestCase {
    func testRenderStarterIcons() async throws {
        guard let only = ProcessInfo.processInfo.environment["LAMP_RENDER_STARTER_ICONS"] else {
            throw XCTSkip("Set LAMP_RENDER_STARTER_ICONS=1 to draw the starters' icons again.")
        }
        let fm = FileManager.default
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let root = fm.temporaryDirectory.appendingPathComponent("lamp-starter-icons-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let folders = try fm.contentsOfDirectory(at: repo.appendingPathComponent("Resources/Starters"), includingPropertiesForKeys: nil)
            .filter { $0.hasDirectoryPath && (only == "1" || $0.lastPathComponent == only) }
        XCTAssertFalse(folders.isEmpty)
        for folder in folders {
            let spec = try JSONDecoder().decode(IconSpec.self, from: Data(contentsOf: folder.appendingPathComponent("icon.json")))
            let project = try Template.draft(name: folder.lastPathComponent, in: root)
            _ = try await Icons.write(spec, art: nil, for: project)
            let icon = folder.appendingPathComponent(Starters.iconFolder)
            try? fm.removeItem(at: icon)
            try fm.createDirectory(at: icon, withIntermediateDirectories: true)
            for made in Starters.iconFiles(of: project) where fm.fileExists(atPath: made.path) {
                try fm.copyItem(at: made, to: icon.appendingPathComponent(made.lastPathComponent))
            }
            // What it was drawn from, so Lamp can tell when the app's icon.json has changed since.
            try fm.copyItem(at: folder.appendingPathComponent("icon.json"), to: icon.appendingPathComponent("icon.json"))
            XCTAssertTrue(fm.fileExists(atPath: icon.appendingPathComponent("icon.png").path), folder.lastPathComponent)
            XCTAssertTrue(fm.fileExists(atPath: icon.appendingPathComponent("AppIcon.icns").path), folder.lastPathComponent)
            // Without the Liquid Glass one a Mac with Xcode would get a flatter icon for a starter than for its own apps.
            XCTAssertTrue(fm.fileExists(atPath: icon.appendingPathComponent("Assets.car").path),
                          "\(folder.lastPathComponent): no Assets.car. Is Xcode installed and set up (xcodebuild -runFirstLaunch)?")
        }
    }
}
