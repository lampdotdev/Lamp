import SwiftUI
import LampSidebarKit

/// The agent's cards in Lamp's window: the views themselves are shared with the chat inside each app's window
/// (LampSidebarKit's TalkCards.swift); these give them the chat's line and what a click does.

/// How far each open card has been answered, by its line. Kept apart from the card's view because the same
/// card is drawn in Lamp's window and in the chat inside the app's window (`Sidebar`): an answer begun in one is
/// carried on in the other, not started over.
@MainActor
final class AskProgresses: ObservableObject {
    static let shared = AskProgresses()
    @Published private var progress: [UUID: AskProgress] = [:]

    func binding(for line: UUID) -> Binding<AskProgress> {
        Binding(get: { self.progress[line] ?? AskProgress() }, set: { self.progress[line] = $0 })
    }

    /// The same for the chat inside the app's window (`Sidebar`), which keeps its own copy over the wire.
    func progress(for line: UUID) -> AskProgress? { progress[line] }
    func set(_ value: AskProgress, for line: UUID) {
        guard progress[line] != value else { return }
        progress[line] = value
    }
}

/// A set of questions in the chat. Open, it's answered by clicking; after that it shows what was chosen, or
/// just what was asked when the person typed their answer instead.
struct AskCard: View {
    let line: LogLine
    let dir: URL
    let isOpen: Bool
    @ObservedObject private var store = Store.shared
    @ObservedObject private var progresses = AskProgresses.shared

    var body: some View {
        if let ask = line.ask, let project = store.projects.first(where: { $0.dir == dir }) {
            AskCardView(ask: ask, isOpen: isOpen, progress: progresses.binding(for: line.id)) { answers in
                withAnimation(.snappy(duration: 0.3)) { store.answer(line, with: answers, in: project) }
            }
        }
    }
}

/// What a request made, in one sentence, a new app's as much as a change's (`ResultCardView`).
struct ResultCard: View {
    let line: LogLine

    var body: some View {
        if let result = line.result { ResultCardView(result: result) }
    }
}

