import XCTest
import AppKit
@testable import Lamp

/// The wishes Lamp comes with are the first thing a new person uses, so each one must be whole: its own
/// starter.md read (a name, an offer and three short changes to suggest), APP.md for the agent, an icon with its artwork,
/// and none of the files Lamp writes itself, which a copy would otherwise freeze at this Lamp's version.
final class StartersTests: XCTestCase {
    private var starters: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Starters")
    }

    func testFrontMatterIsRead() throws {
        let text = """
        ---
        name: Tidy Up
        offer: "Make it tidy your way"
        repository: https://github.com/lampdotdev/tidyup
        commit: 199f010cf9b35eb58ec934d95eba1ab977c880c1
        tweaks:
          - doc.text: Group my invoices by client
          - 'Never touch design files'
          - Group: by client
        ---
        Anything after it is ignored.
        """
        let starter = try XCTUnwrap(Starters.parse(text, folder: starters))
        XCTAssertEqual(starter.name, "Tidy Up")
        XCTAssertEqual(starter.offer, "Make it tidy your way")
        // Where it lives and the commit this Lamp ships, which a copy's chain carries for its updates.
        XCTAssertEqual(starter.repository, "https://github.com/lampdotdev/tidyup")
        XCTAssertEqual(starter.commit, "199f010cf9b35eb58ec934d95eba1ab977c880c1")
        XCTAssertEqual(starter.tweaks, [Starters.Tweak(title: "Group my invoices by client", symbol: "doc.text"),
                                        Starters.Tweak(title: "Never touch design files"),
                                        Starters.Tweak(title: "Group: by client")])
        // Its chat opens on a card of Lamp's own, which doesn't hold the wish up.
        let card = try XCTUnwrap(Starters.card(for: starter))
        XCTAssertEqual(card.ask?.offer, true)
        XCTAssertEqual(card.ask?.questions.first?.options.map(\.title).first, "Group my invoices by client")
        XCTAssertNotNil(Talk.open(in: [card]))
        XCTAssertNil(Talk.waiting(in: [card]))
        // Just the offer and its changes: a line under it pushed them down in the wand's narrow panel.
        XCTAssertNil(card.ask?.questions.first?.detail)
        XCTAssertNil(Starters.parse("name: No front matter", folder: starters))
    }

    func testEveryStarterIsWhole() throws {
        let fm = FileManager.default
        let folders = try fm.contentsOfDirectory(at: starters, includingPropertiesForKeys: nil)
            .filter { $0.hasDirectoryPath }
        XCTAssertFalse(folders.isEmpty)
        for folder in folders {
            let name = folder.lastPathComponent
            let text = try String(contentsOf: folder.appendingPathComponent("starter.md"), encoding: .utf8)
            let starter = try XCTUnwrap(Starters.parse(text, folder: folder), name)
            XCTAssertFalse(starter.offer.isEmpty, name)
            XCTAssertEqual(starter.tweaks.count, 3, name)
            for words in starter.tweaks.map(\.title) + [starter.offer] {
                XCTAssertLessThanOrEqual(words.split(separator: " ").count, 6, "\(name): \(words)")
            }
            for tweak in starter.tweaks {
                let symbol = try XCTUnwrap(tweak.symbol, "\(name): \(tweak.title) has no symbol")
                XCTAssertNotNil(NSImage(systemSymbolName: symbol, accessibilityDescription: nil), "\(name): \(symbol)")
            }
            XCTAssertTrue(fm.fileExists(atPath: folder.appendingPathComponent("APP.md").path), name)
            // A Mac app's code starts at App.swift; a game or a screen is its page (Lamp writes the Swift around it).
            let entry = starter.kind.target.recipe.language == .swift ? "Sources/App.swift" : "Web/index.html"
            XCTAssertTrue(fm.fileExists(atPath: folder.appendingPathComponent(entry).path), "\(name): no \(entry)")
            let spec = try JSONDecoder().decode(IconSpec.self, from: Data(contentsOf: folder.appendingPathComponent("icon.json")))
            XCTAssertTrue(Icons.backgrounds.contains { $0.name == spec.background }, name)
            let about = try XCTUnwrap(AppDescription.description(at: folder.appendingPathComponent("about.json")), name)
            // The desk shows it in large type beside the app's picture, in four lines at most.
            XCTAssertLessThanOrEqual(about.count, AppDescription.limit, "\(name): \(about)")
            // Its icon ships drawn (StarterIconsTests), from the icon.json it has now.
            let icon = folder.appendingPathComponent(Starters.iconFolder)
            XCTAssertTrue(fm.fileExists(atPath: icon.appendingPathComponent("icon.png").path), "\(name) ships no icon")
            let drawn = try? JSONDecoder().decode(IconSpec.self, from: Data(contentsOf: icon.appendingPathComponent("icon.json")))
            XCTAssertEqual(drawn, spec, "\(name)'s icon was drawn from another icon.json: draw it again")
            // Glass, or a painting for a game, as an app's icon would be drawn.
            if spec.game {
                XCTAssertNotNil(NSImage(contentsOf: icon.appendingPathComponent(Starters.artFile)), "\(name)'s icon has no painting")
            } else {
                XCTAssertNotNil(GlassArt.load(from: icon.appendingPathComponent(Starters.glassFile)), "\(name)'s icon has no glass design")
            }
            // What the desk shows when the pointer rests on it, before anyone has opened it.
            XCTAssertNotNil(NSImage(contentsOf: folder.appendingPathComponent("preview.png")), "\(name) ships no preview.png")
            for owned in ["Sources/LampSupport.swift", "Widget/LampWidgetSupport.swift", "Share/LampShareSupport.swift", "build.sh", "Package.swift"] {
                XCTAssertFalse(fm.fileExists(atPath: folder.appendingPathComponent(owned).path), "\(name) ships \(owned)")
            }
        }
    }
}
