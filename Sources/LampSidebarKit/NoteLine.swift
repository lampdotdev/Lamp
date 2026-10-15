import SwiftUI

extension ChatLook {
    /// The receipt for a save of Lamp's notes: one line saying what was noted and about whom, with Undo. The line
    /// opens to the notes themselves, the way a command Lamp ran does (`RanCommand`): a receipt is there to be
    /// glanced at, and drawn as a card it competed with the card the person is answering. Taken back, it is the
    /// two words.
    public struct NoteLine: View {
        let title: String
        let added: [String]
        let removed: [String]
        let undone: Bool
        let problem: String?
        let undo: (() -> Void)?
        @State private var expanded = false

        /// More lines than this and the rest are counted, not listed: it is a receipt, not the notes.
        private static let shown = 4

        public init(title: String, added: [String], removed: [String], undone: Bool, problem: String?, undo: (() -> Void)?) {
            self.title = title
            self.added = added
            self.removed = removed
            self.undone = undone
            self.problem = problem
            self.undo = undo
        }

        public var body: some View {
            let lines = added.map { ($0, false) } + removed.map { ($0, true) }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { expanded.toggle() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "note.text").frame(width: 16)
                            // The title is given room before the notes beside it, and a long app name is cut
                            // short rather than pushing Undo out of the chat.
                            Text(title).lineLimit(1).layoutPriority(1)
                            // Closed, the line says what the notes are as far as it has room.
                            if !expanded && !undone {
                                Text((added.isEmpty ? removed : added).joined(separator: " "))
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
                    .help(undone ? "Show what was taken back" : "Show what was noted")
                    Spacer(minLength: 8)
                    if !undone, let undo {
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
                                .strikethrough(item.1 || undone)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if lines.count > Self.shown { Text("and \(lines.count - Self.shown) more") }
                    }
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 22)
                }
                if let problem { Text(problem).font(.caption).foregroundStyle(.orange).padding(.leading, 22) }
            }
            .font(.callout)
            .foregroundStyle(undone ? .tertiary : .secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
        }
    }
}
