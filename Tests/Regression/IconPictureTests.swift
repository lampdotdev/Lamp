import AppKit
import XCTest
@testable import Lamp

/// A picture the person gives becomes the wish's icon (`use_icon_picture`): a finished icon, an .icns among them, fills
/// the tile as it is, and anything else is taken as an object on the icon's background.
@MainActor
final class IconPictureTests: XCTestCase {
    private var roots: [URL] = []
    private let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    override func tearDown() {
        unsetenv("GIT_CONFIG_GLOBAL")
        for root in roots { try? FileManager.default.removeItem(at: root) }
    }

    /// Under the home folder, as Lamp's own git runs confined to it, with git's Mac-wide settings an empty file.
    private func newRoot() throws -> URL {
        let fm = FileManager.default
        let root = fm.homeDirectoryForCurrentUser.appendingPathComponent(".lamp-icon-picture-test-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        roots.append(root)
        let settings = fm.temporaryDirectory.appendingPathComponent("lamp-test-git-settings-\(UUID().uuidString)")
        roots.append(settings)
        try "".write(to: settings, atomically: true, encoding: .utf8)
        setenv("GIT_CONFIG_GLOBAL", settings.path, 1)
        return root
    }

    private func png(_ size: Int, _ draw: (NSRect) -> Void) throws -> Data {
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                                                 samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                                 bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        draw(NSRect(x: 0, y: 0, width: size, height: size))
        NSGraphicsContext.restoreGraphicsState()
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }

    /// Lamp's own .icns, a rounded square on Apple's grid with margins and a shadow, is a finished icon: cropped to the
    /// rounded square and used whole.
    func testAnIcnsFillsTheTile() throws {
        let icns = try Data(contentsOf: repo.appendingPathComponent("Resources/AppIcon.icns"))
        let made = try Icons.ownPicture(icns)
        XCTAssertTrue(made.fills)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: made.png))
        XCTAssertEqual(rep.pixelsWide, 1024)
        XCTAssertEqual(rep.pixelsHigh, 1024)
        XCTAssertGreaterThan(rep.colorAt(x: 512, y: 20)?.alphaComponent ?? 0, 0.5, "the margin above the rounded square is cropped away")
    }

    /// A square picture with nothing see-through fills the tile too.
    func testAnOpaqueSquareFillsTheTile() throws {
        let square = try png(300) { rect in NSColor.systemTeal.setFill(); rect.fill() }
        XCTAssertTrue(try Icons.ownPicture(square).fills)
    }

    /// A round logo on a see-through background is an object: kept as it is, cropped to what's in it.
    func testARoundLogoIsAnObject() throws {
        let logo = try png(400) { rect in
            NSColor.systemOrange.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 100, dy: 100)).fill()
        }
        let made = try Icons.ownPicture(logo)
        XCTAssertFalse(made.fills)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: made.png))
        XCTAssertEqual(rep.pixelsWide, 200, accuracy: 2)
    }

    func testAnUnreadableFileIsRefused() {
        XCTAssertThrowsError(try Icons.ownPicture(Data("not a picture".utf8)))
        XCTAssertThrowsError(try Icons.ownPicture(try png(64) { _ in }), "an empty picture")
    }

    /// `picture` is kept in icon.json, and its artwork is apart from a painting for the same subject.
    func testTheDesignRemembersItsPicture() throws {
        var spec = IconSpec(subject: "a lamp", symbol: "lamp.desk", background: "blue", tint: "#0A84FF")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("icon-picture-\(UUID().uuidString)")
        roots.append(dir)
        let app = LampProject(id: "picture-\(UUID().uuidString)", name: "Lamp Test", exe: "LampTest", dir: dir)
        let painted = Icons.artURL(app, spec: spec)
        spec.picture = true
        XCTAssertNotEqual(Icons.artURL(app, spec: spec), painted)
        XCTAssertTrue(spec.fillsTile)
        let read = try JSONDecoder().decode(IconSpec.self, from: JSONEncoder().encode(spec))
        XCTAssertEqual(read, spec)
        spec.picture = false
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(spec), as: UTF8.self).contains("picture"), "left out when false")
    }

    /// Called as Claude Code and Codex call it (`Store.mcp`; pi's extension posts the same arguments to `/agent/icon`):
    /// an attached .icns becomes the icon's artwork, and the design says it's the person's picture.
    func testTheAgentUsesAnAttachedIcns() async throws {
        let root = try newRoot()
        let made = try Template.scaffold(name: "Bites \(UUID().uuidString.prefix(6))", platform: .mac, in: root)
        let store = Store(testingAt: root)
        _ = await store.initRepo(made, message: "Scaffold")
        let wish = try XCTUnwrap(store.current(made))
        if Icons.load(wish) == nil { Icons.save(IconSpec(subject: "a lamp", symbol: "lamp.desk", background: "blue", tint: "#0A84FF"), for: wish) }
        let attachments = wish.dir.appendingPathComponent("Attachments")
        try FileManager.default.createDirectory(at: attachments, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: repo.appendingPathComponent("Resources/AppIcon.icns"),
                                         to: attachments.appendingPathComponent("Mine.icns"))
        _ = try XCTUnwrap(store.begin(wish))

        func call(_ arguments: [String: Any]) async throws -> (text: String, failed: Bool) {
            let body = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 1, "method": "tools/call",
                                                                   "params": ["name": "use_icon_picture", "arguments": arguments]])
            let (_, answer) = await store.mcp(body, for: wish, fileTools: false)
            let result = try XCTUnwrap(answer["result"] as? [String: Any])
            let text = (result["content"] as? [[String: Any]])?.compactMap { $0["text"] as? String }.joined() ?? ""
            return (text, result["isError"] as? Bool == true)
        }

        let missing = try await call(["path": "Attachments/Nothing.icns"])
        XCTAssertTrue(missing.failed, missing.text)
        let outside = try await call(["path": "../../etc/hosts"])
        XCTAssertTrue(outside.failed, outside.text)

        let used = try await call(["path": "Attachments/Mine.icns"])
        XCTAssertFalse(used.failed, used.text)
        let spec = try XCTUnwrap(Icons.load(wish))
        XCTAssertTrue(spec.picture)
        guard case .picture = Icons.artwork(wish, spec: spec) else { return XCTFail("the picture is the icon's artwork") }
        store.finish(wish)
    }

    /// The same tool for every engine: in the shared definitions, pi's extension and list, Claude Code's allowed tools,
    /// the prompt's rule, and the chat's words for it.
    func testEveryEngineHasIt() throws {
        let json = try Data(contentsOf: repo.appendingPathComponent("Resources/lamp-tools.json"))
        let tools = try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [[String: Any]])
        XCTAssertTrue(tools.contains { $0["name"] as? String == "use_icon_picture" })
        let extensionCode = try String(contentsOf: repo.appendingPathComponent("Resources/lamp-tools.ts"), encoding: .utf8)
        XCTAssertTrue(extensionCode.contains("pi.registerTool(useIconPicture)"))
        let engines = try String(contentsOf: repo.appendingPathComponent("Sources/Lamp/Engines.swift"), encoding: .utf8)
        XCTAssertTrue(engines.contains("mcp__lamp__use_icon_picture"))
        let agent = try String(contentsOf: repo.appendingPathComponent("Sources/Lamp/Agent.swift"), encoding: .utf8)
        // The icon's address reaches every engine's environment from where it's set up for all of them.
        XCTAssertTrue(engines.contains("LAMP_ICON_URL") || agent.contains("LAMP_ICON_URL"))
        XCTAssertTrue(agent.contains(",use_icon_picture,"))
        XCTAssertTrue(Agent.Rules.icon.contains("`use_icon_picture`"))
        XCTAssertEqual(ToolCall("use_icon_picture").action, .icon)
    }
}
