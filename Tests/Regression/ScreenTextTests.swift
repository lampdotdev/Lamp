import XCTest
@testable import Lamp

/// The iPhone's screen as text, which the agent reads beside the picture: one short line for each thing,
/// with the point to tap it.
@MainActor
final class ScreenTextTests: XCTestCase {
    private typealias Item = Simulator.Driver.Item

    func testEachThingIsOneLineWithItsNameValueAndWhereToTapIt() {
        let text = Simulator.Driver.text(for: [
            Item(role: "AXHeading", label: "Groceries", frame: CGRect(x: 16, y: 100, width: 200, height: 40)),
            Item(role: "AXTextField", label: "New item", value: "Milk", frame: CGRect(x: 16, y: 160, width: 300, height: 44)),
            Item(role: "AXButton", label: "Add", frame: CGRect(x: 330, y: 160, width: 44, height: 44), disabled: true)
        ])
        XCTAssertEqual(text?.components(separatedBy: "\n").dropFirst().joined(separator: "\n"), """
            heading "Groceries" @116,120 200x40
            text field "New item" = Milk @166,182 300x44
            button "Add", dimmed @352,182 44x44
            """)
    }

    func testSwitchesAndChoicesSayTheirStateInWords() {
        let frame = CGRect(x: 0, y: 0, width: 10, height: 10)
        let lines = Simulator.Driver.text(for: [
            Item(role: "AXCheckBox", label: "Reminders", value: "1", frame: frame),
            Item(role: "AXCheckBox", label: "Sounds", value: "0", frame: frame),
            Item(role: "AXRadioButton", label: "Week", value: "1", frame: frame),
            Item(role: "AXRadioButton", label: "Month", value: "0", frame: frame),
            Item(role: "AXButton", label: "Today", frame: frame, selected: true)
        ])?.components(separatedBy: "\n").dropFirst() ?? []
        XCTAssertEqual(Array(lines), [
            #"switch "Reminders" = on @5,5 10x10"#, #"switch "Sounds" = off @5,5 10x10"#,
            #"choice "Week", selected @5,5 10x10"#, #"choice "Month" @5,5 10x10"#, #"button "Today", selected @5,5 10x10"#
        ])
    }

    func testAControlWithNoNameIsStillListedSoItCanBeTappedAndFixed() {
        let text = Simulator.Driver.text(for: [Item(role: "AXButton", frame: CGRect(x: 350, y: 60, width: 30, height: 30))])
        XCTAssertTrue(text?.hasSuffix("\nbutton @365,75 30x30") == true)
    }

    func testAControlWithNoNameKeepsItsStateAndPlainTextIsNamedByItsWords() {
        // A switch that's on, with no label: still "on", and still plainly unnamed.
        let unnamed = Simulator.Driver.naming(control: true, label: "", value: "1")
        XCTAssertEqual([unnamed.label, unnamed.value], ["", "1"])
        let frame = CGRect(x: 0, y: 0, width: 10, height: 10)
        let lines = Simulator.Driver.text(for: [
            Item(role: "AXCheckBox", label: unnamed.label, value: unnamed.value, frame: frame),
            Item(role: "AXRadioButton", value: "1", frame: frame),
            Item(role: "AXSlider", value: "0.5", frame: frame)
        ])?.components(separatedBy: "\n").dropFirst() ?? []
        XCTAssertEqual(Array(lines), ["switch = on @5,5 10x10", "choice, selected @5,5 10x10", "slider = 0.5 @5,5 10x10"])
        let words = Simulator.Driver.naming(control: false, label: "", value: " 2 of 4 packed ")
        XCTAssertEqual([words.label, words.value], ["2 of 4 packed", ""])
        let named = Simulator.Driver.naming(control: true, label: "Days away", value: "0.31")
        XCTAssertEqual([named.label, named.value], ["Days away", "0.31"])
    }

    func testLongTextAndLongScreensAreCutSoATurnStaysSmall() {
        let frame = CGRect(x: 0, y: 0, width: 10, height: 10)
        let note = Item(role: "AXStaticText", label: String(repeating: "word ", count: 100) + "\nsecond line", frame: frame)
        let many = [note] + (0..<200).map { Item(role: "AXStaticText", label: "Row \($0)", frame: frame) }
        let lines = Simulator.Driver.text(for: many)?.components(separatedBy: "\n") ?? []
        XCTAssertEqual(lines.count, 1 + Simulator.Driver.itemLimit + 1)
        XCTAssertLessThan(lines[1].count, 110)
        XCTAssertEqual(lines.last, "… and 81 more")
        XCTAssertLessThan(lines.joined(separator: "\n").utf8.count, 4_000)
    }

    func testAnEmptyScreenSaysNothing() {
        XCTAssertNil(Simulator.Driver.text(for: []))
    }
}
