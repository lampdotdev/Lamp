import XCTest
@testable import Lamp

/// A wish worked on for days keeps its conversation small enough to send: the older pictures come out of Claude Code's
/// and Codex's files before they're resumed, and a request cut off while sending a large one starts a fresh one.
final class ConversationSizeTests: XCTestCase {
    private func file(_ lines: [String]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jsonl")
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testClaudeKeepsTheNewestPicturesAndTheRestOfTheFile() throws {
        let image = #"{"type":"image","source":{"type":"base64","media_type":"image/jpeg","data":"QUJD"}}"#
        let pictures = (0..<14).map { index in
            #"{"type":"user","uuid":"u\#(index)","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t\#(index)","content":[{"type":"text","text":"look \#(index)"},\#(image)]}]},"toolUseResult":[\#(image)]}"#
        }
        let words = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"a/b"}],"usage":{"input_tokens":10,"cache_read_input_tokens":90}}}"#
        let url = try file([words] + pictures)
        XCTAssertEqual(Conversation.measure(url, engine: .claude).pictures, 14)

        XCTAssertEqual(Conversation.keepPicturesFew(in: url, engine: .claude), 8)
        let size = Conversation.measure(url, engine: .claude)
        XCTAssertEqual(size.pictures, 6)
        XCTAssertEqual(size.tokens, 100)
        let lines = try String(contentsOf: url, encoding: .utf8).components(separatedBy: "\n")
        XCTAssertEqual(lines[0], words, "a line with no picture is left as it was")
        XCTAssertFalse(lines[1].contains("base64"), "the copy beside the message goes too")
        XCTAssertTrue(lines[1].contains("look 0") && lines[1].contains("taken out of the conversation"))
        XCTAssertEqual(lines[14], pictures[13])
        // Under the line nothing changes, so the conversation's cached beginning stays as it was.
        XCTAssertEqual(Conversation.keepPicturesFew(in: url, engine: .claude), 0)
    }

    func testCodexPicturesBecomeItsOwnWords() throws {
        let pictures = (0..<13).map { index in
            #"{"type":"response_item","payload":{"type":"function_call_output","call_id":"c\#(index)","output":[{"type":"input_text","text":"look"},{"type":"input_image","image_url":"data:image/jpeg;base64,QUJD"}]}}"#
        }
        let url = try file(pictures)
        XCTAssertEqual(Conversation.keepPicturesFew(in: url, engine: .codex), 7)
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(text.components(separatedBy: "input_image").count - 1, 6)
        let words = text.components(separatedBy: "\n").first.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) } as? [String: Any]
        let output = (words?["payload"] as? [String: Any])?["output"] as? [[String: Any]]
        XCTAssertEqual(output?.last?["type"] as? String, "input_text")
        XCTAssertEqual(output?.last?["text"] as? String, Conversation.droppedPicture)
    }

    func testACutConnectionStartsAfreshOnlyForALargeConversation() {
        let failure = "API Error: Unable to connect to API (EPROTO)"
        XCTAssertTrue(Conversation.isTooBigToSend(failure, size: Conversation.Size(tokens: 466_000, pictures: 157, pictureBytes: 65_000_000)))
        XCTAssertFalse(Conversation.isTooBigToSend(failure, size: Conversation.Size(tokens: 20_000, pictures: 2, pictureBytes: 200_000)))
        XCTAssertFalse(Conversation.isTooBigToSend(failure, size: nil))
        XCTAssertTrue(Conversation.isTooBigToSend("Prompt is too long", size: nil))
        XCTAssertFalse(Conversation.isTooBigToSend("429 rate limit exceeded", size: Conversation.Size(tokens: 466_000)))
    }
}
