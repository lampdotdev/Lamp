import XCTest
@testable import Lamp

/// A Mac app writes its front window as text with `LampScreen` in LampSupport.swift, and Lamp writes an
/// iPhone's screen with `Simulator.Driver`: two copies of one format, since the app's runs in another process.
/// Here the app's copy is cut out of the template, compiled and run, so that it still says what Lamp's says.
@MainActor
final class MacScreenTextTests: XCTestCase {
    private typealias Item = Simulator.Driver.Item

    private static let frame = CGRect(x: 16, y: 100, width: 200, height: 40)

    /// The same window as each copy's items: Lamp's are by AX role, the app's by the role's word.
    private static let items: [(role: String, word: String, label: String, value: String, selected: Bool, disabled: Bool)] = [
        ("AXHeading", "heading", "Groceries", "", false, false),
        ("AXTextField", "text field", "New item", "Milk", false, false),
        ("AXButton", "button", "Add", "", false, true),
        ("AXCheckBox", "switch", "Reminders", "1", false, false),
        ("AXCheckBox", "switch", "", "0", false, false),
        ("AXRadioButton", "choice", "Week", "1", false, false),
        ("AXButton", "button", "Today", "", true, false),
        ("AXSlider", "slider", "", "0.5", false, false),
        ("AXStaticText", "text", String(repeating: "word ", count: 40) + "\nsecond line", "", false, false),
        ("AXButton", "button", "Export…", "", false, false),
        ("AXButton", "button", "Delete", "", false, false),
        ("AXButton", "button", "Delete", "", false, false)
    ]

    private static let targets = ["b1", " F1 ", "add", "Export...", "Delete", "Save"]

    func testTheAppsCopyOfTheScreenAsTextSaysWhatLampsSays() throws {
        let support = Template.lampSupportSwift
        let start = try XCTUnwrap(support.range(of: "enum LampScreen {"))
        let end = try XCTUnwrap(support.range(of: "// end LampScreen", range: start.upperBound..<support.endIndex))
        let items = Self.items.map { item in
            "LampScreen.Item(role: \"\(item.word)\", label: \(literal(item.label)), value: \(literal(item.value)), " +
            "frame: CGRect(x: \(Self.frame.minX), y: \(Self.frame.minY), width: \(Self.frame.width), height: \(Self.frame.height)), " +
            "selected: \(item.selected), disabled: \(item.disabled))"
        }
        let program = """
        import Foundation
        import CoreGraphics
        \(support[start.lowerBound..<end.lowerBound])
        let items = [\(items.joined(separator: ",\n"))]
        print(LampScreen.text(for: items) ?? "nothing")
        print(LampScreen.text(for: []) ?? "nothing")
        for target in [\(Self.targets.map(literal).joined(separator: ", "))] {
            switch LampScreen.find(target, in: items) {
            case .one(let index): print("one \\(index)")
            case .none: print("none")
            case .several(let ids): print("several \\(ids.joined(separator: " "))")
            }
        }
        """
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-screen-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        try program.write(to: work.appendingPathComponent("main.swift"), atomically: true, encoding: .utf8)
        let built = try run(Shell.compatibleSDK + "xcrun swiftc -o screen main.swift 2>&1", in: work)
        XCTAssertEqual(built.status, 0, built.output)
        let printed = try run("./screen", in: work).output

        let mine = Self.items.map { Item(role: $0.role, label: $0.label, value: $0.value, frame: Self.frame, selected: $0.selected, disabled: $0.disabled) }
        var expected = try XCTUnwrap(Simulator.Driver.text(for: mine)) + "\nnothing\n"
        for target in Self.targets {
            switch Simulator.Driver.find(target, in: mine) {
            case .one(let index): expected += "one \(index)\n"
            case .none: expected += "none\n"
            case .several(let ids): expected += "several \(ids.joined(separator: " "))\n"
            }
        }
        XCTAssertEqual(printed, expected)
        // And what it says is what the agent is told to rely on.
        XCTAssertTrue(printed.hasPrefix(Simulator.Driver.heading))
        XCTAssertTrue(printed.contains("\nf1 text field \"New item\" = Milk @116,120 200x40\n"))
        XCTAssertTrue(printed.contains("\nb1 button \"Add\", dimmed @116,120 200x40\n"))
        XCTAssertTrue(printed.contains("\ns2 switch = off @116,120 200x40\n"))
        XCTAssertTrue(printed.hasSuffix("one 2\none 1\none 2\none 9\nseveral b4 b5\nnone\n"))
    }

    private func literal(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n") + "\""
    }

    private func run(_ command: String, in directory: URL) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.currentDirectoryURL = directory
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
