import XCTest
@testable import Lamp

/// The glow on an open app while its change is built is Lamp's to start: the app takes a request only when Lamp
/// signed it, recently, and only once. The app's check is compiled out of LampSupport.swift and given requests
/// signed the way Lamp signs them, so the two sides can't drift apart.
@MainActor
final class AppTransitionTests: XCTestCase {
    func testTheAppTakesOnlyLampsFreshRequestsOnce() throws {
        let token = "made-up-token"
        let now = Int(Date().timeIntervalSince1970)
        func signed(_ phase: String, _ id: String, at: Int, token: String = token) -> String {
            "\(phase) \(id) \(at) \(AppTransition.signature(phase: phase, id: id, at: String(at), token: token))"
        }
        let printed = try runGate(token: token, requests: [
            signed("begin", "a", at: now),
            signed("begin", "a", at: now),                       // the same request again
            signed("land", "b", at: now - 60),                   // too old
            signed("land", "c", at: now, token: "another-app"),  // signed with another app's token
            signed("dance", "d", at: now),                       // not a phase
            "end e \(now) 00",                                   // not signed
            signed("end", "f", at: now),
        ])
        XCTAssertEqual(printed.split(separator: "\n"), ["a true", "a false", "b false", "c false", "d false", "e false", "f true"], printed)
    }

    /// Lamp knows an app understands the request by this line in its binary, which the app's code carries.
    func testTheMarkerIsInEveryApp() {
        XCTAssertTrue(Template.lampSupportSwift.contains("\"\(AppTransition.marker)\""))
    }

    /// The pictures of the app for the builder leave out the windows the effect is drawn in.
    func testThePicturesLeaveTheEffectOut() {
        XCTAssertTrue(Template.lampSupportSwift.contains("!($0 is LampTransition.Glass)"))
    }

    private func runGate(token: String, requests: [String]) throws -> String {
        let support = Template.lampSupportSwift
        let start = try XCTUnwrap(support.range(of: "        struct Gate {"))
        let end = try XCTUnwrap(support.range(of: "        @MainActor private static var gate", range: start.upperBound..<support.endIndex))
        let program = """
        import Foundation
        import CryptoKit
        \(support[start.lowerBound..<end.lowerBound])
        var gate = Gate(token: "\(token)")
        for line in CommandLine.arguments.dropFirst() {
            let parts = line.split(separator: " ").map(String.init)
            print(parts[1], gate.admits(phase: parts[0], id: parts[1], at: parts[2], signature: parts[3], now: Date()))
        }
        """
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("transition-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        try program.write(to: work.appendingPathComponent("main.swift"), atomically: true, encoding: .utf8)
        let built = try run(Shell.compatibleSDK + "xcrun swiftc -o gate main.swift 2>&1", in: work)
        XCTAssertEqual(built.status, 0, built.output)
        let arguments = requests.map { "'\($0)'" }.joined(separator: " ")
        return try run("./gate \(arguments)", in: work).output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func run(_ command: String, in directory: URL) throws -> (status: Int32, output: String) {
        TestShell.run(command, in: directory)
    }
}
