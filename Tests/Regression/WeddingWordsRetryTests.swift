import Network
import XCTest
@testable import Lamp

/// At Wedding Words' table, a reply whose call to the AI fails stays in the conversation, saved, and Try again
/// sends it once more: nothing to type again and no second copy of it. The starter's conversation code is
/// compiled with the support code Lamp writes into it and pointed at a stand-in for Lamp whose first answer
/// is an error, with a made-up home folder, so what it saves is real and nobody's own.
final class WeddingWordsRetryTests: XCTestCase {
    func testAFailedReplyIsKeptAndSentOnceMore() throws {
        let starter = try StarterTrees.starter("weddingwords")
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-weddingwords-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: work) }
        let project = try Template.draft(name: starter.name, in: work.appendingPathComponent("apps"))
        try Template.fill(project)
        try Starters.copy(starter, into: project)
        try Template.writeOwnedFiles(for: project)

        let lamp = try StandInLamp()
        defer { lamp.stop() }
        // The app finds Lamp where its Info.plist says, as an installed copy does: here, at the stand-in.
        var values = Template.installValues(for: project)
        values["port"] = String(lamp.port)
        let install = try InstallValues.linkerFlags(values, in: work)

        let words = "Piacere, sono la sorella della sposa."
        let program = """
        import Foundation
        @main struct Check {
            @MainActor static func main() async {
                let talk = TableTalk()
                talk.open(0)
                _ = await talk.ask("\(words)", as: "Mother", context: "Milestone: introductions.")
                print(talk.turns.map(\\.who), talk.awaitsHer, talk.error.isEmpty ? "no error" : talk.error)
                let reopened = TableTalk()
                reopened.open(0)
                print(reopened.turns.map(\\.text))
                _ = await talk.ask(as: "Mother", context: "Milestone: introductions.")
                print(talk.turns.map(\\.who), talk.awaitsHer, talk.error.isEmpty ? "no error" : talk.error)
            }
        }
        """
        try program.write(to: work.appendingPathComponent("check.swift"), atomically: true, encoding: .utf8)
        let sources = ["LampSupport.swift", "TableTalk.swift"]
            .map { "\"\(project.dir.appendingPathComponent("Sources/\($0)").path)\"" }.joined(separator: " ")
        let built = try run(Shell.compatibleSDK + "xcrun swiftc -parse-as-library -o check check.swift \(sources) \(install) 2>&1", in: work)
        XCTAssertEqual(built.status, 0, built.output)
        let home = work.appendingPathComponent("home")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let ran = try run("CFFIXED_USER_HOME=\"\(home.path)\" ./check 2>/dev/null", in: work)
        XCTAssertEqual(ran.status, 0, ran.output)
        XCTAssertEqual(ran.output, """
        ["You"] true The AI is busy right now.
        ["\(words)"]
        ["You", "Mother"] false no error

        """)
        // Both calls carried the reply, and only once each.
        let asked = lamp.asked
        XCTAssertEqual(asked.count, 2)
        for body in asked { XCTAssertEqual(body.components(separatedBy: words).count - 1, 1, body) }
    }

    private func run(_ command: String, in directory: URL) throws -> (status: Int32, output: String) {
        TestShell.run(command, in: directory)
    }
}

/// Answers the app's AI calls as Lamp would: text AI is there, the first request fails with Lamp's error shape, and
/// the next gets a reply in character. Keeps the body of each AI request.
private final class StandInLamp: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "stand-in-lamp")
    private var bodies: [String] = []
    private(set) var port: UInt16 = 0

    init() throws {
        listener = try NWListener(using: .tcp, on: .any)
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { if case .ready = $0 { ready.signal() } }
        listener.newConnectionHandler = { [unowned self] connection in
            connection.start(queue: queue)
            receive(on: connection, Data())
        }
        listener.start(queue: queue)
        guard ready.wait(timeout: .now() + 5) == .success, let port = listener.port?.rawValue else {
            throw CocoaError(.fileNoSuchFile)
        }
        self.port = port
    }

    var asked: [String] { queue.sync { bodies } }
    func stop() { listener.cancel() }

    private func receive(on connection: NWConnection, _ data: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [unowned self] chunk, _, done, _ in
            let data = data + (chunk ?? Data())
            let text = String(decoding: data, as: UTF8.self)
            if let end = text.range(of: "\r\n\r\n") {
                let head = String(text[..<end.lowerBound])
                let length = head.split(separator: "\r\n")
                    .first { $0.lowercased().hasPrefix("content-length:") }
                    .flatMap { Int($0.split(separator: ":")[1].trimmingCharacters(in: .whitespaces)) } ?? 0
                let body = data.suffix(from: data.startIndex + text[..<end.upperBound].utf8.count)
                if body.count >= length {
                    answer(head.split(separator: " ").dropFirst().first.map(String.init) ?? "",
                           String(decoding: body, as: UTF8.self), on: connection)
                    return
                }
            }
            if done { connection.cancel() } else { receive(on: connection, data) }
        }
    }

    private func answer(_ path: String, _ body: String, on connection: NWConnection) {
        let (status, json): (Int, Any)
        switch path {
        case "/ai/status": (status, json) = (200, ["text": true])
        case "/ai":
            bodies.append(body)
            if bodies.count == 1 {
                (status, json) = (500, ["error": "The AI is busy right now."])
            } else {
                let reply = #"{"italian":"Che piacere! Come stai?","translation":"What a pleasure! How are you?","coaching":"Lovely.","score":3,"phrase":"Come stai?","meaning":"How are you?"}"#
                (status, json) = (200, ["text": reply])
            }
        default: (status, json) = (404, [String: Any]())
        }
        let data = (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
        let head = "HTTP/1.1 \(status) X\r\nContent-Type: application/json\r\nContent-Length: \(data.count)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(head.utf8) + data, completion: .contentProcessed { _ in connection.cancel() })
    }
}
