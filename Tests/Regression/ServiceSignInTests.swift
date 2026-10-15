import XCTest
@testable import Lamp

/// An app made with Lamp signs the person in to a service on addresses the service's own descriptions give it, and
/// sends the person's browser and the proof of the sign-in to them. Here `LampService` is cut out of the template,
/// compiled and run with every web request answered from a table: the five services as they answered when
/// recorded, and the same answers with one link pointing somewhere else, which must stop the sign-in before the
/// browser opens.
@MainActor
final class ServiceSignInTests: XCTestCase {
    func testTheFiveServicesAsTheyAnswerAreReached() throws {
        let printed = try runProgram(scenarios: ["notion", "linear", "todoist", "atlassian", "monday"].map { "real:\($0)" })
        XCTAssertTrue(printed.contains("real:notion ok mcp.notion.com mcp.notion.com"), printed)
        XCTAssertTrue(printed.contains("real:linear ok mcp.linear.app mcp.linear.app"), printed)
        XCTAssertTrue(printed.contains("real:todoist ok todoist.com todoist.com"), printed)
        XCTAssertTrue(printed.contains("real:atlassian ok auth.atlassian.com auth.atlassian.com"), printed)
        XCTAssertTrue(printed.contains("real:monday ok auth.monday.com auth.monday.com"), printed)
    }

    /// Each of these is Linear's real answers with one thing changed. Before the check, the app opened the other
    /// host's sign-in page and posted the proof of the sign-in to it.
    func testAnAddressOffTheServicesOwnChainStopsTheSignIn() throws {
        let scenarios = ["endpoints-elsewhere", "endpoints-http", "issuer-elsewhere", "description-elsewhere", "resource-mismatch",
                         "description-redirected", "description-redirected-http"]
        let printed = try runProgram(scenarios: scenarios)
        for scenario in scenarios {
            XCTAssertTrue(printed.contains("\(scenario) refused"), "\(scenario) was followed:\n\(printed)")
        }
        XCTAssertFalse(printed.contains("attacker.example"), printed)
        XCTAssertFalse(printed.contains("evilas.test"), printed)
    }

    /// What a service says when it turns the app down is shown in the app's own Connect button, so it is cut short.
    func testAServicesRefusalIsShownShort() throws {
        let printed = try runProgram(scenarios: ["long-refusal"])
        let line = try XCTUnwrap(printed.split(separator: "\n").first { $0.hasPrefix("long-refusal ") }, printed)
        let length = Int(line.split(separator: " ")[1]) ?? .max
        XCTAssertLessThanOrEqual(length, 200, String(line))
        XCTAssertTrue(line.hasSuffix("one-line"), String(line))
    }

    /// Disconnect asks the service to end both keys a sign-in holds, and the app's log keeps what it answered,
    /// without the keys themselves.
    func testDisconnectEndsBothKeysAndLogsTheAnswer() throws {
        let printed = try runProgram(scenarios: ["disconnect"])
        XCTAssertTrue(printed.contains("revoked made-up-refresh"), printed)
        XCTAssertTrue(printed.contains("revoked made-up-access"), printed)
        let logged = printed.split(separator: "\n").filter { $0.hasPrefix("LampService:") }
        XCTAssertTrue(logged.contains { $0.contains("renewal key") && $0.contains("200") }, printed)
        XCTAssertTrue(logged.contains { $0.contains("access key") && $0.contains("200") }, printed)
        XCTAssertFalse(logged.contains { $0.contains("made-up-") }, printed)
    }

    // MARK: - The program

    private func runProgram(scenarios: [String]) throws -> String {
        let support = Template.lampSupportSwift
        let start = try XCTUnwrap(support.range(of: "@MainActor final class LampService"))
        let end = try XCTUnwrap(support.range(of: "// end LampService", range: start.upperBound..<support.endIndex))
        let program = """
        import Foundation
        import SwiftUI
        import AppKit
        import Network
        import CryptoKit
        import Security
        enum LampRuntime { static let folder = URL(fileURLWithPath: "/nonexistent-lamp-runtime") }
        \(support[start.lowerBound..<end.lowerBound])
        \(Self.harness)
        """
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-service-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        try program.write(to: work.appendingPathComponent("main.swift"), atomically: true, encoding: .utf8)
        try ServiceMetadataRecorded.json.write(to: work.appendingPathComponent("recorded.json"), atomically: true, encoding: .utf8)
        let built = try run(Shell.compatibleSDK + "xcrun swiftc -parse-as-library -o service main.swift 2>&1", in: work)
        XCTAssertEqual(built.status, 0, built.output)
        return try run("./service recorded.json " + scenarios.joined(separator: " "), in: work).output
    }

    /// Answers every request from a table, says what each scenario came to, and never touches the network.
    private static let harness = #"""
    final class Answers: URLProtocol {
        nonisolated(unsafe) static var table: [String: (Int, [String: String], Data)] = [:]
        nonisolated(unsafe) static var posted: [(String, String)] = []
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            if request.httpMethod == "POST" {
                var body = request.httpBody ?? Data()
                if body.isEmpty, let stream = request.httpBodyStream {
                    stream.open()
                    var buffer = [UInt8](repeating: 0, count: 4096)
                    while stream.hasBytesAvailable { let read = stream.read(&buffer, maxLength: buffer.count); if read <= 0 { break }; body.append(buffer, count: read) }
                    stream.close()
                }
                Answers.posted.append((request.url!.absoluteString, String(decoding: body, as: UTF8.self)))
            }
            let answer = Answers.table[request.url!.absoluteString] ?? (404, [:], Data())
            let response = HTTPURLResponse(url: request.url!, statusCode: answer.0, httpVersion: "HTTP/1.1", headerFields: answer.1)!
            // A redirect is offered to the session, which follows it unless the request said not to.
            if (300..<400).contains(answer.0), let location = answer.1["Location"].flatMap(URL.init(string:)) {
                client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: location), redirectResponse: response)
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: answer.2)
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    @main struct Harness {
        @MainActor static func main() async {
            URLProtocol.registerClass(Answers.self)
            let recorded = try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))) as! [String: Any]
            let real = recorded["answers"] as! [String: [String: Any]]
            func load(_ answers: [String: [String: Any]]) {
                Answers.table = answers.mapValues { answer in
                    var headers = ["Content-Type": "application/json"]
                    if let challenge = answer["www-authenticate"] as? String { headers["WWW-Authenticate"] = challenge }
                    return (answer["status"] as! Int, headers, Data((answer["body"] as? String ?? "").utf8))
                }
            }
            // Linear's real answers with one document's fields changed.
            func linear(_ change: (inout [String: [String: Any]]) -> Void) -> [String: [String: Any]] {
                var answers = real
                change(&answers)
                return answers
            }
            func edit(_ answers: inout [String: [String: Any]], _ url: String, _ change: (inout [String: Any]) -> Void) {
                var body = try! JSONSerialization.jsonObject(with: Data((answers[url]!["body"] as! String).utf8)) as! [String: Any]
                change(&body)
                answers[url]!["body"] = String(decoding: try! JSONSerialization.data(withJSONObject: body), as: UTF8.self)
            }
            let description = "https://mcp.linear.app/.well-known/oauth-protected-resource/mcp"
            let server = "https://mcp.linear.app/.well-known/oauth-authorization-server"
            var opened: [URL] = []
            LampService.openPage = { opened.append($0) }

            for scenario in CommandLine.arguments.dropFirst(2) {
                var service = LampService.linear
                switch scenario {
                case let name where name.hasPrefix("real:"):
                    service = LampService.all.first { "real:" + $0.id == name }!
                    load(real)
                case "endpoints-elsewhere":
                    load(linear { edit(&$0, server) { $0["authorization_endpoint"] = "https://attacker.example/authorize"; $0["token_endpoint"] = "https://attacker.example/token"; $0["registration_endpoint"] = "https://attacker.example/register" } })
                case "endpoints-http":
                    load(linear { edit(&$0, server) { $0["authorization_endpoint"] = "http://mcp.linear.app/authorize"; $0["token_endpoint"] = "http://mcp.linear.app/token" } })
                case "issuer-elsewhere":
                    load(linear { answers in
                        edit(&answers, description) { $0["authorization_servers"] = ["https://attacker.example"] }
                        answers["https://attacker.example/.well-known/oauth-authorization-server"] = ["status": 200, "body": #"{"issuer":"https://mcp.linear.app","authorization_endpoint":"https://attacker.example/authorize","token_endpoint":"https://attacker.example/token","registration_endpoint":"https://attacker.example/register"}"#]
                    })
                case "description-elsewhere":
                    load(linear { answers in
                        let probe = "https://mcp.linear.app/mcp"
                        answers[probe]!["www-authenticate"] = #"Bearer resource_metadata="https://attacker.example/.well-known/oauth-protected-resource/mcp""#
                        answers.removeValue(forKey: description)
                        answers["https://attacker.example/.well-known/oauth-protected-resource/mcp"] = ["status": 200, "body": #"{"resource":"https://mcp.linear.app/mcp","authorization_servers":["https://attacker.example"]}"#]
                        answers["https://attacker.example/.well-known/oauth-authorization-server"] = ["status": 200, "body": #"{"issuer":"https://attacker.example","authorization_endpoint":"https://attacker.example/authorize","token_endpoint":"https://attacker.example/token","registration_endpoint":"https://attacker.example/register"}"#]
                    })
                case "description-redirected", "description-redirected-http":
                    // The service's own description address sends the app elsewhere, where a document names an
                    // authorization server that agrees with itself; over https, and over plain http as a network
                    // attacker could answer.
                    let elsewhere = (scenario.hasSuffix("http") ? "http" : "https") + "://evil.test/resource-doc"
                    load(linear { answers in
                        answers[elsewhere] = ["status": 200, "body": #"{"resource":"https://mcp.linear.app/mcp","authorization_servers":["https://evilas.test"]}"#]
                        answers["https://evilas.test/.well-known/oauth-authorization-server"] = ["status": 200, "body": #"{"issuer":"https://evilas.test","authorization_endpoint":"https://evilas.test/authorize","token_endpoint":"https://evilas.test/token","registration_endpoint":"https://evilas.test/register"}"#]
                    })
                    Answers.table[description] = (302, ["Location": elsewhere], Data())
                case "resource-mismatch":
                    load(linear { edit(&$0, description) { $0["resource"] = "https://attacker.example/mcp" } })
                case "disconnect":
                    // A made-up sign-in for Linear, ended by Disconnect; the token address answers as Linear's would.
                    load(real)
                    Answers.table["https://mcp.linear.app/token"] = (200, ["Content-Type": "application/json"], Data("{}".utf8))
                    let id = "test-" + UUID().uuidString.prefix(8)
                    let test = LampService(id: id, name: "Linear", url: "https://mcp.linear.app/mcp")
                    var saved = LampService.Saved(clientID: "made-up-client", clientSecret: nil, redirectURI: "http://127.0.0.1:1/callback",
                                                  authorizationEndpoint: "https://mcp.linear.app/authorize", tokenEndpoint: "https://mcp.linear.app/token")
                    saved.revocationEndpoint = "https://mcp.linear.app/token"
                    saved.accessToken = "made-up-access"
                    saved.refreshToken = "made-up-refresh"
                    saved.save(id)
                    test.disconnect()
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    for (address, body) in Answers.posted where address == "https://mcp.linear.app/token" {
                        for token in ["made-up-refresh", "made-up-access"] where body.contains("token=" + token) { print("revoked " + token) }
                    }
                    SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Bundle.main.bundleIdentifier ?? "lamp",
                                   kSecAttrAccount as String: "lamp-service-" + id] as CFDictionary)
                    continue
                case "long-refusal":
                    // A made-up refusal, long and on several lines, from Linear's real registration address.
                    load(linear { $0["https://mcp.linear.app/register"] = ["status": 400, "body": String(decoding: try! JSONSerialization.data(withJSONObject: ["error": "invalid_client_metadata", "error_description": "one-line\nsecond " + String(repeating: "very long text ", count: 200)]), as: UTF8.self)] })
                    do {
                        try await service.connect()
                        print("long-refusal connected")
                    } catch {
                        let message = error.localizedDescription
                        let shown: String = { if case .failed(let text) = service.state { return text } else { return "" } }()
                        print("long-refusal \(max(message.count, shown.count)) \(message.contains("\n") || shown.contains("\n") ? "multi-line" : "one-line")")
                    }
                    continue
                default: break
                }
                do {
                    let found = try await service.discover()
                    if scenario.hasPrefix("real:") {
                        print("\(scenario) ok \(found.authorizationEndpoint.host ?? "") \(found.tokenEndpoint.host ?? "")")
                    } else {
                        print("\(scenario) followed to \(found.authorizationEndpoint.absoluteString) \(found.tokenEndpoint.absoluteString)")
                    }
                } catch {
                    print("\(scenario) refused: \(error.localizedDescription)")
                }
            }
            if !opened.isEmpty { print("browser opened: " + opened.map(\.absoluteString).joined(separator: " ")) }
            exit(0)
        }
    }
    """#

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
