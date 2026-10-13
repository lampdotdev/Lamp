import XCTest
@testable import Lamp

/// A Mac app's desktop widget: Swift in the app's Widget folder becomes a second program in Lamp's build, put
/// into the app as a widget extension and signed by itself, sandboxed, inside the unsandboxed app.
final class WidgetBuildTests: XCTestCase {
    private var root: URL?
    override func tearDown() { if let root { try? FileManager.default.removeItem(at: root) } }

    private func app(_ name: String = "Tide Clock", platform: Platform = .mac) throws -> LampProject {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-widget-test-\(UUID().uuidString)")
        self.root = root
        return try Template.scaffold(name: name, platform: platform, in: root)
    }

    private func addWidget(to project: LampProject) throws {
        let folder = project.dir.appendingPathComponent("Widget")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Self.widgetSwift.write(to: folder.appendingPathComponent("Widget.swift"), atomically: true, encoding: .utf8)
    }

    private func text(_ path: String, in project: LampProject) throws -> String {
        try String(contentsOf: project.dir.appendingPathComponent(path), encoding: .utf8)
    }

    @discardableResult
    private func run(_ command: String, in directory: URL, env: [String: String] = [:]) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.currentDirectoryURL = directory
        process.environment = ProcessInfo.processInfo.environment.merging(env) { $1 }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    // MARK: - What Lamp writes

    func testAnAppWithoutAWidgetBuildsAsBefore() throws {
        let project = try app()
        XCTAssertFalse(Template.hasWidget(project))
        let package = try text("Package.swift", in: project)
        let build = try text("build.sh", in: project)
        XCTAssertFalse(package.contains("Widget"))
        XCTAssertFalse(package.contains("unsafeFlags"))
        XCTAssertFalse(build.contains("PlugIns"))
        XCTAssertFalse(build.contains("entitlements"))
    }

    func testSwiftInTheWidgetFolderAddsTheSecondProgram() throws {
        let project = try app()
        // An empty folder, or one with no Swift in it, is not a widget: SwiftPM refuses a target with no code.
        try FileManager.default.createDirectory(at: project.dir.appendingPathComponent("Widget"), withIntermediateDirectories: true)
        try "notes".write(to: project.dir.appendingPathComponent("Widget/README.md"), atomically: true, encoding: .utf8)
        XCTAssertFalse(Template.hasWidget(project))

        try addWidget(to: project)
        XCTAssertTrue(Template.hasWidget(project))
        try Template.writeOwnedFiles(for: project)
        let package = try text("Package.swift", in: project)
        XCTAssertTrue(package.contains(#".executableTarget(name: "TideClock", path: "Sources")"#))
        XCTAssertTrue(package.contains(#".executableTarget(name: "TideClockWidget", path: "Widget""#))
        XCTAssertTrue(package.contains("_NSExtensionMain"))
        let build = try text("build.sh", in: project)
        XCTAssertTrue(build.contains(#"WIDGET="$APP/Contents/PlugIns/TideClockWidget.appex""#))
        XCTAssertTrue(build.contains("<string>\(project.bundleID).widget</string>"))
        XCTAssertTrue(build.contains("com.apple.widgetkit-extension"))
        // The widget is signed before the app around it, or the app's signature wouldn't cover it.
        let widgetSigned = try XCTUnwrap(build.range(of: #"codesign --force -s - --entitlements "build/TideClockWidget.entitlements" "$WIDGET""#))
        let appSigned = try XCTUnwrap(build.range(of: #"codesign --force -s - "$APP""#))
        XCTAssertLessThan(widgetSigned.lowerBound, appSigned.lowerBound)

        // Deleting the widget's code takes the second program away again.
        try FileManager.default.removeItem(at: project.dir.appendingPathComponent("Widget/Widget.swift"))
        try Template.writeOwnedFiles(for: project)
        XCTAssertFalse(try text("Package.swift", in: project).contains("Widget"))
        XCTAssertFalse(try text("build.sh", in: project).contains("PlugIns"))
    }

    func testAChangeToTheWidgetNeedsABuild() throws {
        let project = try app()
        let before = Runtime.fingerprint(project)
        try addWidget(to: project)
        let added = Runtime.fingerprint(project)
        XCTAssertNotEqual(before, added)
        try (Self.widgetSwift + "\n// changed").write(to: project.dir.appendingPathComponent("Widget/Widget.swift"), atomically: true, encoding: .utf8)
        XCTAssertNotEqual(added, Runtime.fingerprint(project))
    }

    // MARK: - Signing

    func testTheWidgetIsSandboxedWithNoExceptions() throws {
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(Template.widgetEntitlementsPlist.utf8), format: nil) as? [String: Any])
        // Sandboxed, and allowed to connect out: that is all. No app group (macOS refuses one to a certificate
        // with no team ID) and no exception to the sandbox: the widget asks its app for data instead.
        XCTAssertEqual(plist["com.apple.security.app-sandbox"] as? Bool, true)
        XCTAssertEqual(plist["com.apple.security.network.client"] as? Bool, true)
        XCTAssertEqual(Set(plist.keys), ["com.apple.security.app-sandbox", "com.apple.security.network.client"])
        XCTAssertFalse(Template.widgetEntitlementsPlist.contains("temporary-exception"))
        XCTAssertTrue(Agent.Rules.widget.contains(Template.WidgetSharing.rule))
    }

    // MARK: - The app's data in the widget

    func testAppAndWidgetAreBuiltWithTheSamePortAndSecret() throws {
        let project = try app()
        try addWidget(to: project)
        try Template.writeOwnedFiles(for: project)
        let port = Template.widgetPort(for: project)
        XCTAssertTrue((49_152..<65_152).contains(port))
        XCTAssertEqual(port, Template.widgetPort(for: project))
        let token = Template.widgetToken(for: project)
        XCTAssertEqual(token, Template.widgetToken(for: project))   // kept, so a rebuilt app still answers a placed widget
        XCTAssertNotEqual(token, Template.token(for: project))      // not the secret the app shows Lamp's gateway
        for file in ["Sources/LampSupport.swift", "Widget/LampWidgetSupport.swift"] {
            let code = try text(file, in: project)
            XCTAssertTrue(code.contains("private static let firstPort: UInt16 = \(port)\n"), file)
            XCTAssertTrue(code.contains("private static let token = \"\(token)\"\n"), file)
            XCTAssertFalse(code.contains("{{WIDGET"), file)
        }
        // Another app gets another port and another secret.
        let other = try Template.scaffold(name: "Moon Phase", in: try XCTUnwrap(root))
        XCTAssertNotEqual(Template.widgetPort(for: other), port)
        XCTAssertNotEqual(Template.widgetToken(for: other), token)
    }

    func testLampsFileInTheWidgetFolderIsNotAWidget() throws {
        let project = try app()
        // No widget, no file: an app that never asked for one keeps its one program.
        XCTAssertFalse(FileManager.default.fileExists(atPath: project.dir.appendingPathComponent("Widget").path))
        try addWidget(to: project)
        try Template.writeOwnedFiles(for: project)
        XCTAssertTrue(FileManager.default.fileExists(atPath: project.dir.appendingPathComponent("Widget/LampWidgetSupport.swift").path))
        // The agent takes its widget away: Lamp's file alone doesn't keep the second program.
        try FileManager.default.removeItem(at: project.dir.appendingPathComponent("Widget/Widget.swift"))
        XCTAssertFalse(Template.hasWidget(project))
        try Template.writeOwnedFiles(for: project)
        XCTAssertFalse(try text("Package.swift", in: project).contains("Widget"))
    }

    func testTheAgentIsToldHowTheWidgetGetsTheAppsData() {
        let mac = Agent.systemPrompt
        XCTAssertTrue(mac.contains("LampWidget.share("))
        XCTAssertTrue(mac.contains("LampWidget.read("))
        XCTAssertFalse(mac.contains("isn't possible yet"))
        // The same calls on an iPhone, over a shared folder instead of the Mac's connection.
        XCTAssertTrue(Agent.iPhonePrompt(for: .iphone).contains("LampWidget.share("))
    }

    func testTheWidgetIsSignedBeforeTheApp() {
        XCTAssertEqual(AppSigning.command(adHoc: true, widget: false), #"codesign --force -s - "$LAMP_APP" 2>&1"#)
        XCTAssertEqual(AppSigning.command(adHoc: false, widget: false),
                       #"codesign --force --keychain "$LAMP_KEYCHAIN" -s "$LAMP_IDENTITY" "$LAMP_APP" 2>&1"#)
        XCTAssertEqual(AppSigning.command(adHoc: false, widget: true),
                       #"codesign --force --keychain "$LAMP_KEYCHAIN" -s "$LAMP_IDENTITY" --entitlements "$LAMP_WIDGET_ENTITLEMENTS" "$LAMP_WIDGET" 2>&1 && "#
                       + #"codesign --force --keychain "$LAMP_KEYCHAIN" -s "$LAMP_IDENTITY" "$LAMP_APP" 2>&1"#)
    }

    // MARK: - The connection between them

    /// The two halves Lamp writes, built as two small programs and run against each other and against a
    /// program that only pretends to be the app.
    func testTheWidgetTakesAnswersOnlyFromItsOwnApp() throws {
        let project = try app()
        try addWidget(to: project)
        try Template.writeOwnedFiles(for: project)
        let work = try XCTUnwrap(root).appendingPathComponent("halves")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let port = Template.widgetPort(for: project)

        // The app's half, cut out of LampSupport.swift, with the two things it leans on there.
        let support = try text("Sources/LampSupport.swift", in: project)
        let start = try XCTUnwrap(support.range(of: "enum LampWidget {"))
        let end = try XCTUnwrap(support.range(of: "#endif", range: start.upperBound..<support.endIndex))
        try ("""
        import Foundation
        import Network
        import CryptoKit
        import WidgetKit
        enum LampStore { static let folder = URL(fileURLWithPath: CommandLine.arguments[1]) }
        struct Tide: Codable { var height: Double }
        \(support[start.lowerBound..<end.lowerBound])
        LampWidget.share(Tide(height: 2.5), as: "tide")
        RunLoop.main.run(until: Date().addingTimeInterval(Double(CommandLine.arguments[2])!))
        """).write(to: work.appendingPathComponent("app.swift"), atomically: true, encoding: .utf8)
        // The widget's half as Lamp wrote it, asked once.
        try ("""
        import Foundation
        struct Tide: Codable { var height: Double }
        LampWidget.read(Tide.self, from: "tide") { tide in
            print(tide.map { "height \\($0.height)" } ?? "nothing")
            exit(0)
        }
        RunLoop.main.run(until: Date().addingTimeInterval(20))
        """).write(to: work.appendingPathComponent("main.swift"), atomically: true, encoding: .utf8)
        try text("Widget/LampWidgetSupport.swift", in: project).write(to: work.appendingPathComponent("half.swift"), atomically: true, encoding: .utf8)
        // Something else on the app's port, answering the way the app did before answers were signed, and
        // again with a signature made without the secret.
        try ("""
        import socket, sys
        s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1); s.bind(("127.0.0.1", \(port))); s.listen(5)
        print("listening", flush=True)
        for reply in [b'ok\\n{"height":666}', b'ok ' + b'0' * 64 + b'\\n{"height":666}']:
            c, _ = s.accept(); c.recv(4096); c.sendall(reply); c.close()
        """).write(to: work.appendingPathComponent("pretender.py"), atomically: true, encoding: .utf8)

        // The widget keeps the last answer in its own settings, which macOS files under the program's name:
        // a name of its own for this run, cleared afterwards, keeps one run's answer out of the next.
        let widget = "lamp-widget-test-\(UUID().uuidString)"
        defer { _ = try? run("defaults delete \(widget); rm -f ~/Library/Preferences/\(widget).plist", in: work) }
        let built = try run(Shell.compatibleSDK + "xcrun swiftc -O -o \(widget) half.swift main.swift 2>&1; xcrun swiftc -O -o app app.swift 2>&1", in: work)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: work.appendingPathComponent("app").path), String(built.output.suffix(2000)))
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: work.appendingPathComponent(widget).path), String(built.output.suffix(2000)))

        // Nobody to ask, nothing kept: nothing.
        XCTAssertEqual(try run("./\(widget)", in: work).output, "nothing\n")
        // A pretender on the port, unsigned and then wrongly signed: still nothing, and nothing kept from it.
        XCTAssertEqual(try run("python3 pretender.py > pretender.log & sleep 1; ./\(widget); ./\(widget); wait", in: work).output, "nothing\nnothing\n")
        // The app itself: its answer is taken.
        XCTAssertEqual(try run("./app \"$PWD/store\" 4 & sleep 1.5; ./\(widget); wait", in: work).output, "height 2.5\n")
        // The app's own question, arriving in pieces as a connection may deliver it, is still answered whole;
        // one that never ends its line, longer than any real one, gets nothing.
        try ("""
        import hashlib, hmac, socket, sys, time
        secret = b"\(Template.widgetToken(for: project))"
        def sign(*parts): return hmac.new(secret, "\\n".join(parts).encode(), hashlib.sha256).hexdigest()
        def ask(pieces):
            for port in range(\(port), \(port) + 8):   # the app takes the next port when its own is still busy, as the widget knows
                try: s = socket.create_connection(("127.0.0.1", port), timeout=5); break
                except ConnectionRefusedError: pass
            for piece in pieces:
                s.sendall(piece); time.sleep(0.3)
            reply = b""
            while True:
                more = s.recv(4096)
                if not more: break
                reply += more
            return reply.decode()
        line = ("n1 " + sign("ask", "n1", "tide") + " tide\\n").encode()
        head, _, json = ask([line[:5], line[5:40], line[40:]]).partition("\\n")
        print("pieces:", head == "ok " + sign("answer", "n1", "tide", json), json)
        print("endless:", repr(ask([b"x" * 5000])))
        """).write(to: work.appendingPathComponent("pieces.py"), atomically: true, encoding: .utf8)
        XCTAssertEqual(try run("./app \"$PWD/store\" 6 & sleep 1.5; python3 pieces.py 2>&1; wait", in: work).output,
                       "pieces: True {\"height\":2.5}\nendless: ''\n")
        // The app gone and a pretender in its place: the widget shows what the app said last, not the pretender's.
        XCTAssertEqual(try run("python3 pretender.py > pretender.log & sleep 1; ./\(widget); ./\(widget); wait", in: work).output, "height 2.5\nheight 2.5\n")
    }

    // MARK: - What the agent is told

    func testOnlyAMacAppIsToldItCanHaveAWidget() {
        let mac = Agent.systemPrompt
        XCTAssertTrue(mac.contains("Widget/Widget.swift"))
        // How to add it is the card's to say (WidgetCard), so the agent is told not to.
        XCTAssertTrue(mac.contains("Lamp shows the user a card"))
        XCTAssertFalse(mac.contains("Edit Widgets"))
        XCTAssertTrue(mac.contains("containerBackground(for: .widget)"))
        XCTAssertTrue(mac.contains("(and a widget's code in Widget/)"))
        // An iPhone app's widgets are the home screen's, told in their own rule (PhoneWidgetTests).
        for family in [DeviceFamily.iphone, .ipad] {
            let phone = Agent.iPhonePrompt(for: family)
            XCTAssertFalse(phone.contains("Edit Widgets"))
            XCTAssertFalse(phone.contains("widget for the desktop"))
            XCTAssertFalse(phone.contains("Not possible yet: widgets"))
        }
    }

    // MARK: - A real build

    /// The whole way through with the real tools: SwiftPM builds both programs, build.sh makes the bundle, and
    /// Lamp's signing command, here ad hoc as when there's no certificate, leaves a widget macOS would accept.
    func testAnAppWithAWidgetBuildsAndSigns() throws {
        let project = try app()
        try addWidget(to: project)
        try Template.writeOwnedFiles(for: project)
        let built = try run(Shell.compatibleSDK + "./build.sh", in: project.dir)
        XCTAssertEqual(built.status, 0, String(built.output.suffix(3000)))

        let widget = Template.widgetURL(in: project.builtURL, of: project)
        XCTAssertEqual(widget.path, project.builtURL.path + "/Contents/PlugIns/TideClockWidget.appex")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: widget.appendingPathComponent("Contents/MacOS/TideClockWidget").path))
        let info = try XCTUnwrap(NSDictionary(contentsOf: widget.appendingPathComponent("Contents/Info.plist")) as? [String: Any])
        XCTAssertEqual(info["CFBundleIdentifier"] as? String, Template.widgetBundleID(for: project))
        XCTAssertEqual(info["CFBundlePackageType"] as? String, "XPC!")
        XCTAssertEqual(info["CFBundleDisplayName"] as? String, "Tide Clock")
        XCTAssertEqual((info["NSExtension"] as? [String: Any])?["NSExtensionPointIdentifier"] as? String, "com.apple.widgetkit-extension")
        XCTAssertNotNil(Int(info["CFBundleVersion"] as? String ?? ""))

        // Signed again the way an install does, with the entitlements Lamp writes itself.
        let entitlements = project.dir.appendingPathComponent(".lamp/widget-entitlements.plist")
        try Template.widgetEntitlementsPlist.write(to: entitlements, atomically: true, encoding: .utf8)
        let signed = try run(AppSigning.command(adHoc: true, widget: true), in: project.dir,
                             env: ["LAMP_APP": project.builtURL.path, "LAMP_WIDGET": widget.path, "LAMP_WIDGET_ENTITLEMENTS": entitlements.path])
        XCTAssertEqual(signed.status, 0, signed.output)
        let verified = try run("codesign --verify --deep --strict \"$APP\" 2>&1", in: project.dir, env: ["APP": project.builtURL.path])
        XCTAssertEqual(verified.status, 0, verified.output)
        let widgetHas = try run("codesign -d --entitlements - --xml \"$CODE\" 2>/dev/null", in: project.dir, env: ["CODE": widget.path]).output
        XCTAssertTrue(widgetHas.contains("com.apple.security.app-sandbox"), widgetHas)
        // The app itself stays unsandboxed: everything a Lamp app does (its files, Lamp's gateway) depends on it.
        let appHas = try run("codesign -d --entitlements - --xml \"$CODE\" 2>/dev/null", in: project.dir, env: ["CODE": project.builtURL.path]).output
        XCTAssertFalse(appHas.contains("app-sandbox"), appHas)
    }

    static let widgetSwift = """
    import WidgetKit
    import SwiftUI

    struct Tide: Codable { var height: Double }
    struct Entry: TimelineEntry { let date: Date; var tide: Tide? }

    struct Provider: TimelineProvider {
        func placeholder(in context: Context) -> Entry { Entry(date: .now) }
        func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) { completion(Entry(date: .now)) }
        func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
            LampWidget.read(Tide.self, from: "tide") { tide in
                completion(Timeline(entries: [Entry(date: .now, tide: tide)], policy: .after(.now.addingTimeInterval(900))))
            }
        }
    }

    @main
    struct TideWidget: Widget {
        var body: some WidgetConfiguration {
            StaticConfiguration(kind: "tide", provider: Provider()) { entry in
                Text(entry.date, style: .time)
                    .containerBackground(for: .widget) { Color.teal }
            }
            .configurationDisplayName("Tide Clock")
            .description("The time.")
            .supportedFamilies([.systemSmall])
        }
    }

    """
}
