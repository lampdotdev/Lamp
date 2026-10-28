import XCTest
import AppKit
@testable import Lamp

/// The wishes Lamp comes with carry their icons ready-made (the icon/ folder among the pictures in each starter's
/// repository, `Starters.iconFolder(of:)`), so they're on the desk the moment the starters are, instead of being drawn
/// one by one on a new person's Mac. This draws them again from each tree's icon.json and the artwork shipped beside
/// the icon (icon/art.json, a glass design, or icon/art.png, a game's painting) with Lamp's own drawing, the way an
/// app's icon is made, into the fetched tree, for scripts/publish-starters.sh to put up: run it after changing how
/// icons are drawn, with Xcode installed so the Liquid Glass icon is compiled too.
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
        let root = fm.temporaryDirectory.appendingPathComponent("lamp-starter-icons-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let paint = ProcessInfo.processInfo.environment["LAMP_PAINT_STARTER_ART"] == "1"
        if paint {
            let key = try XCTUnwrap(ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"], "Drawing needs OPENROUTER_API_KEY.")
            KeyStore.useForThisRun(key, for: "openrouter")
        }
        let folders = try StarterTrees.folders()
            .filter { only == "1" || only.split(separator: ",").contains(Substring($0.lastPathComponent)) }
        XCTAssertFalse(folders.isEmpty)
        // Where each one is drawn to: the icon folder its repository will carry, in the fetched tree.
        func drawnIcon(_ folder: URL) throws -> (tree: URL, icon: URL) {
            let starter = try XCTUnwrap(Starters.read(folder))
            return (starter.tree, starter.tree.appendingPathComponent(Starters.picturesFolder).appendingPathComponent(Starters.iconFolder))
        }

        // Drawn all at once, since each takes a minute or two of looking and drawing again.
        let drawn = try await withThrowingTaskGroup(of: (URL, Icons.Artwork).self) { group in
            for folder in folders {
                group.addTask {
                    let name = folder.lastPathComponent
                    let (tree, icon) = try drawnIcon(folder)
                    let spec = try JSONDecoder().decode(IconSpec.self, from: Data(contentsOf: tree.appendingPathComponent("icon.json")))
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
                    let about = (try? String(contentsOf: tree.appendingPathComponent("APP.md"), encoding: .utf8)) ?? ""
                    return (folder, .glass(try await GlassIcons.generateBest(for: spec, appName: name, about: about, log: log)))
                }
            }
            return try await group.reduce(into: []) { $0.append($1) }
        }

        for (folder, art) in drawn {
            let (tree, icon) = try drawnIcon(folder)
            let spec = try JSONDecoder().decode(IconSpec.self, from: Data(contentsOf: tree.appendingPathComponent("icon.json")))
            let project = try Template.draft(name: folder.lastPathComponent, in: root)
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
            try fm.copyItem(at: tree.appendingPathComponent("icon.json"), to: icon.appendingPathComponent("icon.json"))
            XCTAssertTrue(fm.fileExists(atPath: icon.appendingPathComponent("icon.png").path), folder.lastPathComponent)
            XCTAssertTrue(fm.fileExists(atPath: icon.appendingPathComponent("AppIcon.icns").path), folder.lastPathComponent)
            // Without the Liquid Glass one a Mac with Xcode would get a flatter icon for a starter than for its own apps.
            XCTAssertTrue(fm.fileExists(atPath: icon.appendingPathComponent("Assets.car").path),
                          "\(folder.lastPathComponent): no Assets.car. Is Xcode installed and set up (xcodebuild -runFirstLaunch)?")
        }
    }
}
