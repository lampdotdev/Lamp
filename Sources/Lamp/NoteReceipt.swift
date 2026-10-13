import SwiftUI

/// What one `save_notes` changed, kept on a chat line (`LogLine.noted`) so the person sees what Lamp noted
/// when it notes it, and can take it back there. Without it a save was silent: the notes only showed in
/// Settings → Memory, and nobody could tell whether Lamp was keeping any.
struct NoteReceipt: Codable, Equatable {
    /// Whose notes, as the agent names them: "you" or "app".
    var about: String
    var before: Memory.Notes
    var after: Memory.Notes
    /// The person took it back.
    var undone: Bool? = nil

    /// A note as the person reads it: one line of the notes, without the list mark or heading mark the agent
    /// may have given it.
    static func lines(_ text: String) -> [String] {
        text.components(separatedBy: .newlines).map(plain).filter { !$0.isEmpty }
    }

    private static func plain(_ line: String) -> String {
        var line = Substring(line.trimmed)
        while let first = line.first, "-*•#".contains(first) { line = line.dropFirst() }
        return String(line).trimmed
    }

    /// A summary made from the notes themselves, for when no summary anyone wrote describes them: their
    /// lines one after another, as many as fit in a line. It is what the person sees in Settings and all the
    /// agent is told of the notes, so it has to be true of what is there.
    static func summary(of text: String) -> String {
        let parts = lines(text).map { line in
            var line = Substring(line)
            while let last = line.last, ".;,".contains(last) { line = line.dropLast() }
            return String(line)
        }.filter { !$0.isEmpty }
        var summary = ""
        for (index, part) in parts.enumerated() {
            let next = summary.isEmpty ? part : summary + "; " + part
            // Whatever doesn't fit is stood for by a mark, which needs its own place in the line.
            let room = Memory.summaryLimit - (index == parts.count - 1 ? 0 : 1)
            guard next.count <= room else {
                return (summary.isEmpty ? String(part.prefix(Memory.summaryLimit - 1)) : summary) + "…"
            }
            summary = next
        }
        return summary
    }

    /// The lines this save added, and the ones it removed or replaced.
    var added: [String] { let old = Set(Self.lines(before.text)); return Self.lines(after.text).filter { !old.contains($0) } }
    var removed: [String] { let new = Set(Self.lines(after.text)); return Self.lines(before.text).filter { !new.contains($0) } }

    /// Nothing the person would read as a change: the same lines in another order, or only a new summary.
    var isEmpty: Bool { added.isEmpty && removed.isEmpty }

    /// The notes with this save taken back. When nothing has touched them since, that is the notes as they
    /// were. When something has (a later save, the person's own edit in Settings), only this save's lines are
    /// undone: what it added goes, what it removed comes back, and the rest stays.
    /// `rejected` are lines the person already took back on other receipts: a later save may have replaced
    /// one of them, and undoing that save must not bring it back. One that is in the notes now stays.
    func takenBack(from current: Memory.Notes, rejected: Set<String> = []) -> Memory.Notes {
        var lines = (current == after ? before.text : merged(into: current)).components(separatedBy: .newlines)
        // Only what this Undo would bring back: a line that is in the notes now is there by a later choice.
        let returning = rejected.subtracting(Self.lines(current.text))
        lines.removeAll { returning.contains(Self.plain($0)) }
        let text = lines.joined(separator: "\n").trimmed
        if text.isEmpty { return Memory.Notes() }
        // A summary goes with the notes it was written for. Those as they were before this save, or as they
        // are now, keep theirs; anything between has lines neither summary was written for, or lacks some it
        // was, so its summary is made from the lines themselves.
        if text == before.text { return before }
        if text == current.text { return current }
        return Memory.Notes(summary: Self.summary(of: text), text: text)
    }

    private func merged(into current: Memory.Notes) -> String {
        let added = Set(added), removed = Set(removed)
        var lines = current.text.components(separatedBy: .newlines).filter { !added.contains(Self.plain($0)) }
        let present = Set(lines.map(Self.plain))
        lines += before.text.components(separatedBy: .newlines).filter {
            removed.contains(Self.plain($0)) && !present.contains(Self.plain($0))
        }
        return lines.joined(separator: "\n").trimmed
    }
}

/// The receipt in the chat: what was noted, about whom, and Undo.
struct NoteCard: View {
    let line: LogLine
    let dir: URL
    @ObservedObject private var store = Store.shared
    @State private var problem: String?

    /// More lines than this and the rest are counted, not listed: the card is a receipt, not the notes.
    private static let shown = 4

    private var project: LampProject? { store.projects.first { $0.dir == dir } }

    static func title(_ receipt: NoteReceipt, app: String) -> String {
        let whom = receipt.about == "you" ? "you" : app
        if receipt.undone == true { return "Taken back" }
        return receipt.added.isEmpty ? "No longer noted about \(whom)" : "Noted about \(whom)"
    }

    var body: some View {
        if let receipt = line.noted {
            let undone = receipt.undone == true
            let lines = receipt.added.map { ($0, false) } + receipt.removed.map { ($0, true) }
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "note.text").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(Self.title(receipt, app: project?.name ?? "this app")).font(.callout.weight(.medium))
                    ForEach(Array(lines.prefix(Self.shown).enumerated()), id: \.offset) { _, item in
                        Text(item.0)
                            .strikethrough(item.1 || undone)
                            .foregroundStyle(item.1 || undone ? .tertiary : .secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if lines.count > Self.shown {
                        Text("and \(lines.count - Self.shown) more").foregroundStyle(.tertiary)
                    }
                    if let problem { Text(problem).font(.caption).foregroundStyle(.orange) }
                }
                .font(.callout)
                Spacer(minLength: 8)
                if !undone, let project {
                    Button("Undo") { problem = store.undoNote(line.id, in: project) }
                        .controlSize(.small)
                        .help("Lamp forgets this. Everything it remembers is in Settings, under Memory.")
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
            .accessibilityElement(children: .contain)
        }
    }
}
