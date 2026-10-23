import XCTest
@testable import Lamp

/// An integration is data the model writes and Lamp acts on: these hold the checks that turn a bad one away, and the
/// guards that keep a request or a command on the person's own device whatever the data says.
final class IntegrationTests: XCTestCase {
    private let roku = """
    {
      "id": "roku", "name": "Roku", "maker": "Roku",
      "find": [{ "ssdp": "roku:ecp" }],
      "identity": {
        "os": "Roku OS",
        "id": { "http": { "port": 8060, "path": "/query/device-info" }, "xml": "serial-number" },
        "model": { "http": { "port": 8060, "path": "/query/device-info" }, "xml": "model-name" }
      },
      "steps": [
        { "id": "developer-mode", "title": "Turn on developer mode", "wait": true,
          "lines": ["Press Home three times on the remote"], "accepts": ["softwareRisk"],
          "check": [{ "http": { "port": 8060, "path": "/query/device-info" }, "xml": "developer-enabled", "equals": "true" }] },
        { "id": "password", "title": "Give Lamp the developer password",
          "field": { "key": "password", "label": "Developer password", "secret": true },
          "check": [{ "http": { "port": 80, "path": "/", "auth": { "digest": true, "user": "rokudev", "password": "{field:password}" } } }] }
      ],
      "bridge": {
        "install": [{ "http": { "method": "POST", "port": 80, "path": "/plugin_install",
                                "auth": { "digest": true, "user": "rokudev", "password": "{field:password}" },
                                "form": { "mysubmit": "Install", "archive": "@{package}" } } }],
        "use": [{ "http": { "method": "POST", "port": 8060, "path": "/keypress/{key}" } }],
        "keys": { "home": "Home", "select": "Select" }
      }
    }
    """

    private func problems(_ change: (inout [String: Any]) -> Void) -> [String] {
        var json = try! JSONSerialization.jsonObject(with: Data(roku.utf8)) as! [String: Any]
        change(&json)
        let data = try! JSONSerialization.data(withJSONObject: json)
        return IntegrationCheck.unknownKeys(data) + IntegrationCheck.problems(data)
    }

    private func step(_ index: Int, _ json: inout [String: Any], _ change: (inout [String: Any]) -> Void) {
        var steps = json["steps"] as! [[String: Any]]
        change(&steps[index])
        json["steps"] = steps
    }

    func testAWellFormedIntegrationIsTaken() {
        XCTAssertEqual(problems { _ in }, [])
    }

    func testEachMistakeIsTurnedAwayWithItsReason() {
        // What the person types never goes into a path or a command, where it could change what's done.
        XCTAssertTrue(problems { json in
            step(1, &json) { $0["check"] = [["http": ["port": 80, "path": "/login/{field:password}"]]] }
        }.contains { $0.contains("{field:password} can't go in a path") })
        // Only Lamp's own values are filled in.
        XCTAssertTrue(problems { json in
            step(0, &json) { $0["show"] = [["label": "Server", "value": "{evil}"]] }
        }.contains { $0.contains("{evil} isn't a value Lamp fills") })
        // A step is done by its check, so every step has one.
        XCTAssertTrue(problems { json in step(0, &json) { $0["check"] = [] } }.contains { $0.contains("check is empty") })
        // The model may not claim a step was tried.
        XCTAssertTrue(problems { json in step(0, &json) { $0["known"] = ["how": "lamp"] } }.contains { $0.contains("known.how can only be \"read\"") })
        // A command on the device needs the person to accept that commands run there.
        XCTAssertTrue(problems { json in
            step(0, &json) { $0["run"] = [["ssh": ["user": "root", "command": "reboot", "explanation": "Restarts the device."]]] }
        }.contains { $0.contains("commandRuns") })
        // A request names a path on the device, never an address of its own.
        XCTAssertTrue(problems { json in
            step(0, &json) { $0["check"] = [["http": ["port": 80, "path": "//evil.example/x"]]] }
        }.contains { $0.contains("path must start with one /") })
        XCTAssertTrue(problems { json in
            step(0, &json) { $0["check"] = [["http": ["port": 80, "path": "/x@evil.example"]]] }
        }.contains { $0.contains("not an address") })
        // A setting changed for a sequence and put back after is a change: a PUT or POST with a body.
        XCTAssertTrue(problems { json in
            step(0, &json) { $0["check"] = [["http": ["port": 80, "path": "/settings/x", "restore": "Value"]]] }
        }.contains { $0.contains("restore is for a PUT or POST") })
        XCTAssertTrue(problems { json in
            step(0, &json) { $0["check"] = [["http": ["method": "PUT", "port": 80, "path": "/settings/x", "body": "{}", "restore": "Value"]]] }
        }.contains { $0.contains("a check only asks") })
        // A misspelt key isn't passed over quietly.
        XCTAssertTrue(problems { $0["fnd"] = [] }.contains { $0.contains("fnd isn't part of an integration") })
        // A program that isn't Lamp's needs its checksum.
        XCTAssertTrue(problems { json in
            step(0, &json) {
                $0["accepts"] = ["commandRuns"]
                $0["run"] = [["tool": ["download": "https://example.org/tool", "explanation": "Sends the app."]]]
            }
        }.contains { $0.contains("sha256") })
        // Words on the card are held to a limit, as the chat's are.
        XCTAssertTrue(problems { json in
            step(0, &json) { $0["title"] = "Turn on the developer mode of this device by pressing many keys" }
        }.contains { $0.contains("title must be 1 to 8 words") })
    }

    /// What Lamp writes back after a step passes is read again as it wrote it, though the builder may not write it.
    func testAStepLampMarkedIsKeptWhenReadBack() {
        var json = try! JSONSerialization.jsonObject(with: Data(roku.utf8)) as! [String: Any]
        step(0, &json) { $0["known"] = ["how": "lamp", "model": "4850X", "version": "14.0"] }
        let data = try! JSONSerialization.data(withJSONObject: json)
        XCTAssertFalse(IntegrationCheck.problems(data).isEmpty, "the builder can't claim a step was checked")
        XCTAssertEqual(IntegrationCheck.problems(data, submitted: false), [])
    }

    /// A device's API often takes JSON: its braces are the template's own text, and only a word in braces is filled.
    func testJSONBracesAreTextAndOnlyPlaceholdersAreFilled() throws {
        XCTAssertEqual(problems { json in
            step(0, &json) { $0["check"] = [["http": ["method": "POST", "port": 3000, "path": "/api", "body": #"{"enabled":true,"id":"{deviceID}"}"#]]] }
        }, [])
        XCTAssertEqual(try Placeholders.fill(#"{"id":"{appID}"}"#, ["appID": "dev"], in: .command), #"{"id":"'dev'"}"#)
        XCTAssertEqual(Placeholders.names(in: #"{"a":{"b":"{field:pin}"}}"#), ["field:pin"])
        // USB is refused until Lamp can reach a device found that way.
        XCTAssertTrue(problems { $0["find"] = [["usb": ["vendor": 1234]]] }.contains { $0.contains("USB") })
    }

    func testPlaceholdersAreCheckedAndQuoted() throws {
        XCTAssertEqual(try Placeholders.fill("/launch/{appID}", ["appID": "dev"], in: .path), "/launch/dev")
        XCTAssertThrowsError(try Placeholders.fill("/keypress/{key}", ["key": "Home\r\nX-Evil: 1"], in: .path))
        XCTAssertThrowsError(try Placeholders.fill("echo {text}", ["text": "a; rm -rf /"], in: .command))
        // A value from the person goes into a command only quoted, and never breaks out of its quotes.
        XCTAssertEqual(try Placeholders.fill("unlock {field:pin}", ["field:pin": "a'b"], in: .command), "unlock 'a'\\''b'")
    }

    // MARK: http

    func testRequestsGoOnlyToTheDeviceOnThePersonsNetwork() throws {
        for address in ["192.168.1.20", "10.0.0.5", "172.20.1.1", "169.254.3.4", "fd12::1", "fe80::1"] {
            XCTAssertTrue(DeviceAddress.isPrivate(address), address)
        }
        // Never this Mac (Lamp's gateway is there), the internet, or a name that could lead anywhere.
        for address in ["127.0.0.1", "::1", "8.8.8.8", "172.32.0.1", "roku.local", "example.com", "0.0.0.0", "::ffff:127.0.0.1"] {
            XCTAssertFalse(DeviceAddress.isPrivate(address), address)
            XCTAssertThrowsError(try DeviceHTTP.url(address: address, port: 80, path: "/"), address)
        }
        XCTAssertEqual(try DeviceHTTP.url(address: "192.168.1.20", port: 8060, path: "/query/device-info").absoluteString,
                       "http://192.168.1.20:8060/query/device-info")
        for path in ["//evil.example/", "/a/../b", "/x@evil.example", "x", "/a b"] {
            XCTAssertThrowsError(try DeviceHTTP.url(address: "192.168.1.20", port: 80, path: path), path)
        }
    }

    /// A device with its own certificate is held to the one it showed first, and nothing secret goes to one whose
    /// certificate Lamp doesn't keep.
    func testHTTPSKeepsTheFirstCertificateAndSendsNoSecretWithoutIt() async {
        XCTAssertEqual(try DeviceHTTP.url(address: "10.0.0.138", port: 11443, path: "/api/os/info", https: true).absoluteString,
                       "https://10.0.0.138:11443/api/os/info")
        XCTAssertEqual(DeviceTLS.judge("aa", kept: nil, keeping: true), .keep)
        XCTAssertEqual(DeviceTLS.judge("aa", kept: "aa", keeping: true), .trust)
        XCTAssertEqual(DeviceTLS.judge("bb", kept: "aa", keeping: true), .refuse)
        XCTAssertEqual(DeviceTLS.judge("bb", kept: nil, keeping: false), .trust, "a read while finding keeps nothing")
        let signIn = Request(port: 11443, path: "/api/os/info", auth: .init(digest: false, user: "lamp", password: "{field:password}"), https: true)
        do {
            _ = try await DeviceHTTP.send(signIn, to: "10.0.0.138", values: ["field:password": "secret"])
            XCTFail("a password went to a device whose certificate isn't kept")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("certificate"), error.localizedDescription)
        }
    }

    func testNoRedirectAndThePasswordOnlyForTheDevicesOwnChallenge() {
        let guardian = DeviceHTTP.Guardian(address: "192.168.1.20", credential: ("rokudev", "secret", true))
        let followed = expectation(description: "redirect answered")
        let response = HTTPURLResponse(url: URL(string: "http://192.168.1.20/")!, statusCode: 302, httpVersion: nil, headerFields: nil)!
        guardian.urlSession(URLSession.shared, task: URLSession.shared.dataTask(with: URL(string: "http://192.168.1.20/")!),
                            willPerformHTTPRedirection: response, newRequest: URLRequest(url: URL(string: "https://example.com/")!)) {
            XCTAssertNil($0)
            followed.fulfill()
        }
        wait(for: [followed], timeout: 1)
        let digest = NSURLAuthenticationMethodHTTPDigest, basic = NSURLAuthenticationMethodHTTPBasic
        XCTAssertTrue(DeviceHTTP.Guardian.answers(space: ("192.168.1.20", digest), address: "192.168.1.20", digest: true, tried: false))
        XCTAssertFalse(DeviceHTTP.Guardian.answers(space: ("10.0.0.9", digest), address: "192.168.1.20", digest: true, tried: false))
        XCTAssertFalse(DeviceHTTP.Guardian.answers(space: ("192.168.1.20", basic), address: "192.168.1.20", digest: true, tried: false),
                       "a device asking for basic when digest was declared doesn't get the password in the clear")
        XCTAssertFalse(DeviceHTTP.Guardian.answers(space: ("192.168.1.20", digest), address: "192.168.1.20", digest: true, tried: true))
        XCTAssertFalse(DeviceHTTP.Guardian.answers(space: ("192.168.1.20", digest), address: "192.168.1.20", digest: nil, tried: false))
    }

    func testValuesAreReadFromJSONAndXML() {
        let xml = Data("<device-info><serial-number>X01</serial-number><developer-enabled>true</developer-enabled></device-info>".utf8)
        XCTAssertEqual(DeviceHTTP.xml("developer-enabled", in: xml), "true")
        XCTAssertEqual(DeviceHTTP.xml("device-info/serial-number", in: xml), "X01")
        let json = Data(#"{"device": {"modelName": "QN50", "on": true}, "items": [{"id": 7}]}"#.utf8)
        XCTAssertEqual(DeviceHTTP.json("device.modelName", in: json), "QN50")
        XCTAssertEqual(DeviceHTTP.json("device.on", in: json), "true")
        XCTAssertEqual(DeviceHTTP.json("items.0.id", in: json), "7")
    }

    // MARK: ssh

    func testSSHReachesOnlyTheDeviceWithItsKeyPinnedAndNothingForwarded() throws {
        let key = URL(fileURLWithPath: "/tmp/key"), hosts = URL(fileURLWithPath: "/tmp/known_hosts")
        let arguments = try DeviceSSH.arguments(address: "192.168.1.30", port: 9922, user: "prisoner", command: "ls", identity: key, knownHosts: hosts)
        let options = Set(stride(from: 0, to: arguments.count - 1, by: 1).filter { arguments[$0] == "-o" }.map { arguments[$0 + 1] })
        for option in ["StrictHostKeyChecking=accept-new", "UserKnownHostsFile=/tmp/known_hosts", "GlobalKnownHostsFile=/dev/null",
                       "ForwardAgent=no", "ClearAllForwardings=yes", "ProxyCommand=none", "IdentityAgent=none", "PermitLocalCommand=no", "Tunnel=no"] {
            XCTAssertTrue(options.contains(option), option)
        }
        XCTAssertEqual(Array(arguments.prefix(2)), ["-F", "/dev/null"], "none of the person's own SSH settings")
        XCTAssertEqual(Array(arguments.suffix(3)), ["--", "192.168.1.30", "ls"])
        XCTAssertThrowsError(try DeviceSSH.arguments(address: "203.0.113.5", port: 22, user: "root", command: "ls", identity: key, knownHosts: hosts))
        XCTAssertThrowsError(try DeviceSSH.arguments(address: "192.168.1.30", port: 22, user: "-oProxyCommand=x", command: "ls", identity: key, knownHosts: hosts))
        XCTAssertThrowsError(try DeviceSSH.arguments(address: "192.168.1.30", port: 22, user: "root", command: "ls\nrm -rf /", identity: key, knownHosts: hosts))
    }

    func testAnApprovalIsForTheExactCommandOnThatDevice() {
        let device = "test:\(UUID().uuidString)"
        defer { DeviceApprovals.forget(device) }
        let action = IntegrationAction(ssh: .init(user: "root", command: "luna-send -n 1 {appID}", explanation: "Opens the app."))
        let subject = DeviceApprovals.subject(of: action)!
        XCTAssertFalse(DeviceApprovals.isApproved(subject, on: device))
        DeviceApprovals.approve(subject, on: device)
        XCTAssertTrue(DeviceApprovals.isApproved(subject, on: device))
        XCTAssertFalse(DeviceApprovals.isApproved(subject, on: device + "-other"))
        var changed = action
        changed.ssh?.command += " ; reboot"
        XCTAssertFalse(DeviceApprovals.isApproved(DeviceApprovals.subject(of: changed)!, on: device))
    }
    /// A device that turns the password away has said so: the step fails with words to fix it instead of waiting on
    /// the device for ever, and the same step still passes once the device lets Lamp in.
    func testARejectedSignInFailsTheStepAndAnAcceptedOnePassesIt() async throws {
        let roku = try JSONDecoder().decode(Integration.self, from: Data(roku.utf8))
        let step = roku.steps[1]
        var device = Device(id: "roku:TEST", kind: .other, maker: "Roku", model: "Roku Ultra", modelID: "4800X",
                            name: "Test Roku", os: "Roku OS", osVersion: "14.0", reach: .network)
        device.address = "192.168.1.20"
        func runner(answering status: Int) -> IntegrationRunner {
            var runner = IntegrationRunner(integration: roku, device: device)
            runner.send = { _, _, _, _ in DeviceHTTP.Answer(status: status, body: Data()) }
            return runner
        }

        let rejected = await runner(answering: 401).check(step)
        XCTAssertFalse(rejected.passed)
        XCTAssertTrue(rejected.failed, "a rejected sign-in is shown as a failure, not as waiting with a spinner")
        XCTAssertEqual(rejected.why, "The device rejected the sign-in. Check the user name and password, then try again.")

        let accepted = await runner(answering: 200).check(step)
        XCTAssertTrue(accepted.passed)
        XCTAssertFalse(accepted.failed)
    }
}

