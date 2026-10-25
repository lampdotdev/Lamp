import SwiftUI
import LampSidebarKit

/// A new app's first build in the chat: the parts of the agent's plan (its `plan` tool) are the chat's chapters, each a
/// heading with its tick and how long it took, with what the agent said during it and its steps, folded, under it. The
/// parts still to come wait greyed below. Once the app is made it all folds to one line ("Built it in 3 parts · 4 min 29 s"), with the agent's answer under it.
/// It took the place of a card above the chat, whose checklist and steps took over the window and left the agent's
/// own words and its question lost below it.
///
/// Which part a line goes under is decided as it's logged, from what Lamp is sure of (`TurnProgress.chapter(for:)`),
/// and kept on the line (`LogLine.part`); the build's summary keeps the plan's parts (`LogLine.plan`), so the chat
/// reads the same once the turn is over and after a relaunch. A line with no part (one logged before the plan came)
/// goes with the part of the line before it, the first part at the start.
enum Chapters {
    /// A stretch of the chat drawn as it is, or a first build drawn as its plan's parts.
    enum Segment {
        case lines([LogLine])
        case build(Build)
    }

    /// One first build: the lines of its run after the request, under its parts.
    struct Build {
        /// The run's first line.
        let id: UUID
        /// The plan's parts, in order. Empty while the agent hasn't given one.
        let titles: [String]
        /// Each part's lines (with no plan yet, one list with every line).
        let parts: [[LogLine]]
        /// The run's summary, once the agent's run is over.
        let summary: LogLine?
        /// The build is the turn going on.
        let live: Bool
        /// Over and made: the agent's answer, which goes under the folded build.
        let answer: LogLine?
        /// The whole chat, for which question still waits.
        let chat: [LogLine]

        /// The app came of it, with nothing gone wrong after: the build folds to one line.
        let built: Bool
        var folded: Bool { built }

        /// The part the build is on: the last one anything came in.
        var current: Int { parts.lastIndex { !$0.isEmpty } ?? 0 }

        enum State { case done, now, later }

        func state(of part: Int) -> State {
            if folded || live && summary != nil { return .done }
            return part < current ? .done : part == current ? .now : .later
        }

        /// How long a part took: from its first line to the next part's first, or to the run's end. Only for a
        /// part that's done, and nil in a chat from before lines were timed.
        func seconds(of part: Int) -> TimeInterval? {
            guard state(of: part) == .done, let start = parts[part].first?.at else { return nil }
            let end = parts[(part + 1)...].first { !$0.isEmpty }?.first?.at ?? summary?.at
            return end.map { max(0, $0.timeIntervalSince(start)) }
        }

        /// "Built it in 3 parts".
        var foldTitle: String { titles.count == 1 ? "Built it" : "Built it in \(titles.count) parts" }

        /// The run's whole time, from its summary ("4 min 29 s").
        var time: String? {
            guard let summary else { return nil }
            let worked = ChatItem.workedFor(summary.text)
            return worked.hasPrefix("Worked for ") ? String(worked.dropFirst("Worked for ".count)) : nil
        }
    }

    /// The chat cut into what's drawn as it is and the first builds drawn as chapters. A build is a run (a request and
    /// what came of it, up to its summary) whose summary carries a plan, or the run going on in a new app's first turn
    /// (`progress`), whose plan may not have come yet.
    static func segments(_ lines: [LogLine], progress: TurnProgress?) -> [Segment] {
        let going = progress.flatMap { $0.newApp && $0.finished == nil ? $0 : nil }
        // A question asked before there was a plan waits as it came: a plan given after it doesn't make chapters round
        // it, which would move the card under the pointer.
        let waiting = Talk.open(in: lines)
        var segments: [Segment] = []
        var plain: [LogLine] = []
        var start = lines.startIndex
        while start < lines.endIndex {
            let summary = lines[start...].firstIndex { $0.kind == .summary }
            let end = summary.map { $0 + 1 } ?? lines.endIndex
            // The turn going on: no request after this run's.
            let live = going != nil && !lines[end...].contains { $0.kind == .user }
            let unplanned = waiting.map { ask in ask.part == nil && lines[start..<end].contains { $0.id == ask.id } } ?? false
            let titles = unplanned ? [] : summary.flatMap { lines[$0].plan } ?? (live && summary == nil && going?.chaptersClosed != true ? going?.plan.map(\.title) ?? [] : [])
            // What's logged after the agent's run (Lamp building and opening the app) is no build of its own: the run's
            // summary closed its chapters, and it's drawn after them.
            guard !titles.isEmpty || live && summary == nil && going?.chaptersClosed != true else {
                plain += lines[start..<end]
                start = end
                continue
            }
            // The build starts after its request. A run begun by an answer clicked on a card has none in the chat
            // (the card shows it), and starts where the run does.
            var body = lines[start..<end].firstIndex { $0.kind == .user } ?? start
            while body < end, lines[body].kind == .user { body += 1 }
            plain += lines[start..<body]
            if !plain.isEmpty { segments.append(.lines(plain)) }
            plain = []
            var run = Array(lines[body..<(summary ?? end)])
            // What came after the summary, up to the next request: Lamp's own build and opening, and what went wrong.
            let next = lines[end...].firstIndex { $0.kind == .user } ?? lines.endIndex
            let failed = lines[end..<next].contains { $0.kind == .error || $0.kind == .status && $0.text.hasPrefix("Stopped.") }
            let built = summary != nil && !live && !failed && !titles.isEmpty && !run.contains { $0.kind == .ask }
            var answer: LogLine?
            if built, let last = run.lastIndex(where: { $0.kind == .agent }) { answer = run.remove(at: last) }
            let count = max(titles.count, 1)
            var parts = Array(repeating: [LogLine](), count: count)
            var part = 0
            for line in run {
                if let stamped = line.part { part = min(max(stamped, 0), count - 1) }
                parts[part].append(line)
            }
            segments.append(.build(Build(id: lines[min(body, end - 1)].id, titles: titles, parts: parts,
                                         summary: summary.map { lines[$0] }, live: live, answer: answer, chat: lines,
                                         built: built)))
            start = summary.map { $0 + 1 } ?? end
        }
        if !plain.isEmpty { segments.append(.lines(plain)) }
        return segments
    }
}
