import SwiftUI
import AppKit

/// The agent's cards as the person sees them (`Talk`): questions to click through in the chat, and what a
/// request made. Built like the setup card, so the chat reads as one thing.

/// Where a person is in a set of questions, and how an answer moves them on.
public struct AskProgress: Equatable, Codable {
    public init() {}

    public var step = 0
    public var answers: [Int: String] = [:]
    /// What's typed for each question instead of picking one of its answers. Each question keeps its own, so
    /// going Back doesn't show what was typed for the next one.
    public var own: [Int: String] = [:]

    /// Takes what's typed as a question's answer; emptied, the question is unanswered again.
    public mutating func type(_ text: String, for question: Int) {
        own[question] = text
        answers[question] = text.trimmed.nilIfEmpty
    }

    /// Takes a chip as a question's answer, in place of anything typed for it.
    public mutating func choose(_ answer: String, for question: Int) {
        own[question] = nil
        answers[question] = answer
    }

    /// Takes an answer for the question showing. True when that was the last one.
    public mutating func take(_ answer: String, of count: Int) -> Bool {
        // A picked answer replaces what was typed for the question; a typed one stays, to read on Back.
        if own[step]?.trimmed != answer { own[step] = nil }
        answers[step] = answer
        guard step < count - 1 else { return true }
        step += 1
        return false
    }

    /// Every question's answer, with the ones left out given to Lamp.
    public func all(_ count: Int) -> [String] { (0..<count).map { answers[$0] ?? TalkCard.youDecide } }
}

/// The card itself, drawn from plain values: by Lamp's window, its gallery, and the chat inside each app's window.
public struct AskCardView: View {
    let ask: TalkCard.Ask
    let isOpen: Bool
    @Binding var progress: AskProgress
    let send: ([String]) -> Void
    let waiting: AskWaiting?

    public init(ask: TalkCard.Ask, isOpen: Bool, progress: Binding<AskProgress>, waiting: AskWaiting? = nil,
                send: @escaping ([String]) -> Void) {
        self.ask = ask
        self.isOpen = isOpen
        _progress = progress
        self.waiting = waiting
        self.send = send
    }

    public var body: some View {
        if !isOpen {
            Answered(ask: ask, waiting: waiting)
        } else {
            Group {
                if ask.layout == .together && ask.questions.count > 1 {
                    together
                } else {
                    AskSteps(ask: ask, progress: $progress, send: send)
                }
            }
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Every question at once, each answered by a chip.
    private var together: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(ask.questions.enumerated()), id: \.offset) { index, question in
                if index > 0 { Divider() }
                VStack(alignment: .leading, spacing: 8) {
                    Text(question.question).font(.headline)
                    ChipRow(options: question.options, chosen: progress.answers[index],
                            own: Binding(get: { progress.own[index] ?? "" }, set: { progress.type($0, for: index) })) {
                        progress.choose($0, for: index)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
            }
            Divider()
            HStack {
                if progress.answers.isEmpty {
                    Button(TalkCard.youDecide) { send(progress.all(ask.questions.count)) }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Send") { send(progress.all(ask.questions.count)) }
                    .buttonStyle(.borderedProminent)
                    .cardButtons()
                    .disabled(progress.answers.isEmpty)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
    }
}

/// Answers clicked on a card that wait in line behind the agent's turn. The folded card is all the chat shows of
/// them, from the click on: drawn as a waiting message too, they'd be there only until they're sent, when the chat
/// leaves them out because the card shows them. So taking them back is offered on the card.
public struct AskWaiting {
    let forSetup: Bool
    let takeBack: () -> Void

    public init(forSetup: Bool, takeBack: @escaping () -> Void) {
        self.forSetup = forSetup
        self.takeBack = takeBack
    }
}

/// A card that's no longer waiting, folded where it was to a line like the ones for what Lamp did: each
/// question with the answer clicked for it, or, when the person typed their own answer instead, what was asked (their
/// message under it is the answer). Only the card that waits is drawn as a card.
private struct Answered: View {
    let ask: TalkCard.Ask
    let waiting: AskWaiting?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let folded = ask.folded {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "checkmark.circle").frame(width: 16)
                    Text(folded).fixedSize(horizontal: false, vertical: true)
                    if let waiting {
                        Button(action: waiting.takeBack) { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                            .buttonStyle(.plain)
                            .help("Take back and answer again")
                            .accessibilityLabel("Take back and answer again")
                    }
                }
                if waiting?.forSetup == true {
                    Label(ChatLook.waitingForSetup, systemImage: "clock")
                        .font(.caption).foregroundStyle(.secondary).padding(.leading, 22)
                }
            } else {
                ForEach(Array(ask.questions.enumerated()), id: \.offset) { _, question in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "questionmark.circle").frame(width: 16)
                        Text(question.question).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        // Set in, sized and coloured as the turn's steps are, since it now reads as one.
        .font(ChatLook.stepFont)
        .foregroundStyle(.secondary)
        .padding(.leading, ChatLook.stepIndent)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// One question at a time: its answers as tiles, a field for something else, and a way back.
///
/// The card is laid out for all its questions at once and shows one: its height is the tallest question's,
/// and the field and the links under the tiles never move. A card that changed size from one question to the
/// next would slide what's about to be clicked out from under the pointer. So that this never shows as a
/// card with room to spare, a question's tiles grow toward the height another's needed (`Tallest`, `TileRows`).
struct AskSteps: View {
    let ask: TalkCard.Ask
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
                        VStack(alignment: .leading, spacing: 4) {
                            Text(question.question)
                                .font(.title3.weight(.semibold))
                                .fixedSize(horizontal: false, vertical: true)
                            if let detail = question.detail {
                                Text(detail)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        let tiles = Self.tiles(for: question)
                        TileRows(least: OptionTile.widestLine(in: tiles)) {
                            ForEach(Array(tiles.enumerated()), id: \.offset) { _, option in
                                OptionTile(option: option, chosen: progress.answers[index] == option.title) {
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
            // What's typed is sent from beside the field as well as with Return. The button takes room from the
            // field only once there's something to send: a row kept for it under the field left the card a gap
            // the height of a button.
            HStack(spacing: 8) {
                TextField("Something else…", text: Binding(get: { progress.own[step] ?? "" }, set: { progress.own[step] = $0 }))
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
                    .onSubmit { if !typed.isEmpty { pick(typed) } }
                if !typed.isEmpty {
                    Button(step < count - 1 ? "Next" : "Send") { pick(typed) }
                        .buttonStyle(.borderedProminent)
                        .cardButtons()
                }
            }
            .allowsHitTesting(armed)
            // The links under it, where any question of the card has one. Back keeps its place on the first
            // question, so the card is the same height on each.
            if count > 1 || ask.questions.contains(where: { !TalkCard.decidesAsTile($0) }) {
                HStack(spacing: 16) {
                    if !TalkCard.decidesAsTile(ask.questions[step]) {
                        Button(TalkCard.youDecide) { pick(TalkCard.youDecide) }
                    }
                    if count > 1 {
                        Button("Back") { progress.step -= 1 }
                            .opacity(step > 0 ? 1 : 0)
                            .allowsHitTesting(step > 0)
                            .accessibilityHidden(step == 0)
                    }
                    Spacer()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .allowsHitTesting(armed)
            }
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

    /// A question's answers, and "Decide for me" as one more where it fits as a tile (`TalkCard.decidesAsTile`).
    static func tiles(for question: TalkCard.Question) -> [TalkCard.Option] {
        guard TalkCard.decidesAsTile(question) else { return question.options }
        return question.options + [TalkCard.Option(title: TalkCard.youDecide, symbol: "wand.and.sparkles")]
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

/// A question's answers as tiles of one size: in one row where the card is wide and every answer fits on one line in
/// it, else one under another, as they always are in the wand's panel. A row fills the height it is given, so its
/// question is as tall as the others on its card; one under another, each grows only a little toward it, since
/// tall tiles in a column read as padding, and what's left stays under them.
private struct TileRows: Layout {
    /// The narrowest a tile in a row can be with its answer on one line.
    let least: CGFloat
    static let spacing: CGFloat = 8
    /// Narrower than this, a card stacks its answers however short they are: tiles side by side in the wand's
    /// panel were too cramped to read at a glance.
    static let stackBelow: CGFloat = 440
    /// Narrower than this, tiles in a row look cramped even when their words fit.
    static let narrowest: CGFloat = 120
    /// How much taller than it needs a tile one under another may grow.
    static let growth: CGFloat = 10

    static func inRow(_ count: Int, width: CGFloat, least: CGFloat) -> Bool {
        guard width >= stackBelow, count > 1 else { return false }
        let tile = (width - spacing * CGFloat(count - 1)) / CGFloat(count)
        return tile >= max(least, narrowest)
    }

    private func grid(_ subviews: Subviews, width: CGFloat) -> (row: Bool, tile: CGSize, heights: [CGFloat]) {
        let row = Self.inRow(subviews.count, width: width, least: least)
        let tileWidth = row ? max(0, (width - Self.spacing * CGFloat(subviews.count - 1)) / CGFloat(subviews.count)) : width
        let heights = subviews.map { $0.sizeThatFits(ProposedViewSize(width: tileWidth, height: nil)).height }
        return (row, CGSize(width: tileWidth, height: heights.max() ?? 0), heights)
    }

    private func natural(_ grid: (row: Bool, tile: CGSize, heights: [CGFloat])) -> CGFloat {
        grid.row ? grid.tile.height
            : grid.heights.reduce(0, +) + Self.spacing * CGFloat(max(grid.heights.count - 1, 0))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 600
        return CGSize(width: width, height: max(natural(grid(subviews, width: width)), proposal.height ?? 0))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let grid = grid(subviews, width: bounds.width)
        if grid.row {
            let height = max(grid.tile.height, bounds.height)
            for (index, subview) in subviews.enumerated() {
                subview.place(at: CGPoint(x: bounds.minX + CGFloat(index) * (grid.tile.width + Self.spacing), y: bounds.minY),
                              proposal: ProposedViewSize(width: grid.tile.width, height: height))
            }
            return
        }
        let spare = max(0, bounds.height - natural(grid))
        let extra = subviews.isEmpty ? 0 : min(Self.growth, spare / CGFloat(subviews.count))
        var y = bounds.minY
        for (index, subview) in subviews.enumerated() {
            let height = grid.heights[index] + extra
            subview.place(at: CGPoint(x: bounds.minX, y: y), proposal: ProposedViewSize(width: grid.tile.width, height: height))
            y += height + Self.spacing
        }
    }
}

/// An answer to click: its symbol and name on one line, and a few words under them when it has them. As small as
/// the chips of a card with every question on it, so a question's answers take little room in the wand's panel.
private struct OptionTile: View {
    let option: TalkCard.Option
    let chosen: Bool
    let action: () -> Void
    static let padding: CGFloat = 12
    static let symbolWidth: CGFloat = 18
    static let symbolSpacing: CGFloat = 8

    /// The widest of these answers on one line, as the tiles set them, padding included.
    static func widestLine(in options: [TalkCard.Option]) -> CGFloat {
        let title = NSFont.systemFont(ofSize: NSFont.preferredFont(forTextStyle: .body).pointSize, weight: .medium)
        return options.map { option in
            ceil(NSAttributedString(string: option.title, attributes: [.font: title]).size().width)
                + (option.symbol == nil ? 0 : symbolWidth + symbolSpacing)
        }.max().map { $0 + padding * 2 + 2 } ?? 0
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: Self.symbolSpacing) {
                if let symbol = option.symbol {
                    Image(systemName: symbol)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: Self.symbolWidth)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(option.title).fontWeight(.medium)
                    if let detail = option.detail {
                        Text(detail).font(.callout).foregroundStyle(.secondary)
                    }
                }
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Self.padding).padding(.vertical, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(chosen ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary), lineWidth: chosen ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.title)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}

/// A question's answers as chips on one line, or as tiles one under another where the card is narrow, as a card
/// with one question at a time has them (`TileRows`).
struct ChipRow: View {
    let options: [TalkCard.Option]
    let chosen: String?
    /// The person's own answer, typed beside the chips. Nil where there is nothing to type: a choice
    /// between the two ways something was built.
    var own: Binding<String>? = nil
    let pick: (String) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { chips; field(stacked: false) }
                .frame(minWidth: TileRows.stackBelow, alignment: .leading)
            VStack(alignment: .leading, spacing: TileRows.spacing) {
                ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                    OptionTile(option: option, chosen: chosen == option.title) { pick(option.title) }
                }
                field(stacked: true)
            }
        }
    }

    /// Shaped as the chips beside it are, or as the tiles above it.
    @ViewBuilder
    private func field(stacked: Bool) -> some View {
        if let own {
            let typed = !own.wrappedValue.trimmed.isEmpty
            // A capsule is a rounded rectangle rounded all the way.
            let shape = RoundedRectangle(cornerRadius: stacked ? 9 : 100, style: .continuous)
            TextField("Something else…", text: own)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12).padding(.vertical, stacked ? 8 : 6)
                // As wide as the row has left, and asking for the same whatever is typed: a field that
                // asked for the width of its words would push the chips onto lines of their own mid-answer.
                .frame(minWidth: 140, idealWidth: 140, maxWidth: .infinity)
                .background(Color(nsColor: .textBackgroundColor), in: shape)
                .overlay(shape.strokeBorder(typed ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary), lineWidth: typed ? 2 : 1))
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

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
