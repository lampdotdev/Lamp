import XCTest
@testable import Lamp

/// Do It for Me: the device table names a skill only where it applies, the shipped skill's steps can be followed, and
/// the runner says only what it saw, stops with a plain reason for each way a device fails, and stops when cancelled.
@MainActor
final class SetupGuideTests: XCTestCase {
    /// The skills as they ship, read from the repository (tests don't run inside Lamp's bundle).
    private let shipped = Skills.load(from: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Resources/skills"))

    /// The TV row covers Samsung's TVs too: only webOS has a setup skill, and Lamp ships it, ending in the passphrase.
    func testOnlyWebOSTVsHaveTheSetupSkillAndItCanBeFollowed() throws {
        XCTAssertNil(Places.setupSkill(row: "tv", system: "Tizen", skills: shipped))
        let skill = try XCTUnwrap(Places.setupSkill(row: "tv", system: "webOS", skills: shipped))
        guard case .success(let steps) = SetupSteps.parse(skill: skill.body) else { return XCTFail("the skill's steps don't parse") }
        XCTAssertEqual(steps.connection, "webos-second-screen")
        XCTAssertEqual(steps.steps.first?.kind, .connect)
        XCTAssertEqual(steps.steps.last?.kind, .passphrase)
        // Whatever the person does on the TV that Lamp can't see is theirs to confirm, and their Continue claims nothing
        // as done: no "You turned Dev Mode Status on" when they may only have clicked.
        let confirms = steps.steps.filter { $0.kind == .confirm }
        XCTAssertFalse(confirms.isEmpty)
        for confirm in confirms { XCTAssertNil(confirm.done, confirm.ask ?? "") }
        for place in Places.builtIn {
            for name in place.setupSkills.values {
                let skill = try XCTUnwrap(shipped[name], "\(place.name) names \(name), which Lamp doesn't ship")
                if case .failure(let problem) = SetupSteps.parse(skill: skill.body) { XCTFail("\(name): \(problem.reason)") }
            }
        }
    }

    func testStepsThatCantBeFollowedAreRefused() {
        let body = { (steps: String) in "Words.\n\n```lamp-setup\n{\"connection\": \"webos-second-screen\", \"steps\": [\(steps)]}\n```\n" }
        XCTAssertEqual(SetupSteps.parse(skill: "No block").failureReason, "the skill has no lamp-setup block")
        XCTAssertEqual(SetupSteps.parse(skill: body("{\"do\": \"press-buttons\"}")).failureReason, "step 1 does nothing Lamp knows")
        XCTAssertEqual(SetupSteps.parse(skill: body("{\"do\": \"wait\", \"uri\": \"x\"}")).failureReason, "step 1 is missing what it sends or waits for")
        XCTAssertEqual(SetupSteps.parse(skill: body("{\"do\": \"confirm\", \"ask\": \"Done?\"}")).failureReason, "step 1 doesn't say what the person confirms")
        XCTAssertEqual(SetupSteps.parse(skill: "```lamp-setup\n{\"connection\": \"telnet\", \"steps\": []}\n```").failureReason, "its connection isn't one Lamp has")
    }

    func testValuesAreReadThroughArrays() {
        let answer: [String: Any] = ["apps": [["id": "a"], ["id": "b"], ["title": "no id"]], "returnValue": true]
        XCTAssertEqual(SetupSteps.values(at: "apps.id", in: answer), ["a", "b"])
        XCTAssertEqual(SetupSteps.values(at: "missing.id", in: answer), [])
    }

    // MARK: Running the steps

    /// Steps of the same kinds as a real skill's, against a connection that answers as each case needs.
    private let steps: SetupSteps = {
        let body = """
        ```lamp-setup
        {"connection": "webos-second-screen", "steps": [
          {"do": "connect", "doing": "Asking {name}…", "ask": "Choose Accept.", "done": "{name} let Lamp in", "refused": "{name} said no."},
          {"do": "request", "uri": "open-store", "doing": "Opening the store…", "done": "Asked for the store", "failed": "Open the store yourself.", "continueOnFailure": true},
          {"do": "wait", "uri": "list", "until": {"path": "apps.id", "contains": "dev"}, "every": 1, "doing": "Waiting…", "ask": "Choose Install.", "done": "Installed"},
          {"do": "confirm", "ask": "Sign in and turn it on.", "button": "Continue", "done": "You turned it on"},
          {"do": "connect", "doing": "Again…", "done": "Connected again"},
          {"do": "passphrase", "ask": "Type the passphrase."}
        ]}
        ```
        """
        guard case .success(let steps) = SetupSteps.parse(skill: body) else { fatalError() }
        return steps
    }()

    func testAWholeRunConfirmsWhatLampCantSeeAndEndsAtThePassphrase() async throws {
        let device = FakeDevice()
        device.lists = [["apps": [["id": "other"]]], ["apps": [["id": "dev"]]]]
        let guided = GuidedSetup()
        guided.start(steps, name: "Den TV", connection: device)
        try await until { guided.button != nil }
        // The app showed up in the list: that's seen. The sign-in isn't, so nothing claims it until the person says so.
        XCTAssertEqual(guided.lines.map(\.text), ["Den TV let Lamp in", "Asked for the store", "Installed"])
        XCTAssertEqual(guided.ask, "Sign in and turn it on.")
        XCTAssertEqual(device.sent, ["open-store", "list", "list"])
        guided.confirm()
        await guided.finished()
        XCTAssertEqual(guided.lines.map(\.text), ["Den TV let Lamp in", "Asked for the store", "Installed", "You turned it on", "Connected again"])
        XCTAssertTrue(guided.atPassphrase)
        XCTAssertEqual(guided.ask, "Type the passphrase.")
        XCTAssertEqual(device.connects, 2)
        XCTAssertTrue(device.closed)
        XCTAssertFalse(guided.running)
    }

    func testARefusedPairingStopsWithTheSkillsWords() async {
        let device = FakeDevice()
        device.connectFailure = .refused
        let guided = GuidedSetup()
        guided.start(steps, name: "Den TV", connection: device)
        await guided.finished()
        XCTAssertEqual(guided.failure, "Den TV said no.")
        XCTAssertEqual(guided.lines, [])
        XCTAssertTrue(device.sent.isEmpty)
        XCTAssertFalse(guided.running)
    }

    /// A store the TV can't open is said, with what to do instead, and the steps go on to wait for the app.
    func testAStoreThatWontOpenIsSaidAndTheStepsGoOn() async throws {
        let device = FakeDevice()
        device.failing = ["open-store": .failed("404 no such app")]
        device.lists = [["apps": [["id": "dev"]]]]
        let guided = GuidedSetup()
        guided.start(steps, name: "Den TV", connection: device)
        try await until { guided.button != nil }
        XCTAssertEqual(guided.lines.map(\.text), ["Den TV let Lamp in", "Open the store yourself.", "Installed"])
        XCTAssertEqual(guided.lines[1].state, .note)
        guided.cancel()
    }

    /// A TV that stops answering stops the steps, even where a refusal of the request itself would have let them go on.
    func testATVThatStopsAnsweringStopsTheSteps() async {
        let device = FakeDevice()
        device.failing = ["open-store": .unreachable]
        let guided = GuidedSetup()
        guided.start(steps, name: "Den TV", connection: device)
        await guided.finished()
        XCTAssertEqual(guided.failure, "Den TV isn't answering. Check it's on and on the same network as this Mac, then click Try Again.")
        XCTAssertEqual(guided.lines.map(\.text), ["Den TV let Lamp in"])
        XCTAssertEqual(device.sent, ["open-store"])
    }

    func testCancellingStopsTheStepsAndClosesTheConnection() async throws {
        let device = FakeDevice()
        device.lists = [["apps": []]]
        let guided = GuidedSetup()
        guided.start(steps, name: "Den TV", connection: device)
        try await until { device.sent.contains("list") }
        guided.cancel()
        XCTAssertTrue(device.closed)
        XCTAssertFalse(guided.started)
        let asked = device.sent.count
        try await Task.sleep(for: .seconds(1.5))
        XCTAssertEqual(device.sent.count, asked, "the TV was still asked after the steps were cancelled")
    }

    private func until(_ condition: @escaping () -> Bool) async throws {
        for _ in 0..<100 where !condition() { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertTrue(condition(), "timed out")
    }
}

private final class FakeDevice: SetupConnection {
    var connectFailure: SetupConnectionError?
    var failing: [String: SetupConnectionError] = [:]
    /// What each `list` request answers, in turn; the last one again once they run out.
    var lists: [[String: Any]] = []
    var sent: [String] = []
    var connects = 0
    var closed = false

    func connect() async throws {
        connects += 1
        if let connectFailure { throw connectFailure }
    }

    func request(_ uri: String, payload: [String: Any]) async throws -> [String: Any] {
        sent.append(uri)
        if let failure = failing[uri] { throw failure }
        guard uri == "list" else { return ["returnValue": true] }
        return lists.count > 1 ? lists.removeFirst() : lists.first ?? [:]
    }

    func close() { closed = true }
}

private extension Result where Failure == SetupSteps.Problem {
    var failureReason: String? { if case .failure(let problem) = self { problem.reason } else { nil } }
}
