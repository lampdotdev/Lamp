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

    func testPromiseFollowsTheQueue() {
        let next = SideAnswer.prompt(for: "Make it blue", ahead: 0, at: Date())
        XCTAssertTrue(next.contains("is next after it"))
        XCTAssertTrue(next.contains("<message>\nMake it blue\n</message>"))
        let later = SideAnswer.prompt(for: "Make it blue", ahead: 2, at: Date())
        XCTAssertFalse(later.contains("is next after it"))
        XCTAssertTrue(later.contains("2 earlier messages wait"))
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
                   "LAMP_SYSTEM": "s", "LAMP_SESSION": "lamp-1"]
        XCTAssertEqual(SideAnswer.route(env: env, engine: .pi, local: false, keyProvider: "openrouter")?.model, "m")
        XCTAssertNil(SideAnswer.route(env: env, engine: .pi, local: true, keyProvider: "local"))
        XCTAssertNil(SideAnswer.route(env: env, engine: .claude, local: false, keyProvider: "openrouter"))
        XCTAssertNil(SideAnswer.route(env: env, engine: .codex, local: false, keyProvider: "openrouter"))
    }

    func testTheForkHasNoToolsAndNoneOfTheBuildersEnvironment() {
        let route = SideAnswer.Route(executable: "/pi", configFolder: "/config", provider: "openrouter", keyProvider: "openrouter",
                                     model: "m", system: "s", session: "lamp-1")
        let arguments = SideAnswer.arguments(prompt: "p", conversation: URL(fileURLWithPath: "/main.jsonl"),
                                             sessions: URL(fileURLWithPath: "/private"), route: route)
        XCTAssertTrue(arguments.contains("--no-tools"))
        XCTAssertTrue(arguments.contains("--no-extensions"))
        XCTAssertFalse(arguments.contains("-e"))
        XCTAssertFalse(arguments.contains("--tools"))
        XCTAssertEqual(arguments[arguments.firstIndex(of: "--fork")! + 1], "/main.jsonl")
        let env = SideAnswer.environment(route: route, keys: ["LAMP_KEY_TICKET": "t"])
        XCTAssertNil(env["LAMP_TOKEN"])
        XCTAssertTrue(env.keys.filter { $0.hasSuffix("_URL") }.isEmpty)
    }
}
