import XCTest
@testable import Lamp

/// A Mac app's desktop widget gets the app's data by asking the app over this Mac's own address, so the
/// widget must take answers only from its own app.
final class WidgetBuildTests: XCTestCase {
    private var root: URL?
    override func tearDown() { if let root { try? FileManager.default.removeItem(at: root) } }

    private func app() throws -> LampProject {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-widget-test-\(UUID().uuidString)")
        self.root = root
        return try Template.scaffold(name: "Tide Clock", in: root)
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
    private func run(_ command: String, in directory: URL) throws -> (status: Int32, output: String) {
        TestShell.run(command, in: directory)
    }

    /// The two halves Lamp writes, built as two small programs and run against each other and against a
    /// program that only pretends to be the app.
    func testTheWidgetTakesAnswersOnlyFromItsOwnApp() throws {
        let project = try app()
        try addWidget(to: project)
        try Template.writeOwnedFiles(for: project)
        let work = try XCTUnwrap(root).appendingPathComponent("halves")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let port = Template.widgetPort(for: project)

        // The app's half, cut out of LampSupport.swift, with the things it leans on there. Its link handling
        // (`LampWidgetLinks`) answers clicks on the widget, which a program run from the shell never gets.
        let support = try text("Sources/LampSupport.swift", in: project)
        let start = try XCTUnwrap(support.range(of: "enum LampWidget {"))
        let end = try XCTUnwrap(support.range(of: "#endif", range: start.upperBound..<support.endIndex))
        try ("""
        import Foundation
        import Network
        import CryptoKit
        import WidgetKit
        enum LampStore { static let folder = URL(fileURLWithPath: CommandLine.arguments[1]) }
        enum LampWidgetLinks { static let start: Void = () }
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
        s.settimeout(30)   # a widget that never asks fails the test rather than leaving this waiting
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
