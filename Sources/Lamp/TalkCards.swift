import SwiftUI
import LampSidebarKit

/// The agent's cards: their views are LampSidebarKit's (TalkCards.swift), drawn by the shared chat.

/// How far each open card has been answered, by its line. Kept here, not in the card's view, because the chat that
/// draws it can move (beside the app, into Lamp's panel) or be drawn twice for a moment: an answer begun in one is
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
