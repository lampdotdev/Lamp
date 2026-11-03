import Foundation

/// A game has one hidden preview, staged from one folder, so one look or `use_app` has it at a time, whichever turn
/// asked: two at once would stage and play over each other, however an engine schedules its calls. The rest wait in
/// the order they came, and a wait ends early when its turn is stopped or the person writes (`drop`), so nothing plays
/// for a turn that has moved on.
@MainActor final class HiddenCopyLine {
    private var taken = false
    private var waiting: [(turn: ObjectIdentifier, resume: CheckedContinuation<String?, Never>)] = []

    /// Nil once the copy is the caller's, who then lets it go (`letGo`); else why it never was.
    func take(for turn: AnyObject) async -> String? {
        guard taken else {
            taken = true
            return nil
        }
        return await withCheckedContinuation { waiting.append((ObjectIdentifier(turn), $0)) }
    }

    func letGo() {
        if waiting.isEmpty { taken = false } else { waiting.removeFirst().resume.resume(returning: nil) }
    }

    /// Ends the waits of one turn, each answered with `reason`.
    func drop(_ turn: AnyObject, saying reason: String) {
        let id = ObjectIdentifier(turn)
        for waiter in waiting where waiter.turn == id { waiter.resume.resume(returning: reason) }
        waiting.removeAll { $0.turn == id }
    }
}
