import XCTest
@testable import Lamp

/// Do It for Me: a guide is a skill that says which setup step it does, checked against that setup before anything is
/// sent; the runner says only what it saw, stops with a plain reason for each way a device fails, goes on from the step
/// that failed, and hands the device back to the setup's own step without completing it.
@MainActor
final class SetupGuideTests: XCTestCase {
    private static let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    /// The skills as they ship, read from the repository (tests don't run inside Lamp's bundle).
    private let shipped = Skills.load(from: repository.appendingPathComponent("Resources/skills"))
    private let tv = SetupGuides.Host(row: "tv", system: "webOS", steps: Set(TVSetup.Step.allCases.map(\.rawValue)))

    /// The TV row covers Samsung's TVs too: only webOS has a guide, and Lamp ships it, ending in the TV's own passphrase.
    func testOnlyWebOSTVsHaveAGuideAndItCanBeFollowed() throws {
        XCTAssertNil(SetupGuides.find("developer-mode", in: .init(row: "tv", system: "Tizen", steps: tv.steps), skills: shipped))
        XCTAssertNil(SetupGuides.find("connected", in: tv, skills: shipped))
        let steps = try XCTUnwrap(SetupGuides.find("developer-mode", in: tv, skills: shipped)).get()
        XCTAssertEqual(steps.connection, "webos-second-screen")
        XCTAssertEqual(steps.steps.first?.kind, .connect)
        XCTAssertEqual(steps.steps.last?.kind, .handoff)
        XCTAssertEqual(steps.offer, "Lamp opens each screen on the TV; you press the buttons.")
        // The restart is the person's (unplugging the TV), and Lamp carries on by itself once it sees the TV come back.
        XCTAssertTrue(steps.steps.contains { $0.kind == .rejoin && ($0.ask ?? "").contains("unplug") })
    }

    /// Every guide Lamp ships names a row, a system and a step that exist, and can be followed there.
    func testEveryShippedGuideFitsTheSetupItNames() throws {
        let devices = Self.repository.appendingPathComponent("Resources/Devices")
        let integrations = try FileManager.default.contentsOfDirectory(atPath: devices.path).filter { $0.hasSuffix(".json") }.map {
            try JSONDecoder().decode(Integration.self, from: Data(contentsOf: devices.appendingPathComponent($0)))
        }
        let registrations = SetupGuides.registrations(shipped)
        XCTAssertFalse(registrations.isEmpty)
        for registration in registrations {
            var host = SetupGuides.Host(row: "tv", system: registration.system ?? "webOS", steps: tv.steps)
            if registration.row != "tv" {
                let found: Integration? = integrations.first { $0.id == registration.row }
                let integration = try XCTUnwrap(found, "\(registration.skill) names \(registration.row), which Lamp doesn't ship")
                let fields: Set<String> = Set(integration.steps.compactMap { $0.field?.key })
                host = SetupGuides.Host(row: integration.id, system: registration.system ?? integration.identity.os,
                                        steps: Set(integration.steps.map(\.id)), fields: fields, integration: true)
            }
            switch SetupGuides.find(registration.step, in: host, skills: shipped) {
            case .success?: break
            case .failure(let problem)?: XCTFail("\(registration.skill): \(problem.reason)")
            case nil: XCTFail("\(registration.skill) isn't found for the step it names")
            }
        }
    }

    /// Roku's guide does the Roku integration's developer-mode step with the same keys, in the same order, that the
    /// step's own button presses (which people have done on a Roku), and waits for exactly what the step checks, so it
    /// never hands back before the step itself would pass.
    func testRokusGuideMatchesItsIntegrationsStep() throws {
        let data = try Data(contentsOf: Self.repository.appendingPathComponent("Resources/Devices/roku.json"))
        let roku = try JSONDecoder().decode(Integration.self, from: data)
        let step = try XCTUnwrap(roku.steps.first { $0.id == "developer-mode" })
        let host = SetupGuides.Host(row: "roku", system: roku.identity.os, steps: Set(roku.steps.map(\.id)),
                                    fields: Set(roku.steps.compactMap { $0.field?.key }), integration: true)
        let guide = try XCTUnwrap(SetupGuides.find("developer-mode", in: host, skills: shipped)).get()
        XCTAssertEqual(guide.connection, "http")
        let presses = try XCTUnwrap(guide.steps.first { $0.kind == .request })
        XCTAssertEqual(presses.run, step.run)
        XCTAssertNotNil(presses.unless, "the keys aren't pressed when developer mode is on already")
        XCTAssertNotNil(presses.failed, "a failure part way says which keys to press")
        guard case .http(let until)? = guide.steps.first(where: { $0.kind == .wait })?.until else { return XCTFail("no wait") }
        XCTAssertEqual(until, step.check)
        XCTAssertTrue(guide.steps.contains { $0.kind == .rejoin })
        XCTAssertEqual(guide.steps.last?.kind, .handoff)
        // Only the developer-mode step has a guide: the password is the person's.
        XCTAssertNil(SetupGuides.find("password", in: host, skills: shipped))
    }

    // MARK: Which guide

    private func skill(_ name: String, row: String = "roku", system: String? = nil, step: String = "developer-mode", connection: String = "webos-second-screen") -> Skills.Skill {
        var meta = ["setup-for": row, "setup-step": step]
        meta["setup-system"] = system
        let reach = connection == "http" ? ", \"reach\": [{\"tcp\": 8060}]" : ""
        return Skills.Skill(name: name, description: "A guide.", body: "```lamp-setup\n{\"connection\": \"\(connection)\"\(reach), \"steps\": [{\"do\": \"connect\"}]}\n```", meta: meta)
    }

    private let roku = SetupGuides.Host(row: "roku", system: "Roku OS", steps: ["developer-mode", "password"], integration: true)

    /// A guide for the device's own system wins over one for any; two that say the same are both left out.
    func testAGuideForTheSystemWinsAndTwoAlikeAreRefused() throws {
        let any = skill("any")
        let mine = skill("mine", system: "Roku OS")
        let other = skill("other", system: "Fire OS")
        func found(_ skills: [Skills.Skill], _ host: SetupGuides.Host? = nil) -> Result<SetupSteps, SetupSteps.Problem>? {
            SetupGuides.find("developer-mode", in: host ?? roku, skills: Dictionary(uniqueKeysWithValues: skills.map { ($0.name, $0) }))
        }
        XCTAssertNotNil(try found([any, other])?.get())
        XCTAssertNotNil(try found([any, mine])?.get())
        XCTAssertEqual(found([mine, skill("mine-too", system: "Roku OS")])?.failureReason, "mine and mine-too both do developer-mode")
        XCTAssertEqual(found([any, skill("any-too")])?.failureReason, "any and any-too both do developer-mode")
        XCTAssertNil(found([other]))
        XCTAssertNil(found([skill("elsewhere", row: "xbox-one")]))
        // Checked against the setup it runs in: a step it doesn't have, and HTTP to a device no integration reaches.
        XCTAssertEqual(found([any], .init(row: "roku", system: "Roku OS", steps: ["password"]))?.failureReason, "any does developer-mode, which isn't a step of this setup")
        XCTAssertEqual(found([skill("web", connection: "http")], .init(row: "roku", system: "Roku OS", steps: ["developer-mode"]))?.failureReason,
                       "web speaks HTTP, which reaches only a device integration's devices")
        XCTAssertNotNil(try found([skill("web", connection: "http")])?.get())
    }

    func testStepsThatCantBeFollowedAreRefused() {
        let socket = { (steps: String) in "Words.\n\n```lamp-setup\n{\"connection\": \"webos-second-screen\", \"steps\": [\(steps)]}\n```\n" }
        let http = { (steps: String) in "```lamp-setup\n{\"connection\": \"http\", \"reach\": [{\"tcp\": 8060}], \"steps\": [\(steps)]}\n```" }
        XCTAssertEqual(SetupSteps.parse(skill: "No block").failureReason, "the skill has no lamp-setup block")
        XCTAssertEqual(SetupSteps.parse(skill: socket("{\"do\": \"press-buttons\"}")).failureReason, "step 1 does nothing Lamp knows")
        XCTAssertEqual(SetupSteps.parse(skill: socket("{\"do\": \"wait\"}")).failureReason, "step 1 is missing what it sends or waits for")
        XCTAssertEqual(SetupSteps.parse(skill: socket("{\"do\": \"wait\", \"until\": {\"uri\": \"x\"}}")).failureReason, "step 1 until needs a uri, a json path, and one of equals or contains")
        XCTAssertEqual(SetupSteps.parse(skill: socket("{\"do\": \"confirm\", \"ask\": \"Done?\"}")).failureReason, "step 1 doesn't say what the person confirms")
        XCTAssertEqual(SetupSteps.parse(skill: "```lamp-setup\n{\"connection\": \"telnet\", \"steps\": []}\n```").failureReason, "its connection isn't one Lamp has")
        // What Lamp can't see is never said done, and the guide's end completes nothing.
        XCTAssertEqual(SetupSteps.parse(skill: socket("{\"do\": \"confirm\", \"ask\": \"Sign in.\", \"button\": \"Done\", \"done\": \"You signed in\"}")).failureReason,
                       "step 1 is a confirm, which can't say anything is done: Lamp doesn't see it")
        XCTAssertEqual(SetupSteps.parse(skill: socket("{\"do\": \"handoff\", \"done\": \"Set up\"}")).failureReason, "step 1 is a handoff, which does nothing and says nothing is done")
        XCTAssertEqual(SetupSteps.parse(skill: socket("{\"do\": \"handoff\"}, {\"do\": \"connect\"}")).failureReason, "step 1 is a handoff, which can only be the last step")
        // HTTP steps are a device integration's actions and checks, held to its rules, and only those that ask and wait.
        XCTAssertEqual(SetupSteps.parse(skill: "```lamp-setup\n{\"connection\": \"http\", \"steps\": [{\"do\": \"connect\"}]}\n```").failureReason,
                       "an HTTP connection needs reach: what the device answering means")
        XCTAssertEqual(SetupSteps.parse(skill: http("{\"do\": \"request\", \"run\": [{\"ssh\": {\"user\": \"root\", \"command\": \"reboot\", \"explanation\": \"Restarts it.\"}}]}")).failureReason,
                       "step 1 run[0] can only be http, probe or wait: commands, tools and sign-ins are the device's own setup steps")
        XCTAssertEqual(SetupSteps.parse(skill: http("{\"do\": \"request\", \"run\": [{\"http\": {\"port\": 8060, \"path\": \"/x/{secret}\"}}]}")).failureReason,
                       IntegrationCheck.actionProblems(IntegrationAction(http: Request(port: 8060, path: "/x/{secret}")), at: "step 1 run[0]", fields: [], steps: [], inBridge: false).first)
        XCTAssertEqual(SetupSteps.parse(skill: http("{\"do\": \"wait\", \"until\": [{\"field\": \"password\"}]}"), fields: ["password"]).failureReason,
                       "step 1 until[0] must ask the device, over http or tcp")
        // Key presses are sent once: a request of more than one says how Lamp knows it's done, for Try Again.
        let presses = "{\"do\": \"request\", \"run\": [{\"http\": {\"method\": \"POST\", \"port\": 8060, \"path\": \"/keypress/Home\"}}, {\"http\": {\"method\": \"POST\", \"port\": 8060, \"path\": \"/keypress/Up\"}}]"
        XCTAssertEqual(SetupSteps.parse(skill: http(presses + "}")).failureReason, "step 1 sends the device more than one change, so it needs unless: what holds once it's done")
        XCTAssertNil(SetupSteps.parse(skill: http(presses + ", \"unless\": [{\"http\": {\"port\": 8060, \"path\": \"/query/device-info\"}, \"xml\": \"developer-enabled\", \"equals\": \"true\"}]}")).failureReason)
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
          {"do": "wait", "until": {"uri": "list", "json": "apps.id", "equals": "dev"}, "every": 1, "doing": "Waiting…", "ask": "Choose Install.", "done": "Installed"},
          {"do": "confirm", "ask": "Sign in and turn it on.", "button": "Continue"},
          {"do": "connect", "doing": "Again…", "done": "Connected again"},
          {"do": "handoff", "ask": "Type the passphrase."}
        ]}
        ```
        """
        guard case .success(let steps) = SetupSteps.parse(skill: body) else { fatalError() }
        return steps
    }()

    private func start(_ steps: SetupSteps, on device: FakeDevice, finished: (() -> Void)? = nil) -> GuidedSetup {
        let guided = GuidedSetup()
        guided.start(steps, name: "Den TV", step: "developer-mode", connect: { device }, onFinish: finished ?? {})
        return guided
    }

    func testAWholeRunConfirmsWhatLampCantSeeAndHandsTheDeviceBack() async throws {
        let device = FakeDevice()
        device.lists = [["apps": [["id": "other"]]], ["apps": [["id": "dev"]]]]
        var handedBack = 0
        let guided = start(steps, on: device) { handedBack += 1 }
        XCTAssertTrue(guided.holdsDevice)
        try await until { guided.button != nil }
        // The app showed up in the list: that's seen. The sign-in isn't, so nothing claims it, before or after the click.
        XCTAssertEqual(guided.lines.map(\.text), ["Den TV let Lamp in", "Asked for the store", "Installed"])
        XCTAssertEqual(guided.ask, "Sign in and turn it on.")
        XCTAssertEqual(device.sent, ["open-store", "list", "list"])
        guided.confirm()
        await guided.finished()
        XCTAssertEqual(guided.lines.map(\.text), ["Den TV let Lamp in", "Asked for the store", "Installed", "Connected again"])
        XCTAssertTrue(guided.handedBack)
        XCTAssertFalse(guided.holdsDevice, "the setup watches its own step again")
        XCTAssertEqual(handedBack, 1, "the setup is asked once to check its own step")
        XCTAssertEqual(guided.ask, "Type the passphrase.")
        XCTAssertEqual(device.connects, 2)
        XCTAssertTrue(device.closed)
        XCTAssertFalse(guided.running)
    }

    func testARefusedPairingStopsWithTheSkillsWords() async {
        let device = FakeDevice()
        device.connectFailure = .refused
        let guided = start(steps, on: device)
        await guided.finished()
        XCTAssertEqual(guided.failure, "Den TV said no.")
        XCTAssertEqual(guided.lines, [])
        XCTAssertTrue(device.sent.isEmpty)
        XCTAssertFalse(guided.running)
        XCTAssertTrue(guided.holdsDevice, "a failed guide keeps its place for Try Again")
    }

    /// A store the TV can't open is said, with what to do instead, and the steps go on to wait for the app.
    func testAStoreThatWontOpenIsSaidAndTheStepsGoOn() async throws {
        let device = FakeDevice()
        device.failing = ["open-store": .failed("404 no such app")]
        device.lists = [["apps": [["id": "dev"]]]]
        let guided = start(steps, on: device)
        try await until { guided.button != nil }
        XCTAssertEqual(guided.lines.map(\.text), ["Den TV let Lamp in", "Open the store yourself.", "Installed"])
        XCTAssertEqual(guided.lines[1].state, .note)
        guided.cancel()
    }

    /// A TV that stops answering stops the steps, even where a refusal of the request itself would have let them go on;
    /// Try Again lets Lamp in again and goes on from that step, without sending what came before again.
    func testATVThatStopsAnsweringStopsTheStepsAndTryAgainGoesOnFromThere() async throws {
        let device = FakeDevice()
        device.failing = ["open-store": .unreachable]
        device.lists = [["apps": [["id": "dev"]]]]
        let guided = start(steps, on: device)
        await guided.finished()
        XCTAssertEqual(guided.failure, "Den TV isn't answering. Check it's on and on the same network as this Mac, then click Try Again.")
        XCTAssertEqual(guided.lines.map(\.text), ["Den TV let Lamp in"])
        XCTAssertEqual(device.sent, ["open-store"])
        device.failing = [:]
        guided.retry()
        try await until { guided.button != nil }
        XCTAssertNil(guided.failure)
        XCTAssertEqual(device.connects, 2, "let in again before going on")
        XCTAssertEqual(device.sent, ["open-store", "open-store", "list"])
        XCTAssertEqual(guided.lines.map(\.text), ["Den TV let Lamp in", "Asked for the store", "Installed"])
        guided.cancel()
    }

    /// A request whose `unless` holds is already done: nothing is sent, and nothing says Lamp asked for it.
    func testARequestAlreadyDoneIsntSentAgain() async throws {
        let steps = try parsed("""
          {"do": "request", "uri": "open-app", "unless": {"uri": "list", "json": "apps.id", "equals": "dev"}, "done": "Asked {name} to open it"},
          {"do": "handoff", "ask": "Type it."}
        """)
        let device = FakeDevice()
        device.connected = true
        device.lists = [["apps": [["id": "dev"]]]]
        let guided = start(steps, on: device)
        await guided.finished()
        XCTAssertEqual(device.sent, ["list"])
        XCTAssertEqual(guided.lines, [])
        XCTAssertTrue(guided.handedBack)
    }

    /// A restart: Lamp says the device is back only once it saw it stop answering and answer again.
    func testARestartIsSeenGoingAndComingBack() async throws {
        let device = FakeDevice()
        device.connectResults = [nil, .unreachable, .unreachable, nil]
        let guided = start(try rejoin(), on: device)
        try await until { guided.button != nil }
        XCTAssertEqual(guided.lines, [], "nothing is said while the TV is still on")
        await guided.finished()
        XCTAssertEqual(guided.lines.map(\.text), ["Den TV is back on"])
        XCTAssertEqual(device.connects, 4)
        XCTAssertTrue(guided.handedBack)
    }

    /// Lamp looks before it asks: a device already gone when the step starts is seen gone, and its return is the restart.
    func testARestartUnderWayBeforeTheAskIsSeen() async throws {
        let device = FakeDevice()
        device.connectResults = [.unreachable, nil]
        let guided = start(try rejoin(), on: device)
        await guided.finished()
        XCTAssertEqual(guided.lines.map(\.text), ["Den TV is back on"])
    }

    /// A restart already done, as `unless` reads it: no restart is asked for or waited for, and none is claimed.
    func testARestartAlreadyDoneIsntWaitedFor() async throws {
        let device = FakeDevice()
        device.lists = [["apps": [["id": "dev"]]]]
        let guided = start(try rejoin(unless: true), on: device)
        await guided.finished()
        XCTAssertEqual(guided.lines, [])
        XCTAssertNil(guided.button)
        XCTAssertEqual(device.connects, 1)
        XCTAssertTrue(guided.handedBack)
    }

    /// A device that answers but won't take Lamp hasn't gone anywhere: that stops the steps, and no restart is claimed.
    func testADeviceThatTurnsLampAwayIsntARestart() async throws {
        let device = FakeDevice()
        device.connectResults = [nil, .rejected("It isn't the device Lamp set up."), nil]
        let guided = start(try rejoin(), on: device)
        await guided.finished()
        XCTAssertEqual(guided.failure, "It isn't the device Lamp set up.")
        XCTAssertEqual(guided.lines, [])
        XCTAssertFalse(guided.handedBack)
    }

    /// The person skips a restart that isn't needed: the steps go on, and nothing claims the TV restarted.
    func testSkippingARestartClaimsNothing() async throws {
        let device = FakeDevice()
        let guided = start(try rejoin(), on: device)
        try await until { guided.button == "Not Needed" }
        guided.confirm()
        await guided.finished()
        XCTAssertEqual(guided.lines, [])
        XCTAssertTrue(guided.handedBack)
    }

    /// Skipped while the device isn't answering: the steps go on only once it answers again, so the next request has
    /// a connection, and still nothing claims a restart.
    func testASkipWhileTheDeviceIsAwayWaitsForItToAnswer() async throws {
        let steps = try parsed("""
          {"do": "rejoin", "ask": "Unplug it.", "button": "Not Needed", "every": 1, "done": "{name} is back on"},
          {"do": "request", "uri": "open-app", "done": "Asked {name} to open it"},
          {"do": "handoff", "ask": "Type it."}
        """)
        let device = FakeDevice()
        device.connectResults = [.unreachable, .unreachable, .unreachable, nil]
        let guided = start(steps, on: device)
        try await until { guided.button != nil }
        guided.confirm()
        await guided.finished()
        XCTAssertNil(guided.failure)
        XCTAssertEqual(guided.lines.map(\.text), ["Asked Den TV to open it"])
        XCTAssertTrue(guided.handedBack)
    }

    private func rejoin(unless: Bool = false) throws -> SetupSteps {
        let check = unless ? ", \"unless\": {\"uri\": \"list\", \"json\": \"apps.id\", \"equals\": \"dev\"}" : ""
        return try parsed("""
          {"do": "rejoin", "ask": "Unplug it.", "button": "Not Needed", "every": 1, "done": "{name} is back on"\(check)},
          {"do": "handoff", "ask": "Type it."}
        """)
    }

    private func parsed(_ steps: String) throws -> SetupSteps {
        let body = "```lamp-setup\n{\"connection\": \"webos-second-screen\", \"steps\": [\(steps)]}\n```"
        return try SetupSteps.parse(skill: body).get()
    }

    func testCancellingStopsTheStepsAndClosesTheConnection() async throws {
        let device = FakeDevice()
        device.lists = [["apps": []]]
        var handedBack = false
        let guided = start(steps, on: device) { handedBack = true }
        try await until { device.sent.contains("list") }
        guided.cancel()
        XCTAssertTrue(device.closed)
        XCTAssertFalse(guided.started)
        XCTAssertFalse(guided.holdsDevice)
        let asked = device.sent.count
        try await Task.sleep(for: .seconds(1.5))
        XCTAssertEqual(device.sent.count, asked, "the TV was still asked after the steps were cancelled")
        XCTAssertFalse(handedBack, "a cancelled guide asks nothing of the setup")
    }

    // MARK: Over HTTP

    /// A guide's HTTP checks tell the device answering otherwise from its not answering and from its not taking Lamp,
    /// since only silence is a restart.
    func testHTTPChecksTellApartAnsweringOtherwiseSilenceAndRefusal() async throws {
        let integration = try JSONDecoder().decode(Integration.self, from: Data("""
        {"id": "roku", "name": "Roku", "maker": "Roku", "find": [{"ssdp": "roku:ecp"}],
         "identity": {"os": "Roku OS", "id": {"http": {"port": 8060, "path": "/query/device-info"}, "xml": "serial-number"},
                      "model": {"http": {"port": 8060, "path": "/query/device-info"}, "xml": "model-name"}},
         "steps": [{"id": "developer-mode", "title": "Turn on developer mode", "check": [{"tcp": 8060}]}]}
        """.utf8))
        var device = Device(id: "roku:TEST", kind: .other, maker: "Roku", model: "Roku Ultra", modelID: "4800X",
                            name: "Test Roku", os: "Roku OS", osVersion: "14.0", reach: .network)
        device.address = "192.168.1.20"
        let enabled = [Integration.Condition(http: Request(port: 8060, path: "/query/device-info"), xml: "developer-enabled", equals: "true")]
        func connection(_ answer: @escaping () throws -> DeviceHTTP.Answer) -> HTTPSetupConnection {
            var runner = IntegrationRunner(integration: integration, device: device)
            runner.send = { _, _, _, _ in try answer() }
            return HTTPSetupConnection(runner: runner, reach: [Integration.Condition(http: Request(port: 8060, path: "/query/device-info"))])
        }
        let off = connection { DeviceHTTP.Answer(status: 200, body: Data("<device-info><developer-enabled>false</developer-enabled></device-info>".utf8)) }
        try await off.connect()
        let held = try await off.holds(.http(enabled))
        XCTAssertFalse(held)
        let on = connection { DeviceHTTP.Answer(status: 200, body: Data("<device-info><developer-enabled>true</developer-enabled></device-info>".utf8)) }
        let holds = try await on.holds(.http(enabled))
        XCTAssertTrue(holds)
        // Answering with an error is still answering: the device is there.
        try await connection { DeviceHTTP.Answer(status: 503, body: Data()) }.connect()

        let away = connection { throw URLError(.timedOut) }
        await assertThrows(SetupConnectionError.unreachable) { try await away.connect() }
        await assertThrows(SetupConnectionError.unreachable) { _ = try await away.holds(.http(enabled)) }
        let changed = connection { throw DeviceTLS.Refusal.changed }
        await assertThrows(SetupConnectionError.rejected(DeviceTLS.Refusal.changed.localizedDescription)) { try await changed.connect() }
    }

    // MARK: What a retry, a late check, a rejected sign-in and a closed port can't do

    /// A request of several key presses that failed part way: Lamp can't tell which presses reached the device, so it
    /// doesn't send them again. The guide hands the device back to the setup's own step, with no Try Again.
    func testAKeySequenceThatFailedPartWayIsntSentAgain() async throws {
        let body = """
        ```lamp-setup
        {"connection": "http", "reach": [{"tcp": 8060}], "steps": [
          {"do": "request", "doing": "Pressing keys…", "done": "Pressed",
           "run": [{"http": {"method": "POST", "port": 8060, "path": "/keypress/Home"}}, {"http": {"method": "POST", "port": 8060, "path": "/keypress/Up"}}],
           "unless": [{"http": {"port": 8060, "path": "/query/device-info"}, "xml": "developer-enabled", "equals": "true"}]},
          {"do": "handoff", "ask": "Finish on the device."}
        ]}
        ```
        """
        let steps = try SetupSteps.parse(skill: body).get()
        let device = SequenceDevice()
        var handedBack = 0
        let guided = GuidedSetup()
        guided.start(steps, name: "Den TV", step: "developer-mode", connect: { device }, onFinish: { handedBack += 1 })
        await guided.finished()
        XCTAssertEqual(device.sequences, 1)
        XCTAssertNotNil(guided.failure)
        XCTAssertFalse(guided.state.canRetry, "no Try Again for presses that may have reached the device")
        guided.retry()
        await guided.finished()
        XCTAssertEqual(device.sequences, 1, "the presses were sent again")
        XCTAssertTrue(guided.handedBack)
        XCTAssertEqual(handedBack, 1, "the setup takes its step back and checks it itself")
    }

    /// A check of the setup's own step that was under way when the guide started answers after it: what it found is
    /// left alone, so it can't pass the step or cancel the guide that now holds the device.
    func testACheckUnderWayWhenTheGuideStartsIsDropped() async throws {
        let integration = try JSONDecoder().decode(Integration.self, from: Data("""
        {"id": "simulated", "name": "Simulated", "maker": "Lamp", "find": [{"ssdp": "lamp:simulated"}],
         "identity": {"os": "Simulated OS", "id": {"http": {"port": 8060, "path": "/info"}, "xml": "serial"},
                      "model": {"http": {"port": 8060, "path": "/info"}, "xml": "model"}},
         "steps": [{"id": "developer-mode", "title": "Turn on developer mode", "wait": true,
                    "check": [{"http": {"port": 8060, "path": "/info"}, "xml": "developer", "equals": "true"}]}]}
        """.utf8))
        let guide = Skills.Skill(name: "simulated-guide", description: "A guide.", body: """
        ```lamp-setup
        {"connection": "http", "reach": [{"http": {"port": 8060, "path": "/info"}}], "steps": [
          {"do": "connect", "done": "{name} answers"},
          {"do": "confirm", "ask": "Turn it on.", "button": "Done"},
          {"do": "handoff", "ask": "Finish."}
        ]}
        ```
        """, meta: ["setup-for": "simulated", "setup-step": "developer-mode"])
        var device = Device(id: "simulated:RACE", kind: .other, maker: "Lamp", model: "Simulated", modelID: "SIM-1",
                            name: "Simulated Device", os: "Simulated OS", osVersion: "1.0", reach: .network)
        device.address = "192.168.1.20"
        let gate = Gate()
        let model = DeviceSetupModel(testing: device, integration: integration, skills: [guide.name: guide]) { request, _, _, _ in
            // The first look is the watch's, held until the guide has started; every later one answers at once.
            await gate.firstWaits()
            return DeviceHTTP.Answer(status: 200, body: Data("<info><developer>false</developer></info>".utf8))
        }
        XCTAssertNotNil(model.guide)
        model.watch()
        try await until { gate.waiting }
        model.doItForMe()
        try await until { model.guided.button == "Done" }
        gate.open()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(model.state, .idle, "the watch's late answer was shown over the guide")
        XCTAssertEqual(model.guided.button, "Done", "the guide was cancelled")
        XCTAssertTrue(model.guided.holdsDevice)
        model.guided.cancel()
        model.stopWatching()
    }

    /// A request whose sign-in the device turns away stops the guide with that reason, even where an ordinary failure
    /// would let it go on: the person has to fix the password, as a check that meets a 401 says.
    func testARejectedSignInOnARequestStopsTheGuide() async throws {
        let integration = try JSONDecoder().decode(Integration.self, from: Data("""
        {"id": "simulated", "name": "Simulated", "maker": "Lamp", "find": [{"ssdp": "lamp:simulated"}],
         "identity": {"os": "Simulated OS", "id": {"http": {"port": 8060, "path": "/info"}, "xml": "serial"},
                      "model": {"http": {"port": 8060, "path": "/info"}, "xml": "model"}},
         "steps": [{"id": "developer-mode", "title": "Turn on developer mode", "check": [{"tcp": 8060}]}]}
        """.utf8))
        var device = Device(id: "simulated:AUTH", kind: .other, maker: "Lamp", model: "Simulated", modelID: "SIM-1",
                            name: "Simulated Device", os: "Simulated OS", osVersion: "1.0", reach: .network)
        device.address = "192.168.1.20"
        var asked: [String] = []
        var runner = IntegrationRunner(integration: integration, device: device)
        runner.send = { request, _, _, _ in
            asked.append(request.path)
            return DeviceHTTP.Answer(status: request.path == "/install" ? 401 : 200, body: Data())
        }
        let steps = try SetupSteps.parse(skill: """
        ```lamp-setup
        {"connection": "http", "reach": [{"http": {"port": 8060, "path": "/info"}}], "steps": [
          {"do": "request", "run": [{"http": {"method": "POST", "port": 80, "path": "/install",
                                              "auth": {"digest": true, "user": "dev", "password": "{field:password}"}}}],
           "failed": "Do it yourself.", "continueOnFailure": true},
          {"do": "request", "run": [{"http": {"method": "POST", "port": 8060, "path": "/next"}}], "done": "Went on"},
          {"do": "handoff", "ask": "Finish."}
        ]}
        ```
        """, fields: ["password"]).get()
        let guided = GuidedSetup()
        guided.start(steps, name: "Simulated Device", step: "developer-mode", connect: { HTTPSetupConnection(runner: runner, reach: steps.reach) }, onFinish: {})
        await guided.finished()
        XCTAssertEqual(guided.failure, "The device rejected the sign-in. Check the user name and password, then try again.")
        XCTAssertFalse(asked.contains("/next"), "the guide went on past a rejected sign-in")
        XCTAssertEqual(guided.lines, [])
    }

    /// The device answers but the port `unless` reads is closed (developer mode is off): that isn't the device going
    /// away, so its next answer isn't a restart, and nothing claims one.
    func testAClosedPortInUnlessIsntARestart() async throws {
        let device = FakeDevice()
        device.failing = ["list": .unreachable]
        let guided = start(try rejoin(unless: true), on: device)
        try await until { guided.button == "Not Needed" }
        try await Task.sleep(for: .seconds(2.5))
        XCTAssertEqual(guided.lines, [], "a closed port was taken for a restart")
        XCTAssertTrue(guided.running)
        guided.confirm()
        await guided.finished()
        XCTAssertEqual(guided.lines, [])
        XCTAssertTrue(guided.handedBack)
    }

    /// A check the person asked for, under way when the window closes: its answer is dropped, and the card isn't left
    /// checking, so the step's button works when the window opens again; a check asked for after that is left alone.
    func testACheckDroppedByClosingTheWindowDoesntLeaveTheStepBusy() async throws {
        let integration = try JSONDecoder().decode(Integration.self, from: Data("""
        {"id": "simulated", "name": "Simulated", "maker": "Lamp", "find": [{"ssdp": "lamp:simulated"}],
         "identity": {"os": "Simulated OS", "id": {"http": {"port": 8060, "path": "/info"}, "xml": "serial"},
                      "model": {"http": {"port": 8060, "path": "/info"}, "xml": "model"}},
         "steps": [{"id": "reachable", "title": "Let Lamp reach it", "check": [{"http": {"port": 8060, "path": "/info"}}]}]}
        """.utf8))
        var device = Device(id: "simulated:CLOSE", kind: .other, maker: "Lamp", model: "Simulated", modelID: "SIM-1",
                            name: "Simulated Device", os: "Simulated OS", osVersion: "1.0", reach: .network)
        device.address = "192.168.1.20"
        let gate = Gate()
        // Every check is held until the test lets it go, and then finds the device not ready (nothing is kept).
        let model = DeviceSetupModel(testing: device, integration: integration, skills: [:]) { _, _, _, _ in
            await gate.waits()
            return DeviceHTTP.Answer(status: 503, body: Data())
        }
        model.act()
        try await until { gate.count == 1 }
        XCTAssertEqual(model.state, .checking)
        model.windowClosed()
        model.watch()
        XCTAssertEqual(model.state, .idle, "the step was left checking after its window closed")
        // Opened again, the person checks again; the first check's late answer leaves this one as it is.
        model.act()
        try await until { gate.count == 2 }
        gate.open()
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(model.state, .checking, "the dropped check's answer touched the newer one")
        gate.open()
        try await until { model.state != .checking }
        XCTAssertEqual(model.state, .waiting("Waiting for Simulated Device…"))
    }

    /// Key presses turned away part way through: still sent only once and handed back, with the device's own reason.
    func testARejectionPartWayThroughKeyPressesSaysWhy() async throws {
        let steps = try SetupSteps.parse(skill: """
        ```lamp-setup
        {"connection": "http", "reach": [{"tcp": 8060}], "steps": [
          {"do": "request", "doing": "Pressing keys…", "done": "Pressed",
           "run": [{"http": {"method": "POST", "port": 8060, "path": "/keypress/Home"}}, {"http": {"method": "POST", "port": 8060, "path": "/keypress/Up"}}],
           "unless": [{"http": {"port": 8060, "path": "/query/device-info"}, "xml": "developer-enabled", "equals": "true"}]},
          {"do": "handoff", "ask": "Finish on the device."}
        ]}
        ```
        """).get()
        let device = RejectingSequenceDevice()
        let guided = GuidedSetup()
        guided.start(steps, name: "Den TV", step: "developer-mode", connect: { device }, onFinish: {})
        await guided.finished()
        XCTAssertEqual(guided.failure, "The device rejected the sign-in. Check the user name and password, then try again.")
        XCTAssertFalse(guided.state.canRetry)
        XCTAssertTrue(guided.handedBack)
        guided.retry()
        await guided.finished()
        XCTAssertEqual(device.sequences, 1)
    }

    /// A wait whose check reads a port that isn't open yet (a Roku's installer on port 80, after the Roku already says
    /// developer mode is on) goes on waiting while the device answers where `reach` reads it: a closed port isn't the
    /// device going away, so the guide doesn't stop with a failure.
    func testAWaitGoesOnWhileAPortIsntOpenYet() async throws {
        let integration = try JSONDecoder().decode(Integration.self, from: Data("""
        {"id": "simulated", "name": "Simulated", "maker": "Lamp", "find": [{"ssdp": "lamp:simulated"}],
         "identity": {"os": "Simulated OS", "id": {"http": {"port": 8060, "path": "/query/device-info"}, "xml": "serial"},
                      "model": {"http": {"port": 8060, "path": "/query/device-info"}, "xml": "model"}},
         "steps": [{"id": "developer-mode", "title": "Turn on developer mode", "check": [{"tcp": 8060}]}]}
        """.utf8))
        var device = Device(id: "simulated:PORT", kind: .other, maker: "Lamp", model: "Simulated", modelID: "SIM-1",
                            name: "Simulated Device", os: "Simulated OS", osVersion: "1.0", reach: .network)
        device.address = "192.168.1.20"
        var installerAsked = 0
        var runner = IntegrationRunner(integration: integration, device: device)
        runner.send = { request, _, _, _ in
            guard request.port == 80 else {
                return DeviceHTTP.Answer(status: 200, body: Data("<device-info><developer-enabled>true</developer-enabled></device-info>".utf8))
            }
            // The installer's port opens on the third look.
            installerAsked += 1
            if installerAsked < 3 { throw URLError(.cannotConnectToHost) }
            return DeviceHTTP.Answer(status: 200, body: Data())
        }
        let steps = try SetupSteps.parse(skill: """
        ```lamp-setup
        {"connection": "http", "reach": [{"http": {"port": 8060, "path": "/query/device-info"}}], "steps": [
          {"do": "wait", "every": 1, "doing": "Waiting…", "done": "Developer mode is on",
           "until": [{"http": {"port": 8060, "path": "/query/device-info"}, "xml": "developer-enabled", "equals": "true"},
                     {"http": {"port": 80, "path": "/"}}]},
          {"do": "handoff", "ask": "Type the password."}
        ]}
        ```
        """).get()
        let guided = GuidedSetup()
        guided.start(steps, name: "Simulated Device", step: "developer-mode", connect: { HTTPSetupConnection(runner: runner, reach: steps.reach) }, onFinish: {})
        await guided.finished()
        XCTAssertNil(guided.failure, "a port that wasn't open yet stopped the guide")
        XCTAssertEqual(guided.lines.map(\.text), ["Developer mode is on"])
        XCTAssertEqual(installerAsked, 3)
        XCTAssertTrue(guided.handedBack)
    }

    private func assertThrows(_ expected: SetupConnectionError, _ body: () async throws -> Void, line: UInt = #line) async {
        do { try await body(); XCTFail("didn't throw", line: line) } catch { XCTAssertEqual(error as? SetupConnectionError, expected, line: line) }
    }

    private func until(_ condition: @escaping () -> Bool) async throws {
        for _ in 0..<100 where !condition() { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertTrue(condition(), "timed out")
    }
}

/// An HTTP-like device whose key presses fail part way through the first time they're sent.
private final class SequenceDevice: SetupConnection {
    var sequences = 0
    func connect() async throws {}
    func send(_ step: SetupSteps.Step) async throws {
        sequences += 1
        // One press reached the device before the connection dropped.
        if sequences == 1 { throw SetupConnectionError.unreachable }
    }
    func holds(_ check: SetupSteps.Check) async throws -> Bool { false }
    func close() {}
}

/// Holds requests until opened, in the order they came: the first only (`firstWaits`), or each (`waits`).
@MainActor
private final class Gate {
    private var held: [CheckedContinuation<Void, Never>] = []
    private(set) var count = 0
    private var first = true
    var waiting: Bool { !held.isEmpty }
    func firstWaits() async {
        guard first else { return }
        first = false
        await waits()
    }
    func waits() async { await withCheckedContinuation { held.append($0); count += 1 } }
    /// Lets the oldest held request go on.
    func open() { if !held.isEmpty { held.removeFirst().resume() } }
}

/// An HTTP-like device whose key presses are turned away part way through: the device answers, but not to Lamp.
private final class RejectingSequenceDevice: SetupConnection {
    var sequences = 0
    func connect() async throws {}
    func send(_ step: SetupSteps.Step) async throws {
        sequences += 1
        throw SetupConnectionError.rejected("The device rejected the sign-in. Check the user name and password, then try again.")
    }
    func holds(_ check: SetupSteps.Check) async throws -> Bool { false }
    func close() {}
}

private final class FakeDevice: SocketSetupConnection {
    var connectFailure: SetupConnectionError?
    /// What each connect does, in turn (nil: it lets Lamp in); once they run out, `connectFailure`.
    var connectResults: [SetupConnectionError?] = []
    var failing: [String: SetupConnectionError] = [:]
    /// What each `list` request answers, in turn; the last one again once they run out.
    var lists: [[String: Any]] = []
    var sent: [String] = []
    var connects = 0
    var closed = false

    /// Whether the last connect let Lamp in: a request without it finds no one there, as on a real socket.
    var connected = false

    func connect() async throws {
        connects += 1
        connected = false
        if !connectResults.isEmpty { if let result = connectResults.removeFirst() { throw result }; connected = true; return }
        if let connectFailure { throw connectFailure }
        connected = true
    }

    func request(_ uri: String, payload: [String: Any]) async throws -> [String: Any] {
        sent.append(uri)
        guard connected else { throw SetupConnectionError.unreachable }
        if let failure = failing[uri] { throw failure }
        guard uri == "list" else { return ["returnValue": true] }
        return lists.count > 1 ? lists.removeFirst() : lists.first ?? [:]
    }

    func close() { closed = true }
}

private extension Result where Failure == SetupSteps.Problem {
    var failureReason: String? { if case .failure(let problem) = self { problem.reason } else { nil } }
}
