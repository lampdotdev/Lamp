import XCTest
import Network
@testable import Lamp

/// `LampConnection`, the helper every app made with Lamp uses to sign the person in to another service: what
/// Lamp writes into an app for it, what the agent is told, and the helper itself, compiled as apps get it and
/// run against a stand-in for the service on this Mac.
final class ConnectionTests: XCTestCase {
    private var root: URL?
    private var server: StandIn?

    override func tearDown() {
        server?.stop()
        Self.forget()
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    /// A service as an entry in `Connections` would be, with a registration.
    private static let service: Connections.Service = {
        var service = Connections.github
        service.clientID = "lamp-test-client"
        return service
    }()

    private func app(platform: Platform = .mac) throws -> LampProject {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-connection-test-\(UUID().uuidString)")
        self.root = root
        return try Template.scaffold(name: "Repo Radar", platform: platform, in: root)
    }

    // MARK: - What Lamp writes and says

    func testEveryEntryCanBeWrittenAsAnApp() {
        for service in Connections.known {
            XCTAssertNotNil(service.id.range(of: "^[a-z][A-Za-z0-9]*$", options: .regularExpression), service.id)
            for address in [service.deviceURL, service.tokenURL, service.accountURL] {
                XCTAssertEqual(URL(string: address)?.scheme, "https", address)
            }
            XCTAssertFalse(service.hosts.isEmpty)
            XCTAssertNotNil(NSImage(data: Data(base64Encoded: service.icon) ?? Data()), "\(service.name)'s mark isn't a picture")
            XCTAssertNotNil(ConnectionCard.page(service, app: "Repo Radar"), "\(service.name) has no page to register an app on")
        }
    }

    // MARK: - Where an app's id comes from

    private func write(_ code: String, in project: LampProject) throws {
        try code.write(to: project.dir.appendingPathComponent("Sources/ContentView.swift"), atomically: true, encoding: .utf8)
    }

    private func declare(_ json: String, in project: LampProject) throws {
        try json.write(to: project.dir.appendingPathComponent(Template.Capabilities.file), atomically: true, encoding: .utf8)
    }

    func testAnAppThatNamesAServiceWithNoIdWaitsForOne() throws {
        let project = try app()
        XCTAssertEqual(Connections.waiting(in: project), [])
        try write(#"LampConnectionGate(.github, scopes: ["repo"], reason: "") { Text("in") }"#, in: project)
        XCTAssertEqual(Connections.waiting(in: project).map(\.id), ["github"])
        XCTAssertTrue(Template.supportSwift(for: project).contains(#"id: "github", name: "GitHub", clientID: """#))

        // The id whoever builds the app pastes into the card is kept with the app, and the app is given it.
        try Connections.keep("Ov23liTESTtestTEST00", for: "github", in: project)
        XCTAssertEqual(Connections.waiting(in: project), [])
        XCTAssertTrue(Template.supportSwift(for: project).contains(#"id: "github", name: "GitHub", clientID: "Ov23liTESTtestTEST00""#))
        XCTAssertEqual(Template.Capabilities.load(project).checked.connections, [Connections.Declared(id: "github", clientID: "Ov23liTESTtestTEST00")])
    }

    func testOneCardForEachServiceInAChat() {
        XCTAssertTrue(ConnectionCard.isNeeded("github", after: []))
        XCTAssertFalse(ConnectionCard.isNeeded("github", after: [LogLine(kind: .connect, text: "github")]))
        XCTAssertTrue(ConnectionCard.isNeeded("acme", after: [LogLine(kind: .connect, text: "github")]))
    }

    func testTheCardOpensThePageWithTheAppsNameFilledIn() throws {
        let page = try XCTUnwrap(ConnectionCard.page(Connections.github, app: "Repo Radar & Co"))
        XCTAssertEqual(page.host, "github.com")
        XCTAssertTrue(page.absoluteString.contains("oauth_application%5Bname%5D=Repo%20Radar%20%26%20Co&"), page.absoluteString)
        XCTAssertEqual(ConnectionCard.filled("{{NAME}}", app: "Repo Radar"), "Repo Radar")
        XCTAssertEqual(ConnectionCard.idLabel(Connections.github), "Client ID")
        XCTAssertEqual(ConnectionCard.instructions(Connections.github, app: "Repo Radar"), "Tick Enable Device Flow, then press Register application.")
        var bare = Connections.github
        bare.register?.notes = nil
        XCTAssertEqual(ConnectionCard.instructions(bare, app: "Repo Radar"), "Fill in the form there and register the app.")
    }

    func testOnePressTakesTheIdFromTheClipboard() {
        XCTAssertEqual(ConnectionCard.pasted("  Ov23liTESTtestTEST00 \n"), "Ov23liTESTtestTEST00")
        XCTAssertEqual(ConnectionCard.pasted("\n\nOv23liTESTtestTEST00\nsomething else"), "Ov23liTESTtestTEST00")
        XCTAssertEqual(ConnectionCard.pasted(nil), "")
        XCTAssertEqual(ConnectionCard.pasted(" \n "), "")
    }

    func testTheIdTravelsWithASharedApp() throws {
        let project = try app()
        try Connections.keep("Ov23liTESTtestTEST00", for: "github", in: project)
        let shared = try Sharing.open(try Sharing.export(project))
        XCTAssertEqual(shared.capabilities.connections, [Connections.Declared(id: "github", clientID: "Ov23liTESTtestTEST00")])
        let copy = try Template.scaffold(name: "Copy", in: try XCTUnwrap(root).appendingPathComponent("copies"))
        try Sharing.install(shared, into: copy)
        XCTAssertEqual(Connections.services(for: copy).first { $0.id == "github" }?.clientID, "Ov23liTESTtestTEST00")
    }

    private static let acme = """
    {"connections": [{"id": "acme", "name": "Acme", "deviceURL": "https://acme.example/oauth/device/code",
      "tokenURL": "https://acme.example/oauth/token", "hosts": ["api.acme.example"], "accountURL": "https://api.acme.example/me",
      "accountField": "name", "scopes": {"read": "See your projects"},
      "register": {"url": "https://acme.example/apps/new", "values": [{"label": "App name", "value": "{{NAME}}"}],
                   "notes": ["Turn on device sign-in."], "idLabel": "Client ID"}}]}
    """

    func testAnAppCanDescribeAServiceLampHasNoEntryFor() throws {
        let project = try app()
        try declare(Self.acme, in: project)
        let acme = try XCTUnwrap(Connections.services(for: project).first { $0.id == "acme" })
        XCTAssertEqual(acme.name, "Acme")
        XCTAssertEqual(acme.hosts, ["api.acme.example"])
        XCTAssertEqual(acme.register?.values, [.init(label: "App name", value: "{{NAME}}")])
        // Declared with no id, it waits for one whatever the code says, and the app can already name it.
        XCTAssertEqual(Connections.waiting(in: project).map(\.id), ["acme"])
        XCTAssertTrue(Template.supportSwift(for: project).contains("static let acme = LampService("))
        XCTAssertEqual(ConnectionCard.page(acme, app: "Repo Radar")?.absoluteString, "https://acme.example/apps/new")
    }

    func testOnlyAWholeAndPlainServiceIsTaken() {
        func kept(_ change: (inout Connections.Declared) -> Void) -> [String] {
            var entry = Connections.Declared(id: "acme", name: "Acme", deviceURL: "https://acme.example/device", tokenURL: "https://acme.example/token",
                                             hosts: ["api.acme.example"])
            change(&entry)
            return Connections.checked([entry]).map(\.id)
        }
        XCTAssertEqual(kept { _ in }, ["acme"])
        XCTAssertEqual(kept { $0.deviceURL = "http://acme.example/device" }, [])
        XCTAssertEqual(kept { $0.tokenURL = "https://user:pass@acme.example/token" }, [])
        XCTAssertEqual(kept { $0.tokenURL = nil }, [])
        XCTAssertEqual(kept { $0.hosts = ["127.0.0.1", "api acme"] }, [])
        XCTAssertEqual(kept { $0.name = "Acme\nGitHub" }, [])
        XCTAssertEqual(kept { $0.id = "Acme; import Foundation" }, [])
        XCTAssertEqual(kept { $0.id = "init" }, [])
        // Not by one of Lamp's names at another address.
        XCTAssertEqual(kept { $0.name = "github" }, [])

        // One of Lamp's keeps its id and none of the rest.
        let github = Connections.Declared(id: "github", clientID: "Ov23liTESTtestTEST00", name: "GitHub", deviceURL: "https://evil.example/device",
                                          tokenURL: "https://evil.example/token", hosts: ["evil.example"])
        XCTAssertEqual(Connections.checked([github]), [Connections.Declared(id: "github", clientID: "Ov23liTESTtestTEST00")])
        XCTAssertEqual(Connections.services(declared: [github]).first?.tokenURL, Connections.github.tokenURL)
        XCTAssertEqual(Connections.checked([Connections.Declared(id: "github", clientID: "has spaces")]), [])
    }

    func testAWrongFieldDoesNotLoseTheRestOfTheFile() throws {
        let project = try app()
        try declare(#"{"opens": ["png"], "connections": [{"id": "github", "clientID": 12}, {"id": "github", "clientID": "Ov23liTESTtestTEST00", "hosts": "x"}]}"#, in: project)
        let read = Template.Capabilities.load(project).checked
        XCTAssertEqual(read.opens, ["png"])
        XCTAssertEqual(read.connections, [Connections.Declared(id: "github", clientID: "Ov23liTESTtestTEST00")])
    }

    func testASharedAppWithAServiceOfItsOwnSaysWhereItSignsIn() throws {
        let project = try app()
        try declare(Self.acme, in: project)
        let found = Sharing.inspect(try Sharing.open(try Sharing.export(project)))
        let line = try XCTUnwrap(found.detected.first { $0.label.contains("Acme") })
        XCTAssertEqual(line.label, "Asks you to sign in to Acme at api.acme.example, a service Lamp doesn't know")
        XCTAssertEqual(line.level, .sensitive)
    }

    func testAnIdIsCheckedWithTheServiceBeforeItIsKept() async throws {
        try start()
        var service = Connections.github
        service.deviceURL = "http://127.0.0.1:\(try XCTUnwrap(server).port)/login/device/code"
        let good = await Connections.verify("lamp-test-client", for: service)
        XCTAssertEqual(good, .good)
        let off = await Connections.verify("flow-off-client", for: service)
        XCTAssertEqual(off, .refused("GitHub knows this app, but its device flow is off. Turn that on in the app's page there, then save again."))
        let unknown = await Connections.verify("somebody-else", for: service)
        XCTAssertEqual(unknown, .refused("GitHub doesn't know that id. Copy it again from the app's page there."))
        let pasted = await Connections.verify("the whole page, pasted", for: service)
        XCTAssertEqual(pasted, .refused("That doesn't look like an id from GitHub. Copy it again from the page."))
        service.deviceURL = "http://127.0.0.1:9/login/device/code"
        let away = await Connections.verify("lamp-test-client", for: service)
        XCTAssertEqual(away, .unreachable)
    }

    func testAnAppGetsTheServicesAsNames() throws {
        let project = try app()
        let support = Template.supportSwift(for: project, services: [Self.service])
        XCTAssertTrue(support.contains("static let github = LampService("))
        XCTAssertTrue(support.contains(#"clientID: "lamp-test-client""#))
        XCTAssertFalse(support.contains("{{SERVICES}}"))
        // Nothing an app carries is a secret: the sign-in needs none.
        XCTAssertFalse(support.lowercased().contains("client_secret"))
        XCTAssertFalse(Template.supportSwift(for: project, services: []).contains("static let github"))
        // By itself, an app gets Lamp's services, to name before it has an id for any of them.
        XCTAssertTrue(Template.supportSwift(for: project).contains("static let github = LampService("))
    }

    func testTheAgentIsToldOnBothKindsOfApp() {
        for prompt in [Agent.prompt(platform: .mac, device: "Mac", services: [Self.service]),
                       Agent.prompt(platform: .iphone, device: "iPhone", services: [Self.service])] {
            XCTAssertTrue(prompt.contains("`LampConnection` from LampSupport.swift is strongly recommended"))
            XCTAssertTrue(prompt.contains("GitHub (`.github`; its API at https://api.github.com"))
            XCTAssertTrue(prompt.contains(#"LampConnectionGate(.github, scopes: ["repo"]"#))
            XCTAssertTrue(prompt.contains("LampConnection.send(request, to: .github)"))
            XCTAssertTrue(prompt.contains("Never ask the person for a token, key or password"))
            XCTAssertTrue(prompt.contains("Lamp puts a card in the chat"))
            XCTAssertTrue(prompt.contains("never put a secret, key or token in the app"))
        }
        // Lamp's services are named whether or not there is an id yet: registering is the card's job.
        XCTAssertTrue(Agent.systemPrompt.contains("GitHub (`.github`"))
        XCTAssertTrue(Agent.iPhonePrompt(for: .iphone).contains("GitHub (`.github`"))
    }

    func testASharedAppThatConnectsSaysSo() throws {
        let line = try XCTUnwrap(Sharing.checklist.first { $0.patterns.contains("LampConnect") })
        XCTAssertEqual(line.level, .powerful)
        for use in ["LampConnectionGate(.github, reason: \"\") { }", "LampConnection.send(request, to: .github)", "LampConnectButton(.github)",
                    ".lampConnectionSheet(isPresented: $asking, .github, reason: \"\")"] {
            XCTAssertTrue(line.patterns.contains { use.contains($0) }, use)
        }
    }

    // MARK: - The helper, as an app has it

    /// The library with a small program at its end that drives the helper the way the screen does, one step
    /// for each word it's given. Built once for all the tests below.
    private static let harness: Result<URL, Error> = Result {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-connection-harness-\(UUID().uuidString)")
        let project = try Template.scaffold(name: "Harness", in: folder.appendingPathComponent("apps"))
        let source = Template.supportSwift(for: project, services: [service]) + driver
        try source.write(to: folder.appendingPathComponent("Harness.swift"), atomically: true, encoding: .utf8)
        let built = try run(Shell.compatibleSDK + "xcrun swiftc -parse-as-library -o harness Harness.swift 2>&1", in: folder)
        guard built.status == 0 else { throw Problem(text: String(built.output.suffix(4000))) }
        return folder.appendingPathComponent("harness")
    }

    private struct Problem: Error, CustomStringConvertible {
        let text: String
        var description: String { text }
    }

    private static let driver = #"""

    @main
    enum ConnectionHarness {
        static func main() async {
            let service = LampService.github
            for step in CommandLine.arguments.dropFirst() {
                switch step {
                case "connect":
                    let state = await MainActor.run { LampConnectionState(service, scopes: ["repo"]) }
                    await MainActor.run { state.connect() }
                    var shown = false
                    waiting: while true {
                        let (on, step) = await MainActor.run { (state.isOn, state.step) }
                        if on {
                            print("connected as \(state.account ?? "nobody")")
                            break waiting
                        }
                        switch step {
                        case .failed(let why):
                            print("failed: \(why)")
                            break waiting
                        case .waiting(let code) where !shown:
                            print("code \(code.shown) at \(code.page.path)")
                            shown = true
                        default: break
                        }
                        try? await Task.sleep(nanoseconds: 50_000_000)
                    }
                case "has": print("has \(LampConnection.has(service, scopes: ["repo"]))")
                case "has-more": print("has-more \(LampConnection.has(service, scopes: ["repo", "gist"]))")
                case "call": print(await call("https://api.github.com/user", service))
                case "elsewhere": print(await call("https://example.com/user", service))
                case "plain": print(await call("http://api.github.com/user", service))
                case "five":
                    let answers = await withTaskGroup(of: String.self) { group in
                        for _ in 0..<5 { group.addTask { await call("https://api.github.com/user", service) } }
                        var answers: [String] = []
                        for await answer in group { answers.append(answer) }
                        return answers
                    }
                    print("five \(answers.filter { $0.hasPrefix("call 200") }.count)")
                case "wait": try? await Task.sleep(nanoseconds: 1_500_000_000)
                case "leave-during-call":
                    // The person disconnects while a call is out renewing the sign-in.
                    async let answer = call("https://api.github.com/user", service)
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    LampConnection.disconnect(service)
                    print(await answer)
                case "disconnect": LampConnection.disconnect(service)
                default: print("unknown step \(step)")
                }
            }
        }

        static func call(_ address: String, _ service: LampService) async -> String {
            do {
                let (data, response) = try await LampConnection.send(URLRequest(url: URL(string: address)!), to: service)
                return "call \(response.statusCode) \(String(decoding: data, as: UTF8.self))"
            } catch let failure as LampConnection.Failure {
                return "refused: \(failure.message) notConnected=\(failure.notConnected)"
            } catch {
                return "error: \(error.localizedDescription)"
            }
        }
    }

    """#

    @discardableResult
    private static func run(_ command: String, in directory: URL, env: [String: String] = [:]) throws -> (status: Int32, output: String) {
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

    /// The stand-in's sign-ins are kept apart from real ones, under their own name in the Keychain. Taken
    /// out by the system's own tool, which needs nobody's leave to delete.
    private static func forget() {
        _ = try? run("security delete-generic-password -s lamp -a lamp-connection-github-test >/dev/null 2>&1", in: FileManager.default.temporaryDirectory)
    }

    /// Runs the steps in one launch of the harness, pointed at the stand-in, and gives back what it printed
    /// (without the helper's own log lines).
    private func drive(_ steps: String...) throws -> [String] {
        let harness = try Self.harness.get()
        let server = try XCTUnwrap(self.server)
        let ran = try Self.run("./harness " + steps.joined(separator: " "), in: harness.deletingLastPathComponent(),
                               env: ["LAMP_CONNECTION_SERVER": "http://127.0.0.1:\(server.port)"])
        XCTAssertEqual(ran.status, 0, ran.output)
        return ran.output.split(separator: "\n").map(String.init).filter { !$0.hasPrefix("LampConnection:") }
    }

    private func start(_ configure: (StandIn) -> Void = { _ in }) throws {
        Self.forget()
        let server = try StandIn()
        configure(server)
        self.server = server
    }

    func testThePersonEntersACodeAndTheAppIsConnected() throws {
        try start { $0.pendingAnswers = 2; $0.slowDownOnce = true }
        let said = try drive("has", "connect", "has", "has-more", "call")
        XCTAssertEqual(said, ["has false", "code WDJB-MJHT at /login/device", "connected as octocat", "has true", "has-more false",
                              #"call 200 {"login":"octocat"}"#])

        let server = try XCTUnwrap(self.server)
        let asked = try XCTUnwrap(server.requests.first { $0.path == "/login/device/code" })
        XCTAssertEqual(asked.fields, ["client_id": "lamp-test-client", "scope": "repo"])
        let polls = server.requests.filter { $0.path == "/login/oauth/access_token" }
        XCTAssertEqual(polls.count, 4)   // twice not yet, once too fast, then yes
        XCTAssertEqual(polls.last?.fields, ["client_id": "lamp-test-client", "device_code": "device-1",
                                            "grant_type": "urn:ietf:params:oauth:grant-type:device_code"])
        XCTAssertEqual(server.requests.last?.authorization, "Bearer access-1")
    }

    func testTheSignInIsStillThereTheNextTimeTheAppOpens() throws {
        try start()
        XCTAssertEqual(try drive("connect").last, "connected as octocat")
        XCTAssertEqual(try drive("has", "call"), ["has true", #"call 200 {"login":"octocat"}"#])
        XCTAssertEqual(try drive("disconnect", "has", "call"), ["has false", "refused: Connect to GitHub first. notConnected=true"])
        XCTAssertEqual(try drive("has"), ["has false"])
    }

    func testTurningItDownOnTheServiceSaysSo() throws {
        try start { $0.outcome = .denied }
        XCTAssertEqual(try drive("connect", "has"), ["code WDJB-MJHT at /login/device", "failed: The request was turned down on GitHub.", "has false"])
    }

    func testACodeThatRanOutSaysSo() throws {
        try start { $0.outcome = .expired }
        XCTAssertEqual(try drive("connect").last, "failed: That code ran out. Connect again for a new one.")
    }

    func testTheSignInOnlyGoesToTheService() throws {
        try start()
        let said = try drive("connect", "elsewhere", "plain")
        XCTAssertEqual(Array(said.dropFirst(2)), Array(repeating: "refused: The GitHub connection only reaches api.github.com, over https. notConnected=false", count: 2))
        // Neither request left the app.
        XCTAssertEqual(try XCTUnwrap(server).requests.filter { $0.path == "/user" }.count, 1)
    }

    func testASignInAboutToRunOutIsRenewedFirst() throws {
        try start { $0.lifetime = 30 }
        let said = try drive("connect", "call", "call")
        XCTAssertEqual(Array(said.suffix(2)), Array(repeating: #"call 200 {"login":"octocat"}"#, count: 2))
        let server = try XCTUnwrap(self.server)
        // Each renewal hands out a new renewal code, and the app used the newest each time.
        XCTAssertEqual(server.renewals.map { $0.fields["refresh_token"] }, ["refresh-1", "refresh-2"])
        XCTAssertEqual(server.renewals.first?.fields, ["client_id": "lamp-test-client", "grant_type": "refresh_token", "refresh_token": "refresh-1"])
        XCTAssertEqual(server.requests.last?.authorization, "Bearer access-3")
    }

    func testASignInTheServiceStoppedTakingIsRenewedAndTheCallMadeAgain() throws {
        try start { $0.lifetime = 3600 }
        XCTAssertEqual(try drive("connect").last, "connected as octocat")
        let server = try XCTUnwrap(self.server)
        server.endAccess()
        // A new launch, so the renewed sign-in was read from and written to the Keychain.
        XCTAssertEqual(try drive("call"), [#"call 200 {"login":"octocat"}"#])
        XCTAssertEqual(server.renewals.count, 1)
        XCTAssertEqual(try drive("call"), [#"call 200 {"login":"octocat"}"#])
        XCTAssertEqual(server.renewals.count, 1)
        XCTAssertEqual(server.requests.last?.authorization, "Bearer access-2")
    }

    func testCallsAtTheSameMomentRenewOnce() throws {
        try start { $0.lifetime = 3600 }
        XCTAssertEqual(try drive("connect").last, "connected as octocat")
        let server = try XCTUnwrap(self.server)
        server.endAccess()
        XCTAssertEqual(try drive("five"), ["five 5"])
        XCTAssertEqual(server.renewals.count, 1)
    }

    func testARenewalTheServiceRefusesDisconnects() throws {
        try start { $0.lifetime = 3600 }
        XCTAssertEqual(try drive("connect").last, "connected as octocat")
        let server = try XCTUnwrap(self.server)
        server.endAccess()
        server.refusesRenewal = true
        XCTAssertEqual(try drive("call", "has"), ["refused: Connect to GitHub first. notConnected=true", "has false"])
        XCTAssertEqual(try drive("has"), ["has false"])
    }

    func testAServiceTooBusyToRenewKeepsTheSignIn() throws {
        try start { $0.lifetime = 3600 }
        XCTAssertEqual(try drive("connect").last, "connected as octocat")
        let server = try XCTUnwrap(self.server)
        server.endAccess()
        server.busyRenewals = 2
        // Busy in the way of an error page with a status, then in the words of OAuth: neither says anything
        // about the sign-in, so it's kept and the call can be made again.
        XCTAssertEqual(try drive("call", "has", "call", "has"),
                       ["refused: GitHub couldn't renew your sign-in just now. Try again in a moment. notConnected=false", "has true",
                        "refused: GitHub couldn't renew your sign-in just now. Try again in a moment. notConnected=false", "has true"])
        XCTAssertEqual(try drive("call", "has"), [#"call 200 {"login":"octocat"}"#, "has true"])
        XCTAssertEqual(server.renewals.map { $0.fields["refresh_token"] }, ["refresh-1", "refresh-1", "refresh-1"])
    }

    func testARenewalThatComesBackLateDoesNotUndoDisconnect() throws {
        try start { $0.lifetime = 3600 }
        XCTAssertEqual(try drive("connect").last, "connected as octocat")
        let server = try XCTUnwrap(self.server)
        server.endAccess()
        server.renewalDelay = 1.5
        XCTAssertEqual(try drive("leave-during-call", "has"), ["refused: Connect to GitHub first. notConnected=true", "has false"])
        XCTAssertEqual(server.renewals.count, 1)
        // Nor was it put back in the Keychain for the next time the app opens.
        XCTAssertEqual(try drive("has"), ["has false"])
    }

    func testASignInThatEndedWithNothingToRenewItDisconnects() throws {
        try start()
        XCTAssertEqual(try drive("connect").last, "connected as octocat")
        try XCTUnwrap(server).endAccess()
        XCTAssertEqual(try drive("call", "has"), ["refused: Connect to GitHub first. notConnected=true", "has false"])
    }

    /// The same source has to compile for an iPhone app. Needs Xcode's iPhone simulator SDK.
    func testTheLibraryCompilesForAnIPhoneApp() throws {
        let sdk = try Self.run("xcrun --sdk iphonesimulator --show-sdk-path 2>/dev/null", in: FileManager.default.temporaryDirectory)
        let path = sdk.output.trimmingCharacters(in: .whitespacesAndNewlines)
        try XCTSkipIf(sdk.status != 0 || path.isEmpty, "no iPhone simulator SDK on this Mac")
        let project = try app(platform: .iphone)
        let file = project.dir.appendingPathComponent("Sources/LampSupport.swift")
        try declare(Self.acme, in: project)
        try Template.supportSwift(for: project).write(to: file, atomically: true, encoding: .utf8)
        let checked = try Self.run("xcrun swiftc -typecheck -parse-as-library -target arm64-apple-ios17.0-simulator -sdk '\(path)' Sources/LampSupport.swift 2>&1",
                                   in: project.dir)
        XCTAssertEqual(checked.status, 0, String(checked.output.suffix(4000)))
    }
}

/// A service's sign-in, on this Mac: the three addresses GitHub's device flow uses, answering as it does.
private final class StandIn {
    struct Request {
        let method: String
        let path: String
        let fields: [String: String]
        let authorization: String?
    }
    enum Outcome { case approved, denied, expired }

    /// How many times the app is told "not yet" before the answer.
    var pendingAnswers = 1
    var slowDownOnce = false
    var outcome = Outcome.approved
    /// Seconds a sign-in lasts. Nil is GitHub's own kind: it doesn't run out and comes with nothing to renew it.
    var lifetime: Int?
    var refusesRenewal = false
    /// How many renewals are answered as a service that is busy: first with a 503, then in OAuth's own words.
    var busyRenewals = 0
    /// Seconds a renewal's answer takes.
    var renewalDelay = 0.0

    private let listener: NWListener
    private let queue = DispatchQueue(label: "lamp.connection.stand-in")
    private let lock = NSLock()
    private var log: [Request] = []
    private var issued = 0
    private var ended = false
    private(set) var port: UInt16 = 0

    var requests: [Request] { lock.withLock { log } }
    var renewals: [Request] { requests.filter { $0.fields["grant_type"] == "refresh_token" } }

    /// The service stops taking the sign-in it last gave, as when it runs out early or is ended there.
    func endAccess() { lock.withLock { ended = true } }

    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in
            if case .ready = state { ready.signal() }
            if case .failed = state { ready.signal() }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            connection.start(queue: self.queue)
            self.read(connection, Data())
        }
        listener.start(queue: queue)
        guard ready.wait(timeout: .now() + 5) == .success, let port = listener.port?.rawValue else { throw URLError(.cannotConnectToHost) }
        self.port = port
    }

    func stop() { listener.cancel() }

    private func read(_ connection: NWConnection, _ soFar: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, done, error in
            guard let self else { return }
            let all = soFar + (data ?? Data())
            if let request = Self.parse(all) {
                let (status, body) = self.answer(request)
                let head = "HTTP/1.1 \(status) OK\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n"
                let late = request.fields["grant_type"] == "refresh_token" ? self.lock.withLock { self.renewalDelay } : 0
                self.queue.asyncAfter(deadline: .now() + late) {
                    connection.send(content: Data((head + body).utf8), completion: .contentProcessed { _ in connection.cancel() })
                }
            } else if done || error != nil {
                connection.cancel()
            } else {
                self.read(connection, all)
            }
        }
    }

    /// A whole request, once all of it has arrived.
    private static func parse(_ data: Data) -> Request? {
        guard let end = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let lines = String(decoding: data[..<end.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
        let first = lines[0].split(separator: " ")
        guard first.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let body = data[end.upperBound...]
        guard body.count >= Int(headers["content-length"] ?? "0") ?? 0 else { return nil }
        var fields: [String: String] = [:]
        for pair in String(decoding: body, as: UTF8.self).split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            fields[String(parts[0])] = parts.count > 1 ? String(parts[1]).removingPercentEncoding : ""
        }
        return Request(method: String(first[0]), path: String(first[1]), fields: fields, authorization: headers["authorization"])
    }

    private func answer(_ request: Request) -> (Int, String) {
        lock.lock()
        defer { lock.unlock() }
        log.append(request)
        switch (request.method, request.path) {
        case ("POST", "/login/device/code") where request.fields["client_id"] == "flow-off-client":
            return (400, #"{"error":"device_flow_disabled","error_description":"Device Flow must be explicitly enabled for this App"}"#)
        case ("POST", "/login/device/code") where request.fields["client_id"] != "lamp-test-client":
            return (404, #"{"error":"Not Found"}"#)
        case ("POST", "/login/device/code"):
            return (200, #"{"device_code":"device-1","user_code":"WDJB-MJHT","verification_uri":"http://127.0.0.1:\#(port)/login/device","expires_in":900,"interval":1}"#)
        case ("POST", "/login/oauth/access_token") where request.fields["grant_type"] == "refresh_token" && busyRenewals > 0:
            busyRenewals -= 1
            return busyRenewals % 2 == 1 ? (503, #"{"message":"Service unavailable"}"#) : (200, #"{"error":"temporarily_unavailable"}"#)
        case ("POST", "/login/oauth/access_token") where request.fields["grant_type"] == "refresh_token":
            guard !refusesRenewal, request.fields["refresh_token"] == "refresh-\(issued)" else {
                return (200, #"{"error":"bad_refresh_token","error_description":"The refresh token passed is incorrect or expired."}"#)
            }
            return (200, signIn())
        case ("POST", "/login/oauth/access_token"):
            if pendingAnswers > 0 {
                pendingAnswers -= 1
                return (200, #"{"error":"authorization_pending"}"#)
            }
            if slowDownOnce {
                slowDownOnce = false
                return (200, #"{"error":"slow_down","interval":1}"#)
            }
            switch outcome {
            case .approved: return (200, signIn())
            case .denied: return (200, #"{"error":"access_denied"}"#)
            case .expired: return (200, #"{"error":"expired_token"}"#)
            }
        case ("GET", "/user"):
            guard !ended, issued > 0, request.authorization == "Bearer access-\(issued)" else { return (401, #"{"message":"Bad credentials"}"#) }
            return (200, #"{"login":"octocat"}"#)
        default:
            return (404, #"{"message":"Not Found"}"#)
        }
    }

    private func signIn() -> String {
        issued += 1
        ended = false
        guard let lifetime else { return #"{"access_token":"access-\#(issued)","token_type":"bearer","scope":"repo"}"# }
        return #"{"access_token":"access-\#(issued)","refresh_token":"refresh-\#(issued)","expires_in":\#(lifetime),"token_type":"bearer"}"#
    }
}
