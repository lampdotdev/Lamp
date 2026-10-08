import XCTest
@testable import Lamp

/// The review of a shared app opens with the app itself: the description and icon its file carries.
final class SharedAppAboutTests: XCTestCase {
    private var folder: URL?
    override func tearDown() { if let folder { try? FileManager.default.removeItem(at: folder) } }

    private func package(files: [String: Data]) throws -> Sharing.Package {
        let fm = FileManager.default
        let folder = fm.temporaryDirectory.appendingPathComponent("lamp-about-\(UUID().uuidString)")
        self.folder = folder
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        for (name, data) in files { try data.write(to: folder.appendingPathComponent(name)) }
        return Sharing.Package(name: "Tally", folder: folder, sources: [], attachments: [], fileCount: files.count)
    }

    func testDescriptionIsWhatTheAppSaysItDoes() {
        let about = """
        # Tally

        A macOS SwiftUI app built and live-edited with Lamp.

        ## What it does
        Counts things with **plus** and `minus` buttons,
        and remembers the count.

        A second paragraph of detail.

        ## Structure
        - `Sources/App.swift`: entry point and window.
        """
        XCTAssertEqual(Sharing.description(fromAbout: about), "Counts things with plus and minus buttons, and remembers the count.")
    }

    func testDescriptionFallsBackToTheOpeningLine() {
        XCTAssertEqual(Sharing.description(fromAbout: "# Tally\n\nA counter with plus and minus buttons.\n"), "A counter with plus and minus buttons.")
    }

    /// An app nobody described yet says nothing, rather than Lamp's own words for a new app.
    func testNewAppHasNoDescription() {
        XCTAssertNil(Sharing.description(fromAbout: Template.appMd.replacingOccurrences(of: "{{NAME}}", with: "Tally")))
        XCTAssertNil(Sharing.description(fromAbout: ""))
    }

    func testLongDescriptionIsCut() {
        let text = Sharing.description(fromAbout: "## What it does\n" + String(repeating: "word ", count: 200))
        XCTAssertEqual(text?.count, 280)
        XCTAssertEqual(text?.last, "…")
    }

    func testIconIsDrawnFromTheFile() async throws {
        let spec = ##"{"subject": "a tally counter", "symbol": "plusminus", "background": "blue", "tint": "#FFFFFF"}"##
        let image = await Sharing.icon(of: try package(files: ["icon.json": Data(spec.utf8)]))
        XCTAssertEqual(image?.size, NSSize(width: 256, height: 256))
    }

    /// A file without an icon keeps the plain one; artwork that isn't a picture is left out, not fatal.
    func testMissingOrBrokenIconParts() async throws {
        let none = await Sharing.icon(of: try package(files: [:]))
        XCTAssertNil(none)
        let spec = ##"{"subject": "a tally counter", "symbol": "plusminus", "background": "blue", "tint": "#FFFFFF"}"##
        let image = await Sharing.icon(of: try package(files: ["icon.json": Data(spec.utf8), "icon-art.png": Data([1, 2, 3])]))
        XCTAssertNotNil(image)
    }
}
