import XCTest
import SwiftUI
import LampSidebarKit
@testable import Lamp

/// An answer clicked on a question card while the agent's turn is still ending waits in line. Drawn as a waiting
/// message as well as the folded card, it showed until it was sent and then went, since the folded card says it.
@MainActor
final class WaitingAnswerTests: XCTestCase {
    private let question = Talk.Question(question: "Pull real title links from that page?",
                                         options: [Talk.Option(title: "Try real links"), Talk.Option(title: "Keep search links")])

    private func chat() -> (lines: [LogLine], card: LogLine) {
        let card = LogLine(kind: .ask, text: "", ask: Talk.Ask(layout: .steps, questions: [question]))
        return ([LogLine(kind: .user, text: "Are we using deeplinks when possible?"), card], card)
    }

    func testAClickedAnswerWaitingInLineIsOnlyItsFoldedCard() throws {
        var (lines, card) = chat()
        let ask = try XCTUnwrap(Talk.give(["Try real links"], to: card.id, in: &lines))
        let clicked = QueuedMessage(text: Talk.message(for: ask, answers: ["Try real links"]), card: card.id)
        let other = QueuedMessage(text: "Make it blue")
        var queue = [clicked, other]

        // Not drawn as a waiting message: the folded card stands for it, and offers taking it back.
        XCTAssertEqual(Talk.drawnWaiting(queue, in: lines).map(\.id), [other.id])
        XCTAssertEqual(Talk.waiting(on: lines[1], in: queue)?.id, clicked.id)

        // Taken back from there, the card opens again for another answer.
        XCTAssertTrue(Talk.unqueue(clicked, from: &queue, lines: &lines))
        XCTAssertEqual(Talk.open(in: lines)?.id, card.id)
        XCTAssertNil(Talk.waiting(on: lines[1], in: queue))
    }

    /// An answer typed instead is a message of its own, which the chat shows once it's sent: it waits as one too.
    func testATypedAnswerWaitsAsAMessage() {
        var (lines, card) = chat()
        lines[1].ask?.typed = true
        let typed = QueuedMessage(text: "Only for shows with a page of their own", card: card.id)

        XCTAssertEqual(Talk.drawnWaiting([typed], in: lines).map(\.id), [typed.id])
        XCTAssertNil(Talk.waiting(on: lines[1], in: [typed]))
    }

    /// The chat while a clicked answer waits, drawn offscreen as Lamp's window draws it, into the PNG named by
    /// `LAMP_RENDER_WAITING_ANSWER`. Nothing is drawn without it.
    func testRenderTheChatWhileAnAnswerWaits() throws {
        guard let path = ProcessInfo.processInfo.environment["LAMP_RENDER_WAITING_ANSWER"] else {
            throw XCTSkip("Set LAMP_RENDER_WAITING_ANSWER to a PNG path to draw the chat.")
        }
        var (lines, card) = chat()
        let ask = try XCTUnwrap(Talk.give(["Try real links"], to: card.id, in: &lines))
        let queue = [QueuedMessage(text: Talk.message(for: ask, answers: ["Try real links"]), card: card.id)]
        let folded = try XCTUnwrap(lines[1].ask)
        let waiting = Talk.waiting(on: lines[1], in: queue).map { _ in AskWaiting(forSetup: false) {} }

        let chat = VStack(alignment: .leading, spacing: 16) {
            ChatLook.UserBubble(lines[0].text).frame(maxWidth: .infinity, alignment: .trailing)
            AskCardView(ask: folded, isOpen: false, progress: .constant(AskProgress()), waiting: waiting) { _ in }
            ForEach(Talk.drawnWaiting(queue, in: lines)) { message in
                ChatLook.QueuedRow(text: message.text, waitingForSetup: false, onRemove: {}) { EmptyView() }
            }
        }
        .padding(24)
        .frame(width: 560, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))

        let view = NSHostingView(rootView: chat)
        view.appearance = NSAppearance(named: .darkAqua)
        view.frame = CGRect(origin: .zero, size: view.fittingSize)
        let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = view.appearance
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: path))
    }
}
