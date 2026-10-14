import XCTest
import CryptoKit
import Network
@testable import Lamp

/// The wand in an app on the person's phone talks to Lamp over plain HTTP on the Wi‑Fi, so what it sends is sealed
/// with the app's phone secret (`PhoneWand`), and the app's half of that is a copy in LampSupport.swift
/// (`LampWandSeal`). Here the app's copy is cut out of the template, compiled and run against Lamp's, and what
/// someone else on the network could send is turned away.
final class PhoneWandTests: XCTestCase {
    private let secret = "phone-secret-of-this-app"

    func testTheAppsSealedMessageOpensOnTheMacAndTheMacsReplyOpensInTheApp() throws {
        let support = Template.lampSupportSwift
        let start = try XCTUnwrap(support.range(of: "enum LampWandSeal {"))
        let end = try XCTUnwrap(support.range(of: "// end LampWandSeal", range: start.upperBound..<support.endIndex))
        let at = Date().timeIntervalSince1970
        let reply = PhoneWand.seal(["nonce": "n-1", "on": true, "phase": "working"], secret: secret)
        let replyBody = String(decoding: try JSONSerialization.data(withJSONObject: reply), as: UTF8.self)
        let program = """
        import Foundation
        import CryptoKit
        \(support[start.lowerBound..<end.lowerBound])
        let key = LampWandSeal.key(\(literal(secret)))
        let sent = LampWandSeal.seal(["op": "send", "id": "6C1E2A55-0D4B-4C1E-9E7A-1F1E2A55A0D4", "text": "Make it blue", "nonce": "n-1", "at": \(at)], key: key)!
        print(String(decoding: sent, as: UTF8.self))
        let reply = LampWandSeal.open(Data(\(literal(replyBody)).utf8), key: key, nonce: "n-1")
        print(reply?["phase"] as? String ?? "unopened")
        print(LampWandSeal.open(Data(\(literal(replyBody)).utf8), key: key, nonce: "another") == nil ? "refused" : "taken")
        print(LampWandSeal.open(sent, key: key, nonce: "n-1") == nil ? "refused" : "taken")
        """
        let output = try run(program).split(separator: "\n").map(String.init)
        XCTAssertEqual(output.count, 4, output.joined(separator: "\n"))
        let message = try PhoneWand.open(Data(output[0].utf8), secret: secret)
        XCTAssertEqual(message["op"] as? String, "send")
        XCTAssertEqual(message["text"] as? String, "Make it blue")
        XCTAssertEqual(output[1], "working")
        XCTAssertEqual(output[2], "refused", "a reply to another question must not be taken")
        XCTAssertEqual(output[3], "refused", "the app's own message sent back to it isn't Lamp's reply")
        let replyAsRequest = try JSONSerialization.data(withJSONObject: reply)
        XCTAssertThrowsError(try PhoneWand.open(replyAsRequest, secret: secret), "Lamp's reply sent back to Lamp isn't a request")
    }

    func testAMessageSealedWithAnotherSecretIsRefused() throws {
        let body = try sealedBody(["op": "send", "at": Date().timeIntervalSince1970], secret: "someone-elses")
        XCTAssertThrowsError(try PhoneWand.open(body, secret: secret)) { XCTAssertEqual($0 as? PhoneWand.Refusal, .unreadable) }
        XCTAssertThrowsError(try PhoneWand.open(Data(#"{"op":"send","text":"plain"}"#.utf8), secret: secret))
    }

    func testAMessageTakenOffTheAirAndSentLaterIsRefused() throws {
        let sent = Date()
        let body = try sealedBody(["op": "send", "at": sent.timeIntervalSince1970], secret: secret)
        XCTAssertNoThrow(try PhoneWand.open(body, secret: secret, now: sent.addingTimeInterval(60)))
        XCTAssertThrowsError(try PhoneWand.open(body, secret: secret, now: sent.addingTimeInterval(PhoneWand.freshness + 60))) {
            XCTAssertEqual($0 as? PhoneWand.Refusal, .stale)
        }
    }

    func testAnIdIsTakenOnceEvenAfterARelaunch() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("wand-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        var taken = PhoneWand.Taken(file: file)
        XCTAssertTrue(taken.take("A"))
        XCTAssertFalse(taken.take("A"), "a retry or a copy of the same message")
        var relaunched = PhoneWand.Taken(file: file)
        XCTAssertFalse(relaunched.take("A"), "Lamp quit and opened again in between")
        XCTAssertTrue(relaunched.take("B"))
    }

    /// The gateway answers on every address while an app opens on a phone, this Mac's own among them. A program
    /// here (the agent, the simulator's copy of the app) can read the app's secret, so it mustn't pass for the phone.
    func testAConnectionFromThisMacIsNotThePhone() {
        func endpoint(_ host: String) -> NWEndpoint { .hostPort(host: NWEndpoint.Host(host), port: 47821) }
        XCTAssertTrue(Gateway.isThisMac(endpoint("::1")))
        XCTAssertTrue(Gateway.isThisMac(endpoint("127.0.0.1")))
        XCTAssertTrue(Gateway.isThisMac(endpoint("::ffff:127.0.0.1")))
        XCTAssertTrue(Gateway.isThisMac(.unix(path: "/tmp/socket")))
        var own: [String] = []
        var list: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&list) == 0, let first = list {
            for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
                guard let raw = entry.pointee.ifa_addr, raw.pointee.sa_family == UInt8(AF_INET) else { continue }
                var name = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(raw, socklen_t(MemoryLayout<sockaddr_in>.size), &name, socklen_t(name.count), nil, 0, NI_NUMERICHOST) == 0 {
                    own.append(String(cString: name))
                }
            }
            freeifaddrs(list)
        }
        for address in own { XCTAssertTrue(Gateway.isThisMac(endpoint(address)), address) }
        XCTAssertTrue(Gateway.isThisMac(endpoint("127.1.2.3")), "all of 127/8 is this Mac")
        XCTAssertFalse(Gateway.isThisMac(endpoint("192.0.2.44")), "another device on the network")
    }

    /// Only the network the phone is on: the subnet of this Mac's Wi‑Fi or wired interface, not a VPN or a virtual
    /// machine's bridge, nor anywhere further away.
    func testOnlyTheMacsOwnWiFiOrWiredNetworkCounts() throws {
        var neighbour: String?
        var elsewhere: [String] = []
        var list: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&list) == 0, let first = list {
            for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
                guard let raw = entry.pointee.ifa_addr, raw.pointee.sa_family == UInt8(AF_INET) else { continue }
                let address = raw.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr.s_addr.bigEndian }
                let other = address ^ 1   // another host in the same subnet
                let text = "\(other >> 24).\((other >> 16) & 255).\((other >> 8) & 255).\(other & 255)"
                let name = String(cString: entry.pointee.ifa_name)
                if name.hasPrefix("en"), neighbour == nil { neighbour = text }
                if name.hasPrefix("utun") || name.hasPrefix("bridge") { elsewhere.append(text) }
            }
            freeifaddrs(list)
        }
        func endpoint(_ host: String) -> NWEndpoint { .hostPort(host: NWEndpoint.Host(host), port: 47821) }
        let phone = try XCTUnwrap(neighbour, "this Mac has no Wi‑Fi or wired address to test with")
        XCTAssertTrue(Gateway.isOnLocalNetwork(endpoint(phone)), phone)
        for peer in elsewhere { XCTAssertFalse(Gateway.isOnLocalNetwork(endpoint(peer)), peer) }
        XCTAssertFalse(Gateway.isOnLocalNetwork(endpoint("192.0.2.44")), "a host beyond the Mac's networks")
    }

    func testMessagesTurnedAwayDontCountTowardTheDaysLimit() {
        var taken = PhoneWand.Taken(file: nil)
        XCTAssertTrue(taken.take("A", for: "app"))
        XCTAssertTrue(taken.take("B", for: "app", counted: false))
        XCTAssertTrue(taken.take("C", for: "other"))
        XCTAssertEqual(taken.count(for: "app"), 1)
        XCTAssertFalse(taken.take("B", for: "app"), "a message turned away can't be sent again later")
    }

    private func sealedBody(_ message: [String: Any], secret: String) throws -> Data {
        let box = try AES.GCM.seal(JSONSerialization.data(withJSONObject: message), using: PhoneWand.key(secret: secret))
        return try JSONSerialization.data(withJSONObject: ["sealed": try XCTUnwrap(box.combined).base64EncodedString()])
    }

    private func literal(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private func run(_ program: String) throws -> String {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("wand-seal-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("main.swift")
        try program.write(to: source, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
        process.arguments = [source.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self)
        XCTAssertEqual(process.terminationStatus, 0, output)
        return output
    }
}
