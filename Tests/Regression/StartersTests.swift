import XCTest
import AppKit
@testable import Lamp

/// The wishes Lamp comes with are the first thing a new person uses, so each one must be whole: its own
/// starter.md read (a name, an offer and three short changes to suggest, where it lives and the commit this Lamp
/// ships), and in its tree at that commit APP.md for the agent and an icon with its artwork.
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
        // Choosing "more fun" for the whole game is a request the note goes with; one that scopes or refuses it isn't.
        XCTAssertTrue(GameFun.asked(Talk.message(for: try XCTUnwrap(card.ask), answers: ["Make it a lot more fun"])))
        XCTAssertTrue(GameFun.asked("make Dodge Lab more fun!", name: "Dodge Lab"))
        XCTAssertFalse(GameFun.asked("Make the menu more fun, leave gameplay unchanged"))
        XCTAssertFalse(GameFun.asked("Do not make it more fun; only fix the crash"))
        XCTAssertNil(Starters.parse("name: No front matter", folder: starters))
    }

    func testEveryStarterIsWhole() throws {
        let fm = FileManager.default
        let folders = try StarterTrees.folders()
        XCTAssertFalse(folders.isEmpty)
        for folder in folders {
            let name = folder.lastPathComponent
            let starter = try XCTUnwrap(Starters.read(folder), name)
            XCTAssertFalse(starter.offer.isEmpty, name)
            XCTAssertEqual(starter.tweaks.count, 3, name)
            for words in starter.tweaks.map(\.title) + [starter.offer] {
                XCTAssertLessThanOrEqual(words.split(separator: " ").count, 6, "\(name): \(words)")
            }
            for tweak in starter.tweaks {
                let symbol = try XCTUnwrap(tweak.symbol, "\(name): \(tweak.title) has no symbol")
                XCTAssertNotNil(NSImage(systemSymbolName: symbol, accessibilityDescription: nil), "\(name): \(symbol)")
            }
            // Where it lives and the commit this Lamp ships, which its tree is at (fetched detached, HEAD is the commit).
            let url = try XCTUnwrap(starter.repository, "\(name) names no repository")
            XCTAssertTrue(url.hasPrefix("https://github.com/\(Starters.account)/"), "\(name): \(url)")
            let commit = try XCTUnwrap(starter.commit, "\(name) names no commit")
            XCTAssertEqual(try String(contentsOf: starter.tree.appendingPathComponent(".git/HEAD"), encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines), commit, "\(name)'s tree isn't at its commit: run scripts/fetch-starters.sh")
            let tree = starter.tree
            XCTAssertTrue(fm.fileExists(atPath: tree.appendingPathComponent("APP.md").path), name)
            // A Mac app's code starts at App.swift; a game or a screen is its page (Lamp writes the Swift around it).
            let entry = starter.kind.target.recipe.language == .swift ? "Sources/App.swift" : "Web/index.html"
            XCTAssertTrue(fm.fileExists(atPath: tree.appendingPathComponent(entry).path), "\(name): no \(entry)")
            let spec = try JSONDecoder().decode(IconSpec.self, from: Data(contentsOf: tree.appendingPathComponent("icon.json")))
            XCTAssertTrue(Icons.backgrounds.contains { $0.name == spec.background }, name)
            let about = try XCTUnwrap(Starters.about(starter), name)
            // The desk shows it in large type beside the app's picture, in four lines at most.
            XCTAssertLessThanOrEqual(about.count, AppDescription.limit, "\(name): \(about)")
            // Its icon ships drawn (StarterIconsTests), from the icon.json it has now.
            let icon = Starters.iconFolder(of: starter)
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
            XCTAssertNotNil(NSImage(contentsOf: Starters.preview(of: starter)), "\(name) ships no preview.png")
        }
    }
}
