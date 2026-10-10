import Foundation

/// The ordinary Mac transcript, projected as text. Files and controls never cross this boundary:
/// a phone can read the conversation, but approvals, setup and attachments still happen on the Mac.
enum PhoneTranscript {
    static func chat(id: UUID, title: String, lines: [LogLine], queued: [PhoneLink.ChatLine]) -> PhoneLink.Chat {
        let visible = LogLine.visible(lines, details: false)
        let grouped = ChatItem.items(visible).flatMap { item -> [LogLine] in
            switch item {
            case .line(let line): [line]
            case .statuses(let lines): lines
            case .tools: []
            }
        }
        let messages = grouped.compactMap { line -> PhoneLink.ChatLine? in
            let kind: PhoneLink.ChatLine.Kind
            var text = line.text
            switch line.kind {
            case .user: kind = .user
            case .agent: kind = .agent
            case .status: kind = .status
            case .error: kind = .error
            case .needsKey, .offer:
                kind = .notice
                text += (text.isEmpty ? "" : "\n") + "Complete setup in Lamp on Mac."
            case .drawIcon: kind = .notice; text = "Draw the icon in Lamp on Mac."
            case .widget: kind = .notice; text = "Set up the widget on Mac."
            case .detail, .tool, .summary: return nil
            }
            return .init(id: line.id, kind: kind, text: text, attachments: line.attachments?.count ?? 0)
        }
        let shown = Set(messages.map(\.id))
        return .init(id: id, title: title, lines: messages + queued.filter { !shown.contains($0.id) })
    }
}
