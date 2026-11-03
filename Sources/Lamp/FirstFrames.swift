import Foundation

/// When a game's page has drawn, as the page says it (`PageLive.state`, "playing", the frame after its first) for one
/// launch of its app, named by the process: what a page of an earlier launch said, or the hidden preview, which says
/// nothing of the kind, never answers for this one. A report may come before anyone waits for it. A wait settles once:
/// on the report, at its limit, or when it's ended (`end`: the turn was stopped, or the app closed).
@MainActor final class FirstFrames {
    enum Outcome: Equatable { case drawn, timedOut, ended }

    private struct Waiter {
        let launch: Int32
        let resume: CheckedContinuation<Outcome, Never>
        let limit: Task<Void, Never>
    }
    private var seen: [String: Int32] = [:]
    private var waiters: [String: Waiter] = [:]

    func report(app: String, launch: Int32) {
        seen[app] = launch
        if waiters[app]?.launch == launch { settle(app, .drawn) }
    }

    func wait(app: String, launch: Int32, limit: Duration) async -> Outcome {
        settle(app, .ended)
        if seen[app] == launch { return .drawn }
        return await withCheckedContinuation { resume in
            let limit = Task { [weak self] in
                try? await Task.sleep(for: limit)
                guard !Task.isCancelled else { return }
                self?.settle(app, .timedOut)
            }
            waiters[app] = Waiter(launch: launch, resume: resume, limit: limit)
        }
    }

    func end(app: String) { settle(app, .ended) }

    /// Before an app opens again, so nothing said of its last launch stays.
    func forget(app: String) {
        seen[app] = nil
        settle(app, .ended)
    }

    private func settle(_ app: String, _ outcome: Outcome) {
        guard let waiter = waiters.removeValue(forKey: app) else { return }
        waiter.limit.cancel()
        waiter.resume.resume(returning: outcome)
    }
}
