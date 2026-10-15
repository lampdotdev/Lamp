import SwiftUI

/// The agent's cards as the person sees them (`Talk`): questions to click through in the chat, and what a
/// request made. Built like the setup card, so the chat reads as one thing.

/// Where a person is in a set of questions, and how an answer moves them on.
struct AskProgress: Equatable {
    var step = 0
    var answers: [Int: String] = [:]
    /// What's typed for each question instead of picking one of its answers. Each question keeps its own, so
    /// going Back doesn't show what was typed for the next one.
    var own: [Int: String] = [:]

    /// Takes what's typed as a question's answer; emptied, the question is unanswered again.
    mutating func type(_ text: String, for question: Int) {
        own[question] = text
        answers[question] = text.trimmed.nilIfEmpty
    }

    /// Takes a chip as a question's answer, in place of anything typed for it.
    mutating func choose(_ answer: String, for question: Int) {
        own[question] = nil
        answers[question] = answer
    }

    /// Takes an answer for the question showing. True when that was the last one.
    mutating func take(_ answer: String, of count: Int) -> Bool {
        // A picked answer replaces what was typed for the question; a typed one stays, to read on Back.
        if own[step]?.trimmed != answer { own[step] = nil }
        answers[step] = answer
        guard step < count - 1 else { return true }
        step += 1
        return false
    }

    /// Every question's answer, with the ones left out given to Lamp.
    func all(_ count: Int) -> [String] { (0..<count).map { answers[$0] ?? Talk.youDecide } }
}

/// How far each open card has been answered, by its line. Kept apart from the card's view because the same
/// card is drawn in Lamp's window and in the wand's panel beside the app (`MagicPanel`): an answer begun in one
/// is carried on in the other, not started over.
@MainActor
final class AskProgresses: ObservableObject {
    static let shared = AskProgresses()
    @Published private var progress: [UUID: AskProgress] = [:]

    func binding(for line: UUID) -> Binding<AskProgress> {
        Binding(get: { self.progress[line] ?? AskProgress() }, set: { self.progress[line] = $0 })
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
    private var progress: Binding<AskProgress> { progresses.binding(for: line.id) }

    var body: some View {
        if let ask = line.ask, let project = store.projects.first(where: { $0.dir == dir }) {
            if !isOpen {
                Answered(ask: ask)
            } else {
                Group {
                    if ask.layout == .together && ask.questions.count > 1 {
                        together(ask, project)
                    } else {
                        AskSteps(ask: ask, progress: progress) { answers in withAnimation(.snappy(duration: 0.3)) { store.answer(line, with: answers, in: project) } }
                    }
                }
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
                .frame(maxWidth: 620, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Every question at once, each answered by a chip.
    private func together(_ ask: Talk.Ask, _ project: LampProject) -> some View {
        let progress = progress
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(ask.questions.enumerated()), id: \.offset) { index, question in
                if index > 0 { Divider() }
                VStack(alignment: .leading, spacing: 8) {
                    Text(question.question).font(.headline)
                    ChipRow(options: question.options, chosen: progress.wrappedValue.answers[index],
                            own: Binding(get: { progress.wrappedValue.own[index] ?? "" }, set: { progress.wrappedValue.type($0, for: index) })) {
                        progress.wrappedValue.choose($0, for: index)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
            }
            Divider()
            HStack {
                if progress.wrappedValue.answers.isEmpty {
                    Button(Talk.youDecide) { withAnimation(.snappy(duration: 0.3)) { store.answer(line, with: progress.wrappedValue.all(ask.questions.count), in: project) } }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Send") { withAnimation(.snappy(duration: 0.3)) { store.answer(line, with: progress.wrappedValue.all(ask.questions.count), in: project) } }
                    .buttonStyle(.borderedProminent)
                    .disabled(progress.wrappedValue.answers.isEmpty)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
    }
}

/// A card that's no longer waiting, folded where it was to a line like the ones for what Lamp did: each
/// question with the answer clicked for it, or, when the person typed their own answer instead, what was asked (their
/// message under it is the answer). Only the card that waits is drawn as a card.
private struct Answered: View {
    let ask: Talk.Ask

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let folded = ask.folded {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "checkmark.circle").foregroundStyle(.secondary).frame(width: 16)
                    Text(folded).fixedSize(horizontal: false, vertical: true)
                }
            } else {
                ForEach(Array(ask.questions.enumerated()), id: \.offset) { _, question in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "questionmark.circle").frame(width: 16)
                        Text(question.question).fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// One question at a time: its answers as tiles, a field for something else, and a way back.
///
/// The card is laid out for all its questions at once and shows one: its height is the tallest question's,
/// and the field and the links under the tiles never move. A card that changed size from one question to the
/// next would slide what's about to be clicked out from under the pointer. So that this never shows as a
/// card with room to spare, the questions are kept the same height: a question's answers are one row however
/// many there are, and each question's tiles fill whatever another's wording needed (`Tallest`, `TileRows`).
struct AskSteps: View {
    let ask: Talk.Ask
    @Binding var progress: AskProgress
    let send: ([String]) -> Void
    /// Off for a moment after the question changes, so the second click of a double-click doesn't answer
    /// the next question with whatever tile arrived under the pointer.
    @State private var armed = true

    private var count: Int { ask.questions.count }
    private var step: Int { min(progress.step, count - 1) }
    private var typed: String { (progress.own[step] ?? "").trimmed }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if count > 1 {
                Text("Question \(step + 1) of \(count)").font(.subheadline).foregroundStyle(.secondary)
            }
            Tallest {
                ForEach(Array(ask.questions.enumerated()), id: \.offset) { index, question in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(question.question)
                            .font(.title3.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        let widest = OptionTile.widestWord(in: question.options)
                        TileRows(least: widest + OptionTile.padding * 2) {
                            ForEach(Array(question.options.enumerated()), id: \.offset) { _, option in
                                OptionTile(option: option, widest: widest, chosen: progress.answers[index] == option.title) {
                                    pick(option.title)
                                }
                            }
                        }
                    }
                    // Only the current one is there to see, click or read aloud.
                    .opacity(index == step ? 1 : 0)
                    .allowsHitTesting(index == step)
                    .accessibilityHidden(index != step)
                }
            }
            .allowsHitTesting(armed)
            TextField("Something else…", text: Binding(get: { progress.own[step] ?? "" }, set: { progress.own[step] = $0 }))
                .textFieldStyle(.plain)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
                .onSubmit { if !typed.isEmpty { pick(typed) } }
            HStack(spacing: 16) {
                Group {
                    Button(Talk.youDecide) { pick(Talk.youDecide) }
                    if step > 0 {
                        Button("Back") { progress.step -= 1 }
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                Spacer()
                // What's typed is sent from here as well as with Return. Its place is kept while there's
                // nothing typed, so the card is the same height before and after the first letter.
                Button(step < count - 1 ? "Next" : "Send") { pick(typed) }
                    .buttonStyle(.borderedProminent)
                    .opacity(typed.isEmpty ? 0 : 1)
                    .allowsHitTesting(!typed.isEmpty)
                    .accessibilityHidden(typed.isEmpty)
            }
            .allowsHitTesting(armed)
        }
        .padding(16)
        .task(id: step) {
            guard step > 0 || !armed else { return }
            armed = false
            try? await Task.sleep(for: .seconds(0.4))
            armed = true
        }
    }

    private func pick(_ answer: String) {
        if progress.take(answer, of: count) { send(progress.all(count)) }
    }
}

/// Every question of a card in the same place, each given the room the tallest one needs.
private struct Tallest: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil)) }
        return CGSize(width: proposal.width ?? sizes.map(\.width).max() ?? 0, height: sizes.map(\.height).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews { subview.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size)) }
    }
}

/// A question's answers as tiles of one size, filling the height they are given. One row: two rows for four
/// answers made that question a row taller than the others on its card, which showed as a gap under theirs.
/// Fewer to a row only where a row would leave each too narrow to read: four go two by two, and any number
/// goes one under another when even that would break a word (in the wand's narrow panel).
private struct TileRows: Layout {
    /// The narrowest a tile can be without breaking a word of its answer.
    let least: CGFloat
    static let spacing: CGFloat = 10
    /// Narrower than this, four tiles in a row look cramped even when their words fit.
    static let narrowest: CGFloat = 120

    static func columns(for count: Int, width: CGFloat, least: CGFloat) -> Int {
        func tile(_ columns: Int) -> CGFloat { (width - spacing * CGFloat(columns - 1)) / CGFloat(columns) }
        let count = max(count, 1)
        let tries = count == 4 ? [4, 2] : [count]
        return tries.first { tile($0) >= max(least, $0 == 4 ? narrowest : 0) } ?? 1
    }

    private func grid(_ subviews: Subviews, width: CGFloat) -> (columns: Int, rows: Int, tile: CGSize) {
        let columns = Self.columns(for: subviews.count, width: width, least: least)
        let tileWidth = max(0, (width - Self.spacing * CGFloat(columns - 1)) / CGFloat(columns))
        let height = subviews.map { $0.sizeThatFits(ProposedViewSize(width: tileWidth, height: nil)).height }.max() ?? 0
        return (columns, (subviews.count + columns - 1) / columns, CGSize(width: tileWidth, height: height))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 600
        let grid = grid(subviews, width: width)
        let natural = grid.tile.height * CGFloat(grid.rows) + Self.spacing * CGFloat(grid.rows - 1)
        return CGSize(width: width, height: max(natural, proposal.height ?? 0))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let grid = grid(subviews, width: bounds.width)
        let height = max(grid.tile.height, (bounds.height - Self.spacing * CGFloat(grid.rows - 1)) / CGFloat(grid.rows))
        for (index, subview) in subviews.enumerated() {
            let column = CGFloat(index % grid.columns), row = CGFloat(index / grid.columns)
            subview.place(at: CGPoint(x: bounds.minX + column * (grid.tile.width + Self.spacing),
                                      y: bounds.minY + row * (height + Self.spacing)),
                          proposal: ProposedViewSize(width: grid.tile.width, height: height))
        }
    }
}

/// An answer to click: its symbol, its name and a few words.
private struct OptionTile: View {
    let option: Talk.Option
    /// The longest word of any answer to its question, so every tile of a question is laid out the same way.
    let widest: CGFloat
    let chosen: Bool
    let action: () -> Void
    static let padding: CGFloat = 11

    /// The widest single word in these answers, as the tiles set them. A tile narrower than that would break it
    /// in the middle ("Scre / ensh / ots").
    static func widestWord(in options: [Talk.Option]) -> CGFloat {
        let title = NSFont.systemFont(ofSize: NSFont.preferredFont(forTextStyle: .body).pointSize, weight: .semibold)
        let detail = NSFont.preferredFont(forTextStyle: .callout)
        func widest(_ text: String?, _ font: NSFont) -> CGFloat {
            (text ?? "").split(whereSeparator: \.isWhitespace)
                .map { ceil(NSAttributedString(string: String($0), attributes: [.font: font]).size().width) }.max() ?? 0
        }
        return options.map { max(widest($0.title, title), widest($0.detail, detail)) }.max().map { $0 + 2 } ?? 0
    }

    var body: some View {
        Button(action: action) {
            TileFace(widest: widest) {
                if let symbol = option.symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 34, height: 34)
                        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(option.title).fontWeight(.semibold)
                    if let detail = option.detail {
                        Text(detail).font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .multilineTextAlignment(.leading)
            }
            .padding(Self.padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(chosen ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary), lineWidth: chosen ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.title)
    }
}

/// A tile's symbol and words: the symbol beside them while the longest word still fits there, else above them.
private struct TileFace: Layout {
    let widest: CGFloat
    static let spacing: CGFloat = 10

    private func beside(_ subviews: Subviews, width: CGFloat?) -> Bool {
        guard subviews.count == 2 else { return false }
        guard let width else { return true }
        return width - subviews[0].sizeThatFits(.unspecified).width - Self.spacing >= widest
    }

    private func words(_ subviews: Subviews, width: CGFloat?, beside: Bool) -> CGSize {
        let symbol = subviews.count == 2 ? subviews[0].sizeThatFits(.unspecified).width + Self.spacing : 0
        return subviews[subviews.count - 1].sizeThatFits(ProposedViewSize(width: width.map { beside ? $0 - symbol : $0 }, height: nil))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let beside = beside(subviews, width: proposal.width)
        let words = words(subviews, width: proposal.width, beside: beside)
        guard subviews.count == 2 else { return CGSize(width: proposal.width ?? words.width, height: words.height) }
        let symbol = subviews[0].sizeThatFits(.unspecified)
        return beside
            ? CGSize(width: proposal.width ?? symbol.width + Self.spacing + words.width, height: max(symbol.height, words.height))
            : CGSize(width: proposal.width ?? max(symbol.width, words.width), height: symbol.height + 8 + words.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let beside = beside(subviews, width: bounds.width)
        let words = words(subviews, width: bounds.width, beside: beside)
        let text = subviews[subviews.count - 1]
        guard subviews.count == 2 else {
            return text.place(at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(words))
        }
        let symbol = subviews[0].sizeThatFits(.unspecified)
        if beside {
            subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading, proposal: .unspecified)
            text.place(at: CGPoint(x: bounds.minX + symbol.width + Self.spacing, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(words))
        } else {
            let top = bounds.midY - (symbol.height + 8 + words.height) / 2
            subviews[0].place(at: CGPoint(x: bounds.minX, y: top), proposal: .unspecified)
            text.place(at: CGPoint(x: bounds.minX, y: top + symbol.height + 8), proposal: ProposedViewSize(words))
        }
    }
}

/// A question's answers as chips on one line, or stacked when the card is too narrow for them.
struct ChipRow: View {
    let options: [Talk.Option]
    let chosen: String?
    /// The person's own answer, typed beside the chips. Nil where there is nothing to type: a choice
    /// between the two ways something was built.
    var own: Binding<String>? = nil
    let pick: (String) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { chips; field }
            VStack(alignment: .leading, spacing: 6) { chips; field }
        }
    }

    @ViewBuilder
    private var field: some View {
        if let own {
            let typed = !own.wrappedValue.trimmed.isEmpty
            TextField("Something else…", text: own)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12).padding(.vertical, 6)
                // As wide as the row has left, and asking for the same whatever is typed: a field that
                // asked for the width of its words would push the chips onto lines of their own mid-answer.
                .frame(minWidth: 140, idealWidth: 140, maxWidth: .infinity)
                .background(Color(nsColor: .textBackgroundColor), in: Capsule())
                .overlay(Capsule().strokeBorder(typed ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary), lineWidth: typed ? 2 : 1))
        }
    }

    private var chips: some View {
        ForEach(Array(options.enumerated()), id: \.offset) { _, option in
            let on = chosen == option.title
            Button { pick(option.title) } label: {
                HStack(spacing: 6) {
                    if let symbol = option.symbol {
                        Image(systemName: symbol).foregroundStyle(on ? Color.white : Color.accentColor)
                    }
                    Text(option.title).lineLimit(1)
                }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .foregroundStyle(on ? Color.white : Color.primary)
                    .background(on ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color(nsColor: .textBackgroundColor)), in: Capsule())
                    .overlay(Capsule().strokeBorder(.quaternary))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(on ? .isSelected : [])
        }
    }
}

/// What a request made: its picture and one sentence, a new app's as much as a change's. Rows under the picture
/// read as captions of it, and a new app's guesses and idea there made a form to go through when it's the app
/// the person wants to try. What the agent didn't try is a row to try it, there while it would still do what it
/// says, until the person asks for something else.
struct ResultCard: View {
    let line: LogLine
    let dir: URL
    let isCurrent: Bool
    @ObservedObject private var store = Store.shared

    var body: some View {
        if let result = line.result, let project = store.projects.first(where: { $0.dir == dir }) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 14) {
                    if let version = result.version,
                       let picture = NSImage(contentsOf: Versions.pictureURL(in: project, for: version)) {
                        Image(nsImage: picture)
                            .resizable().scaledToFit()
                            .frame(maxWidth: 150, maxHeight: 100)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(.quaternary))
                            .accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(result.summary).font(.headline).fixedSize(horizontal: false, vertical: true)
                        // A card saved while it had rows of what's new: where to find each, as part of its
                        // sentence rather than rows under the picture.
                        ForEach(Array((result.news ?? []).enumerated()), id: \.offset) { _, news in
                            Text("\(news.what): \(news.place)").font(.callout).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
                // A card saved while guesses were buttons keeps the one the person turned, as what they chose:
                // the chat doesn't show the message that click sent (`Talk.shows`).
                ForEach(Array(result.guesses.enumerated()), id: \.offset) { index, guess in
                    if result.switched?.contains(index) == true {
                        Divider()
                        Label {
                            Text(guess.instead).fontWeight(.medium)
                        } icon: {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if isCurrent, let untried = result.untried {
                    row(untried, detail: "Lamp hasn't tested this yet.", button: "Have Lamp Test It") {
                        store.send(Talk.tryRequest(untried), to: project)
                    }
                }
            }
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func row(_ title: String, detail: String?, button: String? = nil, action: @escaping () -> Void = {}) -> some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).fixedSize(horizontal: false, vertical: true)
                    if let detail {
                        Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                if let button { Button(button, action: action) }
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
        }
    }
}
