import XCTest
import AppKit
@testable import Lamp

/// The wishes Lamp comes with carry their icons ready-made (each starter's icon/ folder), so they're on the desk
/// the moment the starters are, instead of being drawn one by one on a new person's Mac. This draws them again from
/// each icon.json and the artwork shipped beside it (icon/art.json, a glass design, or icon/art.png, a game's painting)
/// with Lamp's own drawing, the way an app's icon is made: run it after changing how icons are drawn, with Xcode
/// installed so the Liquid Glass icon is compiled too.
/// `LAMP_RENDER_STARTER_ICONS=1 swift test --filter StarterIconsTests` (or `=today` for one).
///
/// After changing a starter's icon.json, or how artwork is drawn, draw its artwork again as an app's is (the best of
/// a few, picked by the judge) by adding `LAMP_PAINT_STARTER_ART=1` and an OpenRouter key in `OPENROUTER_API_KEY`, and
/// look at what it picked before committing: drawing isn't the same twice.
final class StarterIconsTests: XCTestCase {
    func testRenderStarterIcons() async throws {
        guard let only = ProcessInfo.processInfo.environment["LAMP_RENDER_STARTER_ICONS"] else {
            throw XCTSkip("Set LAMP_RENDER_STARTER_ICONS=1 to draw the starters' icons again.")
        }
        let fm = FileManager.default
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let root = fm.temporaryDirectory.appendingPathComponent("lamp-starter-icons-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let paint = ProcessInfo.processInfo.environment["LAMP_PAINT_STARTER_ART"] == "1"
        if paint {
            let key = try XCTUnwrap(ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"], "Drawing needs OPENROUTER_API_KEY.")
            KeyStore.useForThisRun(key, for: "openrouter")
        }
        let folders = try fm.contentsOfDirectory(at: repo.appendingPathComponent("Resources/Starters"), includingPropertiesForKeys: nil)
            .filter { $0.hasDirectoryPath && (only == "1" || only.split(separator: ",").contains(Substring($0.lastPathComponent))) }
        XCTAssertFalse(folders.isEmpty)

        // Drawn all at once, since each takes a minute or two of looking and drawing again.
        let drawn = try await withThrowingTaskGroup(of: (URL, Icons.Artwork).self) { group in
            for folder in folders {
                group.addTask {
                    let name = folder.lastPathComponent
                    let spec = try JSONDecoder().decode(IconSpec.self, from: Data(contentsOf: folder.appendingPathComponent("icon.json")))
                    let icon = folder.appendingPathComponent(Starters.iconFolder)
                    let log: @MainActor (String) -> Void = { print("\(name): \($0)") }
                    guard paint else {
                        if let glass = GlassArt.load(from: icon.appendingPathComponent(Starters.glassFile)), !spec.game {
                            return (folder, .glass(glass))
                        }
                        let painting = try XCTUnwrap(NSImage(contentsOf: icon.appendingPathComponent(Starters.artFile)),
                                                     "\(name) has no artwork yet: draw it with LAMP_PAINT_STARTER_ART=1.")
                        return (folder, .picture(painting))
                    }
                    if spec.game { return (folder, .picture(try await Icons.generateBestArt(spec, appName: name, log: log))) }
                    let about = (try? String(contentsOf: folder.appendingPathComponent("APP.md"), encoding: .utf8)) ?? ""
                    return (folder, .glass(try await GlassIcons.generateBest(for: spec, appName: name, about: about, log: log)))
                }
            }
            return try await group.reduce(into: []) { $0.append($1) }
        }

        for (folder, art) in drawn {
            let spec = try JSONDecoder().decode(IconSpec.self, from: Data(contentsOf: folder.appendingPathComponent("icon.json")))
            let project = try Template.draft(name: folder.lastPathComponent, in: root)
            let icon = folder.appendingPathComponent(Starters.iconFolder)
            _ = try await Icons.write(spec, art: art, for: project)
            try? fm.removeItem(at: icon)
            try fm.createDirectory(at: icon, withIntermediateDirectories: true)
            switch art {
            case .glass(let glass):
                try glass.encoded().write(to: icon.appendingPathComponent(Starters.glassFile))
            case .picture(let painting):
                let png = try XCTUnwrap(painting.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:))?
                    .representation(using: .png, properties: [:]))
                try png.write(to: icon.appendingPathComponent(Starters.artFile))
            case .waiting:
                XCTFail("\(folder.lastPathComponent) was drawn with no artwork")
            }
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
