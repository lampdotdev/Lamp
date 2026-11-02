import XCTest
@testable import Lamp

/// The answer beside a running turn: which messages get one, what the agent is told, and the run's limits.
@MainActor
final class SideAnswerTests: XCTestCase {
    func testOffUnlessChosen() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "SideAnswerTests"))
        defaults.removePersistentDomain(forName: "SideAnswerTests")
        XCTAssertFalse(SideAnswer.isOn(in: defaults))
        defaults.set(true, forKey: SideAnswer.switchKey)
        XCTAssertTrue(SideAnswer.isOn(in: defaults))
    }

    func testOnlyAPlainTypedMessageIsAnswered() {
        XCTAssertTrue(SideAnswer.canAnswer(QueuedMessage(text: "Make it blue")))
        let others = [
            QueuedMessage(text: "   "),
            QueuedMessage(text: "Blue", card: UUID()),
            QueuedMessage(text: "Like this", attachments: [URL(fileURLWithPath: "/tmp/a.png")]),
            QueuedMessage(text: "Again", kept: ["a.png"]),
            QueuedMessage(text: "This", pointed: PointedAt(title: "Button", detail: nil, picture: "/tmp/a.png")),
            QueuedMessage(text: "Again", replaces: "Before"),
            QueuedMessage(text: "Again", tookBack: ["Before"]),
            QueuedMessage(text: "Now", sendNow: true),
            QueuedMessage(text: "Fix it", byLamp: true),
            QueuedMessage(text: "Carry on", afterReload: true),
        ]
        for message in others { XCTAssertFalse(SideAnswer.canAnswer(message), message.text) }
    }

    func testTheWordsStandApartAndTheQueueIsNotMentioned() {
        let prompt = SideAnswer.prompt(for: "Make it blue")
        XCTAssertTrue(prompt.contains("<message>\nMake it blue\n</message>"))
        XCTAssertTrue(prompt.contains("Sure, I'll make that change."))
        XCTAssertFalse(prompt.contains("next in line"))
    }

    func testReceiptIsLabeledAndGrantsNothing() {
        let receipt = SideAnswer.receipt("Got it, I'll do that next.")
        XCTAssertTrue(receipt.contains("Lamp context, not a new user instruction"))
        XCTAssertTrue(receipt.contains("Got it, I'll do that next."))
        XCTAssertTrue(receipt.contains("grant no permissions"))
    }

    func testAnswerStaysWithItsMessageAcrossARelaunch() {
        let waiting = QueuedMessage(text: "Make it blue", side: .answered("Got it."))
        XCTAssertEqual(QueuedMessage(saved: waiting.saved, attachments: []).sideReply, "Got it.")
        let unfinished = QueuedMessage(text: "Make it blue", side: .answering)
        XCTAssertNil(QueuedMessage(saved: unfinished.saved, attachments: []).side)
    }

    func testTheLocalModelAndOtherEnginesHaveNoRoute() {
        let env = ["LAMP_PI": "/pi", "PI_CODING_AGENT_DIR": "/config", "LAMP_PROVIDER": "openrouter", "LAMP_MODEL": "m",
                   "LAMP_SYSTEM": "s", "LAMP_SESSION": "lamp-1", "LAMP_TOOL_NAMES": "read,bash", "LAMP_TOOLS": "/tools.ts"]
        func route(_ engine: Engine, local: Bool = false, tools: [String: String]? = nil, definitions: Data? = Data()) -> SideAnswer.Route? {
            SideAnswer.route(env: tools ?? env, engine: engine, local: local, keyProvider: "openrouter", definitions: definitions, folder: "/app")
        }
        XCTAssertEqual(route(.pi)?.model, "m")
        XCTAssertNil(route(.pi, local: true))
        XCTAssertNil(route(.claude))
        XCTAssertNil(route(.codex))
        XCTAssertNil(route(.pi, definitions: nil))
        XCTAssertNil(route(.pi, tools: env.merging(["LAMP_TOOLS": ""]) { $1 }), "no extension means no guard")
    }

    func testTheForkHasNoneOfTheBuildersRoutes() {
        let route = SideAnswer.Route(executable: "/pi", configFolder: "/config", provider: "openrouter", keyProvider: "openrouter",
                                     model: "m", system: "s", session: "lamp-1", tools: "read,bash", extensionFile: "/tools.ts",
                                     definitions: Data(), folder: "/app")
        let arguments = SideAnswer.arguments(conversation: URL(fileURLWithPath: "/main.jsonl"),
                                             sessions: URL(fileURLWithPath: "/private"), route: route)
        XCTAssertEqual(arguments[arguments.firstIndex(of: "--mode")! + 1], "rpc")
        XCTAssertEqual(arguments[arguments.firstIndex(of: "--tools")! + 1], "read,bash")
        XCTAssertEqual(arguments[arguments.firstIndex(of: "--fork")! + 1], "/main.jsonl")
        XCTAssertFalse(arguments.contains("lamp-1"), "the fork has a session of its own")
        let env = SideAnswer.environment(route: route, keys: ["LAMP_KEY_TICKET": "t"], definitions: URL(fileURLWithPath: "/private/tools.json"))
        XCTAssertEqual(env["LAMP_SIDE_GUARD"], SideAnswer.guardCommand)
        XCTAssertNil(env["LAMP_TOKEN"])
        XCTAssertTrue(env.keys.filter { $0.hasSuffix("_URL") }.isEmpty)
    }

    func testTheModelIsAskedNothingUnlessTheGuardIsListed() {
        var reader = SideAnswer.Reader()
        let none = #"{"id":"guard","type":"response","command":"get_commands","success":true,"data":{"commands":[]}}"#
        XCTAssertEqual(reader.read(none), .failed("no guard"))
        let other = #"{"type":"response","command":"get_commands","success":true,"data":{"commands":[{"name":"\#(SideAnswer.guardCommand)","source":"skill"}]}}"#
        XCTAssertEqual(reader.read(other), .failed("no guard"))
        let listed = #"{"type":"response","command":"get_commands","success":true,"data":{"commands":[{"name":"\#(SideAnswer.guardCommand)","source":"extension"}]}}"#
        XCTAssertEqual(reader.read(listed), .guarded)
    }

    func testABlockedCallIsToldFromOneThatRan() {
        var reader = SideAnswer.Reader()
        let blocked = #"{"type":"tool_execution_end","toolName":"bash","isError":true,"result":{"content":[{"type":"text","text":"\#(SideAnswer.refusal)"}]}}"#
        XCTAssertEqual(reader.read(blocked), .failed("blocked bash"))
        let ran = #"{"type":"tool_execution_end","toolName":"bash","isError":false,"result":{"content":[{"type":"text","text":"done"}]}}"#
        XCTAssertEqual(reader.read(ran), .failed("bash ran"))
    }
}
