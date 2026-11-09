import Foundation

/// The AI's part of the one review being made (`Store.inspectAndAsk`), waited on until whichever comes first: the AI's
/// answer, or the review being stopped (Cancel, a newer review, the deadline). Each wait belongs to the review that
/// started it, and only that review's id settles it: an answer from a review that was stopped or replaced, arriving
/// late, finds another review waiting and leaves it alone. Settled once; later settlements for it do nothing.
@MainActor final class ReviewSettlement<Answer> {
    private var waiting: (id: UUID, done: CheckedContinuation<Answer?, Never>)?
    /// An outcome that came before its review began to wait, kept for that review only.
    private var early: (id: UUID, answer: Answer?)?

    /// Waits for review `id`'s outcome: its answer, or nil when it was stopped.
    func wait(for id: UUID) async -> Answer? {
        // A review only ever waits once, and only one review is made at a time: one still waiting has been replaced.
        settle(nil, for: waiting?.id)
        if let kept = early, kept.id == id {
            early = nil
            return kept.answer
        }
        early = nil
        return await withCheckedContinuation { waiting = (id, $0) }
    }

    /// Settles review `id`'s wait with `answer` if it's the one waiting, or keeps it for that review's wait to come when
    /// none is waiting. Nil `id` settles nothing, and a review other than the one waiting never settles it.
    func settle(_ answer: Answer?, for id: UUID?) {
        guard let id else { return }
        guard let current = waiting else {
            if early == nil { early = (id, answer) }
            return
        }
        guard current.id == id else { return }
        waiting = nil
        current.done.resume(returning: answer)
    }
}
