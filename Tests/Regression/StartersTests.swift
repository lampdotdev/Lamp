import XCTest
import AppKit
@testable import Lamp

/// The wishes Lamp comes with are the first thing a new person uses, so each one must be whole: its own
/// starter.md read (a name, an offer and three short changes to suggest), APP.md for the agent, a symbol icon,
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
        XCTAssertEqual(starter.tweaks, [Starters.Tweak(title: "Group my invoices by client", symbol: "doc.text"),
                                        Starters.Tweak(title: "Never touch design files"),
                                        Starters.Tweak(title: "Group: by client")])
        // Its chat opens on a card of Lamp's own, which doesn't hold the wish up.
        let card = try XCTUnwrap(Starters.card(for: starter))
        XCTAssertEqual(card.ask?.offer, true)
        XCTAssertEqual(card.ask?.questions.first?.options.map(\.title).first, "Group my invoices by client")
        XCTAssertNotNil(Talk.open(in: [card]))
        XCTAssertNil(Talk.waiting(in: [card]))
        XCTAssertEqual(card.ask?.questions.first?.detail?.hasPrefix("Tidy Up came with Lamp"), true)
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
            XCTAssertTrue(fm.fileExists(atPath: folder.appendingPathComponent("Sources/App.swift").path), name)
            let spec = try JSONDecoder().decode(IconSpec.self, from: Data(contentsOf: folder.appendingPathComponent("icon.json")))
            XCTAssertTrue(Icons.backgrounds.contains { $0.name == spec.background }, name)
            XCTAssertNotNil(AppDescription.description(at: folder.appendingPathComponent("about.json")), name)
            // Its icon ships drawn (StarterIconsTests), from the icon.json it has now.
            let icon = folder.appendingPathComponent(Starters.iconFolder)
            XCTAssertTrue(fm.fileExists(atPath: icon.appendingPathComponent("icon.png").path), "\(name) ships no icon")
            let drawn = try? JSONDecoder().decode(IconSpec.self, from: Data(contentsOf: icon.appendingPathComponent("icon.json")))
            XCTAssertEqual(drawn, spec, "\(name)'s icon was drawn from another icon.json: draw it again")
            // What the desk shows when the pointer rests on it, before anyone has opened it.
            XCTAssertNotNil(NSImage(contentsOf: folder.appendingPathComponent("preview.png")), "\(name) ships no preview.png")
            for owned in ["Sources/LampSupport.swift", "Widget/LampWidgetSupport.swift", "build.sh", "Package.swift"] {
                XCTAssertFalse(fm.fileExists(atPath: folder.appendingPathComponent(owned).path), "\(name) ships \(owned)")
            }
        }
    }
}
