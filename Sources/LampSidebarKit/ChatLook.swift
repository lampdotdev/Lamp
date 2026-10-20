import SwiftUI
import AppKit

/// The chat's pieces as they look, shared by Lamp's window and the chat inside each app's window (the LampSidebar
/// extension), so the two are drawn by the same code and can't drift apart. Each takes plain values: what a line
/// says and how it stands, never Lamp's own state.
public enum ChatLook {
    /// A request's bubble, on the right, as Messages draws what you sent: white words on the accent colour.
    /// A request still waiting its turn is the same bubble, faded.
    public struct UserBubble: View {
        let text: String
        let waiting: Bool
        public init(_ text: String, waiting: Bool = false) {
            self.text = text
            self.waiting = waiting
        }

        public var body: some View {
            Text(text)
                .textSelection(.enabled)
                .lineSpacing(2)
                .foregroundStyle(.white)
                .tint(.white)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Bubble(.trailing).fill(Color.accentColor))
                .opacity(waiting ? 0.7 : 1)
                .padding(.trailing, ChatLook.tailRoom)
        }
    }

    /// What the agent says, as prose with its markdown (`ChatLook.pieces`).
    public struct AgentText: View {
        let text: String
        let keep: Bool
        /// `keep` is false while the message may still be growing, so each step isn't kept parsed.
        public init(_ text: String, keep: Bool = true) {
            self.text = text
            self.keep = keep
        }

        /// In a grey bubble on the left, as Messages draws the other person's. Answers run longer than a text
        /// message, so the bubble may take most of the width, leaving room on the right to tell it from a request.
        public var body: some View {
            content
                .lineSpacing(3)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Bubble(.leading).fill(ChatLook.agentBubble))
                .padding(.leading, ChatLook.tailRoom)
                .padding(.trailing, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
        }

        /// A reply is drawn as few texts as it can be. Each selectable text costs macOS far more to lay out than
        /// its words do, and every reply above is measured again with each word of one being written, so a reply
        /// cut into a text per line, cell and item made the whole chat slow while the agent wrote.
        @ViewBuilder private var content: some View {
            let pieces = ChatLook.pieces(text, keep: keep)
            if pieces.count == 1, case .text(let string) = pieces[0] {
                Text(string).textSelection(.enabled)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(pieces.indices, id: \.self) { PieceView(piece: pieces[$0]) }
                }
            }
        }
    }

    /// A reply as it's drawn: its prose, headings, lists and quotes run together as one styled text, and only what a
    /// text can't draw is a piece of its own.
    public enum Piece: Equatable {
        case text(AttributedString)
        case code(String)
        case rule
        case table(columns: [HorizontalAlignment], header: [AttributedString], rows: [[AttributedString]])
    }

    private struct PieceView: View {
        let piece: Piece

        var body: some View {
            switch piece {
            case .text(let string):
                Text(string).textSelection(.enabled)
            case .code(let code):
                Text(code)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
            case .rule:
                Divider()
            case .table(let columns, let header, let rows):
                // Top-aligned: lining cells up by their first baselines cost several times as much to lay out, and
                // a cell's first line sits level with its neighbours' either way. The cells can't be selected, for
                // the same cost: a selectable text in each would make a table the slowest thing in the chat.
                Grid(alignment: .topLeading, horizontalSpacing: 14, verticalSpacing: 4) {
                    GridRow {
                        ForEach(header.indices, id: \.self) { column in
                            Text(header[column]).fontWeight(.semibold).gridColumnAlignment(columns[column])
                        }
                    }
                    Divider().gridCellUnsizedAxes(.horizontal)
                    ForEach(rows.indices, id: \.self) { row in
                        GridRow { ForEach(rows[row].indices, id: \.self) { Text(rows[row][$0]) } }
                    }
                }
                .textSelection(.disabled)
            }
        }
    }

    /// Read once per message, like its prose.
    @MainActor private static var pieceCache: [String: [Piece]] = [:]

    /// The reply's pieces, read by Apple's markdown parser with its full syntax. A reply with nothing but prose (no
    /// line starts as a block could) skips it and is read as before, inline styles only, so its line breaks stay as
    /// the agent wrote them; in a reply with blocks a line break inside a paragraph is kept too.
    @MainActor public static func pieces(_ text: String, keep: Bool = true) -> [Piece] {
        if let cached = pieceCache[text] { return cached }
        if pieceCache.count > 2000 { pieceCache.removeAll() }
        var pieces = [Piece.text(prose(text, keep: keep))]
        if mayHaveBlocks(text),
           let parsed = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .full,
                                                                             failurePolicy: .returnPartiallyParsedIfPossible)),
           parsed.runs.contains(where: { $0.presentationIntent?.components.contains { $0.kind != .paragraph } == true }) {
            pieces = Self.pieces(of: parsed)
        }
        if keep { pieceCache[text] = pieces }
        return pieces
    }

    /// Whether a line starts the way a heading, list, quote, table, rule or fence does. Most replies are prose, and
    /// a quick look spares them the full parse.
    static func mayHaveBlocks(_ text: String) -> Bool {
        text.split(separator: "\n", omittingEmptySubsequences: true).contains { line in
            guard let first = line.first(where: { $0 != " " && $0 != "\t" }) else { return false }
            return "#|>-*+_`~=".contains(first) || first.isNumber
        }
    }

    /// Walks the parsed reply's runs block by block (a paragraph, heading, code block, rule or table cell, the
    /// innermost of each run's intents), joining what a text can draw and keeping the rest as pieces.
    private static func pieces(of parsed: AttributedString) -> [Piece] {
        var pieces: [Piece] = []
        var text = AttributedString()
        var lastBlock: [PresentationIntent.IntentType] = []
        var markedItems = Set<Int>()
        var table: (id: Int, columns: [HorizontalAlignment], cells: [Int: [Int: AttributedString]])?

        func endText() {
            if !text.characters.isEmpty { pieces.append(.text(text)) }
            text = AttributedString()
            lastBlock = []
        }
        func endTable() {
            guard let done = table else { return }
            table = nil
            let width = done.columns.count
            let row = { (index: Int) in (0..<width).map { done.cells[index]?[$0] ?? AttributedString() } }
            let rows = done.cells.keys.filter { $0 > 0 }.sorted().map(row)
            pieces.append(.table(columns: done.columns, header: row(0), rows: rows))
        }

        var index = parsed.startIndex
        while index < parsed.endIndex {
            let components = parsed.runs[index].presentationIntent?.components ?? []
            let leaf = components.first?.identity
            // The run of runs in the same block.
            var end = parsed.runs[index].range.upperBound
            while end < parsed.endIndex, parsed.runs[end].presentationIntent?.components.first?.identity == leaf {
                end = parsed.runs[end].range.upperBound
            }
            var content = AttributedString(parsed[index..<end])
            index = end

            if let tableIntent = components.first(where: { if case .table = $0.kind { true } else { false } }) {
                guard case .table(let columns) = tableIntent.kind else { continue }
                if table?.id != tableIntent.identity {
                    endText()
                    endTable()
                    table = (tableIntent.identity, columns.map { column in
                        switch column.alignment {
                        case .center: .center
                        case .right: .trailing
                        default: .leading
                        }
                    }, [:])
                }
                var row = 0, column = 0
                for component in components {
                    switch component.kind {
                    case .tableRow(let number): row = number
                    case .tableCell(let number): column = number
                    default: break
                    }
                }
                styleInline(&content)
                table?.cells[row, default: [:]][column] = content
                continue
            }
            endTable()

            switch components.first?.kind {
            case .codeBlock:
                endText()
                var code = String(content.characters)
                if code.hasSuffix("\n") { code.removeLast() }
                pieces.append(.code(code))
            case .thematicBreak:
                endText()
                pieces.append(.rule)
            default:
                styleInline(&content)
                if case .header = components.first?.kind { content.font = .headline }
                let lists = components.filter { if case .listItem = $0.kind { true } else { false } }
                if components.contains(where: { $0.kind == .blockQuote }) {
                    // A bar before each of the quote's lines, as a quote is drawn in mail.
                    content.foregroundColor = .secondary
                    var bar = AttributedString("▍ ")
                    bar.foregroundColor = Color.secondary.opacity(0.5)
                    var lines = content.characters.indices.filter { content.characters[$0] == "\n" }
                        .map { content.characters.index(after: $0) }
                    lines.insert(content.startIndex, at: 0)
                    for start in lines.reversed() { content.insert(bar, at: start) }
                }
                if let item = lists.first {
                    // An item's marker once, before its first paragraph; nested lists go in a step each.
                    let indent = String(repeating: "    ", count: lists.count - 1)
                    var marker = indent + "    "
                    if markedItems.insert(item.identity).inserted, case .listItem(let ordinal) = item.kind {
                        let ordered = components.drop { $0.identity != item.identity }.dropFirst().first?.kind == .orderedList
                        marker = indent + (ordered ? "\(ordinal)." : "•") + " "
                    }
                    content = AttributedString(marker) + content
                }
                if !text.characters.isEmpty {
                    // Items of one list follow on the next line; anything else is a paragraph apart.
                    let listsHere = Set(components.filter(isList).map(\.identity))
                    let sameList = lastBlock.contains { isList($0) && listsHere.contains($0.identity) }
                    text.append(AttributedString(sameList ? "\n" : "\n\n"))
                }
                text.append(content)
                lastBlock = components
            }
        }
        endTable()
        endText()
        return pieces
    }

    private static func isList(_ intent: PresentationIntent.IntentType) -> Bool {
        intent.kind == .unorderedList || intent.kind == .orderedList
    }

    /// The parser's soft line breaks back as the line breaks the agent typed, and code spans set off as in prose.
    private static func styleInline(_ string: inout AttributedString) {
        for run in string.runs.reversed() {
            guard let intent = run.inlinePresentationIntent else { continue }
            if intent.contains(.softBreak) { string.replaceSubrange(run.range, with: AttributedString("\n")) }
            else if intent.contains(.code) { string[run.range].backgroundColor = Color.primary.opacity(0.07) }
        }
    }

    /// The line above a fix Lamp started on its own after the app crashed: the request it sent isn't shown, so this
    /// says why the agent is at work with nobody having asked.
    public static let fixingCrash = "The app crashed, so Lamp is fixing it"

    /// One status line: a check, or a small spinner for a step still going.
    public struct StatusLine: View {
        let text: String
        let running: Bool
        public init(_ text: String, running: Bool) {
            self.text = text
            self.running = running
        }

        public var body: some View {
            HStack(spacing: 6) {
                Group {
                    if running { ProgressView().controlSize(.mini) } else { Image(systemName: "checkmark.circle") }
                }
                .frame(width: 16)
                Text(text)
            }
            .font(ChatLook.stepFont)
            .foregroundStyle(.secondary)
            .padding(.leading, ChatLook.stepIndent)
        }
    }

    /// What the agent said about how the work was going ("The layout's in. Now the timer."), once its turn is over
    /// and the line is among the turn's steps: grey like them. While the turn goes on it's a message like any other
    /// (`AgentText`).
    public struct ProgressLine: View {
        let text: String
        public init(_ text: String) { self.text = text }

        public var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: ChatLook.progressSymbol).frame(width: 16)
                Text(text).fixedSize(horizontal: false, vertical: true)
            }
            .font(ChatLook.stepFont)
            .foregroundStyle(.secondary)
            .padding(.leading, ChatLook.stepIndent)
            .padding(.trailing, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }

    /// The progress line's mark, which also tells the sidebar a status line is one (`SidebarLine.symbol`).
    public static let progressSymbol = "ellipsis.bubble"

    /// The agent's steps (what it ran, read, checked) are told in small grey words under its bubbles, as Messages
    /// says a message was delivered: there, but quieter than what's said.
    public static let stepFont = Font.subheadline
    /// Steps line up with the words in the agent's bubbles.
    public static let stepIndent: CGFloat = tailRoom + 4

    /// A finished turn's steps under one line, "Worked for 2 min 3 s", opened with a click to show each of them.
    /// The steps draw themselves, set in as the agent's steps are.
    public struct Worked<Steps: View>: View {
        let title: String
        let steps: Steps
        @State private var expanded = false

        public init(_ title: String, @ViewBuilder steps: () -> Steps) {
            self.title = title
            self.steps = steps()
        }

        public var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                Button {
                    withAnimation(.snappy(duration: 0.2)) { expanded.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Text(title)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointingHand()
                .font(ChatLook.stepFont)
                .foregroundStyle(.secondary)
                .padding(.leading, ChatLook.stepIndent)
                .help(expanded ? "Hide the steps" : "Show the steps")
                .accessibilityHint(expanded ? "Hides the steps" : "Shows the steps")
                if expanded {
                    VStack(alignment: .leading, spacing: 4) { steps }
                        .transition(.opacity)
                }
            }
        }
    }

    /// A command the agent ran ("Ran: git clone …"). The chat says that it happened, by what the agent said it was
    /// for when it said ("Reading how the shelf works"); the command itself is a click away, for anyone who wants
    /// to see it. Several the agent gave one name to are one row, their commands one under another.
    public struct RanCommand: View {
        let command: String
        let said: String?
        @State private var expanded = false
        public init(_ command: String, said: String? = nil) {
            self.command = command
            self.said = said
        }

        public var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                Button {
                    withAnimation(.snappy(duration: 0.2)) { expanded.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle").frame(width: 16)
                        Text(said ?? "Ran a command")
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointingHand()
                .help("Show the command")
                if expanded {
                    Text(command)
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                        .padding(.leading, 22)
                }
            }
            .font(ChatLook.stepFont)
            .foregroundStyle(.secondary)
            .padding(.leading, ChatLook.stepIndent)
        }
    }

    /// The command in a status line that says one was run.
    public static func ranCommand(in status: String) -> String? {
        status.hasPrefix("Ran: ") ? String(status.dropFirst(5)) : nil
    }

    /// A turn's progress: one line saying what the agent is doing and for how long, which changes in place as it
    /// moves from one thing to the next, and opens to show the steps so far. `since` is when the activity began,
    /// which a long think or build is counted from (the turn's start when it isn't known). When the turn ends this
    /// line's place is taken by its "Worked for…" (`Worked`), which opens to the same steps.
    public struct ActivityLine<Steps: View>: View {
        let activity: String
        let started: Date
        let since: Date
        let hasSteps: Bool
        let steps: Steps
        @State private var expanded = false
        @State private var dim = false

        public init(_ activity: String, started: Date, since: Date? = nil, hasSteps: Bool,
                    @ViewBuilder steps: () -> Steps) {
            self.activity = activity
            self.started = started
            self.since = since ?? started
            self.hasSteps = hasSteps
            self.steps = steps()
        }

        public var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                Button {
                    guard hasSteps else { return }
                    withAnimation(.snappy(duration: 0.2)) { expanded.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini).frame(width: 16)
                        // It breathes while the agent works, so the line reads as live rather than stuck.
                        ActivityText(activity, since: since)
                            .opacity(dim ? 0.5 : 1)
                            .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: dim)
                        Text("·")
                        Elapsed(from: started, to: nil)
                        if hasSteps {
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.tertiary)
                                .rotationEffect(.degrees(expanded ? 90 : 0))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointingHand()
                .font(ChatLook.stepFont)
                .foregroundStyle(.secondary)
                .padding(.leading, ChatLook.stepIndent)
                .help(hasSteps ? (expanded ? "Hide the steps" : "Show the steps") : "")
                .onAppear { dim = true }
                if expanded && hasSteps {
                    VStack(alignment: .leading, spacing: 4) { steps }
                        .transition(.opacity)
                }
            }
        }
    }

    /// The line that ends a turn ("Worked for 8s"), small and centred, the way Messages marks the time between
    /// messages.
    public struct SummaryLine: View {
        let text: String
        public init(_ text: String) { self.text = text }

        public var body: some View {
            Text(text)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
    }

    /// Something that went wrong, set off in orange.
    public struct ErrorNote<Extra: View>: View {
        let text: String
        let extra: Extra
        public init(_ text: String, @ViewBuilder extra: () -> Extra = { EmptyView() }) {
            self.text = text
            self.extra = extra()
        }

        public var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                Label {
                    Text(text).textSelection(.enabled).lineSpacing(2)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                extra
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.leading, ChatLook.tailRoom)
        }
    }

    /// The message box as a row of controls with nothing behind them, in Lamp's window and beside an app alike: a round attach button,
    /// the rounded field with the text (what's attached above it, and small buttons such as dictation at its end, so
    /// the text keeps the width), and a round button that sends, or stops the turn while one runs.
    public struct MessageBar<Field: View, Above: View, Inside: View>: View {
        let busy: Bool
        let canSend: Bool
        let attachHelp: String
        let attach: () -> Void
        /// Pointing at part of the app, offered beside Add Files in the + menu while the app is open on this Mac.
        let point: (() -> Void)?
        let send: () -> Void
        let stop: () -> Void
        let focus: () -> Void
        let field: Field
        let above: Above
        let inside: Inside

        public init(busy: Bool, canSend: Bool, attachHelp: String, attach: @escaping () -> Void, point: (() -> Void)? = nil,
                    send: @escaping () -> Void, stop: @escaping () -> Void, focus: @escaping () -> Void,
                    @ViewBuilder field: () -> Field,
                    @ViewBuilder above: () -> Above = { EmptyView() }, @ViewBuilder inside: () -> Inside = { EmptyView() }) {
            self.busy = busy
            self.canSend = canSend
            self.attachHelp = attachHelp
            self.attach = attach
            self.point = point
            self.send = send
            self.stop = stop
            self.focus = focus
            self.field = field()
            self.above = above()
            self.inside = inside()
        }

        /// How tall a one-line field is. The round buttons are a little smaller, level with its middle.
        public static var height: CGFloat { Composer.lineHeight + 2 * padding }
        static var padding: CGFloat { 6 }
        public static var buttonSide: CGFloat { 30 }
        /// Under each round button, so it sits level with a one-line field and stays at the bottom of a taller one.
        static var buttonLift: CGFloat { (height - buttonSide) / 2 }

        public var body: some View {
            HStack(alignment: .bottom, spacing: 8) {
                Button(action: plus) { Image(systemName: "plus") }
                    .buttonStyle(Round(prominent: false))
                    .help(point == nil ? attachHelp : "Point at part of the app, or attach a file")
                    .accessibilityLabel(point == nil ? "Attach files" : "Add")
                    .padding(.bottom, Self.buttonLift)
                HStack(alignment: .bottom, spacing: 4) {
                    VStack(alignment: .leading, spacing: 6) {
                        above
                        field
                    }
                    inside
                }
                .padding(.vertical, Self.padding).padding(.leading, 10).padding(.trailing, 8)
                .frame(minHeight: Self.height)
                // Pressing anywhere in the field, not only on the text, is for typing: the field's padding hands
                // focus to the text. Behind the text and what's attached, so clicks on those stay theirs.
                .background {
                    Self.fieldShape.fill(Color(nsColor: .textBackgroundColor))
                        .onTapGesture(perform: focus)
                }
                .overlay(Self.fieldShape.strokeBorder(Color(nsColor: .separatorColor)))
                // While a turn runs the round button stops it; Return still sends what's typed, which waits its turn,
                // so the row needs no second button for that.
                if busy {
                    Button(action: stop) { Image(systemName: "stop.fill") }
                        .buttonStyle(Round(prominent: true))
                        .help("Stop. Press Return to send what you've typed after this change.")
                        .accessibilityLabel("Stop")
                        .padding(.bottom, Self.buttonLift)
                } else {
                    Button(action: send) { Image(systemName: "arrow.up") }
                        .buttonStyle(Round(prominent: true))
                        .disabled(!canSend)
                        .help("Send")
                        .accessibilityLabel("Send")
                        .padding(.bottom, Self.buttonLift)
                }
            }
        }

        /// Straight to the files when that's all there is; else a menu under the button, as the system's own +
        /// buttons have.
        private func plus() {
            guard let point else { return attach() }
            PlusMenu.show([("Point at the Screen", "scope", point), ("Attach a File…", "paperclip", attach)])
        }

        static var fieldShape: RoundedRectangle { RoundedRectangle(cornerRadius: height / 2, style: .continuous) }
    }

    /// A round button beside the message box: the accent colour for Send and Stop, plain for the rest.
    public struct Round: ButtonStyle {
        let prominent: Bool
        @Environment(\.isEnabled) private var isEnabled

        public init(prominent: Bool) { self.prominent = prominent }

        public func makeBody(configuration: Configuration) -> some View {
            let size = MessageBar<EmptyView, EmptyView, EmptyView>.buttonSide
            configuration.label
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(prominent ? (isEnabled ? AnyShapeStyle(.white) : AnyShapeStyle(.tertiary))
                                           : AnyShapeStyle(.secondary))
                .frame(width: size, height: size)
                .background {
                    if prominent {
                        Circle().fill(isEnabled ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary))
                    } else {
                        Circle().fill(Color(nsColor: .textBackgroundColor))
                            .overlay(Circle().strokeBorder(Color(nsColor: .separatorColor)))
                    }
                }
                .contentShape(Circle())
                .opacity(configuration.isPressed ? 0.7 : 1)
        }
    }

    /// Dictation, as a small button at the end of the message box: red and pulsing while it listens.
    public struct MicButton: View {
        let listening: Bool
        let action: () -> Void
        public init(listening: Bool, action: @escaping () -> Void) {
            self.listening = listening
            self.action = action
        }

        public var body: some View {
            Button(action: action) {
                Image(systemName: listening ? "mic.fill" : "mic")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(listening ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    .symbolEffect(.pulse, isActive: listening)
                    .frame(width: 22, height: Composer.lineHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(listening ? "Stop dictation" : "Dictate a change")
            .accessibilityLabel(listening ? "Stop dictation" : "Dictate a change")
        }
    }

    /// What the message box says while empty.
    public static func placeholder(busy: Bool, empty: Bool) -> String {
        busy ? "Working… describe the next change" : empty ? "Describe what you'd like…" : "Describe a change…"
    }

    /// What the chat sits on: an off-white a touch warm, calmer than a text view's white, so the cards and the
    /// answers to choose from (still white) stand a little above it. A warm near-black in dark mode.
    public static let paper = Color(nsColor: NSColor(name: "LampChatPaper") { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0x1F / 255, green: 0x1E / 255, blue: 0x1C / 255, alpha: 1)
            : NSColor(srgbRed: 0xF7 / 255, green: 0xF5 / 255, blue: 0xF1 / 255, alpha: 1)
    })

    /// Parsed once per message: parsing markdown on every redraw adds up while an agent is streaming.
    @MainActor private static var proseCache: [String: AttributedString] = [:]

    /// Inline markdown, with code spans set off by a faint background.
    @MainActor public static func prose(_ text: String, keep: Bool = true) -> AttributedString {
        if let cached = proseCache[text] { return cached }
        if proseCache.count > 2000 { proseCache.removeAll() }
        var string = (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
        let code = string.runs.filter { $0.inlinePresentationIntent?.contains(.code) == true }.map(\.range)
        for range in code { string[range].backgroundColor = Color.primary.opacity(0.07) }
        if keep { proseCache[text] = string }
        return string
    }
}

extension View {
    /// The pointing hand over something that opens or closes when clicked (a line of steps, a command to show):
    /// it says the line is a control, which text alone doesn't.
    public func pointingHand() -> some View { modifier(PointingHand()) }
}

private struct PointingHand: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.pointerStyle(.link)
        } else {
            content.onHover { inside in inside ? NSCursor.pointingHand.push() : NSCursor.pop() }
        }
    }
}

/// A running clock, "0:42", that stops at `end`.
public struct Elapsed: View {
    let start: Date
    let end: Date?

    public init(from start: Date, to end: Date?) {
        self.start = start
        self.end = end
    }

    public var body: some View {
        TimelineView(.periodic(from: start, by: 1)) { context in
            let seconds = max(0, Int((end ?? context.date).timeIntervalSince(start)))
            Text(String(format: "%d:%02d", seconds / 60, seconds % 60)).monospacedDigit()
        }
    }
}

/// The + button's menu, opened where the pointer is. That's on the screen itself rather than in the chat's window:
/// in an app's sidebar that window is one macOS keeps out of sight, and a press from VoiceOver or the keyboard
/// carries no click to place it by.
@MainActor
enum PlusMenu {
    private final class Target: NSObject {
        let actions: [() -> Void]
        init(_ actions: [() -> Void]) { self.actions = actions }
        @objc func run(_ item: NSMenuItem) { actions[item.tag]() }
    }

    /// Each item's title, its symbol and what it does.
    static func show(_ items: [(String, String, () -> Void)]) {
        let target = Target(items.map(\.2))
        let menu = NSMenu()
        for (index, entry) in items.enumerated() {
            let item = NSMenuItem(title: entry.0, action: #selector(Target.run(_:)), keyEquivalent: "")
            item.image = NSImage(systemSymbolName: entry.1, accessibilityDescription: nil)
            item.target = target
            item.tag = index
            menu.addItem(item)
        }
        // The target lives as long as the menu is up: popUp returns once it closes.
        withExtendedLifetime(target) { _ = menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil) }
    }
}

extension ChatLook.ActivityLine where Steps == EmptyView {
    /// The line with no steps to open: a turn that has done nothing yet, or a place that doesn't list them.
    public init(_ activity: String, started: Date, since: Date? = nil) {
        self.init(activity, started: started, since: since, hasSteps: false) { EmptyView() }
    }
}
