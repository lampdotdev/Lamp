import XCTest
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
          - Group my invoices by client
          - 'Never touch design files'
        ---
        Anything after it is ignored.
        """
        let starter = try XCTUnwrap(Starters.parse(text, folder: starters))
        XCTAssertEqual(starter.name, "Tidy Up")
        XCTAssertEqual(starter.offer, "Make it tidy your way")
        XCTAssertEqual(starter.tweaks, ["Group my invoices by client", "Never touch design files"])
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
            for tweak in starter.tweaks + [starter.offer] {
                XCTAssertLessThanOrEqual(tweak.split(separator: " ").count, 6, "\(name): \(tweak)")
            }
            XCTAssertTrue(fm.fileExists(atPath: folder.appendingPathComponent("APP.md").path), name)
            XCTAssertTrue(fm.fileExists(atPath: folder.appendingPathComponent("Sources/App.swift").path), name)
            let spec = try JSONDecoder().decode(IconSpec.self, from: Data(contentsOf: folder.appendingPathComponent("icon.json")))
            XCTAssertTrue(Icons.backgrounds.contains { $0.name == spec.background }, name)
            XCTAssertNotNil(AppDescription.description(at: folder.appendingPathComponent("about.json")), name)
            for owned in ["Sources/LampSupport.swift", "Widget/LampWidgetSupport.swift", "build.sh", "Package.swift"] {
                XCTAssertFalse(fm.fileExists(atPath: folder.appendingPathComponent(owned).path), "\(name) ships \(owned)")
            }
        }
    }
}
