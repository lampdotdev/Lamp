import XCTest
@testable import Lamp

/// An app made with Lamp sends the token the person pasted to that service's API and nowhere else, and tells a
/// token the service no longer takes from a call it refused for another reason. Here `LampAPI` is cut out of the
/// template, compiled and run with every web request answered from a table: the services' own answers to a wrong
/// token as recorded, and a made-up service for the rest.
@MainActor
final class TokenServiceTests: XCTestCase {
    /// Each service's check, answered as the service answered a wrong token, refuses it and keeps nothing; Toggl
    /// Track says 403 where the others say 401.
    func testAWrongTokenIsRefusedByEveryService() throws {
        let printed = try runProgram(scenarios: ["recorded"])
        for connector in Connectors.all {
            guard case .token = connector.kind else { continue }
            XCTAssertTrue(printed.contains("\(connector.id): refused, didn't accept that, kept false"), printed)
        }
        XCTAssertFalse(printed.contains("unrecorded"), printed)
    }

    /// A path that leads off the service's API, written as another site, a scheme, or a climb above the base, is
    /// refused before anything is sent; the token reaches only the service's own address.
    func testAPathOffTheServiceIsRefused() throws {
        let printed = try runProgram(scenarios: ["paths"])
        for path in ["https://evil.test/x", "//evil.test/x", "../x", "items/../../../x", "http:evil.test/x", "https:evil.test/x"] {
            XCTAssertTrue(printed.contains("\(path) -> refused"), printed)
        }
        XCTAssertTrue(printed.contains("sent https://api.example.test/v1/items?limit=5"), printed)
        XCTAssertTrue(printed.contains("sent https://api.example.test/v1/me/things"), printed)
        XCTAssertFalse(printed.contains("sent https://evil.test"), printed)
        XCTAssertFalse(printed.contains("sent https://api.example.test/x"), printed)
    }

    /// A redirect is handed back as it is: the token isn't sent where it points, even on the same site.
    func testARedirectIsNotFollowed() throws {
        let printed = try runProgram(scenarios: ["redirect"])
        XCTAssertTrue(printed.contains("redirect -> status 302"), printed)
        XCTAssertFalse(printed.contains("sent https://evil.test"), printed)
    }

    /// A 401, or a 403 that the check address repeats, means the token is over: it's forgotten and the app is told
    /// to show Connect. A 403 for one thing, while the check still passes, keeps the token.
    func testATokenThatsOverIsForgottenAndAPermissionRefusalIsNot() throws {
        let printed = try runProgram(scenarios: ["gone-401", "gone-403", "permission-403"])
        XCTAssertTrue(printed.contains("gone-401: needsConnection true, kept false"), printed)
        XCTAssertTrue(printed.contains("gone-403: needsConnection true, kept false"), printed)
        XCTAssertTrue(printed.contains("permission-403: needsConnection false, kept true, status 403"), printed)
    }

    // MARK: - The program

    private func runProgram(scenarios: [String]) throws -> String {
        let support = Template.lampSupportSwift
        let start = try XCTUnwrap(support.range(of: "@MainActor final class LampAPI"))
        let end = try XCTUnwrap(support.range(of: "// end LampAPI", range: start.upperBound..<support.endIndex))
        let program = """
        import Foundation
        import SwiftUI
        import Security
        \(support[start.lowerBound..<end.lowerBound])
        \(Self.harness)
        """
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-api-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        try program.write(to: work.appendingPathComponent("main.swift"), atomically: true, encoding: .utf8)
        let recorded = TokenServicesRecorded.answers.mapValues { ["status": $0.status, "body": $0.body] as [String: Any] }
        try JSONSerialization.data(withJSONObject: recorded).write(to: work.appendingPathComponent("recorded.json"))
        let built = try run(Shell.compatibleSDK + "xcrun swiftc -parse-as-library -o api main.swift 2>&1", in: work)
        XCTAssertEqual(built.status, 0, built.output)
        return try run("./api recorded.json " + scenarios.joined(separator: " "), in: work).output
    }

    private static let harness = #"""
    final class Answers: URLProtocol {
        nonisolated(unsafe) static var table: [String: (Int, [String: String], Data)] = [:]
        nonisolated(unsafe) static var seen: [String] = []
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            let address = request.url!.absoluteString
            Answers.seen.append(address)
            print("sent \(address) with \(request.value(forHTTPHeaderField: "Authorization") ?? "no key")")
            let answer = Answers.table[address] ?? (404, [:], Data())
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
            let recorded = try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))) as! [String: [String: Any]]
            /// A made-up service, connected with a made-up token kept under a name of its own and forgotten after.
            func example() -> LampAPI {
                let api = LampAPI(id: "test-" + UUID().uuidString.prefix(8), name: "Example", base: "https://api.example.test/v1/",
                                  page: "https://example.test/tokens", steps: "", fields: [.init(key: "token", label: "Token")],
                                  headers: ["Authorization": "Bearer {token}"], check: "me")
                _ = LampAPI.Saved.save(["token": "made-up-token"], for: api.id)
                return api
            }
            func json(_ status: Int) -> (Int, [String: String], Data) { (status, ["Content-Type": "application/json"], Data("{}".utf8)) }

            for scenario in CommandLine.arguments.dropFirst(2) {
                Answers.table = [:]
                switch scenario {
                case "recorded":
                    Answers.table = recorded.mapValues { ($0["status"] as! Int, [:], Data(($0["body"] as! String).utf8)) }
                    for api in LampAPI.all {
                        let before = Answers.seen.count
                        do {
                            try await api.connect(Dictionary(uniqueKeysWithValues: api.fields.map { ($0.key, "made-up-\($0.key)") }))
                            print("\(api.id): connected")
                            api.disconnect()
                        } catch {
                            let refused = error.localizedDescription.contains("didn't accept that")
                            print("\(api.id): \(refused ? "refused, didn't accept that" : error.localizedDescription), kept \(LampAPI.Saved.read(api.id) != nil)")
                        }
                        for address in Answers.seen[before...] where recorded[address] == nil { print("\(api.id): unrecorded \(address)") }
                    }
                case "paths":
                    let api = example()
                    Answers.table["https://api.example.test/v1/items?limit=5"] = json(200)
                    Answers.table["https://api.example.test/v1/me/things"] = json(200)
                    for path in ["https://evil.test/x", "//evil.test/x", "../x", "items/../../../x", "http:evil.test/x", "https:evil.test/x",
                                 "items?limit=5", "/me/things"] {
                        do { _ = try await api.get(path); print("\(path) -> answered") }
                        catch { print("\(path) -> \(error.localizedDescription.contains("isn't part of") ? "refused" : error.localizedDescription)") }
                    }
                    LampAPI.Saved.delete(api.id)
                case "redirect":
                    let api = example()
                    Answers.table["https://api.example.test/v1/away"] = (302, ["Location": "https://evil.test/steal"], Data())
                    do { _ = try await api.get("away"); print("redirect -> answered") }
                    catch let failure as LampAPI.Failure { print("redirect -> status \(failure.status ?? 0)") }
                    catch { print("redirect -> \(error)") }
                    LampAPI.Saved.delete(api.id)
                case "gone-401", "gone-403", "permission-403":
                    let api = example()
                    Answers.table["https://api.example.test/v1/items"] = json(scenario == "gone-401" ? 401 : 403)
                    Answers.table["https://api.example.test/v1/me"] = json(scenario == "permission-403" ? 200 : 403)
                    do { _ = try await api.get("items"); print("\(scenario): answered") }
                    catch let failure as LampAPI.Failure {
                        print("\(scenario): needsConnection \(failure.needsConnection), kept \(LampAPI.Saved.read(api.id) != nil), status \(failure.status ?? 0)")
                    } catch { print("\(scenario): \(error)") }
                    LampAPI.Saved.delete(api.id)
                default: print("unknown scenario \(scenario)")
                }
            }
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
