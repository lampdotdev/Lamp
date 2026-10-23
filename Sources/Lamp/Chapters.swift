import SwiftUI
import LampSidebarKit

/// A new app's first build in the chat: the parts of the agent's plan (its `plan` tool) are the chat's chapters, each a
/// heading with its tick and how long it took, with what the agent said during it and its steps, folded, under it. The
/// parts still to come wait greyed below, and a bar at the top of the chat says where the build is (`ChapterBar`). Once
/// the app is made it all folds to one line ("Built it in 3 parts · 4 min 29 s"), with the agent's answer under it.
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

/// A first build's chapters (`Chapters.Build`). What's under each part is drawn by the chat (`part`), given the part
/// and whether it's the one going on now, which has the turn's live line at its foot.
struct BuildChapters<Part: View>: View {
    let build: Chapters.Build
    /// The turn going on, while the build is.
    let progress: TurnProgress?
    @ViewBuilder let part: (Int, Bool) -> Part
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if build.folded {
                Button {
                    withAnimation(.snappy(duration: 0.2)) { open.toggle() }
                } label: {
                    ChapterHeading(state: .done, number: 0, title: build.foldTitle, time: build.time, chevron: open)
                }
                .buttonStyle(.plain)
                .pointingHand()
                .help(open ? "Hide the parts" : "Show the parts")
                .accessibilityHint(open ? "Hides the parts" : "Shows the parts")
                if open { chapters.padding(.leading, 30).transition(.opacity) }
                if let answer = build.answer { ChatLook.AgentText(answer.text).padding(.top, 12) }
            } else {
                chapters
            }
        }
    }

    private var chapters: some View {
        VStack(alignment: .leading, spacing: 0) {
            if build.titles.isEmpty {
                // No plan yet: what the agent has said and done so far, and Lamp's guess at the parts to come.
                part(0, build.live)
                ForEach(Array((progress?.asking == false ? progress?.sketch ?? [] : []).enumerated()), id: \.offset) { index, title in
                    ChapterHeading(state: .later, number: index + 1, title: title)
                }
            }
            ForEach(Array(build.titles.enumerated()), id: \.offset) { index, title in
                let state = build.state(of: index)
                ChapterHeading(state: state, number: index + 1, title: title,
                               time: build.seconds(of: index).map(ChatItem.duration))
                if state != .later {
                    part(index, build.live && build.summary == nil && index == build.current)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 14).padding(.bottom, 4)
                        .overlay(alignment: .leading) {
                            Rectangle().fill(.quaternary).frame(width: 1.5).padding(.leading, 9)
                        }
                }
            }
            // Lamp's own last part, which no plan lists: building the app and opening it.
            if build.live && !build.titles.isEmpty {
                ChapterHeading(state: build.summary == nil ? .later : .now, number: 0, title: "Lamp builds and opens it",
                               finishing: true, working: build.summary != nil)
                if build.summary != nil, let progress {
                    ChatLook.ActivityText(progress.activity, since: progress.activitySince)
                        .font(ChatLook.stepFont).foregroundStyle(.secondary)
                        .padding(.leading, 30)
                }
            }
        }
    }
}

/// A part's heading: its mark (a tick once done, its number until then), its title, how long it took, and a rule.
struct ChapterHeading: View {
    let state: Chapters.Build.State
    let number: Int
    let title: String
    var time: String? = nil
    /// The folded build's line, which opens to its parts.
    var chevron: Bool? = nil
    /// Lamp's own last part, marked as one no plan lists.
    var finishing = false
    var working = false

    var body: some View {
        HStack(spacing: 10) {
            mark.frame(width: 20, height: 20)
            // A long part wraps rather than losing its end; the rule takes what room is left.
            Text(title)
                .fontWeight(state == .later ? .regular : .semibold)
                .foregroundStyle(state == .later ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
            if let time { Text(time).font(.caption).foregroundStyle(.secondary).fixedSize() }
            if let chevron {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(chevron ? 90 : 0))
            }
            Rectangle().fill(.quaternary).frame(minWidth: 12, maxHeight: 1)
        }
        .contentShape(Rectangle())
        .padding(.top, 18).padding(.bottom, 6)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var mark: some View {
        if working {
            ProgressView().controlSize(.small)
        } else if state == .done {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 18)).foregroundStyle(.white, .green)
        } else if finishing {
            Circle().strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [2, 2])).foregroundStyle(.tertiary)
        } else {
            let color: Color = state == .now ? .accentColor : .secondary
            Circle().strokeBorder(color.opacity(state == .now ? 1 : 0.5), lineWidth: 1.5)
                .overlay { Text("\(number)").font(.system(size: 11, weight: .bold)).foregroundStyle(color.opacity(state == .now ? 1 : 0.7)) }
        }
    }
}

/// The bar pinned at the top of a new app's chat while it's first built: the app, where the build is ("Part 3 of 3"),
/// and a dot for each part. Under it the chat scrolls, so it says where things are when the heading is out of sight.
struct ChapterBar<Icon: View>: View {
    let title: String
    let progress: TurnProgress
    @ViewBuilder let icon: () -> Icon

    var body: some View {
        HStack(spacing: 9) {
            icon()
            Text(title).fontWeight(.semibold).lineLimit(1)
            Spacer(minLength: 12)
            status.font(.callout).foregroundStyle(.secondary).lineLimit(1)
            if !progress.asking, !progress.plan.isEmpty {
                HStack(spacing: 4) {
                    ForEach(progress.plan.indices, id: \.self) { index in
                        Circle().fill(color(of: index)).frame(width: 7, height: 7)
                    }
                }
                .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 9)
        .frame(maxWidth: 680)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    /// Done green, the one being worked on blue, the rest faint.
    private func color(of part: Int) -> Color {
        if progress.ending == .ready || progress.chaptersClosed || part < progress.reached { return .green }
        return part == progress.reached && progress.finished == nil ? .accentColor : Color.secondary.opacity(0.25)
    }

    @ViewBuilder
    private var status: some View {
        if progress.asking {
            Text("Waiting for your answer")
        } else if let ending = progress.ending {
            switch ending {
            case .ready:
                Label { Text("Ready") } icon: { Image(systemName: "circle.fill").foregroundStyle(.green).imageScale(.small) }
            case .didNotFinish: Text("Didn't finish")
            case .didNotOpen: Text("Built, but it didn't open")
            }
        } else if progress.plan.isEmpty {
            // The agent may build without a plan; until one comes the bar says only that it's being built.
            Text(progress.naming ? "Naming your app" : "Building it")
        } else if progress.chaptersClosed {
            Text("Building and opening it")
        } else {
            Text("Part \(min(progress.reached, progress.plan.count - 1) + 1) of \(progress.plan.count)")
        }
    }
}
