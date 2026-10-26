import XCTest
@testable import Lamp

final class TalkTests: XCTestCase {
    /// Result cards saved before there were rows for what's new, and while there were, still read: a chat line
    /// that can't be read loses the whole chat.
    func testEarlierResultsStillRead() throws {
        let before = Data(#"{"summary":"Done","guesses":[]}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(Talk.Result.self, from: before).summary, "Done")
        let withRows = Data(#"{"summary":"Save a meal","guesses":[],"news":[{"what":"Save a meal","place":"The star beside its name"}],"version":"abc"}"#.utf8)
        let read = try JSONDecoder().decode(Talk.Result.self, from: withRows)
        XCTAssertEqual(read.summary, "Save a meal")
        XCTAssertEqual(read.version, "abc")
        // Where to find what it made stays on the card, through the chat being saved again.
        let saved = try JSONDecoder().decode(Talk.Result.self, from: JSONEncoder().encode(read))
        XCTAssertEqual(saved.text, "Save a meal\n- Save a meal: The star beside its name")
        // A new app's card from while it had guesses as buttons and an idea, one guess turned.
        let withGuesses = Data(#"{"summary":"A week of dinners.","guesses":[{"guess":"One list","instead":"A list each","request":"Give each person a list."}],"idea":{"title":"Read recipes","request":"Read recipes from a photo."},"switched":[0]}"#.utf8)
        let first = try JSONDecoder().decode(Talk.Result.self, from: withGuesses)
        XCTAssertEqual(first.guesses.first?.instead, "A list each")
        XCTAssertEqual(first.switched, [0])
    }

    /// A card answered by clicking folds to a line that reads on its own: two questions both answered "Both"
    /// must still say what each "Both" was for.
    func testAFoldedCardSaysWhatWasAsked() {
        let options = [Talk.Option(title: "Grocery list"), Talk.Option(title: "Both")]
        let ask = Talk.Ask(layout: .steps,
                           questions: [Talk.Question(question: "Where should dinner ideas come from?", options: options),
                                       Talk.Question(question: "What else should it do?", options: options)],
                           answers: ["Both", "Both"])
        XCTAssertEqual(ask.folded, "Where should dinner ideas come from? Both\nWhat else should it do? Both")
    }

    /// A clicked answer is shown by its question card, not again, and still ends the request before the agent's
    /// reply to it; a guess clicked on a result card saved by an earlier Lamp shows as its message, the card not.
    func testCardMessagesInTheChat() {
        var answer = LogLine(kind: .user, text: "answer"); answer.fromCard = true
        var guess = LogLine(kind: .user, text: "guess"); guess.fromCard = true
        let lines = [LogLine(kind: .user, text: "wish"), LogLine(kind: .ask, text: "q"), answer,
                     LogLine(kind: .agent, text: "reply"), LogLine(kind: .summary, text: "s"),
                     LogLine(kind: .result, text: "card"), guess, LogLine(kind: .agent, text: "changed"), LogLine(kind: .summary, text: "s")]
        // Each turn's summary stays too, for how long it worked; the chat doesn't draw it as a line.
        XCTAssertEqual(LogLine.visible(lines, details: false).map(\.text), ["wish", "q", "reply", "s", "guess", "changed", "s"])
    }

    /// Lamp's device card is the person's to answer, and what they chose there is all the agent may do to a device.
    func testTheDeviceCardAllowsOnlyWhatWasChosen() {
        let wish = LampProject(id: "remote", name: "Remote", exe: "Remote", dir: URL(fileURLWithPath: "/tmp/remote"), instance: UUID().uuidString)
        defer { DevicePermissions.forget(wish) }
        let card = DevicePermissions.card(device: "Living Room TV", doing: "Press Home")
        XCTAssertEqual(card.device, "Living Room TV")
        XCTAssertTrue(card.questions.allSatisfy { $0.personOnly == true })
        DevicePermissions.answer(DevicePermissions.notNow, about: "Living Room TV", for: wish)
        XCTAssertEqual(DevicePermissions.allowed(wish), [])
        DevicePermissions.answer(DevicePermissions.allowOnce, about: "Living Room TV", for: wish)
        XCTAssertEqual(DevicePermissions.allowed(wish), ["Living Room TV"])
        DevicePermissions.endOnce(for: wish)
        XCTAssertEqual(DevicePermissions.allowed(wish), [])
        DevicePermissions.answer(DevicePermissions.allowAlways("Living Room TV"), about: "Living Room TV", for: wish)
        DevicePermissions.endOnce(for: wish)
        XCTAssertEqual(DevicePermissions.allowed(wish), ["Living Room TV"])
        // Codex's commands are kept off the person's devices by what they do: a plain read passes, a press doesn't.
        XCTAssertFalse(DevicePermissions.mayChangeADevice("curl -s -m 4 http://10.0.0.120:8060/query/device-info | grep model"))
        XCTAssertFalse(DevicePermissions.mayChangeADevice("swift build && curl https://example.com -d x=1"))
        XCTAssertTrue(DevicePermissions.mayChangeADevice("curl -s -X POST http://10.0.0.120:8060/keypress/Home"))
        XCTAssertTrue(DevicePermissions.mayChangeADevice("curl -d '' http://192.168.1.9:1400/MediaRenderer/AVTransport/Control"))
        XCTAssertTrue(DevicePermissions.mayChangeADevice("python3 press.py 172.20.0.5"))
        XCTAssertTrue(DevicePermissions.mayChangeADevice("echo hi | nc living-room.local 1234"))
        // Allowing one device lets a command reach that device alone.
        DevicePermissions.asking(about: "Living Room TV", at: "10.0.0.120", for: wish)
        DevicePermissions.answer(DevicePermissions.allowAlways("Living Room TV"), about: "Living Room TV", for: wish)
        XCTAssertEqual(DevicePermissions.allowedAddresses(wish), ["10.0.0.120"])
        // Asked again at a new address and turned down: the new address isn't allowed.
        DevicePermissions.asking(about: "Living Room TV", at: "10.0.0.121", for: wish)
        DevicePermissions.answer(DevicePermissions.notNow, about: "Living Room TV", for: wish)
        XCTAssertEqual(DevicePermissions.allowedAddresses(wish), ["10.0.0.120"])
        // Allowed once there: for now only, and the lasting grant stays where it was.
        DevicePermissions.asking(about: "Living Room TV", at: "10.0.0.121", for: wish)
        DevicePermissions.answer(DevicePermissions.allowOnce, about: "Living Room TV", for: wish)
        XCTAssertEqual(DevicePermissions.allowedAddresses(wish), ["10.0.0.120", "10.0.0.121"])
        DevicePermissions.endOnce(for: wish)
        XCTAssertEqual(DevicePermissions.allowedAddresses(wish), ["10.0.0.120"])
        XCTAssertEqual(DevicePermissions.devicesChanged(by: "curl -X POST http://10.0.0.120:8060/keypress/Home && curl -d x http://10.0.0.99:1400/x"),
                       ["10.0.0.120", "10.0.0.99"])
    }
}
