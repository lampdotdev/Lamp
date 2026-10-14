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

    /// What the route asks before it takes a message: the day's last one goes through, the one after is turned away.
    func testTheMessageAfterTheDaysLastIsRefused() {
        XCTAssertNil(PhoneWand.refusal(of: "Make it blue", ready: true, sentToday: PhoneWand.dailyLimit - 1))
        XCTAssertNotNil(PhoneWand.refusal(of: "Make it blue", ready: true, sentToday: PhoneWand.dailyLimit))
        var taken = PhoneWand.Taken(file: nil)
        var sentOn = 0
        for index in 0...PhoneWand.dailyLimit {   // 31 messages
            if PhoneWand.refusal(of: "Change \(index)", ready: true, sentToday: taken.count(for: "app")) == nil {
                _ = taken.take("\(index)", for: "app")
                sentOn += 1
            } else {
                _ = taken.take("\(index)", for: "app", counted: false)
            }
        }
        XCTAssertEqual(sentOn, PhoneWand.dailyLimit)
        XCTAssertEqual(taken.count(for: "app"), PhoneWand.dailyLimit)
    }

    func testMessagesTurnedAwayDontCountTowardTheDaysLimit() {
        var taken = PhoneWand.Taken(file: nil)
        XCTAssertTrue(taken.take("A", for: "app"))
        XCTAssertTrue(taken.take("B", for: "app", counted: false))
        XCTAssertTrue(taken.take("C", for: "other"))
        XCTAssertEqual(taken.count(for: "app"), 1)
        XCTAssertFalse(taken.take("B", for: "app"), "a message turned away can't be sent again later")
    }

    /// The phone sends a message again until Lamp answers it. When the first answer was "no" (refused, or another
    /// change going) and got lost, the retry has to hear "no" again, or the phone drops what was typed.
    func testARetriedMessageThatWasTurnedAwayHearsTheSameAnswer() {
        let refused = PhoneWand.turnedAway("A", for: "app", .refused("That's too long."))
        XCTAssertEqual(PhoneWand.answer(toTurnedAway: refused)?["refused"] as? String, "That's too long.")
        let busy = PhoneWand.turnedAway("B", for: "app", .busy("C"))
        XCTAssertEqual(PhoneWand.answer(toTurnedAway: busy)?["busy"] as? Bool, true)
        XCTAssertEqual(PhoneWand.answer(toTurnedAway: busy)?["going"] as? String, "C")
        XCTAssertNil(PhoneWand.answer(toTurnedAway: PhoneWand.Request(id: "D", project: "app", arrived: Date())))
        XCTAssertNotNil(busy.ended, "a message turned away isn't the change going")
    }

    /// The sheet's own state, cut out of the template and run: a message stays the phone's until Lamp has it, a
    /// "no" puts it back in the box, and a change going when the app closed is followed to its end after it opens.
    func testThePhoneKeepsItsMessageUntilLampHasItAndFollowsAChangeAfterARelaunch() throws {
        let support = Template.lampSupportSwift
        let start = try XCTUnwrap(support.range(of: "struct LampWandFlow {"))
        let end = try XCTUnwrap(support.range(of: "// end LampWandFlow", range: start.upperBound..<support.endIndex))
        let program = """
        import Foundation
        \(support[start.lowerBound..<end.lowerBound])
        func say(_ key: String, _ value: Any?) { print("\\(key)=\\(value.map { "\\($0)" } ?? "nil")") }

        // Sent while Lamp can't be reached: the box waits, and a second message can't take the first's place.
        var flow = LampWandFlow()
        flow.draft = "Make it blue"
        let first = flow.send(id: "A")!
        flow.unreachable()
        say("away", flow.phase == .away)
        say("busyWhileUnsent", flow.busy)
        flow.draft = "Make it red"
        say("secondSend", flow.send(id: "B").map { $0.id })
        say("stillUnsent", flow.unsent?.text)

        // Lamp's answer, sent again for a retry, says the first was refused: what was typed comes back.
        _ = flow.delivered(["on": true, "refused": "That's too long."], id: first.id, sheetOpen: true)
        say("draftAfterRefusal", flow.draft)
        say("phaseAfterRefusal", flow.phase.rawValue)

        // Lamp was restarted and lost what became of it: the text comes back too.
        var lost = LampWandFlow()
        lost.draft = "Add a reset"
        _ = lost.send(id: "C")
        _ = lost.delivered(["on": true, "id": "C", "phase": "failed", "note": "Lamp on your Mac was restarted."], id: "C", sheetOpen: false)
        say("draftAfterRestart", lost.draft)

        // Opened again by an install, with the change still going: followed until Done, and the sheet rises once.
        var reopened = LampWandFlow()
        reopened.request = "D"
        reopened.unreachable()
        say("pollsWhenFirstAskFails", reopened.shouldPoll(sheetOpen: false))
        _ = reopened.apply(["on": true, "id": "D", "phase": "installing"], sheetOpen: false)
        say("pollsWhileInstalling", reopened.shouldPoll(sheetOpen: false))
        say("risesAtDone", reopened.apply(["on": true, "id": "D", "phase": "done", "changed": true], sheetOpen: false))
        say("risesTwice", reopened.apply(["on": true, "id": "D", "phase": "done", "changed": true], sheetOpen: false))
        say("pollsAfterDone", reopened.shouldPoll(sheetOpen: false))
        """
        var said: [String: String] = [:]
        for line in try run(program).split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 { said[parts[0]] = parts[1] }
        }
        XCTAssertEqual(said["away"], "true")
        XCTAssertEqual(said["busyWhileUnsent"], "true", "the box waits while Lamp hasn't the first message")
        XCTAssertEqual(said["secondSend"], "nil", "a second message mustn't replace one Lamp hasn't confirmed")
        XCTAssertEqual(said["stillUnsent"], "Make it blue")
        XCTAssertEqual(said["draftAfterRefusal"], "Make it blue")
        XCTAssertEqual(said["phaseAfterRefusal"], "failed")
        XCTAssertEqual(said["draftAfterRestart"], "Add a reset")
        XCTAssertEqual(said["pollsWhenFirstAskFails"], "true", "an unfinished change is asked about again")
        XCTAssertEqual(said["pollsWhileInstalling"], "true")
        XCTAssertEqual(said["risesAtDone"], "true")
        XCTAssertEqual(said["risesTwice"], "false")
        XCTAssertEqual(said["pollsAfterDone"], "false")
    }

    /// The app keeps the message it follows, and the one whose Done it already showed, in its settings. Read back
    /// as the app opens, the second must survive the first being restored, or every launch shows the old Done again.
    func testAReopenedAppDoesntShowAnOldDoneAgain() throws {
        let support = Template.lampSupportSwift
        let start = try XCTUnwrap(support.range(of: "struct LampWandFlow {"))
        let end = try XCTUnwrap(support.range(of: "// end LampWandSaved", range: start.upperBound..<support.endIndex))
        let suite = "lamp-wand-test-\(UUID().uuidString)"
        let program = """
        import Foundation
        import Combine
        \(support[start.lowerBound..<end.lowerBound])
        let defaults = UserDefaults(suiteName: "\(suite)")!
        defer { defaults.removePersistentDomain(forName: "\(suite)") }
        defaults.set("A", forKey: LampWandSaved.requestKey)
        defaults.set("A", forKey: LampWandSaved.shownKey)
        let saved = LampWandSaved(defaults)
        print("shown=\\(saved.flow.shown ?? "nil")")
        print("kept=\\(defaults.string(forKey: LampWandSaved.shownKey) ?? "nil")")
        print("rises=\\(saved.flow.apply(["on": true, "id": "A", "phase": "done", "changed": true], sheetOpen: false))")
        """
        var said: [String: String] = [:]
        for line in try run(program).split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 { said[parts[0]] = parts[1] }
        }
        XCTAssertEqual(said["shown"], "A")
        XCTAssertEqual(said["kept"], "A", "restoring the followed message mustn't wipe the one already shown")
        XCTAssertEqual(said["rises"], "false", "a Done already shown doesn't rise again")
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
