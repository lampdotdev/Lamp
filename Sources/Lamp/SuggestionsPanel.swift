import AppKit
import LampSidebarKit
import SwiftUI

/// The changes people sent to the person's apps, in the desk's own window, in place of its list: gone to when the person
/// wants, from the side column or an app's line, and never put in front of them. One app at a time, the new ones first,
/// each in a line; sorted by the part of the app Lamp says it touches, and searched by anything in its line. The one chosen
/// says what it does in plain words, what Lamp knows for sure of it, and what its sender wrote, with Try It First and
/// Bring Into My App.
///
/// A request counts as seen once it's shown here, at the head it's shown at; new commits make it new again. A request
/// closed and opened again at the same head is as it was. Mark All as Seen marks those the list shows when it's clicked.
/// Not for Me sets one aside quietly (the sender hears nothing) until its sender changes it.
struct SuggestionsPanel: View {
    @EnvironmentObject private var store: Store
    /// The app whose changes show.
    let wish: String
    let back: () -> Void
    /// The gallery's made-up app and record, in place of the store's.
    var preview: Preview? = nil

    /// What the gallery shows the panel with: an app, its record, and how far along a try or a bring-in is.
    struct Preview {
        var project: LampProject
        var record: SuggestedChanges.Record
        var yours: Set<String> = []
        var picked: Int? = nil
        var standing: [Int: SuggestedChanges.Standing] = [:]
        var trial: SuggestionTrial.Running? = nil
    }

    @State private var picked: Int?
    @State private var topic: String?
    @State private var search = ""
    @State private var showHidden = false
    /// Those new when the panel opened at this app, or that came while it was open: they stay under New while it's open,
    /// even once seen, so a line doesn't move away as it's clicked.
    @State private var newHere: Set<Int> = []
    /// The files the person changed since their last release, for Good to Know.
    @State private var yours: Set<String> = []

    private var project: LampProject? { preview?.project ?? store.projects.first { $0.id == wish } }
    private var record: SuggestedChanges.Record? {
        if let preview { return preview.record }
        _ = store.suggestionsRevision
        return project.flatMap(SuggestedChanges.record(for:))
    }

    var body: some View {
        if let project, let record {
            content(project, record)
                .onAppear { newHere = Set(record.open.filter(record.isNew).map(\.number)) }
                .onChange(of: store.suggestionsRevision) { newHere.formUnion(record.open.filter(record.isNew).map(\.number)) }
                .task(id: wish) {
                    if let preview { yours = preview.yours } else { yours = await SuggestedChanges.yourChanges(in: project) }
                }
        } else {
            VStack(spacing: 12) {
                header(nil, nil)
                Spacer()
                Text("Nobody has sent changes to your apps yet.").foregroundStyle(Paper.muted)
                Spacer()
            }
        }
    }

    // MARK: The parts

    private func content(_ project: LampProject, _ record: SuggestedChanges.Record) -> some View {
        let shown = Self.shown(record, topic: topic, search: search, summaries: record.summaries)
        let chosen = (picked ?? preview?.picked).flatMap(record.about) ?? shown.first(where: { !record.isHidden($0) })
        return VStack(spacing: 0) {
            header(project, record)
            Divider().overlay(Paper.rule)
            HStack(spacing: 0) {
                list(record, shown: shown, chosen: chosen?.number).frame(width: 330)
                Divider().overlay(Paper.rule)
                Group {
                    if let chosen {
                        SuggestionDetail(project: project, record: record, request: chosen, yours: yours,
                                         next: shown.first { $0.number != chosen.number && record.isNew($0) },
                                         given: preview?.standing[chosen.number], givenTrial: preview?.trial) { picked = $0 }
                            .id(chosen.number)
                    } else {
                        Text("Nothing here right now.").foregroundStyle(Paper.muted).frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .onChange(of: chosen.map { "\($0.number) \($0.head)" }, initial: true) {
            // Shown means seen, at the head shown.
            if preview == nil, let chosen, record.isNew(chosen) { store.sawSuggestions([(chosen.number, chosen.head)], in: project) }
        }
    }

    /// Back, which app (as a menu of those with changes), how many, and Mark All as Seen.
    private func header(_ project: LampProject?, _ record: SuggestedChanges.Record?) -> some View {
        HStack(spacing: 12) {
            Button(action: back) { Label("Back", systemImage: "chevron.left") }
                .buttonStyle(PaperButtonStyle(.outline, height: 28))
                .keyboardShortcut(.cancelAction)
            if let project { AppIcon(project: project, size: 30) }
            Menu {
                ForEach(store.wishesWithSuggestions, id: \.id) { other in
                    let count = store.newSuggestions(other)
                    Button(count > 0 ? "\(other.name) · \(count) new" : other.name) { store.suggestionsOpen = other.id }
                }
            } label: {
                Text(project?.name ?? "Sent to you").font(.system(size: 17, weight: .bold)).foregroundStyle(Paper.ink)
            }
            .menuStyle(.borderlessButton).fixedSize()
            if let record {
                let open = record.open.filter { !record.isHidden($0) }
                Text("\(open.count) \(open.count == 1 ? "change" : "changes") from \(Set(open.map(\.login)).count) \(Set(open.map(\.login)).count == 1 ? "person" : "people") · \(record.newCount) new")
                    .font(.system(size: 13)).foregroundStyle(Paper.muted)
            }
            Spacer()
            if let project, let record, record.newCount > 0 {
                Button("Mark All as Seen") {
                    // Those new as the list stands now; one that changes after this click stays new.
                    store.sawSuggestions(record.open.filter(record.isNew).map { ($0.number, $0.head) }, in: project)
                }
                .buttonStyle(PaperButtonStyle(.outline, height: 28))
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
    }

    private func list(_ record: SuggestedChanges.Record, shown: [SuggestedChanges.Request], chosen: Int?) -> some View {
        let visible = shown.filter { !record.isHidden($0) }
        let new = visible.filter { newHere.contains($0.number) || record.isNew($0) }
        let seen = visible.filter { !(newHere.contains($0.number) || record.isNew($0)) }
        let hidden = shown.filter(record.isHidden)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(Paper.muted)
                TextField("Search changes", text: $search).textFieldStyle(.plain)
            }
            .font(.system(size: 13))
            .padding(.horizontal, 10).frame(height: 30)
            .background(Paper.card, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Paper.rule))

            let all = Self.shown(record, topic: nil, search: "", summaries: record.summaries).filter { !record.isHidden($0) }
            let topics = Self.topics(record, among: all)
            if topics.count > 1 {
                SuggestionChips(items: [("All", all.count)] + topics, selected: topic ?? "All") { topic = $0 == "All" ? nil : $0 }
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if !new.isEmpty {
                        heading("New · \(new.count)")
                        ForEach(new, id: \.number) { line($0, record, chosen: chosen) }
                    }
                    if !seen.isEmpty {
                        heading("Seen · \(seen.count)").padding(.top, new.isEmpty ? 0 : 8)
                        ForEach(seen, id: \.number) { line($0, record, chosen: chosen) }
                    }
                    if !hidden.isEmpty {
                        Button { showHidden.toggle() } label: {
                            HStack(spacing: 4) {
                                heading("Not for me · \(hidden.count)")
                                Image(systemName: showHidden ? "chevron.down" : "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(Paper.label)
                            }
                        }
                        .buttonStyle(.plain).padding(.top, 8)
                        if showHidden { ForEach(hidden, id: \.number) { line($0, record, chosen: chosen) } }
                    }
                    if visible.isEmpty && hidden.isEmpty {
                        Text(search.isEmpty ? "No changes here." : "No changes match.").font(.system(size: 13)).foregroundStyle(Paper.muted).padding(8)
                    }
                }
            }
        }
        .padding(14)
        .background(Paper.panel)
    }

    private func heading(_ text: String) -> some View {
        Text(text.uppercased()).font(.system(size: 10.5, weight: .bold)).tracking(1.1).foregroundStyle(Paper.label)
            .padding(.horizontal, 8).padding(.vertical, 4)
    }

    private func line(_ request: SuggestedChanges.Request, _ record: SuggestedChanges.Record, chosen: Int?) -> some View {
        let selected = request.number == chosen
        let summary = record.summaries[String(request.number)]
        return Button { picked = request.number } label: {
            HStack(spacing: 9) {
                SenderMark(login: request.login, size: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: summary?.headline ?? request.title)
                        .font(.system(size: 13, weight: record.isNew(request) ? .semibold : .regular)).foregroundStyle(Paper.ink).lineLimit(1)
                    Text(verbatim: [request.login, summary?.topic, Self.when(request.updated)].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 11)).foregroundStyle(Paper.muted).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(selected ? Paper.card : .clear, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? Paper.rule : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: What shows

    /// The open requests, newest first, in the topic chosen and matching the search (the line's words, the sender, the
    /// topic or the number).
    static func shown(_ record: SuggestedChanges.Record, topic: String?, search: String,
                      summaries: [String: SuggestionSummaries.Summary]) -> [SuggestedChanges.Request] {
        let words = search.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        return record.open.filter { request in
            guard record.ended[String(request.number)] == nil else { return false }
            let summary = summaries[String(request.number)]
            if let topic, (summary?.topic ?? SuggestionSummaries.other) != topic { return false }
            let text = ([request.title, request.login, "#\(request.number)", summary?.headline ?? "", summary?.topic ?? ""] + (summary?.points ?? []))
                .joined(separator: " ").lowercased()
            return words.allSatisfy(text.contains)
        }
        .sorted { ($0.updated ?? "") > ($1.updated ?? "") }
    }

    /// The topics with how many of these are under each, in the order Lamp first named them, "Other" last.
    static func topics(_ record: SuggestedChanges.Record, among requests: [SuggestedChanges.Request]) -> [(String, Int)] {
        let named = requests.map { record.summaries[String($0.number)]?.topic ?? SuggestionSummaries.other }
        let order = record.topics.filter { $0 != SuggestionSummaries.other } + [SuggestionSummaries.other]
        return order.compactMap { topic in
            let count = named.filter { $0 == topic }.count
            return count > 0 ? (topic, count) : nil
        }
    }

    static func when(_ updated: String?) -> String? {
        guard let updated, let date = ISO8601DateFormatter().date(from: updated) else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

/// One request, said in full: what it does, what its sender wrote, what Lamp knows for sure, and what can be done.
struct SuggestionDetail: View {
    @EnvironmentObject private var store: Store
    let project: LampProject
    let record: SuggestedChanges.Record
    let request: SuggestedChanges.Request
    let yours: Set<String>
    /// The next new one, offered once this one is in.
    let next: SuggestedChanges.Request?
    /// The gallery's: where it stands, and a try of it.
    var given: SuggestedChanges.Standing? = nil
    var givenTrial: SuggestionTrial.Running? = nil
    let pick: (Int) -> Void

    private var summary: SuggestionSummaries.Summary? { record.summaries[String(request.number)] }
    private var standing: SuggestedChanges.Standing {
        if let given { return given }
        return SuggestedChanges.standing(of: request.number, in: record, bringingIn: store.fetchingSuggestion[project.id] == request.number,
                                  holds: store.suggestionHolds[project.id]?[request.number] ?? (record.taken(request.number) != nil))
    }
    private var trial: SuggestionTrial.Running? {
        (givenTrial ?? store.trials[project.id]).flatMap { $0.number == request.number ? $0 : nil }
    }

    private var isIn: Bool {
        if case .broughtIn = standing, given != nil || record.taken(request.number)?.head == request.head { return true }
        return false
    }

    /// What it says scrolls; what can be done stays at the foot, always in view.
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if isIn { broughtIn } else { explained }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !isIn {
                Divider().overlay(Paper.rule)
                actions.padding(.horizontal, 24).padding(.vertical, 14)
            }
        }
    }

    private var title: String { summary?.headline ?? request.title }

    @ViewBuilder private var explained: some View {
        HStack(spacing: 12) {
            SenderMark(login: request.login, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: title).font(.system(size: 21, weight: .heavy)).tracking(-0.6).foregroundStyle(Paper.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: "From \(request.login)" + (SuggestionsPanel.when(request.updated).map { ", \($0)" } ?? ""))
                    .font(.system(size: 13)).foregroundStyle(Paper.muted)
                // The headline is Lamp's reading; what the sender called it stays in view, as theirs.
                if summary != nil {
                    Text(verbatim: "Their title: “\(request.title)”").font(.system(size: 12.5)).foregroundStyle(Paper.muted).lineLimit(2)
                }
                if let words = SuggestedChanges.words(standing) {
                    Text(words).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Paper.ink.opacity(0.75))
                }
            }
        }

        section(summary == nil ? "What's different" : "What's different, as Lamp reads it") {
            if let summary, !summary.points.isEmpty {
                ForEach(summary.points, id: \.self) { point("circle.fill", $0, small: true) }
                if summary.partial { note("Lamp read only part of this change.") }
            } else if summary != nil {
                note("Lamp couldn't say more than its title.")
            } else {
                // No account yet: the sender's own title stands, said to be theirs.
                Text(verbatim: "Titled by \(request.login): “\(request.title)”").font(.system(size: 14)).foregroundStyle(Paper.ink)
                note("Lamp explains changes in plain words once AI is set up.")
            }
        }

        if let words = request.note?.trimmed, !words.isEmpty {
            section("\(request.login)'s note") {
                Text(verbatim: "“\(words)”").font(.system(size: 13.5)).italic().foregroundStyle(Paper.ink)
                    .lineLimit(8).fixedSize(horizontal: false, vertical: true)
            }
        }

        if let facts = SuggestedChanges.facts(of: request, in: record, yours: yours) {
            section("Good to know") {
                ForEach(SuggestedChanges.sayings(facts), id: \.self) { point("info.circle", $0, tint: Paper.muted) }
            }
        }

    }

    private var actions: some View {
        VStack(alignment: .trailing, spacing: 8) {
            // A try of it, while it lasts, where its buttons are.
            if let trial { trying(trial) }
            HStack(spacing: 10) {
                Button("Show the Code") { store.viewSuggestion(project, number: request.number) }
                    .buttonStyle(.link).font(.system(size: 12.5)).foregroundStyle(Paper.muted)
                Spacer()
                if case .held = standing, SuggestedChanges.closingComment(record.taken(request.number), request: request, app: project.name) != nil {
                    Button("Close Request…") { store.closeSuggestion(project, number: request.number) }
                        .buttonStyle(PaperButtonStyle(.outline, height: 34))
                }
                if record.isHidden(request) {
                    Button("Put Back") { store.unhideSuggestion(project, number: request.number) }
                        .buttonStyle(PaperButtonStyle(.outline, height: 34))
                } else if case .open = standing {
                    Button("Not for Me") { store.hideSuggestion(project, number: request.number, head: request.head) }
                        .buttonStyle(PaperButtonStyle(.outline, height: 34))
                        .help("Set it aside here. Nothing is said to \(request.login).")
                    if SuggestionTrial.canTry(project), trial == nil {
                        Button("Try It First") { store.trySuggestion(project, number: request.number) }
                            .buttonStyle(PaperButtonStyle(.outline, height: 34))
                            .disabled(busy)
                            .help(SuggestionTrial.note)
                    }
                    Button("Bring Into My App") { store.bringInSuggestion(project, number: request.number) }
                        .buttonStyle(PaperButtonStyle(.ink, height: 34))
                        .disabled(busy)
                }
            }
            if case .open = standing, !record.isHidden(request), SuggestionTrial.canTry(project), trial == nil {
                HStack { Spacer(); note(SuggestionTrial.note) }
            }
        }
    }

    private var busy: Bool { store.busy.contains(project.id) || store.fetchingSuggestion[project.id] != nil }

    private func trying(_ trial: SuggestionTrial.Running) -> some View {
        HStack(spacing: 10) {
            switch trial.stage {
            case .preparing, .building:
                ProgressView().controlSize(.small)
                Text(trial.stage == .preparing ? "Making a copy to try…" : "Building the copy…").font(.system(size: 13))
            case .open:
                Image(systemName: "macwindow").foregroundStyle(Paper.ink)
                Text("Open in a window of its own. Quit it when you're done.").font(.system(size: 13))
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(message).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button({ if case .failed = trial.stage { return "OK" } else { return "Stop Trying" } }()) { store.endTrial(of: project) }
                .buttonStyle(PaperButtonStyle(.outline, height: 28))
        }
        .padding(12)
        .background(Paper.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Paper.rule))
    }

    @ViewBuilder private var broughtIn: some View {
        Image(systemName: "checkmark").font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
            .frame(width: 44, height: 44).background(Color(hex: 0x1F8A4A), in: Circle())
        Text(verbatim: "\(request.login)'s change is in \(project.name)").font(.system(size: 21, weight: .heavy)).tracking(-0.6).foregroundStyle(Paper.ink)
            .fixedSize(horizontal: false, vertical: true)
        Text(SuggestedChanges.words(standing) ?? "").font(.system(size: 14)).foregroundStyle(Paper.muted).fixedSize(horizontal: false, vertical: true)
        HStack(spacing: 10) {
            Button("Undo") { Task { await store.undo(project) } }
                .buttonStyle(PaperButtonStyle(.outline, height: 34))
                .disabled(store.busy.contains(project.id))
            Button("Open \(project.name)") { store.change(project, asking: "") }
                .buttonStyle(PaperButtonStyle(.ink, height: 34))
        }
        .padding(.top, 6)
        if let next {
            Divider().overlay(Paper.rule).padding(.vertical, 8)
            Button { pick(next.number) } label: {
                Text(verbatim: "Next: \(next.login)'s “\(record.summaries[String(next.number)]?.headline ?? next.title)”")
                    .font(.system(size: 13)).foregroundStyle(Paper.muted).underline(true, color: Paper.rule)
            }
            .buttonStyle(.plain)
        }
    }

    private func section(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.system(size: 11, weight: .bold)).tracking(1.2).foregroundStyle(Paper.label)
            VStack(alignment: .leading, spacing: 7) { content() }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Paper.card, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Paper.rule))
        }
    }

    private func point(_ symbol: String, _ text: String, tint: Color = Paper.ink, small: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol).font(.system(size: small ? 5 : 13)).foregroundStyle(tint).frame(width: 18)
            Text(verbatim: text).font(.system(size: 14)).foregroundStyle(Paper.ink).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.system(size: 12)).foregroundStyle(Paper.muted)
    }
}

/// A sender's round mark: their initial on a color of their own, the same everywhere.
struct SenderMark: View {
    let login: String
    var size: CGFloat = 32
    private static let palette: [UInt32] = [0x2F7D9A, 0xB0552E, 0x5B6C2E, 0x7A4BA8, 0x1F8A4A, 0xC0392B, 0x8E6B1F, 0x3E5BA9]
    var body: some View {
        let index = abs(login.unicodeScalars.reduce(0) { $0 &* 31 &+ Int($1.value) }) % Self.palette.count
        Circle().fill(Color(hex: Self.palette[index]))
            .frame(width: size, height: size)
            .overlay(Text(verbatim: String(login.prefix(1)).uppercased()).font(.system(size: size * 0.45, weight: .bold)).foregroundStyle(.white))
            .accessibilityHidden(true)
    }
}

/// The topics to pick from, wrapping onto as many rows as they need.
struct SuggestionChips: View {
    let items: [(String, Int)]
    let selected: String
    let pick: (String) -> Void
    var body: some View {
        ChipFlow(spacing: 6) {
            ForEach(items, id: \.0) { name, count in
                let on = name == selected
                Button { pick(name) } label: {
                    Text(verbatim: "\(name) \(count)")
                        .font(.system(size: 11.5, weight: on ? .semibold : .regular))
                        .foregroundStyle(on ? Paper.onInk : Paper.ink)
                        .padding(.horizontal, 9).frame(height: 24)
                        .background(on ? Paper.ink : Paper.card, in: Capsule())
                        .overlay(Capsule().strokeBorder(on ? .clear : Paper.rule))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

struct ChipFlow: Layout {
    var spacing: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 300
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += row + spacing; row = 0 }
            x += size.width + spacing
            row = max(row, size.height)
        }
        return CGSize(width: width, height: y + row)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += row + spacing; row = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            row = max(row, size.height)
        }
    }
}

extension Store {
    /// The wishes with changes sent to them that are still open, for the panel's menu and the desk's side.
    var wishesWithSuggestions: [LampProject] {
        _ = suggestionsRevision
        return wishes.filter { wish in
            guard !wish.isPart, let record = SuggestedChanges.record(for: wish) else { return false }
            return record.open.contains { !record.isHidden($0) }
        }
    }

    /// How many are new over every app, for the desk's side.
    var newSuggestionsInAll: Int { wishesWithSuggestions.reduce(0) { $0 + newSuggestions($1) } }

    /// Put Back, on one set aside.
    func unhideSuggestion(_ project: LampProject, number: Int) {
        SuggestedChanges.change(project) { $0.hidden[String(number)] = nil }
        suggestionsRevision += 1
    }
}

extension Gallery {
    /// The desk's panel of changes sent, in each state it's in, from made-up requests to a made-up app.
    static let suggestionEntries: [Entry] = [
        panel("Many changes, explained"),
        panel("One without an explanation yet", picked: 9),
        panel("Set aside", picked: 18),
        panel("Trying it", trial: .building),
        panel("Trying it, open", trial: .open),
        panel("Trying it, stopped", trial: .failed("It changes some of the same lines you did. Bring it in instead, and Lamp fits the two together.")),
        panel("Brought in", picked: 1, standing: .broughtIn(leftOut: [])),
        panel("Released, still open on GitHub", picked: 2, standing: .held(tag: "v4")),
        panel("Nothing sent yet", empty: true),
    ]

    private static let littleHouse = LampProject(id: "gallery-little-house", name: "The Little House", exe: "LittleHouse",
                                                 dir: URL(fileURLWithPath: "/nonexistent"))

    private static func panel(_ name: String, picked: Int? = nil, standing: SuggestedChanges.Standing? = nil,
                              trial: SuggestionTrial.Running.Stage? = nil, empty: Bool = false) -> Entry {
        Entry(group: "Sent to you", name: name) {
            var preview = SuggestionsPanel.Preview(project: littleHouse, record: empty ? SuggestedChanges.Record(repo: "someone/little-house") : sentRecord,
                                                   yours: ["Sources/Fire.swift"], picked: picked)
            if let standing, let picked { preview.standing[picked] = standing }
            if let trial {
                let running = SuggestionTrial.Running(wish: littleHouse.id, number: 1, generation: "gallery", folder: URL(fileURLWithPath: "/nonexistent"),
                                                      manifest: SuggestionTrial.Manifest(wish: littleHouse.id, number: 1, bundleID: "", dataID: ""))
                running.stage = trial
                preview.trial = running
            }
            return AnyView(SuggestionsPanel(wish: littleHouse.id, back: {}, preview: preview)
                .frame(width: 940, height: 600)
                .background(Paper.page))
        }
    }

    /// A public app's changes: many people, some of them about the same thing.
    private static let sentRecord: SuggestedChanges.Record = {
        let sent: [(String, String, String, [String], String?)] = [
            ("sam", "A brighter, louder fire", "The fire", ["The fire burns brighter and flickers more.", "A new Crackle slider in the mixer, for the sound of the logs."], "Made the fire cozier for winter. Hope you like it!"),
            ("priya", "Rain you can turn off", "Sounds", ["A switch in the mixer turns the rain off."], nil),
            ("diego", "A cat asleep by the fire", "The fire", ["A sleeping cat curls up on the rug by the fire."], "My kids asked for a cat."),
            ("mei", "Snow instead of rain in December", "The window", ["In December the window shows snow falling."], nil),
            ("jonas", "Bigger buttons for small screens", "Buttons and layout", ["Buttons grow on a small window."], nil),
            ("aisha", "A softer clock tick", "Sounds", ["The clock ticks more quietly."], nil),
            ("tom", "Blue flames", "The fire", ["The flames can be blue."], nil),
            ("lena", "A bookshelf you can browse", "Other", ["A shelf of books by the wall opens to a list of titles."], nil),
            ("kofi", "Thunder now and then", "Sounds", [], nil),
            ("rae", "Spanish words on every button", "Buttons and layout", ["Every button can read in Spanish."], nil),
            ("ben", "A moon over the lake", "The window", ["A moon rises over the lake at night."], nil),
            ("yuki", "Fire that dies down at night", "The fire", ["Late at night the fire burns low."], nil),
            ("omar", "A sleep timer that fades out", "Sounds", ["The sounds fade out after a time you choose."], nil),
            ("ines", "Fewer logs on the fire", "The fire", ["The fire has fewer logs."], nil),
            ("pat", "A darker room", "Colors", ["The room is darker."], nil),
            ("zoe", "Warmer lamp light", "Colors", ["The lamp glows a warmer orange."], nil),
            ("max", "A rug that changes color", "Colors", ["Clicking the rug changes its color."], nil),
            ("ana", "Crickets in summer", "Sounds", ["Crickets chirp on summer nights."], nil),
        ]
        var record = SuggestedChanges.Record(repo: "someone/little-house")
        record.topics = ["The fire", "Sounds", "The window", "Buttons and layout", "Colors"]
        let now = Date()
        for (index, change) in sent.enumerated() {
            let number = index + 1
            let head = String(repeating: String(number % 10), count: 40)
            let updated = ISO8601DateFormatter().string(from: now.addingTimeInterval(-Double(index) * 4 * 3600 - 2 * 3600))
            record.open.append(SuggestedChanges.Request(number: number, login: change.0, title: "Little House: changes from a remix", head: head,
                                                        url: "https://github.com", note: change.4, updated: updated))
            // One still to be explained, which shows its sender's own title.
            if number != 9 {
                record.summaries[String(number)] = SuggestionSummaries.Summary(made: "", headline: change.1, points: change.3, topic: change.2, partial: false)
            }
            let fire = change.2 == "The fire"
            record.files[String(number)] = SuggestedChanges.FileList(head: head, files: [
                SuggestedChanges.ChangedFile(path: fire ? "Sources/Fire.swift" : "Sources/Room\(number).swift", status: "modified"),
            ])
            if number > 12 { record.seen[String(number)] = head }
        }
        // Not for Me, on the last one.
        record.hidden["18"] = record.open[17].head
        return record
    }()
}
