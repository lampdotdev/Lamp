import XCTest
@testable import Lamp

/// Asking for a widget gives the widget and nothing that looks like an app: the app that has to carry it
/// has no window and no Dock icon, and the chat has one card saying how to add the widget, then that it's there.
final class WidgetOnlyTests: XCTestCase {
    private var root: URL?
    override func tearDown() { if let root { try? FileManager.default.removeItem(at: root) } }

    private static let carrier = """
    import SwiftUI

    @main
    struct MainApp: SwiftUI.App {
        var body: some SwiftUI.Scene { LampWidgetOnly() }
    }

    """

    private func app(_ name: String = "Countdown") throws -> LampProject {
        let root = self.root ?? FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("lamp-widget-only-\(UUID().uuidString)")
        self.root = root
        return try Template.scaffold(name: name, in: root)
    }

    private func write(_ text: String, to path: String, in project: LampProject) throws {
        let url = project.dir.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    /// As the agent leaves an app that is only a widget.
    private func makeWidgetOnly(_ project: LampProject) throws {
        try write(WidgetBuildTests.widgetSwift.replacingOccurrences(of: "LampWidget.read(Tide.self, from: \"tide\") { tide in", with: "do { let tide: Tide? = nil"),
                  to: "Widget/Widget.swift", in: project)
        try write(Self.carrier, to: "Sources/App.swift", in: project)
        try FileManager.default.removeItem(at: project.dir.appendingPathComponent("Sources/ContentView.swift"))
        try Template.writeOwnedFiles(for: project)
    }

    private func text(_ path: String, in project: LampProject) throws -> String {
        try String(contentsOf: project.dir.appendingPathComponent(path), encoding: .utf8)
    }

    // MARK: - Which apps are only a widget

    func testAnAppIsOnlyItsWidgetWhenItsCodeIsThatOneScene() throws {
        let project = try app()
        XCTAssertFalse(Template.isWidgetOnly(project))
        // An app with a window and a widget is an app.
        try write(WidgetBuildTests.widgetSwift, to: "Widget/Widget.swift", in: project)
        XCTAssertFalse(Template.isWidgetOnly(project))
        // The scene with no widget to carry is not one either.
        let other = try app("Plain")
        try write(Self.carrier, to: "Sources/App.swift", in: other)
        XCTAssertFalse(Template.isWidgetOnly(other))
        // Both together: the app is only its widget.
        try write(Self.carrier, to: "Sources/App.swift", in: project)
        XCTAssertTrue(Template.isWidgetOnly(project))
        // Lamp's own support file, which defines the scene, doesn't make every app one.
        XCTAssertTrue(try text("Sources/LampSupport.swift", in: project).contains("struct LampWidgetOnly: Scene"))
    }

    /// The scene only counts where it runs: named in a comment or a string, the app still has its window.
    func testASceneNamedInACommentOrAStringIsNotTheAppsScene() throws {
        let project = try app()
        try write(WidgetBuildTests.widgetSwift, to: "Widget/Widget.swift", in: project)
        for mention in ["// Previously: LampWidgetOnly()", "/* was\n   LampWidgetOnly() */", "let note = \"LampWidgetOnly()\"",
                        "let long = \"\"\"\n    LampWidgetOnly()\n    \"\"\"",
                        "/* outer /* inner */ LampWidgetOnly() */", "let raw = #\"a \" LampWidgetOnly() \"#",
                        "let raw = ##\"\"\"\n \"\"\" LampWidgetOnly() \n\"\"\"##", "let s = \"quote \\\" LampWidgetOnly()\"",
                        "let raw = #\"escaped \\#\" LampWidgetOnly() \"#", "let raw = #\"plain backslash \\\"# + \"LampWidgetOnly()\""] {
            try write("import SwiftUI\n\(mention)\n@main struct MainApp: App { var body: some Scene { WindowGroup { Text(\"hi\") } } }\n",
                      to: "Sources/App.swift", in: project)
            XCTAssertFalse(Template.isWidgetOnly(project), mention)
        }
        // What's left is the code: text around a comment or a string is kept.
        XCTAssertEqual(Template.code(in: "a /* b /* c */ d */ e // f\ng \"h\" i #\"j\"k\"# l"), "a   e \ng \"\" i \"\" l")
        // With a comment beside it, the real scene still counts.
        try write("import SwiftUI\n// only a widget\n@main struct MainApp: App { var body: some Scene { LampWidgetOnly() } }\n", to: "Sources/App.swift", in: project)
        XCTAssertTrue(Template.isWidgetOnly(project))
    }

    func testTheCardGoesWhenTheWidgetDoes() throws {
        let project = try app()
        XCTAssertFalse(WidgetCard.isShown(for: project))
        try write(WidgetBuildTests.widgetSwift, to: "Widget/Widget.swift", in: project)
        try Template.writeOwnedFiles(for: project)
        XCTAssertTrue(WidgetCard.isShown(for: project))
        // The widget is taken away: Lamp's own file may linger in the folder, and the card still goes.
        try FileManager.default.removeItem(at: project.dir.appendingPathComponent("Widget/Widget.swift"))
        XCTAssertFalse(WidgetCard.isShown(for: project))
    }

    /// A widget recorded as placed can be taken off the desktop: the app is asked again all the same.
    func testAWidgetOnlyAppIsAskedAgainWhateverItSaidLast() {
        XCTAssertTrue(WidgetCard.asksAgain(hasCard: true, widgetOnly: true, busy: false))
        XCTAssertFalse(WidgetCard.asksAgain(hasCard: false, widgetOnly: true, busy: false))
        XCTAssertFalse(WidgetCard.asksAgain(hasCard: true, widgetOnly: false, busy: false))   // a real app says for itself while it runs
        XCTAssertFalse(WidgetCard.asksAgain(hasCard: true, widgetOnly: true, busy: true))     // a turn has it
    }

    func testOnlyAWidgetOnlyAppIsKeptOutOfTheDock() throws {
        let project = try app()
        try write(WidgetBuildTests.widgetSwift, to: "Widget/Widget.swift", in: project)
        try Template.writeOwnedFiles(for: project)
        XCTAssertFalse(try text("build.sh", in: project).contains("LSUIElement"))
        try write(Self.carrier, to: "Sources/App.swift", in: project)
        try Template.writeOwnedFiles(for: project)
        XCTAssertTrue(try text("build.sh", in: project).contains("<key>LSUIElement</key><true/>"))
        // An app without a widget never is.
        XCTAssertFalse(Template.buildSh(widget: false, widgetOnly: true).contains("LSUIElement"))
    }

    /// The real tools: an app that is only its widget builds, and the built app says it has no Dock icon.
    func testAWidgetOnlyAppBuilds() throws {
        let project = try app()
        try makeWidgetOnly(project)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", Shell.compatibleSDK + "./build.sh 2>&1 | tail -30"]
        process.currentDirectoryURL = project.dir
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        let info = try XCTUnwrap(NSDictionary(contentsOf: project.builtURL.appendingPathComponent("Contents/Info.plist")) as? [String: Any], output)
        XCTAssertEqual(info["LSUIElement"] as? Bool, true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: Template.widgetURL(in: project.builtURL, of: project).path))
    }

    // MARK: - The card

    func testAChatGetsOneCardHoweverManyBuilds() {
        XCTAssertTrue(WidgetCard.isNeeded(after: []))
        XCTAssertTrue(WidgetCard.isNeeded(after: [LogLine(kind: .status, text: "Countdown is ready")]))
        XCTAssertFalse(WidgetCard.isNeeded(after: [LogLine(kind: .widget, text: ""), LogLine(kind: .status, text: "Countdown is ready")]))
    }

    func testTheCardSaysHowToAddTheWidgetUntilItIsThere() throws {
        let project = try app()
        XCTAssertEqual(WidgetCard.title("Countdown"), "Countdown’s widget")
        XCTAssertEqual(WidgetCard.status("Countdown", placed: false), "Right-click the desktop, choose Edit Widgets, then pick Countdown.")
        XCTAssertEqual(WidgetCard.status("Countdown", placed: true), "On your desktop")
        // Placed or not is what the app last told Lamp, in its runtime folder: nothing yet means not.
        XCTAssertFalse(WidgetCard.isPlaced(project))
        try write("0", to: ".lamp/runtime/widget-placed", in: project)
        XCTAssertFalse(WidgetCard.isPlaced(project))
        try write("1\n", to: ".lamp/runtime/widget-placed", in: project)
        XCTAssertTrue(WidgetCard.isPlaced(project))
        // A new build starts from not knowing.
        WidgetCard.forget(project)
        XCTAssertFalse(WidgetCard.isPlaced(project))
    }

    // MARK: - What the agent is told

    func testTheAgentIsToldToGiveOnlyTheWidgetAndSayLittle() {
        let mac = Agent.systemPrompt
        XCTAssertTrue(mac.contains("LampWidgetOnly()"))
        XCTAssertTrue(mac.contains("delete Sources/ContentView.swift"))
        XCTAssertTrue(mac.contains("two sentences at most"))
        XCTAssertTrue(mac.contains("never explain how to add it"))
        // A widget that needs the app's data still gets a real app, in the menu bar.
        XCTAssertTrue(mac.contains("lives in the menu bar (`LampMenuBar`, with its Quit button)"))
        XCTAssertFalse(Agent.iPhonePrompt(for: .iphone).contains("LampWidgetOnly"))
    }
}
