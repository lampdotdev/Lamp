import SwiftUI
import AppKit

/// The chat's cards and the lines that ask something of the person (a setup offer, a widget to place, a note
/// to undo, an icon to draw, iPhone setup), drawn by this one code in Lamp's window and in the chat inside
/// each app's window (the LampSidebar extension). What a card says and what its buttons do are Lamp's: each
/// side gives it plain values and is told which button was pressed, so a card is the same wherever it shows.
public enum CardLook {
    /// The setup card's columns: its rows' symbols sit in a column as wide as the header's tile, against its
    /// right edge, so every line of text in the card starts where the headline does.
    public static let icon: CGFloat = 44
    public static let gap: CGFloat = 12
    /// Where text under a row's title starts.
    public static func indent(compact: Bool) -> CGFloat { compact ? 28 : icon + gap }
    /// Narrower than this (the chat beside an app), a card's buttons go under its words rather than beside
    /// them, which would leave the words a column a few letters wide.
    public static let narrow: CGFloat = 440

    /// The tile a card's header starts with: what it's about, on the accent colour, or green once it's done.
    public struct Badge: View {
        let symbol: String
        let done: Bool
        public init(_ symbol: String, done: Bool = false) {
            self.symbol = symbol
            self.done = done
        }

        public var body: some View {
            let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
            let color = done ? Color.green : Color.accentColor
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(shape.fill(LinearGradient(colors: [color.opacity(0.85), color], startPoint: .top, endPoint: .bottom)))
                .overlay(shape.strokeBorder(.black.opacity(0.08)))
                .frame(width: icon, height: icon)
        }
    }

    /// The box every card in the chat is drawn in.
    public struct Box<Content: View>: View {
        let content: Content
        public init(@ViewBuilder content: () -> Content) { self.content = content() }

        public var body: some View {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
        }
    }

    /// A line in the chat with one thing to do: what's so, and the button that does it.
    public struct ActionLine: View {
        let symbol: String
        let text: String
        let button: String
        let enabled: Bool
        let action: () -> Void

        public init(symbol: String, text: String, button: String, enabled: Bool = true, action: @escaping () -> Void) {
            self.symbol = symbol
            self.text = text
            self.button = button
            self.enabled = enabled
            self.action = action
        }

        public var body: some View {
            HStack(spacing: 8) {
                Image(systemName: symbol).foregroundStyle(.secondary)
                Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button(button, action: action).controlSize(.small).disabled(!enabled).fixedSize()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Setting up what an app needs

/// What the setup card says, worked out by Lamp (`SetupCard`), which alone knows what answers an app.
public struct SetupContent: Codable, Equatable {
    public var symbol: String
    public var title: String
    /// Why it's offered; once it's set up, what answers now; after Not Now, where to find it later.
    public var status: String
    public var done: Bool
    public var declined: Bool
    /// Answered by drawing icons by hand, while this app's icon is still plain.
    public var drawIcon: Bool
    public var rows: [UpgradeRow]
    /// Something answers already, just not as well.
    public var note: String?

    public init(symbol: String, title: String, status: String, done: Bool, declined: Bool, drawIcon: Bool, rows: [UpgradeRow], note: String?) {
        self.symbol = symbol
        self.title = title
        self.status = status
        self.done = done
        self.declined = declined
        self.drawIcon = drawIcon
        self.rows = rows
        self.note = note
    }
}

/// One way to make a capability better: a key, a download or a sign-in.
public struct UpgradeRow: Codable, Equatable, Identifiable {
    public var id: String
    public var symbol: String
    public var title: String
    public var detail: String
    /// What to press, while there's nothing going on.
    public var button: String?
    /// A download under way.
    public var progress: Double?
    /// Something under way with no measure of how far.
    public var working: Bool
    public var problem: String?
    /// A key typed in place.
    public var key: KeyField?

    public init(id: String, symbol: String, title: String, detail: String, button: String? = nil, progress: Double? = nil,
                working: Bool = false, problem: String? = nil, key: KeyField? = nil) {
        self.id = id
        self.symbol = symbol
        self.title = title
        self.detail = detail
        self.button = button
        self.progress = progress
        self.working = working
        self.problem = problem
        self.key = key
    }
}

public struct KeyField: Codable, Equatable {
    /// Whose key: "OpenRouter".
    public var site: String
    public var link: String
    public var checking: Bool
    public var problem: String?

    public init(site: String, link: String, checking: Bool, problem: String?) {
        self.site = site
        self.link = link
        self.checking = checking
        self.problem = problem
    }
}

/// What the person did on a setup card.
public enum SetupAction: Codable, Equatable {
    case notNow
    case drawIcon
    case row(String)
    /// A key typed into a row; `nil` when the field was changed, so what was said about the last one goes.
    case key(String, String?)
}

/// Offers a way to set up a kind of AI where it's first wanted. Built like the build card (an icon, a headline
/// and a status line, then rows); once it's set up it folds down to its header, saying what answers now.
public struct SetupCardView: View {
    let content: SetupContent
    let act: (SetupAction) -> Void

    public init(_ content: SetupContent, act: @escaping (SetupAction) -> Void) {
        self.content = content
        self.act = act
    }

    @State private var width: CGFloat = 600

    public var body: some View {
        let open = !content.done && !content.declined
        let narrow = width < CardLook.narrow
        CardLook.Box {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: narrow ? .top : .center, spacing: CardLook.gap) {
                    CardLook.Badge(content.symbol)
                    VStack(alignment: .leading, spacing: narrow ? 8 : 2) {
                        Text(content.title).font(.headline).fixedSize(horizontal: false, vertical: true)
                        Group {
                            if content.done {
                                Label {
                                    Text(content.status)
                                } icon: {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                }
                            } else {
                                Text(content.status)
                            }
                        }
                        .font(.body).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        if narrow { HStack(spacing: 8) { buttons(open) } }
                    }
                    Spacer(minLength: narrow ? 0 : 8)
                    if !narrow { buttons(open) }
                }
                .padding(14)
                if open {
                    Divider()
                    VStack(alignment: .leading, spacing: 12) {
                        UpgradeRows(content.rows, narrow: narrow, act: act)
                        if let note = content.note {
                            Text(note)
                                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                .padding(.leading, CardLook.indent(compact: false))
                        }
                    }
                    .padding(14)
                    .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.35), value: content.done)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    @ViewBuilder
    private func buttons(_ open: Bool) -> some View {
        if content.drawIcon {
            Button("Draw Icon…") { act(.drawIcon) }.controlSize(.small)
        }
        if open {
            Button("Not Now") { withAnimation { act(.notNow) } }.controlSize(.small)
        }
    }
}

/// What would make a capability better, best first, a row each: what it is, a line on what it costs or
/// gives, and the button that does it. The same rows in the chat's card and in Settings (`compact`), where a
/// key is added in its provider's sheet rather than typed in place.
public struct UpgradeRows: View {
    let rows: [UpgradeRow]
    let compact: Bool
    let narrow: Bool
    let act: (SetupAction) -> Void

    public init(_ rows: [UpgradeRow], compact: Bool = false, narrow: Bool = false, act: @escaping (SetupAction) -> Void) {
        self.rows = rows
        self.compact = compact
        self.narrow = narrow
        self.act = act
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            ForEach(rows) { row in
                UpgradeRowView(row: row, compact: compact, narrow: narrow, act: act)
            }
        }
    }
}

private struct UpgradeRowView: View {
    let row: UpgradeRow
    let compact: Bool
    let narrow: Bool
    let act: (SetupAction) -> Void
    @State private var typing = false
    @State private var key = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: narrow ? .top : .center, spacing: compact ? 10 : CardLook.gap) {
                Image(systemName: row.symbol)
                    .font(compact ? .body : .title3)
                    .foregroundStyle(.secondary)
                    .frame(width: compact ? 18 : CardLook.icon, alignment: compact ? .center : .trailing)
                VStack(alignment: .leading, spacing: narrow ? 6 : 1) {
                    Text(row.title).font(compact ? .callout : .body).fixedSize(horizontal: false, vertical: true)
                    Text(row.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if narrow { accessory }
                }
                Spacer(minLength: narrow ? 0 : 8)
                if !narrow { accessory }
            }
            if let problem = row.problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill").symbolRenderingMode(.multicolor)
                    .font(.caption).fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, CardLook.indent(compact: compact))
            }
            if typing, let field = row.key, !compact {
                keyField(field)
            }
        }
    }

    /// What to press, or how far it has got.
    @ViewBuilder
    private var accessory: some View {
        Group {
            if let progress = row.progress {
                ProgressView(value: progress).frame(width: 80)
            } else if row.working {
                ProgressView()
            } else if let button = row.button, !(typing && row.key != nil) {
                Button(button) {
                    if row.key != nil && !compact {
                        typing = true
                        focused = true
                    } else {
                        act(.row(row.id))
                    }
                }
            }
        }
        .controlSize(.small)
    }

    @ViewBuilder
    private func keyField(_ field: KeyField) -> some View {
        HStack(spacing: 8) {
            SecureField("Paste your key", text: $key)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(save)
                .onChange(of: key) { act(.key(row.id, nil)) }
            if field.checking {
                ProgressView().controlSize(.small)
            } else {
                Button("Cancel") { typing = false; key = ""; act(.key(row.id, nil)) }
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(key.cardTrimmed.isEmpty)
            }
        }
        .controlSize(.small)
        .padding(.leading, CardLook.indent(compact: compact))
        HStack(spacing: 4) {
            if let problem = field.problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let url = URL(string: field.link) {
                Text("No key yet?").foregroundStyle(.secondary)
                Link("Get one from \(field.site)", destination: url)
            }
        }
        .font(.caption)
        .padding(.leading, CardLook.indent(compact: compact))
    }

    private func save() {
        guard !key.cardTrimmed.isEmpty else { return }
        act(.key(row.id, key))
    }
}

// MARK: - A widget to place

/// The card an app with a widget has in its chat: the one thing left for the person to do, and then the plain
/// fact that it's done. Laid out like the setup card: the same badge, title and one gray line.
public struct WidgetCardLook: View {
    let title: String
    let status: String
    let placed: Bool

    public init(title: String, status: String, placed: Bool) {
        self.title = title
        self.status = status
        self.placed = placed
    }

    public var body: some View {
        CardLook.Box {
            HStack(alignment: .center, spacing: 12) {
                CardLook.Badge(placed ? "checkmark" : "widget.small", done: placed)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(status).font(.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
            }
            .padding(14)
        }
    }
}

// MARK: - What Lamp noted

/// What a save of Lamp's notes changed, as the receipt shows it.
public struct NoteContent: Codable, Equatable {
    public var title: String
    /// The notes added, then the ones taken out.
    public var added: [String]
    public var removed: [String]
    public var undone: Bool
    /// Why Undo didn't work, when it didn't.
    public var problem: String?

    public init(title: String, added: [String], removed: [String], undone: Bool, problem: String? = nil) {
        self.title = title
        self.added = added
        self.removed = removed
        self.undone = undone
        self.problem = problem
    }
}

/// The receipt in the chat: one line saying what was noted and about whom, with Undo. The line opens to the
/// notes themselves, the way a command Lamp ran does (`ChatLook.RanCommand`): a receipt is there to be glanced
/// at, and drawn as a card it competed with the card the person is answering. Taken back, it is the two words.
public struct NoteLine: View {
    let note: NoteContent
    let undo: () -> Void
    @State private var expanded = false

    /// More lines than this and the rest are counted, not listed: it is a receipt, not the notes.
    static let shown = 4

    public init(_ note: NoteContent, undo: @escaping () -> Void) {
        self.note = note
        self.undo = undo
    }

    public var body: some View {
        let lines = note.added.map { ($0, false) } + note.removed.map { ($0, true) }
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Button {
                    withAnimation(.snappy(duration: 0.2)) { expanded.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "note.text").frame(width: 16)
                        // The title is given room before the notes beside it, and a long app name is cut
                        // short rather than pushing Undo out of the chat.
                        Text(note.title).lineLimit(1).layoutPriority(1)
                        // Closed, the line says what the notes are as far as it has room.
                        if !expanded && !note.undone {
                            Text((note.added.isEmpty ? note.removed : note.added).joined(separator: " "))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(note.undone ? "Show what was taken back" : "Show what was noted")
                Spacer(minLength: 8)
                if !note.undone {
                    Button("Undo", action: undo)
                        .buttonStyle(.borderless)
                        .fixedSize()
                        .help("Lamp forgets this. Everything it remembers is in Settings, under Memory.")
                }
            }
            if expanded {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(lines.prefix(Self.shown).enumerated()), id: \.offset) { _, item in
                        Text(item.0)
                            .strikethrough(item.1 || note.undone)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if lines.count > Self.shown { Text("and \(lines.count - Self.shown) more") }
                }
                .foregroundStyle(.tertiary)
                .padding(.leading, 22)
            }
            if let problem = note.problem { Text(problem).font(.caption).foregroundStyle(.orange).padding(.leading, 22) }
        }
        .font(.callout)
        .foregroundStyle(note.undone ? .tertiary : .secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}
